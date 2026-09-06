# frozen_string_literal: true

require "test_helper"
require "base64"
require "openssl"

class Webhooks::ShopifyControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

  test "accepts products_create with valid hmac and records ledger" do
    body = { "id" => 99, "title" => "Tee" }.to_json
    assert_enqueued_with(job: Shopify::CatalogSyncJob, args: [ @shop.id ]) do
      post "/webhooks/shopify/products_create",
           params: body,
           headers: webhook_headers(body, webhook_id: "wh-1")
    end
    assert_response :ok
    assert_equal 1, WebhookEvent.where(topic: "products_create", shopify_domain: "acme.myshopify.com").count
  end

  test "inventory_levels_update enqueues catalog sync" do
    body = { "inventory_item_id" => 1, "available" => 4 }.to_json
    assert_enqueued_with(job: Shopify::CatalogSyncJob, args: [ @shop.id ]) do
      post "/webhooks/shopify/inventory_levels_update",
           params: body,
           headers: webhook_headers(body, webhook_id: "wh-inv-1")
    end
    assert_response :ok
  end

  test "duplicate webhook id skips enqueue of catalog sync" do
    body = { "id" => 42 }.to_json
    headers = webhook_headers(body, webhook_id: "wh-dup-product")

    assert_enqueued_jobs 1, only: Shopify::CatalogSyncJob do
      post "/webhooks/shopify/products_update", params: body, headers: headers
      assert_response :ok
    end

    assert_no_enqueued_jobs only: Shopify::CatalogSyncJob do
      post "/webhooks/shopify/products_update", params: body, headers: headers
      assert_response :ok
    end
  end

  test "duplicate webhook id is acknowledged without reprocessing uninstall" do
    body = { "domain" => "acme.myshopify.com" }.to_json
    headers = webhook_headers(body, webhook_id: "wh-uninstall-1")

    post "/webhooks/shopify/app_uninstalled", params: body, headers: headers
    assert_response :ok
    @shop.reload
    assert @shop.uninstalled_at.present?

    # Re-install token for second-delivery check of business side-effect skip.
    @shop.update!(access_token: "shpat_again", uninstalled_at: nil)

    post "/webhooks/shopify/app_uninstalled", params: body, headers: headers
    assert_response :ok
    @shop.reload
    assert_nil @shop.uninstalled_at, "duplicate delivery must not re-run app_uninstalled"
    assert_equal 1, WebhookEvent.where(event_key: "id:wh-uninstall-1").count
  end

  test "app_uninstalled marks shop uninstalled and purges catalog" do
    product = @shop.catalog_products.create!(external_id: "gid://shopify/Product/77", title: "Gone", status: "active")
    product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/77", sku: "GONE")

    body = { "domain" => "acme.myshopify.com" }.to_json
    post "/webhooks/shopify/app_uninstalled",
         params: body,
         headers: webhook_headers(body, webhook_id: "wh-uninstall-2")
    assert_response :ok

    @shop.reload
    assert @shop.uninstalled_at.present?
    assert_nil @shop.access_token
    assert_equal 0, @shop.catalog_products.count
  end

  private

  def webhook_headers(body, webhook_id: "wh-default")
    digest = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @secret, body))
    {
      "CONTENT_TYPE" => "application/json",
      "X-Shopify-Hmac-Sha256" => digest,
      "X-Shopify-Shop-Domain" => "acme.myshopify.com",
      "X-Shopify-Webhook-Id" => webhook_id
    }
  end
end
