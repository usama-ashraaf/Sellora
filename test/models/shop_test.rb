# frozen_string_literal: true

require "test_helper"

class ShopTest < ActiveSupport::TestCase
  test "normalize_domain strips protocol and path" do
    assert_equal "acme.myshopify.com", Shop.normalize_domain("https://Acme.myshopify.com/admin")
  end

  test "rejects invalid domains" do
    shop = Shop.new(shopify_domain: "not-a-shop.com", access_token: "x")
    assert_not shop.valid?
  end

  test "mark_uninstalled clears token" do
    shop = Shop.create!(shopify_domain: "acme.myshopify.com", access_token: "offline-token", scope: "read_products")
    shop.mark_uninstalled!
    assert shop.uninstalled_at.present?
    assert_nil shop.access_token
    assert_not shop.installed?
  end
end
