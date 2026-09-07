# frozen_string_literal: true

require "test_helper"

class Shopify::ActionWritesTest < ActiveSupport::TestCase
  setup do
    account = Account.create!(name: "Writes")
    @shop = Shop.create!(
      shopify_domain: "writes.myshopify.com",
      access_token: "t",
      scope: "write_products,write_discounts",
      account: account
    )
    @product = @shop.catalog_products.create!(
      external_id: "gid://shopify/Product/123",
      title: "Old title",
      status: "active",
      raw_attrs: {}
    )
  end

  test "applies an approved product update and stores the returned state" do
    action = reviewed_action!(
      "product_update",
      "product_id" => @product.external_id,
      "title" => "New title"
    )
    response = {
      "productUpdate" => {
        "product" => { "id" => @product.external_id, "title" => "New title", "descriptionHtml" => "<p>Verified</p>", "status" => "ACTIVE" },
        "userErrors" => []
      }
    }

    result = stub_graphql(response) { Shopify::ProductPatch.apply(shop: @shop, action: action) }
    assert_equal "New title", @product.reload.title
    assert_equal "Verified", @product.raw_attrs["description"]
    assert_match(/Updated New title/, result[:message])
  end

  test "creates a product-specific discount code" do
    action = reviewed_action!(
      "discount_code_create",
      "title" => "Sellora promotion",
      "code" => "SELLORA10",
      "percentage" => 10,
      "starts_at" => "2026-09-08T00:00:00Z",
      "ends_at" => "2026-09-15T00:00:00Z",
      "product_ids" => [ @product.external_id ]
    )
    response = {
      "discountCodeBasicCreate" => {
        "codeDiscountNode" => { "id" => "gid://shopify/DiscountCodeNode/1", "codeDiscount" => { "codes" => { "nodes" => [ { "code" => "SELLORA10" } ] } } },
        "userErrors" => []
      }
    }

    result = stub_graphql(response) { Shopify::DiscountCreator.apply(shop: @shop, action: action) }
    assert_equal "gid://shopify/DiscountCodeNode/1", result[:after]["shopify_discount_id"]
    assert_match(/SELLORA10/, result[:message])
  end

  test "does not call Shopify without the required scope" do
    @shop.update!(scope: "read_products")
    action = reviewed_action!("product_update", "product_id" => @product.external_id, "title" => "New title")
    assert_raises(Shopify::ProductPatch::Error) { Shopify::ProductPatch.apply(shop: @shop, action: action) }
  end

  private

  def reviewed_action!(operation, attributes)
    @shop.reviewed_actions.create!(
      account: @shop.account,
      action_kind: operation,
      status: "approved",
      after_snapshot: attributes.merge("operation" => operation)
    )
  end

  def stub_graphql(response)
    client = Shopify::AdminClient
    fake = Object.new
    fake.define_singleton_method(:graphql) { |_query, _variables| response }
    with_singleton_stub(client, :new, ->(_shop) { fake }) { yield }
  end
end
