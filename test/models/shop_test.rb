# frozen_string_literal: true

require "test_helper"

class ShopTest < ActiveSupport::TestCase
  test "normalize_domain strips protocol and path" do
    assert_equal "acme.myshopify.com", Shop.normalize_domain("https://Acme.myshopify.com/admin")
  end

  test "rejects invalid domains" do
    shop = Shop.new(shopify_domain: "not-a-shop.com", access_token: "x")
    assert_not shop.valid?
  end

  test "mark_uninstalled clears token" do
    shop = Shop.create!(shopify_domain: "acme.myshopify.com", access_token: "offline-token", scope: "read_products", account: Account.create!(name: "Acme Uninstall"))
    shop.mark_uninstalled!
    assert shop.uninstalled_at.present?
    assert_nil shop.access_token
    assert_not shop.installed?
  end

  test "mark_uninstalled purges catalog rows for the shop" do
    shop = Shop.create!(shopify_domain: "purge.myshopify.com", access_token: "offline-token", scope: "read_products", account: Account.create!(name: "Purge Shop"))
    product = shop.catalog_products.create!(external_id: "gid://shopify/Product/1", title: "Tee", status: "active")
    variant = product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/1", sku: "TEE-1")
    variant.catalog_inventory_levels.create!(location_external_id: "gid://shopify/Location/1", available: 4)

    other = Shop.create!(shopify_domain: "other.myshopify.com", access_token: "tok", scope: "read_products", account: Account.create!(name: "Other Shop"))
    other.catalog_products.create!(external_id: "gid://shopify/Product/9", title: "Keep", status: "active")

    shop.mark_uninstalled!

    assert_equal 0, shop.catalog_products.count
    assert_equal 0, CatalogVariant.joins(:catalog_product).where(catalog_products: { shop_id: shop.id }).count
    assert_equal 0, CatalogInventoryLevel.joins(catalog_variant: :catalog_product).where(catalog_products: { shop_id: shop.id }).count
    assert_equal 1, other.catalog_products.count
  end

  test "mark_uninstalled purges findings and activity events for the shop" do
    account = Account.create!(name: "Uninstall Privacy")
    shop = Shop.create!(shopify_domain: "privacy-purge.myshopify.com", access_token: "offline-token", account: account)
    other = Shop.create!(shopify_domain: "privacy-keep.myshopify.com", access_token: "tok", account: account)
    rules = Audit::ClothingRulesSeed.call
    product = shop.catalog_products.create!(external_id: "p-1", title: "Shirt")
    AuditFinding.create!(
      account: account, shop: shop, catalog_product: product,
      audit_rule: rules.audit_rules.first, severity: "medium", message: "Missing size"
    )
    Activity::Ingest.call(account: account, shop: shop, event_name: "page_viewed", source: "web_pixel", payload: { "id" => "a" })
    Activity::Ingest.call(account: account, shop: other, event_name: "page_viewed", source: "web_pixel", payload: { "id" => "b" })

    shop.mark_uninstalled!

    assert_equal 0, shop.audit_findings.count
    assert_equal 0, shop.activity_events.count
    assert_equal 1, other.activity_events.count
  end

  test "mark_uninstalled purges promotion assumptions and decisions" do
    account = Account.create!(name: "Promotion Privacy")
    shop = Shop.create!(shopify_domain: "promotion-privacy.myshopify.com", access_token: "offline-token", account: account)
    product = shop.catalog_products.create!(external_id: "product-1", title: "Shirt")
    shop.create_promotion_policy!(account: account)
    shop.promotion_decisions.create!(account: account, catalog_product: product, status: "limit", score: 50,
                                     confidence: "low", generated_at: Time.current)

    shop.mark_uninstalled!

    assert_nil shop.reload.promotion_policy
    assert_equal 0, shop.promotion_decisions.reload.count
  end

  test "access_token is encrypted at rest" do
    shop = Shop.create!(shopify_domain: "secure.myshopify.com", access_token: "shpat_secret_value", scope: "read_products", account: Account.create!(name: "Secure Shop"))
    raw = Shop.connection.select_value(
      Shop.sanitize_sql_array([ "SELECT access_token FROM shops WHERE id = ?", shop.id ])
    )
    assert raw.present?
    assert_not_equal "shpat_secret_value", raw
    assert_equal "shpat_secret_value", shop.reload.access_token
  end
end
