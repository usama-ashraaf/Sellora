# frozen_string_literal: true

require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "requires name" do
    account = Account.new
    assert_not account.valid?
    assert_includes account.errors[:name], "can't be blank"
  end

  test "demo! is idempotent" do
    a = Account.demo!
    b = Account.demo!
    assert_equal a.id, b.id
    assert_equal Account::DEMO_NAME, a.name
  end

  test "has memberships and shops" do
    account = Account.create!(name: "Acme")
    user = User.create!(email: "owner@example.com", name: "Owner")
    membership = account.memberships.create!(email: user.email, user: user, role: "owner")
    shop = Shop.create!(shopify_domain: "acme-demo.myshopify.com", access_token: "t", scope: "read_products", account: account)

    assert_equal [ membership ], account.memberships.to_a
    assert_equal [ shop ], account.shops.to_a
  end
end
