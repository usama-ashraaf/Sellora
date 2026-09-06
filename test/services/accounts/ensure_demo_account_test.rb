# frozen_string_literal: true

require "test_helper"

class Accounts::EnsureDemoAccountTest < ActiveSupport::TestCase
  test "creates demo account and owner without attaching orphan shops" do
    shop = Shop.create!(shopify_domain: "orphan.myshopify.com", access_token: "t", scope: "read_products")
    assert_nil shop.account_id

    account = Accounts::EnsureDemoAccount.call
    assert_equal Account::DEMO_NAME, account.name
    assert_nil shop.reload.account_id
    assert account.memberships.owners.exists?(email: Accounts::EnsureDemoAccount::DEMO_OWNER_EMAIL)
  end
end
