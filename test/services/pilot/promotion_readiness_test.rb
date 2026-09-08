# frozen_string_literal: true

require "test_helper"

class Pilot::PromotionReadinessTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Promotion Planner")
    @shop = Shop.create!(shopify_domain: "promotion-planner.myshopify.com", access_token: "t", account: @account)
    @policy = Pilot::PromotionReadiness.ensure_policy!(@shop)
    @policy.update!(target_roas: 3, target_acquisition_cost: 500, shipping_cost_per_order: 200,
                    desired_runway_days: 14, minimum_margin_percent: 20, minimum_safe_orders: 5)
  end

  test "promotes a profitable product and calculates demand weighted capacity and spend ceiling" do
    product, variants = create_product("Ready Kurti", [ 30, 30, 30 ])
    variants.each do |variant|
      2.times { create_paid_order(product, variant) }
      2.times { ingest("product_viewed", product, variant) }
    end

    decision = Pilot::PromotionReadiness.call(shop: @shop).find { |row| row.catalog_product == product }

    assert_equal "promote", decision.status
    assert_equal "high", decision.confidence
    assert_equal 90, decision.metrics["safe_order_capacity"]
    assert_equal "45000.0", decision.metrics["promotion_spend_ceiling"]
    assert_equal "PKR", decision.metrics["currency"]
    assert_equal 100, decision.metrics["size_coverage_percent"]
    assert_equal 3, decision.metrics["variant_capacity"].size
  end

  test "blocks a product when the popular size is gone despite high total inventory" do
    product, variants = create_product("Unbalanced Kurti", [ 50, 0, 50 ])
    8.times { ingest("product_added_to_cart", product, variants.second) }
    ingest("product_viewed", product, variants.first)
    ingest("product_viewed", product, variants.third)

    decision = Pilot::PromotionReadiness.call(shop: @shop).find { |row| row.catalog_product == product }

    assert_equal "block", decision.status
    assert_equal 0, decision.metrics["safe_order_capacity"]
    assert decision.reasons.any? { |reason| reason.include?("M") && reason.include?("out of stock") }
    assert_equal 100, decision.metrics["inventory_units"]
  end

  test "limits uncertain economics and recommends the stronger in-stock substitute" do
    weak, weak_variants = create_product("Weak Kurti", [ 2, 2, 2 ], with_costs: false)
    healthy, healthy_variants = create_product("Healthy Kurti", [ 30, 30, 30 ])
    weak_variants.each { |variant| ingest("product_viewed", weak, variant) }
    healthy_variants.each do |variant|
      2.times { create_paid_order(healthy, variant) }
      2.times { ingest("product_viewed", healthy, variant) }
    end

    decisions = Pilot::PromotionReadiness.call(shop: @shop)
    weak_decision = decisions.find { |row| row.catalog_product == weak }

    assert_equal "limit", weak_decision.status
    assert_nil weak_decision.metrics["promotion_spend_ceiling"]
    assert weak_decision.reasons.any? { |reason| reason.include?("cost") }
    assert_equal healthy.id, weak_decision.metrics["substitute_product_id"]
    assert_equal "Healthy Kurti", weak_decision.metrics["substitute_product_title"]
  end

  test "refund outcome prevents a promote decision" do
    product, variants = create_product("Refunded Kurti", [ 30, 30, 30 ])
    variants.each do |variant|
      2.times { create_paid_order(product, variant) }
      2.times { ingest("product_viewed", product, variant) }
    end
    refunded = @shop.commerce_orders.create!(account: @account, external_id: "refund-order", financial_status: "refunded",
                                             processed_at: Time.current)
    refunded.commerce_order_lines.create!(external_id: "refund-line", product_external_id: product.external_id,
                                          variant_external_id: variants.first.external_id, quantity: 1, price: 3000)

    decision = Pilot::PromotionReadiness.call(shop: @shop).find { |row| row.catalog_product == product }

    assert_equal "limit", decision.status
    assert_operator decision.metrics["refunded_order_rate_percent"], :>, 0
    assert decision.reasons.any? { |reason| reason.include?("Refunded-order") }
  end

  test "replaces stale decisions after a product is removed" do
    product, = create_product("Temporary Kurti", [ 10 ])
    Pilot::PromotionReadiness.call(shop: @shop)
    assert_equal 1, @shop.promotion_decisions.count

    product.destroy!
    Pilot::PromotionReadiness.call(shop: @shop)

    assert_equal 0, @shop.promotion_decisions.count
  end

  private

  def create_product(title, inventory, with_costs: true)
    product = @shop.catalog_products.create!(external_id: "gid://shopify/Product/#{SecureRandom.hex(4)}", title: title, status: "active")
    prices = {}
    variants = %w[S M L].first(inventory.size).each_with_index.map do |size, index|
      variant = product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/#{SecureRandom.hex(5)}",
                                                 title: size, option_summary: size, sku: "#{title.parameterize}-#{size}")
      variant.catalog_inventory_levels.create!(location_external_id: "location-#{index}", available: inventory[index])
      prices[variant.external_id] = { "price" => "3000", "unit_cost" => ("1000" if with_costs), "cost_currency" => "PKR" }
      variant
    end
    product.update!(raw_attrs: { "variant_prices" => prices })
    [ product, variants ]
  end

  def create_paid_order(product, variant)
    external_id = "order-#{SecureRandom.hex(5)}"
    order = @shop.commerce_orders.create!(account: @account, external_id: external_id, financial_status: "paid",
                                          fulfillment_status: "fulfilled", processed_at: Time.current)
    order.commerce_order_lines.create!(external_id: "#{external_id}-line", product_external_id: product.external_id,
                                       variant_external_id: variant.external_id, quantity: 1, price: 3000)
  end

  def ingest(event_name, product, variant)
    Activity::Ingest.call(account: @account, shop: @shop, event_name: event_name, source: "web_pixel",
                          payload: { "product_id" => product.external_id, "variant_id" => variant.external_id })
  end
end
