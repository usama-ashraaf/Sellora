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
    shop = Shop.create!(shopify_domain: "acme.myshopify.com", access_token: "offline-token", scope: "read_products")
    shop.mark_uninstalled!
    assert shop.uninstalled_at.present?
    assert_nil shop.access_token
    assert_not shop.installed?
  end

  test "mark_uninstalled purges catalog rows for the shop" do
    shop = Shop.create!(shopify_domain: "purge.myshopify.com", access_token: "offline-token", scope: "read_products")
    product = shop.catalog_products.create!(external_id: "gid://shopify/Product/1", title: "Tee", status: "active")
    variant = product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/1", sku: "TEE-1")
    variant.catalog_inventory_levels.create!(location_external_id: "gid://shopify/Location/1", available: 4)

    other = Shop.create!(shopify_domain: "other.myshopify.com", access_token: "tok", scope: "read_products")
    other.catalog_products.create!(external_id: "gid://shopify/Product/9", title: "Keep", status: "active")

    shop.mark_uninstalled!

    assert_equal 0, shop.catalog_products.count
    assert_equal 0, CatalogVariant.joins(:catalog_product).where(catalog_products: { shop_id: shop.id }).count
    assert_equal 0, CatalogInventoryLevel.joins(catalog_variant: :catalog_product).where(catalog_products: { shop_id: shop.id }).count
    assert_equal 1, other.catalog_products.count
  end

  test "access_token is encrypted at rest" do
    shop = Shop.create!(shopify_domain: "secure.myshopify.com", access_token: "shpat_secret_value", scope: "read_products")
    raw = Shop.connection.select_value(
      Shop.sanitize_sql_array([ "SELECT access_token FROM shops WHERE id = ?", shop.id ])
    )
    assert raw.present?
    assert_not_equal "shpat_secret_value", raw
    assert_equal "shpat_secret_value", shop.reload.access_token
  end
end
