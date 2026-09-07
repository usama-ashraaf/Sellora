# frozen_string_literal: true

require "test_helper"

class Pilot::CommerceSignalsTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Commerce Signals")
    @shop = Shop.create!(shopify_domain: "signals.myshopify.com", access_token: "t", account: @account)
    @product = @shop.catalog_products.create!(external_id: "gid://shopify/Product/1", title: "Linen Kurta", status: "active")
    variant = @product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/2", title: "M")
    variant.catalog_inventory_levels.create!(location_external_id: "gid://shopify/Location/3", available: 8)
    @product.update!(raw_attrs: { "variant_prices" => {
      variant.external_id => { "price" => "2500", "unit_cost" => "1000", "cost_currency" => "PKR" }
    } })
  end

  test "joins product-level funnel events to authoritative order outcomes" do
    4.times { ingest("product_viewed", "product_id" => @product.external_id) }
    ingest("product_viewed", "product_id" => "1")
    ingest("product_added_to_cart", "product_id" => @product.external_id, "quantity" => 1)
    ingest("checkout_started", "line_items" => [ { "product_id" => @product.external_id, "quantity" => 1 } ])
    ingest("checkout_completed", "line_items" => [ { "product_id" => @product.external_id, "quantity" => 1 } ])
    order = create_order(financial_status: "paid", fulfillment_status: "fulfilled", gateways: [ "Cash on Delivery (COD)" ])
    order.commerce_order_lines.create!(external_id: "line-1", product_external_id: @product.external_id, quantity: 2, price: 2500)

    signals = Pilot::CommerceSignals.call(shop: @shop)
    row = signals[:products].sole

    assert_equal 5, signals[:funnel]["product_viewed"]
    assert_equal 1, signals[:funnel]["checkout_completed"]
    assert_equal 5, row[:product_viewed]
    assert_equal 1, row[:checkout_started]
    assert_equal 1, row[:checkout_completed]
    assert_equal 1, row[:paid_orders]
    assert_equal 2, row[:paid_units]
    assert_equal BigDecimal("5000"), row[:paid_revenue]
    assert_equal 8, row[:inventory]
    assert_equal 1, row[:available_variants]
    assert_equal 1, row[:total_variants]
    assert_equal 100, row[:size_coverage_percent]
    assert_equal [ "M" ], row[:available_sizes]
    assert_empty row[:unavailable_sizes]
    assert_equal 100, row[:cost_coverage_percent]
    assert_equal BigDecimal("60"), row[:minimum_margin_percent]
    assert_equal BigDecimal("20000"), row[:inventory_retail_value]
    assert_equal({ total: 1, paid: 1, pending_payment: 0, cancelled: 0, refunded: 0, fulfilled: 1, cod: 1 }, signals[:order_outcomes])
  end

  test "keeps cancellation and refund outcomes out of paid product sales" do
    cancelled = create_order(external_id: "order-cancelled", financial_status: "paid", cancelled_at: Time.current)
    refunded = create_order(external_id: "order-refunded", financial_status: "refunded")
    [ cancelled, refunded ].each_with_index do |order, index|
      order.commerce_order_lines.create!(external_id: "line-#{index}", product_external_id: @product.external_id, quantity: 1, price: 2500)
    end

    signals = Pilot::CommerceSignals.call(shop: @shop)
    row = signals[:products].sole
    assert_equal 0, row[:paid_orders]
    assert_equal 1, row[:cancelled_orders]
    assert_equal 1, row[:refunded_orders]
    assert_equal 1, signals[:order_outcomes][:cancelled]
    assert_equal 1, signals[:order_outcomes][:refunded]
  end

  private

  def ingest(event_name, payload)
    Activity::Ingest.call(account: @account, shop: @shop, event_name: event_name,
                          occurred_at: Time.current, payload: payload, source: "web_pixel")
  end

  def create_order(external_id: "order-1", financial_status:, fulfillment_status: "unfulfilled", cancelled_at: nil, gateways: [])
    @shop.commerce_orders.create!(
      account: @account, external_id: external_id, financial_status: financial_status,
      fulfillment_status: fulfillment_status, cancelled_at: cancelled_at, processed_at: Time.current,
      raw_attrs: { "payment_gateway_names" => gateways }
    )
  end
end
