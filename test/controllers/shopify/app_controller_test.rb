# frozen_string_literal: true

require "test_helper"

class Shopify::AppControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["SHOPIFY_CLIENT_ID"] = "test-client-id"
    ENV["SHOPIFY_API_SECRET"] = "test-shopify-secret"
    ENV["SHOPIFY_APP_URL"] = "https://example-tunnel.test"
  end

  teardown do
    ENV.delete("SHOPIFY_CLIENT_ID")
    ENV.delete("SHOPIFY_API_SECRET")
    ENV.delete("SHOPIFY_APP_URL")
  end

  test "embed home responds 200 with status body" do
    get shopify_embedded_app_path, params: { shop: "acme.myshopify.com", host: "abc" }
    assert_response :ok
    assert_includes response.body, "Sellora"
    assert_includes response.body, "acme.myshopify.com"
    assert_includes response.body, "read_products"
    assert_includes response.body, "read_inventory"
    assert_includes response.body, "read_locations"
    assert_includes response.body, "shopifycloud/app-bridge.js"
  end

  test "embed home via /shopify/app alias" do
    get "/shopify/app", params: { shop: "acme.myshopify.com" }
    assert_response :ok
    assert_includes response.body, "Sellora"
  end

  test "embed home tolerates missing shopify params with friendly message" do
    get shopify_embedded_app_path
    assert_response :ok
    assert_match(/No Shopify embed params/i, response.body)
    assert_includes response.body, "/shopify"
  end

  test "embed home omits X-Frame-Options SAMEORIGIN and sets frame-ancestors CSP" do
    get shopify_embedded_app_path, params: { shop: "acme.myshopify.com" }
    assert_response :ok

    xfo = response.headers["X-Frame-Options"]
    assert_nil xfo, "expected X-Frame-Options to be omitted for Shopify embed, got #{xfo.inspect}"

    csp = response.headers["Content-Security-Policy"].to_s
    assert_includes csp, "frame-ancestors"
    assert_includes csp, "https://admin.shopify.com"
    assert_includes csp, "https://*.myshopify.com"
  end

  test "marketing root still sends default frame protection" do
    get root_path
    assert_response :ok
    # Marketing must not inherit the Shopify embed CSP / deleted XFO behavior.
    xfo = response.headers["X-Frame-Options"]
    assert_equal "SAMEORIGIN", xfo
  end
end
