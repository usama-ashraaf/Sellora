# frozen_string_literal: true

require "test_helper"

class Pilot::RecommendationsTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Pilot Recs")
    @shop = Shop.create!(shopify_domain: "recs.myshopify.com", access_token: "t", account: @account)
    @rules = Audit::ClothingRulesSeed.call
  end

  test "builds recommendations from open findings" do
    product = @shop.catalog_products.create!(external_id: "p1", title: "Hoodie", status: "active")
    %w[S L XL].each_with_index { |size, i| product.catalog_variants.create!(external_id: "v#{i}", title: size, option_summary: size) }
    Audit::Runner.call(shop: @shop, rule_set: @rules)

    recs = Pilot::Recommendations.call(shop: @shop)
    assert recs.any?
    assert @shop.recommendations.open_items.exists?
    assert_equal "availability", @shop.recommendations.where(kind: "availability").first&.kind ||
                                  @shop.recommendations.first.kind
  end

  test "creates a product-specific promotion candidate from views cart and paid order" do
    product = product_with_inventory("p-promo", "Linen Kurta", 10)
    5.times { ingest("product_viewed", product) }
    ingest("product_added_to_cart", product)
    order = @shop.commerce_orders.create!(account: @account, external_id: "o1", financial_status: "paid", processed_at: Time.current)
    order.commerce_order_lines.create!(external_id: "l1", product_external_id: product.external_id, quantity: 1, price: 2200)

    Pilot::Recommendations.call(shop: @shop)
    rec = @shop.recommendations.find_by!(kind: "promotion_opportunity", catalog_product: product)
    assert_equal "high", rec.priority
    assert_equal 5, rec.evidence["product_viewed"]
    assert_equal 1, rec.evidence["paid_orders"]
    assert_match(/No campaign is changed automatically/, rec.suggested_action)
  end

  test "does not promote a product with store-wide views belonging to another product" do
    viewed = product_with_inventory("p-viewed", "Viewed Kurta", 10)
    purchased = product_with_inventory("p-paid", "Paid Kurta", 10)
    5.times { ingest("product_viewed", viewed) }
    ingest("product_added_to_cart", viewed)
    order = @shop.commerce_orders.create!(account: @account, external_id: "o2", financial_status: "paid", processed_at: Time.current)
    order.commerce_order_lines.create!(external_id: "l2", product_external_id: purchased.external_id, quantity: 1, price: 2200)

    Pilot::Recommendations.call(shop: @shop)
    assert_not @shop.recommendations.exists?(kind: "promotion_opportunity")
    assert @shop.recommendations.exists?(kind: "conversion_review", catalog_product: viewed)
  end

  test "dismisses a stale generated signal when current evidence no longer qualifies" do
    product = product_with_inventory("p-stale", "Stale Kurta", 10)
    rec = @shop.recommendations.create!(account: @account, catalog_product: product, kind: "traffic_intent",
                                       priority: "medium", status: "open", title: "Old signal", rationale: "Old evidence")
    Pilot::Recommendations.call(shop: @shop)
    assert_equal "dismissed", rec.reload.status
  end

  private

  def product_with_inventory(external_id, title, available)
    product = @shop.catalog_products.create!(external_id: external_id, title: title, status: "active")
    variant = product.catalog_variants.create!(external_id: "#{external_id}-v", title: "M")
    variant.catalog_inventory_levels.create!(location_external_id: "location-1", available: available)
    product
  end

  def ingest(event_name, product)
    Activity::Ingest.call(account: @account, shop: @shop, event_name: event_name,
                          occurred_at: Time.current, payload: { "product_id" => product.external_id }, source: "web_pixel")
  end
end
