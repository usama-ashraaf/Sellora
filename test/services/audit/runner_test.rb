# frozen_string_literal: true

require "test_helper"

class Audit::RunnerTest < ActiveSupport::TestCase
  setup do
    @account = Account.demo!
    @shop = Shop.create!(
      shopify_domain: "audit-run.myshopify.com",
      access_token: "t",
      scope: "read_products",
      account: @account
    )
    @rule_set = Audit::ClothingRulesSeed.call
  end

  test "emits size_gap finding when M is missing" do
    product = @shop.catalog_products.create!(external_id: "p1", title: "Harbor Fleece Hoodie", status: "active")
    %w[S L XL XXL].each_with_index do |size, i|
      product.catalog_variants.create!(external_id: "v#{i}", title: size, option_summary: size, sku: "SF-HOOD-#{size}")
    end

    findings = Audit::Runner.call(shop: @shop, rule_set: @rule_set).findings
    gap = findings.find { |f| f.audit_rule.rule_key == "size_gap" }
    assert gap, "expected size_gap finding"
    assert_equal @account.id, gap.account_id
    assert_equal "open", gap.status
  end

  test "emits missing_size_attr for Default Title only" do
    product = @shop.catalog_products.create!(external_id: "p2", title: "Riverstone Fabric Pack", status: "active")
    product.catalog_variants.create!(external_id: "v-def", title: "Default Title", option_summary: nil, sku: "SF-NOSIZE-DEF")

    findings = Audit::Runner.call(shop: @shop, rule_set: @rule_set).findings
    miss = findings.find { |f| f.audit_rule.rule_key == "missing_size_attr" }
    assert miss, "expected missing_size_attr finding"
  end

  test "emits compare_at_anomaly from variant_prices side-channel" do
    product = @shop.catalog_products.create!(
      external_id: "p3",
      title: "Sale Tee",
      status: "active",
      raw_attrs: {
        "variant_prices" => {
          "v-xl" => { "price" => 5490, "compare_at_price" => 4990 }
        }
      }
    )
    product.catalog_variants.create!(external_id: "v-xl", title: "XL", option_summary: "XL", sku: "SF-HOOD-XL")

    findings = Audit::Runner.call(shop: @shop, rule_set: @rule_set).findings
    anomaly = findings.find { |f| f.audit_rule.rule_key == "compare_at_anomaly" }
    assert anomaly, "expected compare_at_anomaly finding"
  end
  test "does not duplicate findings on re-run" do
    product = @shop.catalog_products.create!(external_id: "p-dedupe", title: "Gap Tee", status: "active")
    %w[S L XL].each_with_index do |size, i|
      product.catalog_variants.create!(external_id: "vd#{i}", title: size, option_summary: size, sku: "SF-GAP-#{size}")
    end

    first = Audit::Runner.call(shop: @shop, rule_set: @rule_set).findings
    assert first.any? { |f| f.audit_rule.rule_key == "size_gap" }
    count_after_first = AuditFinding.for_shop(@shop).count
    assert count_after_first.positive?

    second = Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    assert AuditFinding.for_shop(@shop).joins(:audit_rule).where(audit_rules: { rule_key: "size_gap" }).exists?
    assert_equal count_after_first, AuditFinding.for_shop(@shop).count
    assert_operator second.skipped, :>=, 1
  end

  test "skips unchanged content when fingerprint matches" do
    product = @shop.catalog_products.create!(external_id: "p-skip", title: "Stable Tee", status: "active")
    product.catalog_variants.create!(external_id: "vs1", title: "M", option_summary: "M", sku: "SF-ST-M")
    Audit::Runner.call(shop: @shop, rule_set: @rule_set, force: true)
    product.reload
    assert product.content_fingerprint.present?

    result = Audit::Runner.call(shop: @shop, rule_set: @rule_set, force: false)
    assert_operator result.skipped, :>=, 1
  end

  test "force re-runs content rules" do
    product = @shop.catalog_products.create!(external_id: "p-force", title: "Gap Tee", status: "active")
    %w[S L XL].each_with_index do |size, i|
      product.catalog_variants.create!(external_id: "vf#{i}", title: size, option_summary: size, sku: "SF-F-#{size}")
    end
    Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    forced = Audit::Runner.call(shop: @shop, rule_set: @rule_set, force: true)
    assert_equal 0, forced.skipped
  end

  test "resolves a content finding after the source issue is corrected" do
    product = @shop.catalog_products.create!(external_id: "p-resolve", title: "Gap Tee", status: "active")
    %w[S L].each_with_index do |size, index|
      product.catalog_variants.create!(external_id: "vr#{index}", title: size, option_summary: size, sku: "SF-R-#{size}")
    end
    Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    finding = AuditFinding.for_shop(@shop).joins(:audit_rule).find_by!(audit_rules: { rule_key: "size_gap" })

    product.catalog_variants.create!(external_id: "vr-m", title: "M", option_summary: "M", sku: "SF-R-M")
    Audit::Runner.call(shop: @shop, rule_set: @rule_set)

    assert_equal "resolved", finding.reload.status
  end

  test "resolves a freshness finding while unchanged content is skipped" do
    product = @shop.catalog_products.create!(
      external_id: "p-fresh-resolve",
      title: "Sale Tee",
      status: "active",
      raw_attrs: { "variant_prices" => { "v-fresh" => { "price" => 100, "compare_at_price" => 90 } } }
    )
    product.catalog_variants.create!(external_id: "v-fresh", title: "M", option_summary: "M", sku: "SF-FRESH-M")
    Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    finding = AuditFinding.for_shop(@shop).joins(:audit_rule).find_by!(audit_rules: { rule_key: "compare_at_anomaly" })

    product.update!(raw_attrs: product.raw_attrs.deep_merge("variant_prices" => { "v-fresh" => { "compare_at_price" => nil } }))
    result = Audit::Runner.call(shop: @shop, rule_set: @rule_set)

    assert_operator result.skipped, :>=, 1
    assert_equal "resolved", finding.reload.status
  end

  test "rejects shop without account" do
    assert_raises(ArgumentError, match: /no account/) do
      Audit::Runner.call(shop: Shop.new(shopify_domain: "orphan-audit.myshopify.com"), rule_set: @rule_set)
    end
  end
end
