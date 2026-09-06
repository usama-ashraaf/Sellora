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

  test "shop may be created without account then assigned" do
    shop = Shop.create!(shopify_domain: "nullable.myshopify.com", access_token: "t", scope: "read_products")
    assert_nil shop.account_id
    account = Account.demo!
    shop.update!(account: account)
    assert_equal account.id, shop.reload.account_id
  end
end
