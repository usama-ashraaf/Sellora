# frozen_string_literal: true

require "test_helper"

class ShopifyConfigTest < ActiveSupport::TestCase
  teardown do
    ENV.delete("SHOPIFY_SCOPES")
  end

  test "ALLOWED_SCOPES is Phase A plus pixel" do
    assert_equal %w[read_products read_inventory read_locations], ShopifyConfig::PHASE_A_SCOPES
    assert_equal %w[write_pixels read_customer_events], ShopifyConfig::PIXEL_SCOPES
    assert_equal(
      %w[read_products read_inventory read_locations write_pixels read_customer_events],
      ShopifyConfig::ALLOWED_SCOPES
    )
  end

  test "scopes defaults to ALLOWED_SCOPES" do
    ENV.delete("SHOPIFY_SCOPES")
    scopes = ShopifyConfig.parse_scopes(ShopifyConfig.scopes)
    assert_equal ShopifyConfig::ALLOWED_SCOPES, scopes
  end

  test "scopes clamps ENV to ALLOWED_SCOPES and drops Phase B/C" do
    ENV["SHOPIFY_SCOPES"] = "read_products,write_products,write_pixels,read_orders"
    scopes = ShopifyConfig.parse_scopes(ShopifyConfig.scopes)
    assert_includes scopes, "read_products"
    assert_includes scopes, "write_pixels"
    refute_includes scopes, "write_products"
    refute_includes scopes, "read_orders"
  end

  test "allowed_scopes_subset? accepts pixel pair and rejects write_products" do
    assert ShopifyConfig.allowed_scopes_subset?("read_products,write_pixels,read_customer_events")
    assert ShopifyConfig.phase_a_scopes_subset?("read_products,read_inventory,read_locations")
    refute ShopifyConfig.allowed_scopes_subset?("read_products,write_products")
    refute ShopifyConfig.allowed_scopes_subset?("read_orders")
  end
end
