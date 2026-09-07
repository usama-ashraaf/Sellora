# frozen_string_literal: true

require "test_helper"
require "base64"
require "openssl"

class Webhooks::ShopifyPrivacyControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @secret = "privacy-secret"
    ENV["SHOPIFY_API_SECRET"] = @secret
    @shop = Shop.create!(shopify_domain: "privacy.myshopify.com", access_token: "token", account: Account.create!(name: "Privacy"))
  end

  teardown { ENV.delete("SHOPIFY_API_SECRET") }

  test "rejects an invalid signature" do
    post shopify_webhooks_privacy_path, params: {}.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "X-Shopify-Hmac-Sha256" => "invalid" }
    assert_response :unauthorized
  end

  test "acknowledges customer privacy requests without storing payload data" do
    body = { shop_domain: @shop.shopify_domain, customer: { id: 123, email: "private@example.com" } }.to_json
    post shopify_webhooks_privacy_path, params: body, headers: headers(body, "customers/data_request", "privacy-1")

    assert_response :ok
    event = WebhookEvent.find_by!(event_key: "id:privacy-1")
    assert_equal "customers/data_request", event.topic
    assert_not_includes event.attributes.to_json, "private@example.com"
  end

  test "queues shop redaction once" do
    body = { shop_domain: @shop.shopify_domain }.to_json
    request_headers = headers(body, "shop/redact", "privacy-redact")

    assert_enqueued_jobs 1, only: Shopify::ShopRedactionJob do
      post shopify_webhooks_privacy_path, params: body, headers: request_headers
      post shopify_webhooks_privacy_path, params: body, headers: request_headers
    end
    assert_response :ok
  end

  test "shop redaction removes the shop and its webhook ledger" do
    WebhookEvent.create!(shopify_domain: @shop.shopify_domain, topic: "orders/create", event_key: "old-shop-data",
                         processed_at: Time.current)

    Shopify::ShopRedactionJob.perform_now(@shop.shopify_domain)

    assert_not Shop.exists?(@shop.id)
    assert_not WebhookEvent.exists?(shopify_domain: @shop.shopify_domain)
  end

  private

  def headers(body, topic, id)
    {
      "CONTENT_TYPE" => "application/json",
      "X-Shopify-Hmac-Sha256" => Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @secret, body)),
      "X-Shopify-Shop-Domain" => @shop.shopify_domain,
      "X-Shopify-Topic" => topic,
      "X-Shopify-Webhook-Id" => id
    }
  end
end
