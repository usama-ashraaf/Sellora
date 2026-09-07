# frozen_string_literal: true

require "test_helper"

class Shopify::WebPixelRegistrarTest < ActiveSupport::TestCase
  setup do
    ENV["SHOPIFY_APP_URL"] = "https://tunnel.example"
    @account = Account.create!(name: "Pixel Merchant")
    @shop = Shop.create!(
      shopify_domain: "outfitters-like.myshopify.com",
      access_token: "shpat_test_token",
      scope: "read_products,read_inventory,read_locations,write_pixels,read_customer_events",
      account: @account
    )
  end

  teardown do
    ENV.delete("SHOPIFY_APP_URL")
  end

  test "creates web pixel when none exists" do
    desired = Shopify::WebPixelRegistrar.settings_for(@shop)
    responses = [
      { "webPixel" => nil },
      {
        "webPixelCreate" => {
          "webPixel" => { "id" => "gid://shopify/WebPixel/1", "settings" => desired },
          "userErrors" => []
        }
      }
    ]

    stub_graphql_sequence(responses) do
      result = Shopify::WebPixelRegistrar.call(@shop)
      assert_equal @shop.id, result[:shop_id]
      assert_equal :created, result[:status]
      assert_equal "gid://shopify/WebPixel/1", result[:id]
      assert_equal desired, result[:settings]
      assert_not_includes result[:settings], "accountID"
      assert_equal @shop.shopify_domain, result[:settings]["shopDomain"]
      assert_equal "https://tunnel.example/web_pixels/events", result[:settings]["ingestUrl"]
      assert_equal Activity::PixelToken.issue(@shop), result[:settings]["ingestToken"]
    end
  end

  test "is idempotent when settings already match" do
    desired = Shopify::WebPixelRegistrar.settings_for(@shop)
    responses = [
      { "webPixel" => { "id" => "gid://shopify/WebPixel/9", "settings" => desired.to_json } }
    ]

    stub_graphql_sequence(responses) do
      result = Shopify::WebPixelRegistrar.call(@shop)
      assert_equal :already_registered, result[:status]
      assert_equal "gid://shopify/WebPixel/9", result[:id]
    end
  end

  test "updates when ingestUrl drifted" do
    desired = Shopify::WebPixelRegistrar.settings_for(@shop)
    responses = [
      {
        "webPixel" => {
          "id" => "gid://shopify/WebPixel/2",
          "settings" => { "ingestUrl" => "https://old.example/web_pixels/events" }
        }
      },
      {
        "webPixelUpdate" => {
          "webPixel" => { "id" => "gid://shopify/WebPixel/2", "settings" => desired },
          "userErrors" => []
        }
      }
    ]

    stub_graphql_sequence(responses) do
      result = Shopify::WebPixelRegistrar.call(@shop)
      assert_equal :updated, result[:status]
      assert_equal "gid://shopify/WebPixel/2", result[:id]
      assert_equal desired["ingestUrl"], result[:settings]["ingestUrl"]
    end
  end

  test "raises on non-idempotent userErrors" do
    responses = [
      { "webPixel" => nil },
      {
        "webPixelCreate" => {
          "webPixel" => nil,
          "userErrors" => [ { "field" => [ "settings" ], "message" => "INVALID_SETTINGS", "code" => "INVALID_SETTINGS" } ]
        }
      }
    ]

    error = assert_raises(Shopify::WebPixelRegistrar::Error) do
      stub_graphql_sequence(responses) { Shopify::WebPixelRegistrar.call(@shop) }
    end
    assert_match(/INVALID_SETTINGS/, error.message)
  end

  test "treats missing web pixel GraphQL error as create path" do
    desired = Shopify::WebPixelRegistrar.settings_for(@shop)
    responses = [
      :missing_pixel_error,
      {
        "webPixelCreate" => {
          "webPixel" => { "id" => "gid://shopify/WebPixel/3", "settings" => desired.to_json },
          "userErrors" => []
        }
      }
    ]

    stub_graphql_sequence(responses) do
      result = Shopify::WebPixelRegistrar.call(@shop)
      assert_equal :created, result[:status]
      assert_equal "gid://shopify/WebPixel/3", result[:id]
    end
  end

  test "settings never expose account identifiers" do
    orphan = Shop.create!(
      shopify_domain: "orphan.myshopify.com",
      access_token: "shpat_orphan",
      scope: "write_pixels",
      account: Account.create!(name: "Orphan Temp")
    )
    orphan.update_columns(account_id: nil)
    settings = Shopify::WebPixelRegistrar.settings_for(orphan)
    assert_not_includes settings, "accountID"
    assert_equal orphan.shopify_domain, settings["shopDomain"]
  end

  private

  ORIGINAL_ADMIN_CLIENT_NEW = Shopify::AdminClient.method(:new)

  def stub_graphql_sequence(payloads)
    queue = payloads.dup
    expected_shop_id = @shop.id
    client = Object.new
    client.define_singleton_method(:graphql) do |_query, _variables = {}|
      raise "unexpected GraphQL call (queue empty)" if queue.empty?

      next_payload = queue.shift
      if next_payload == :missing_pixel_error
        raise Shopify::AdminClient::Error, "Admin API GraphQL errors: No web pixel was found for this app."
      end

      next_payload
    end

    Shopify::AdminClient.define_singleton_method(:new) do |shop|
      raise "unexpected shop" unless shop.id == expected_shop_id
      client
    end

    yield
  ensure
    Shopify::AdminClient.define_singleton_method(:new, ORIGINAL_ADMIN_CLIENT_NEW)
  end
end
