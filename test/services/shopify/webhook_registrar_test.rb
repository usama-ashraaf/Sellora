# frozen_string_literal: true

require "test_helper"

class Shopify::WebhookRegistrarTest < ActiveSupport::TestCase
  setup do
    ENV["SHOPIFY_APP_URL"] = "https://tunnel.example"
    @shop = Shop.create!(
      shopify_domain: "outfitters-like.myshopify.com",
      access_token: "shpat_test_token",
      scope: "read_products,read_inventory,read_locations"
    )
  end

  teardown do
    ENV.delete("SHOPIFY_APP_URL")
  end

  test "creates all Phase A topics when none exist" do
    responses = [
      list_payload([]),
      *Shopify::WebhookRegistrar::PHASE_A_TOPICS.keys.map { |topic| create_payload(topic) }
    ]

    stub_graphql_sequence(responses) do
      result = Shopify::WebhookRegistrar.call(@shop)
      assert_equal @shop.id, result[:shop_id]
      assert_equal 5, result[:subscriptions].size
      assert result[:subscriptions].all? { |s| s[:status] == :created }
      topics = result[:subscriptions].map { |s| s[:topic] }
      assert_equal Shopify::WebhookRegistrar::PHASE_A_TOPICS.keys, topics
      assert_equal(
        "https://tunnel.example/webhooks/shopify/products_create",
        result[:subscriptions].first[:uri]
      )
    end
  end

  test "is idempotent when topics already point at app_url paths" do
    existing = Shopify::WebhookRegistrar::PHASE_A_TOPICS.map do |topic, path|
      {
        "id" => "gid://shopify/WebhookSubscription/#{topic}",
        "topic" => topic,
        "uri" => Shopify::WebhookRegistrar.callback_uri_for(path)
      }
    end

    stub_graphql_sequence([ list_payload(existing) ]) do
      result = Shopify::WebhookRegistrar.call(@shop)
      assert_equal 5, result[:subscriptions].size
      assert result[:subscriptions].all? { |s| s[:status] == :already_registered }
    end
  end

  test "updates subscription when URI drifted from current app_url" do
    existing = [
      {
        "id" => "gid://shopify/WebhookSubscription/1",
        "topic" => "PRODUCTS_CREATE",
        "uri" => "https://old-tunnel.example/webhooks/shopify/products_create"
      }
    ]
    # Remaining Phase A topics absent → create; PRODUCTS_CREATE → update
    responses = [
      list_payload(existing),
      update_payload("PRODUCTS_CREATE", "gid://shopify/WebhookSubscription/1"),
      *%w[PRODUCTS_UPDATE PRODUCTS_DELETE INVENTORY_LEVELS_UPDATE APP_UNINSTALLED].map { |t| create_payload(t) }
    ]

    stub_graphql_sequence(responses) do
      result = Shopify::WebhookRegistrar.call(@shop)
      by_topic = result[:subscriptions].index_by { |s| s[:topic] }
      assert_equal :updated, by_topic["PRODUCTS_CREATE"][:status]
      assert_equal "https://tunnel.example/webhooks/shopify/products_create", by_topic["PRODUCTS_CREATE"][:uri]
      assert_equal :created, by_topic["PRODUCTS_UPDATE"][:status]
    end
  end

  test "treats already-taken userErrors as already_registered when URI matches" do
    responses = [
      list_payload([]),
      {
        "webhookSubscriptionCreate" => {
          "webhookSubscription" => nil,
          "userErrors" => [ { "field" => [ "webhookSubscription" ], "message" => "Address for this topic has already been taken" } ]
        }
      },
      # re-list inside create_subscription!
      list_payload([
        {
          "id" => "gid://shopify/WebhookSubscription/99",
          "topic" => "PRODUCTS_CREATE",
          "uri" => "https://tunnel.example/webhooks/shopify/products_create"
        }
      ]),
      *%w[PRODUCTS_UPDATE PRODUCTS_DELETE INVENTORY_LEVELS_UPDATE APP_UNINSTALLED].map { |t| create_payload(t) }
    ]

    stub_graphql_sequence(responses) do
      result = Shopify::WebhookRegistrar.call(@shop)
      assert_equal :already_registered, result[:subscriptions].first[:status]
      assert_equal "gid://shopify/WebhookSubscription/99", result[:subscriptions].first[:id]
    end
  end

  test "raises on non-idempotent userErrors" do
    responses = [
      list_payload([]),
      {
        "webhookSubscriptionCreate" => {
          "webhookSubscription" => nil,
          "userErrors" => [ { "field" => [ "uri" ], "message" => "URI is invalid" } ]
        }
      }
    ]

    error = assert_raises(Shopify::WebhookRegistrar::Error) do
      stub_graphql_sequence(responses) { Shopify::WebhookRegistrar.call(@shop) }
    end
    assert_match(/URI is invalid/, error.message)
  end

  test "callback_uri_for uses ShopifyConfig.app_url" do
    assert_equal(
      "https://tunnel.example/webhooks/shopify/app_uninstalled",
      Shopify::WebhookRegistrar.callback_uri_for("app_uninstalled")
    )
  end

  private

  def list_payload(nodes)
    {
      "webhookSubscriptions" => {
        "pageInfo" => { "hasNextPage" => false, "endCursor" => nil },
        "nodes" => nodes
      }
    }
  end

  def create_payload(topic)
    path = Shopify::WebhookRegistrar::PHASE_A_TOPICS.fetch(topic)
    {
      "webhookSubscriptionCreate" => {
        "webhookSubscription" => {
          "id" => "gid://shopify/WebhookSubscription/#{topic}",
          "topic" => topic,
          "uri" => Shopify::WebhookRegistrar.callback_uri_for(path)
        },
        "userErrors" => []
      }
    }
  end

  def update_payload(topic, id)
    path = Shopify::WebhookRegistrar::PHASE_A_TOPICS.fetch(topic)
    {
      "webhookSubscriptionUpdate" => {
        "webhookSubscription" => {
          "id" => id,
          "topic" => topic,
          "uri" => Shopify::WebhookRegistrar.callback_uri_for(path)
        },
        "userErrors" => []
      }
    }
  end

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
