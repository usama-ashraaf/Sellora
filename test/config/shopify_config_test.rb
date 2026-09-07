# frozen_string_literal: true

require "test_helper"

class ShopifyConfigTest < ActiveSupport::TestCase
  teardown do
    ENV.delete("SHOPIFY_SCOPES")
  end

  test "ALLOWED_SCOPES includes Phase A pixel Phase B and Phase C write_products" do
    assert_equal %w[read_products read_inventory read_locations], ShopifyConfig::PHASE_A_SCOPES
    assert_equal %w[write_pixels read_customer_events], ShopifyConfig::PIXEL_SCOPES
    assert_equal %w[read_orders], ShopifyConfig::PHASE_B_SCOPES
    assert_equal %w[write_products write_discounts], ShopifyConfig::PHASE_C_SCOPES
    assert_equal(
      %w[read_products read_inventory read_locations write_pixels read_customer_events read_orders write_products write_discounts],
      ShopifyConfig::ALLOWED_SCOPES
    )
  end

  test "scopes defaults to ALLOWED_SCOPES" do
    ENV.delete("SHOPIFY_SCOPES")
    scopes = ShopifyConfig.parse_scopes(ShopifyConfig.scopes)
    assert_equal ShopifyConfig::ALLOWED_SCOPES, scopes
  end

  test "scopes clamps ENV to ALLOWED_SCOPES" do
    ENV["SHOPIFY_SCOPES"] = "read_products,write_products,write_pixels,read_orders,write_orders"
    scopes = ShopifyConfig.parse_scopes(ShopifyConfig.scopes)
    assert_includes scopes, "read_products"
    assert_includes scopes, "write_pixels"
    assert_includes scopes, "read_orders"
    assert_includes scopes, "write_products"
    refute_includes scopes, "write_orders"
  end

  test "allowed_scopes_subset? accepts Phase C write_products and rejects write_orders" do
    assert ShopifyConfig.allowed_scopes_subset?("read_products,write_pixels,read_customer_events")
    assert ShopifyConfig.allowed_scopes_subset?("read_products,read_orders,write_products")
    refute ShopifyConfig.allowed_scopes_subset?("read_products,write_orders")
  end
end
