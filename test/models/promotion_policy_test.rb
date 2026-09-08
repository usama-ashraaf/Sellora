# frozen_string_literal: true

require "test_helper"

class PromotionPolicyTest < ActiveSupport::TestCase
  test "requires bounded assumptions and the shop account" do
    account = Account.create!(name: "Policy Account")
    other = Account.create!(name: "Other Account")
    shop = Shop.create!(shopify_domain: "policy-validation.myshopify.com", access_token: "t", account: account)
    policy = PromotionPolicy.new(shop: shop, account: other, target_roas: 0, expected_cod_failure_rate_percent: 101,
                                 desired_runway_days: 0, minimum_margin_percent: 101, minimum_safe_orders: 0)

    assert_not policy.valid?
    assert_includes policy.errors[:account_id], "must match shop account"
    assert policy.errors[:target_roas].any?
    assert policy.errors[:expected_cod_failure_rate_percent].any?
    assert policy.errors[:desired_runway_days].any?
    assert policy.errors[:minimum_margin_percent].any?
    assert policy.errors[:minimum_safe_orders].any?
  end
end
