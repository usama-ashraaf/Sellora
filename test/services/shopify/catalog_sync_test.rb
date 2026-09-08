# frozen_string_literal: true

require "test_helper"

class Shopify::CatalogSyncTest < ActiveSupport::TestCase
  setup do
    @shop = Shop.create!(
      shopify_domain: "outfitters-like.myshopify.com",
      access_token: "shpat_test_token",
      scope: "read_products,read_inventory,read_locations",
      account: Account.create!(name: "Sync Outfitters")
    )
    @shop_b = Shop.create!(
      shopify_domain: "sapphire-like.myshopify.com",
      access_token: "shpat_test_token_b",
      scope: "read_products,read_inventory,read_locations",
      account: Account.create!(name: "Sync Sapphire")
    )
  end

  test "upserts products variants and inventory from GraphQL pages" do
    pages = [
      [
        product_node(
          id: "gid://shopify/Product/101",
          title: "Linen Kurta",
          handle: "linen-kurta",
          status: "ACTIVE",
          variants: [
            variant_node(
              id: "gid://shopify/ProductVariant/201",
              title: "S / Blue",
              sku: "LK-S-BLU",
              barcode: "111",
              options: [ { "name" => "Size", "value" => "S" }, { "name" => "Color", "value" => "Blue" } ],
              inventory_item_id: "gid://shopify/InventoryItem/301",
              price: "3000.00",
              unit_cost: "1200.00",
              levels: [
                { location: "gid://shopify/Location/1", available: 12 },
                { location: "gid://shopify/Location/2", available: 3 }
              ]
            )
          ]
        )
      ]
    ]

    stub_admin_pages(@shop, pages) do
      result = Shopify::CatalogSync.call(@shop)
      assert_equal 1, result[:products]
    end

    product = @shop.catalog_products.find_by!(external_id: "gid://shopify/Product/101")
    assert_equal "Linen Kurta", product.title
    assert_equal "linen-kurta", product.handle
    assert_equal "active", product.status
    assert_equal "shopify", product.raw_attrs["platform"]
    assert_equal "PKR", product.raw_attrs["currency"]

    variant = product.catalog_variants.find_by!(external_id: "gid://shopify/ProductVariant/201")
    assert_equal "LK-S-BLU", variant.sku
    assert_equal "S / Blue", variant.option_summary
    assert_equal "111", variant.barcode
    assert_equal "gid://shopify/InventoryItem/301", variant.inventory_item_external_id
    assert_equal "1200.00", product.raw_attrs.dig("variant_prices", variant.external_id, "unit_cost")

    levels = variant.catalog_inventory_levels.order(:location_external_id)
    assert_equal 2, levels.size
    assert_equal [ "gid://shopify/Location/1", "gid://shopify/Location/2" ], levels.map(&:location_external_id)
    assert_equal [ 12, 3 ], levels.map(&:available)
  end

  test "extracts only explicitly labeled garment attributes from the product description" do
    node = product_node(
      id: "gid://shopify/Product/attrs",
      title: "Cotton Shirt",
      description_html: "<p>Fit: Slim<br>Fabric: Lawn<br>Piece count: 1<br>Stitched: Yes</p><p>Soft summer shirt.</p>"
    )

    stub_admin_pages(@shop, [ [ node ] ]) { Shopify::CatalogSync.call(@shop) }

    attrs = @shop.catalog_products.find_by!(external_id: node.fetch("id")).raw_attrs.fetch("garment_attrs")
    assert_equal({ "fit" => "Slim", "fabric" => "Lawn", "piece_count" => "1", "stitched" => "Yes" }, attrs)
    assert_not attrs.key?("care")
  end

  test "reconciles removed products and is idempotent on re-sync" do
    pages_v1 = [
      [ product_node(id: "gid://shopify/Product/1", title: "Keep"), product_node(id: "gid://shopify/Product/2", title: "Drop") ]
    ]
    stub_admin_pages(@shop, pages_v1) { Shopify::CatalogSync.call(@shop) }
    assert_equal 2, @shop.catalog_products.count

    pages_v2 = [ [ product_node(id: "gid://shopify/Product/1", title: "Keep Updated") ] ]
    stub_admin_pages(@shop, pages_v2) { Shopify::CatalogSync.call(@shop) }

    assert_equal 1, @shop.catalog_products.count
    product = @shop.catalog_products.find_by!(external_id: "gid://shopify/Product/1")
    assert_equal "Keep Updated", product.title
    assert_nil @shop.catalog_products.find_by(external_id: "gid://shopify/Product/2")

    # Second identical sync stays stable (idempotent upsert).
    stub_admin_pages(@shop, pages_v2) { Shopify::CatalogSync.call(@shop) }
    assert_equal 1, @shop.catalog_products.count
    assert_equal 1, product.catalog_variants.count
  end

  test "fail-closed: empty seen does not wipe existing catalog" do
    pages_v1 = [ [ product_node(id: "gid://shopify/Product/1", title: "Keep Me") ] ]
    stub_admin_pages(@shop, pages_v1) { Shopify::CatalogSync.call(@shop) }
    assert_equal 1, @shop.catalog_products.count

    empty_pages = [ [] ]
    error = assert_raises(Shopify::CatalogSync::EmptySeenError) do
      stub_admin_pages(@shop, empty_pages) { Shopify::CatalogSync.call(@shop) }
    end
    assert_match(/fail-closed/, error.message)

    assert_equal 1, @shop.catalog_products.count
    assert_equal "Keep Me", @shop.catalog_products.find_by!(external_id: "gid://shopify/Product/1").title
  end

  test "fail-closed: unexpected empty page after products aborts without reconcile wipe" do
    pages_v1 = [ [ product_node(id: "gid://shopify/Product/1", title: "A"), product_node(id: "gid://shopify/Product/2", title: "B") ] ]
    stub_admin_pages(@shop, pages_v1) { Shopify::CatalogSync.call(@shop) }
    assert_equal 2, @shop.catalog_products.count

    # First page has one product, second page is unexpectedly empty while more was implied by caller sequence.
    glitched = [
      [ product_node(id: "gid://shopify/Product/1", title: "A") ],
      []
    ]
    assert_raises(Shopify::CatalogSync::EmptySeenError) do
      stub_admin_pages(@shop, glitched) { Shopify::CatalogSync.call(@shop) }
    end

    # Product 2 must still exist — reconcile must not have run a partial wipe.
    assert_equal 2, @shop.catalog_products.count
    assert @shop.catalog_products.exists?(external_id: "gid://shopify/Product/2")
  end

  test "empty remote catalog on empty local shop is a no-op" do
    stub_admin_pages(@shop, [ [] ]) do
      result = Shopify::CatalogSync.call(@shop)
      assert_equal 0, result[:products]
    end
    assert_equal 0, @shop.catalog_products.count
  end

  test "dual-shop sync keeps same external ids isolated per shop for regression compare" do
    shared_shape = [
      [
        product_node(
          id: "gid://shopify/Product/9001",
          title: "Shared Shape Tee",
          handle: "shared-shape-tee",
          variants: [
            variant_node(
              id: "gid://shopify/ProductVariant/9002",
              title: "M",
              sku: "SST-M",
              options: [ { "name" => "Size", "value" => "M" } ],
              inventory_item_id: "gid://shopify/InventoryItem/9003",
              levels: [ { location: "gid://shopify/Location/10", available: 5 } ]
            )
          ]
        )
      ]
    ]

    stub_admin_pages(@shop, shared_shape) { Shopify::CatalogSync.call(@shop) }
    stub_admin_pages(@shop_b, shared_shape) { Shopify::CatalogSync.call(@shop_b) }

    a = @shop.catalog_products.find_by!(external_id: "gid://shopify/Product/9001")
    b = @shop_b.catalog_products.find_by!(external_id: "gid://shopify/Product/9001")
    assert_not_equal a.id, b.id

    shape_a = catalog_shape_for(@shop)
    shape_b = catalog_shape_for(@shop_b)
    assert_equal shape_a, shape_b, "Wave 1 dual-shop regression: catalog shapes should match across shops"
  end

  test "raises when shop is not installed" do
    @shop.mark_uninstalled!
    assert_raises(Shopify::CatalogSync::Error) { Shopify::CatalogSync.call(@shop) }
  end

  private

  def catalog_shape_for(shop)
    shop.catalog_products.order(:external_id).map do |p|
      {
        external_id: p.external_id,
        title: p.title,
        handle: p.handle,
        status: p.status,
        variants: p.catalog_variants.order(:external_id).map do |v|
          {
            external_id: v.external_id,
            sku: v.sku,
            option_summary: v.option_summary,
            inventory_item_external_id: v.inventory_item_external_id,
            levels: v.catalog_inventory_levels.order(:location_external_id).map do |l|
              { location_external_id: l.location_external_id, available: l.available }
            end
          }
        end
      }
    end
  end

  def product_node(id:, title:, handle: "handle", status: "ACTIVE", variants: nil, description_html: nil)
    variants ||= [
      variant_node(
        id: "#{id}-v1",
        title: "Default Title",
        sku: nil,
        options: [ { "name" => "Title", "value" => "Default Title" } ],
        inventory_item_id: "#{id}-ii",
        levels: [ { location: "gid://shopify/Location/1", available: 0 } ]
      )
    ]
    {
      "id" => id,
      "title" => title,
      "handle" => handle,
      "status" => status,
      "descriptionHtml" => description_html,
      "variants" => { "nodes" => variants }
    }
  end

  def variant_node(id:, title:, sku:, inventory_item_id:, levels:, options: [], barcode: nil, price: nil, unit_cost: nil)
    {
      "id" => id,
      "title" => title,
      "sku" => sku,
      "barcode" => barcode,
      "price" => price,
      "selectedOptions" => options,
      "inventoryItem" => {
        "id" => inventory_item_id,
        "unitCost" => unit_cost && { "amount" => unit_cost, "currencyCode" => "PKR" },
        "inventoryLevels" => {
          "nodes" => levels.map do |lvl|
            {
              "location" => { "id" => lvl[:location] },
              "quantities" => [ { "name" => "available", "quantity" => lvl[:available] } ]
            }
          end
        }
      }
    }
  end

  def stub_admin_pages(shop, pages)
    client = Object.new
    page_enum = pages.each
    client.define_singleton_method(:each_product_page) do |&block|
      page_enum.each { |nodes| block.call(nodes) }
    end
    client.define_singleton_method(:shop_currency) { "PKR" }

    original = Shopify::AdminClient.method(:new)
    Shopify::AdminClient.define_singleton_method(:new) do |s|
      raise "unexpected shop" unless s.id == shop.id
      client
    end

    yield
  ensure
    Shopify::AdminClient.define_singleton_method(:new, original)
  end
end
