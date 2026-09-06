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
      assert_equal @account.id.to_s, result[:settings]["accountID"]
      assert_equal "https://tunnel.example/web_pixels/events", result[:settings]["ingestUrl"]
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
          "settings" => { "accountID" => @account.id.to_s, "ingestUrl" => "https://old.example/web_pixels/events" }
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

  test "settings_for falls back to shop id when account_id nil" do
    orphan = Shop.create!(
      shopify_domain: "orphan.myshopify.com",
      access_token: "shpat_orphan",
      scope: "write_pixels"
    )
    settings = Shopify::WebPixelRegistrar.settings_for(orphan)
    assert_equal orphan.id.to_s, settings["accountID"]
  end

  private

  def stub_graphql_sequence(payloads)
    queue = payloads.dup
    expected_shop_id = @shop.id
    client = Object.new
    client.define_singleton_method(:graphql) do |_query, _variables = {}|
      raise "unexpected GraphQL call (queue empty)" if queue.empty?

      queue.shift
    end

    original = Shopify::AdminClient.method(:new)
    Shopify::AdminClient.define_singleton_method(:new) do |shop|
      raise "unexpected shop" unless shop.id == expected_shop_id
      client
    end

    yield
  ensure
    Shopify::AdminClient.define_singleton_method(:new, original)
  end
end
