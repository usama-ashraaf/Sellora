# frozen_string_literal: true

require "test_helper"

class Sellora::CatalogParityTest < ActiveSupport::TestCase
  setup do
    @shop_a = Shop.create!(
      shopify_domain: "sellora-test-outfitters-like.myshopify.com",
      access_token: "shpat_parity_a",
      scope: "read_products,read_inventory,read_locations",
      account: Account.create!(name: "Parity Outfitters")
    )
    @shop_b = Shop.create!(
      shopify_domain: "sellora-test-sapphire-like.myshopify.com",
      access_token: "shpat_parity_b",
      scope: "read_products,read_inventory,read_locations",
      account: Account.create!(name: "Parity Sapphire")
    )
  end

  test "reports parity when counts SKUs and shapes match" do
    seed_matching_catalogs!

    result = Sellora::CatalogParity.call(shop_a: @shop_a, shop_b: @shop_b)

    assert result.parity?
    assert_equal @shop_a.shopify_domain, result.shop_a_domain
    assert_equal @shop_b.shopify_domain, result.shop_b_domain
    assert_equal({ products: 2, variants: 2, inventory_levels: 2, skus: 2 }, result.counts_a)
    assert_equal result.counts_a, result.counts_b
    assert_equal [], result.sku_only_a
    assert_equal [], result.sku_only_b
    assert_equal 2, result.sku_shared_count
    assert_empty result.sample_mismatches
  end

  test "reports SKU symmetric difference and sample mismatches" do
    seed_matching_catalogs!
    # Extra SKU only on A
    product_a = @shop_a.catalog_products.first
    only_a = product_a.catalog_variants.create!(
      external_id: "gid://shopify/ProductVariant/only-a",
      sku: "ONLY-A",
      title: "Only A",
      option_summary: "S"
    )
    only_a.catalog_inventory_levels.create!(location_external_id: "gid://shopify/Location/1", available: 1)

    # Shared SKU with inventory mismatch on B
    shared = CatalogVariant.joins(:catalog_product)
      .where(catalog_products: { shop_id: @shop_b.id }, sku: "SF-TEE-S")
      .first
    shared.catalog_inventory_levels.first.update!(available: 99)

    result = Sellora::CatalogParity.call(shop_a: @shop_a, shop_b: @shop_b)

    assert_not result.parity?
    assert_includes result.sku_only_a, "ONLY-A"
    assert_equal [], result.sku_only_b
    assert result.sample_mismatches.any? { |m| m[:sku] == "SF-TEE-S" && m[:diffs].key?(:inventory_sum) }
  end

  test "for_domains loads Wave 1 shops" do
    seed_matching_catalogs!
    result = Sellora::CatalogParity.for_domains
    assert result.parity?
  end

  private

  def seed_matching_catalogs!
    [
      [ @shop_a, "coastal-crew-tee", "Coastal Crew Tee" ],
      [ @shop_b, "meadow-printed-kurti", "Meadow Printed Kurti" ]
    ].each do |shop, handle, title|
      product = shop.catalog_products.create!(
        external_id: "gid://shopify/Product/#{shop.id}-1",
        title: title,
        handle: handle,
        status: "active"
      )
      v1 = product.catalog_variants.create!(
        external_id: "gid://shopify/ProductVariant/#{shop.id}-1",
        sku: "SF-TEE-S",
        title: "S",
        option_summary: "S"
      )
      v1.catalog_inventory_levels.create!(location_external_id: "gid://shopify/Location/1", available: 40)
    end

    [
      [ @shop_a, "harbor-fleece", "Harbor Fleece Hoodie" ],
      [ @shop_b, "atelier-fleece", "Atelier Fleece Jacket" ]
    ].each do |shop, handle, title|
      product = shop.catalog_products.create!(
        external_id: "gid://shopify/Product/#{shop.id}-2",
        title: title,
        handle: handle,
        status: "active"
      )
      v1 = product.catalog_variants.create!(
        external_id: "gid://shopify/ProductVariant/#{shop.id}-2",
        sku: "SF-HOOD-S",
        title: "S",
        option_summary: "S"
      )
      v1.catalog_inventory_levels.create!(location_external_id: "gid://shopify/Location/1", available: 12)
    end
  end
end
