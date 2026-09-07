# frozen_string_literal: true

require "test_helper"

class Pilot::AutopilotTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Pilot Auto")
    @shop = Shop.create!(shopify_domain: "auto.myshopify.com", access_token: "t", account: @account)
    @policy = Pilot::Autopilot.ensure_policy!(@shop)
  end

  test "disabled by default kill switch semantics" do
    result = Pilot::Autopilot.call(shop: @shop)
    assert_equal "kill_switch_or_disabled", result[:skipped]
    assert_equal 0, result[:applied]
  end

  test "kill_switch disables policy" do
    @policy.update!(enabled: true, allowed_action_kinds: [ "catalog_fix" ])
    @policy.kill_switch!
    assert_not @policy.reload.enabled?
    assert @policy.kill_switch_at.present?
  end

  test "applies an evidence backed discount within stock margin and cost limits" do
    product = product_with_economics
    recommendation = @shop.recommendations.create!(
      account: @account, catalog_product: product, kind: "promotion_opportunity", priority: "high", status: "open",
      title: "Promote Kurti", rationale: "Strong paid demand",
      evidence: { "paid_orders" => 3, "inventory" => 30, "size_coverage_percent" => 100,
                  "cost_coverage_percent" => 100, "minimum_margin_percent" => "50", "inventory_retail_value" => "3000" }
    )
    @shop.update!(scope: "write_discounts")
    @policy.update!(enabled: true, allowed_action_kinds: [ recommendation.kind ], margin_floor_pct: 40,
                    minimum_evidence_count: 2, max_estimated_discount_cost_per_day: 500)
    response = { "discountCodeBasicCreate" => { "codeDiscountNode" => { "id" => "gid://shopify/DiscountCodeNode/1", "codeDiscount" => {} }, "userErrors" => [] } }

    result = with_shopify_write(response) { Pilot::Autopilot.call(shop: @shop) }

    assert_equal 1, result[:applied]
    assert_equal "applied", recommendation.reviewed_actions.first.status
    assert_equal "completed", @policy.autopilot_runs.last.status
  end

  test "records a skip when margin evidence is unavailable" do
    product = product_with_economics
    @shop.recommendations.create!(account: @account, catalog_product: product, kind: "promotion_opportunity",
                                  priority: "high", status: "open", title: "Unknown margin", rationale: "Demand",
                                  evidence: { "paid_orders" => 3, "inventory" => 30, "size_coverage_percent" => 100,
                                              "cost_coverage_percent" => 0, "inventory_retail_value" => "3000" })
    @policy.update!(enabled: true, allowed_action_kinds: [ "promotion_opportunity" ], margin_floor_pct: 30)

    result = Pilot::Autopilot.call(shop: @shop)

    assert_equal 0, result[:applied]
    assert_equal 1, result[:skipped]
    assert_equal 1, @policy.autopilot_runs.last.details.dig("skip_reasons", "margin_unknown_or_below_floor")
  end

  test "checks the margin remaining after the proposed discount" do
    product = product_with_economics
    @shop.recommendations.create!(
      account: @account, catalog_product: product, kind: "promotion_opportunity", priority: "high", status: "open",
      title: "Thin post-discount margin", rationale: "Demand",
      evidence: { "paid_orders" => 3, "inventory" => 30, "size_coverage_percent" => 100,
                  "cost_coverage_percent" => 100, "minimum_margin_percent" => "50", "inventory_retail_value" => "3000" }
    )
    @policy.update!(enabled: true, allowed_action_kinds: [ "promotion_opportunity" ], margin_floor_pct: 45)

    result = Pilot::Autopilot.call(shop: @shop)

    assert_equal 0, result[:applied]
    assert_equal 1, result[:skipped]
    assert_equal 1, @policy.autopilot_runs.last.details.dig("skip_reasons", "margin_unknown_or_below_floor")
  end

  test "enforces the daily action cap across separate runs" do
    product = product_with_economics
    recommendation = @shop.recommendations.create!(
      account: @account, catalog_product: product, kind: "promotion_opportunity", priority: "high", status: "open",
      title: "Daily cap", rationale: "Demand",
      evidence: { "paid_orders" => 3, "inventory" => 30, "size_coverage_percent" => 100,
                  "cost_coverage_percent" => 100, "minimum_margin_percent" => "60", "inventory_retail_value" => "1000" }
    )
    @shop.reviewed_actions.create!(
      account: @account, recommendation: recommendation, action_kind: recommendation.kind, status: "applied",
      before_snapshot: {}, after_snapshot: { "operation" => "discount_code_create", "estimated_discount_cost" => "100" },
      source_fingerprint: "already-applied", applied_at: Time.current
    )
    @policy.update!(enabled: true, allowed_action_kinds: [ recommendation.kind ], max_actions_per_day: 1)

    result = Pilot::Autopilot.call(shop: @shop)

    assert_equal 0, result[:applied]
    assert_equal 1, @policy.autopilot_runs.last.details.dig("skip_reasons", "daily_action_cap")
  end

  test "enforces the estimated daily discount cost cap" do
    product = product_with_economics
    @shop.recommendations.create!(
      account: @account, catalog_product: product, kind: "promotion_opportunity", priority: "high", status: "open",
      title: "Cost cap", rationale: "Demand",
      evidence: { "paid_orders" => 3, "inventory" => 30, "size_coverage_percent" => 100,
                  "cost_coverage_percent" => 100, "minimum_margin_percent" => "60", "inventory_retail_value" => "3000" }
    )
    @policy.update!(enabled: true, allowed_action_kinds: [ "promotion_opportunity" ],
                    max_estimated_discount_cost_per_day: 299)

    result = Pilot::Autopilot.call(shop: @shop)

    assert_equal 0, result[:applied]
    assert_equal 1, @policy.autopilot_runs.last.details.dig("skip_reasons", "daily_discount_cost_cap")
  end

  private

  def product_with_economics
    product = @shop.catalog_products.create!(external_id: "gid://shopify/Product/1", title: "Kurti", status: "active")
    variant = product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/1", title: "M")
    variant.catalog_inventory_levels.create!(location_external_id: "location", available: 30)
    product
  end

  def with_shopify_write(response, &)
    fake = Object.new
    fake.define_singleton_method(:graphql) { |_query, _variables| response }
    with_singleton_stub(ShopifyConfig, :allow_writes?, -> { true }) do
      with_singleton_stub(Shopify::AdminClient, :new, ->(_shop) { fake }, &)
    end
  end
end
