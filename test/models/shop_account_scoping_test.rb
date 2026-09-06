# frozen_string_literal: true

require "test_helper"

class ShopAccountScopingTest < ActiveSupport::TestCase
  test "for_account scopes shops" do
    a = Account.create!(name: "A")
    b = Account.create!(name: "B")
    shop_a = Shop.create!(shopify_domain: "scope-a.myshopify.com", access_token: "t", scope: "read_products", account: a)
    Shop.create!(shopify_domain: "scope-b.myshopify.com", access_token: "t", scope: "read_products", account: b)

    assert_equal [ shop_a ], Shop.for_account(a).to_a
  end

  test "shop requires an account" do
    shop = Shop.new(shopify_domain: "nullable.myshopify.com", access_token: "t", scope: "read_products")
    assert_not shop.valid?
    assert_includes shop.errors[:account], "must exist"
  end
end
