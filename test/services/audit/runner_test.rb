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

    findings = Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    gap = findings.find { |f| f.audit_rule.rule_key == "size_gap" }
    assert gap, "expected size_gap finding"
    assert_equal @account.id, gap.account_id
    assert_equal "open", gap.status
  end

  test "emits missing_size_attr for Default Title only" do
    product = @shop.catalog_products.create!(external_id: "p2", title: "Riverstone Fabric Pack", status: "active")
    product.catalog_variants.create!(external_id: "v-def", title: "Default Title", option_summary: nil, sku: "SF-NOSIZE-DEF")

    findings = Audit::Runner.call(shop: @shop, rule_set: @rule_set)
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

    findings = Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    anomaly = findings.find { |f| f.audit_rule.rule_key == "compare_at_anomaly" }
    assert anomaly, "expected compare_at_anomaly finding"
  end
  test "does not duplicate findings on re-run" do
    product = @shop.catalog_products.create!(external_id: "p-dedupe", title: "Gap Tee", status: "active")
    %w[S L XL].each_with_index do |size, i|
      product.catalog_variants.create!(external_id: "vd#{i}", title: size, option_summary: size, sku: "SF-GAP-#{size}")
    end

    first = Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    assert first.any? { |f| f.audit_rule.rule_key == "size_gap" }
    count_after_first = AuditFinding.for_shop(@shop).count
    assert count_after_first.positive?

    second = Audit::Runner.call(shop: @shop, rule_set: @rule_set)
    assert second.any? { |f| f.audit_rule.rule_key == "size_gap" }
    assert_equal count_after_first, AuditFinding.for_shop(@shop).count
  end

end
