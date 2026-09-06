# frozen_string_literal: true

require "test_helper"

class Activity::PixelTokenTest < ActiveSupport::TestCase
  setup do
    @shop = Shop.create!(
      shopify_domain: "token-shop.myshopify.com",
      access_token: "t",
      account: Account.create!(name: "Token Shop")
    )
  end

  test "issue and resolve round-trip for installed shop" do
    token = Activity::PixelToken.issue(@shop)
    assert_equal @shop.id, Activity::PixelToken.resolve(token).id
  end

  test "resolve rejects blank, oversized, tampered, uninstalled, and rotated tokens" do
    token = Activity::PixelToken.issue(@shop)
    assert_nil Activity::PixelToken.resolve(nil)
    assert_nil Activity::PixelToken.resolve("")
    assert_nil Activity::PixelToken.resolve("x" * 2049)
    assert_nil Activity::PixelToken.resolve("#{token}tamper")

    @shop.mark_uninstalled!
    assert_nil Activity::PixelToken.resolve(token)

    @shop.update!(access_token: "t", uninstalled_at: nil, updated_at: Time.current + 1.second)
    assert_nil Activity::PixelToken.resolve(token)
    assert_equal @shop.id, Activity::PixelToken.resolve(Activity::PixelToken.issue(@shop)).id
  end

  test "resolve rejects shop without account" do
    orphan = Shop.create!(shopify_domain: "orphan-token.myshopify.com", access_token: "t", account: Account.create!(name: "Temp Token"))
    token = Activity::PixelToken.issue(orphan)
    orphan.update_columns(account_id: nil)
    assert_nil Activity::PixelToken.resolve(token)
  end
end
