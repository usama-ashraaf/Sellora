# frozen_string_literal: true

require "test_helper"
require "base64"
require "openssl"

class Webhooks::ShopifyControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "test-shopify-secret"
    ENV["SHOPIFY_API_SECRET"] = @secret
    @shop = Shop.create!(
      shopify_domain: "acme.myshopify.com",
      access_token: "shpat_live",
      scope: "read_products,read_inventory,read_locations"
    )
  end

  teardown do
    ENV.delete("SHOPIFY_API_SECRET")
  end

  test "rejects bad hmac" do
    post "/webhooks/shopify/products_create",
         params: { id: 1 }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Shopify-Hmac-Sha256" => "invalid",
           "X-Shopify-Shop-Domain" => "acme.myshopify.com"
         }
    assert_response :unauthorized
  end

  test "accepts products_create with valid hmac" do
    body = { "id" => 99, "title" => "Tee" }.to_json
    post "/webhooks/shopify/products_create",
         params: body,
         headers: webhook_headers(body)
    assert_response :ok
  end

  test "app_uninstalled marks shop uninstalled" do
    body = { "domain" => "acme.myshopify.com" }.to_json
    post "/webhooks/shopify/app_uninstalled",
         params: body,
         headers: webhook_headers(body)
    assert_response :ok

    @shop.reload
    assert @shop.uninstalled_at.present?
    assert_nil @shop.access_token
  end

  private

  def webhook_headers(body)
    digest = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @secret, body))
    {
      "CONTENT_TYPE" => "application/json",
      "X-Shopify-Hmac-Sha256" => digest,
      "X-Shopify-Shop-Domain" => "acme.myshopify.com"
    }
  end
end
