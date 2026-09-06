# frozen_string_literal: true

require "test_helper"

class CatalogProductTest < ActiveSupport::TestCase
  setup do
    @shop_a = Shop.create!(shopify_domain: "a.myshopify.com", access_token: "t1", scope: "read_products", account: Account.create!(name: "Catalog A"))
    @shop_b = Shop.create!(shopify_domain: "b.myshopify.com", access_token: "t2", scope: "read_products", account: Account.create!(name: "Catalog B"))
  end

  test "same external_id allowed across shops unique within shop" do
    CatalogProduct.create!(shop: @shop_a, external_id: "gid://shopify/Product/1", title: "Tee", status: "active")
    CatalogProduct.create!(shop: @shop_b, external_id: "gid://shopify/Product/1", title: "Tee", status: "active")

    dup = CatalogProduct.new(shop: @shop_a, external_id: "gid://shopify/Product/1", title: "Other", status: "active")
    assert_not dup.valid?
    assert_includes dup.errors[:external_id], "has already been taken"
  end
end
