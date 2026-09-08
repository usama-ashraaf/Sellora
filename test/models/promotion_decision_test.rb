# frozen_string_literal: true

require "test_helper"

class PromotionDecisionTest < ActiveSupport::TestCase
  test "rejects cross-shop products and accounts" do
    account = Account.create!(name: "Decision Account")
    other_account = Account.create!(name: "Other Decision Account")
    shop = Shop.create!(shopify_domain: "decision.myshopify.com", access_token: "t", account: account)
    other_shop = Shop.create!(shopify_domain: "other-decision.myshopify.com", access_token: "t", account: other_account)
    other_product = other_shop.catalog_products.create!(external_id: "other-product", title: "Other")
    decision = PromotionDecision.new(shop: shop, account: other_account, catalog_product: other_product,
                                     status: "unknown", score: 101, confidence: "certain", generated_at: Time.current)

    assert_not decision.valid?
    assert_includes decision.errors[:account_id], "must match shop account"
    assert_includes decision.errors[:catalog_product_id], "must belong to shop"
    assert decision.errors[:status].any?
    assert decision.errors[:score].any?
    assert decision.errors[:confidence].any?
  end
end
