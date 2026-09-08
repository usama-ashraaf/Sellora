# frozen_string_literal: true

require "test_helper"

class Shopify::OrderSyncJobTest < ActiveJob::TestCase
  test "refreshes recommendations after an order webhook sync" do
    account = Account.create!(name: "Webhook Recommendations")
    shop = Shop.create!(shopify_domain: "order-job.myshopify.com", access_token: "t", account: account)
    product = shop.catalog_products.create!(external_id: "p1", title: "Kurta", status: "active")
    variant = product.catalog_variants.create!(external_id: "v1", title: "M")
    variant.catalog_inventory_levels.create!(location_external_id: "l1", available: 4)
    5.times do
      Activity::Ingest.call(account: account, shop: shop, event_name: "product_viewed",
                            occurred_at: Time.current, payload: { "product_id" => product.external_id }, source: "web_pixel")
    end
    Activity::Ingest.call(account: account, shop: shop, event_name: "product_added_to_cart",
                          occurred_at: Time.current, payload: { "product_id" => product.external_id }, source: "web_pixel")

    original = Shopify::OrderSync.method(:call)
    Shopify::OrderSync.define_singleton_method(:call, lambda { |_shop|
      order = shop.commerce_orders.create!(account: account, external_id: "o1", financial_status: "paid", processed_at: Time.current)
      order.commerce_order_lines.create!(external_id: "line1", product_external_id: product.external_id, quantity: 1)
    })
    Shopify::OrderSyncJob.perform_now(shop.id)

    assert shop.recommendations.exists?(kind: "promotion_opportunity", catalog_product: product)
    assert shop.promotion_decisions.exists?(catalog_product: product)
  ensure
    Shopify::OrderSync.define_singleton_method(:call, original) if original
  end
end
