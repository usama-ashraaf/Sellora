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

  test "embed home offers installation for a valid unconnected shop" do
    get shopify_embedded_app_path, params: { shop: "acme.myshopify.com", host: "abc" }
    assert_response :ok
    assert_includes response.body, "Sellora"
    assert_includes response.body, "Connect Sellora"
    assert_includes response.body, "Install or repair connection"
    assert_includes response.body, "shopifycloud/app-bridge.js"
  end

  test "embed home via /shopify/app alias" do
    get "/shopify/app", params: { shop: "acme.myshopify.com" }
    assert_response :ok
    assert_includes response.body, "Sellora"
  end

  test "installed shop dashboard displays navigation funnel and order outcomes" do
    account = Account.create!(name: "Dashboard Merchant")
    Shop.create!(shopify_domain: "dashboard.myshopify.com", access_token: "t", account: account)

    get shopify_embedded_app_path, params: { shop: "dashboard.myshopify.com", host: "abc" }

    assert_response :ok
    assert_includes response.body, "Commerce intelligence"
    assert_includes response.body, "Recommendations"
    assert_includes response.body, "Products"
    assert_includes response.body, "Orders"
    assert_includes response.body, "Activity"
    assert_includes response.body, "Actions"
    assert_includes response.body, "Storefront journey · 7 days"
    assert_includes response.body, "Order outcomes · 30 days"
  end

  test "recommendations provide real Shopify product discount and order actions" do
    account = Account.create!(name: "Actionable Dashboard")
    shop = Shop.create!(shopify_domain: "actionable.myshopify.com", access_token: "t", account: account)
    product = shop.catalog_products.create!(external_id: "gid://shopify/Product/12345", title: "Meadow Kurti", status: "active")
    shop.recommendations.create!(account: account, catalog_product: product, kind: "promotion_opportunity",
                                 priority: "high", status: "open", title: "Promotion candidate",
                                 rationale: "Matched interest and paid orders", suggested_action: "Review the campaign fit.")

    get shopify_embedded_app_path, params: { shop: shop.shopify_domain, host: "abc", section: "recommendations" }

    assert_response :ok
    assert_includes response.body, "Edit product in Shopify"
    assert_includes response.body, "https://admin.shopify.com/store/actionable/products/12345"
    assert_includes response.body, "https://admin.shopify.com/store/actionable/discounts"
    assert_includes response.body, "https://admin.shopify.com/store/actionable/orders"
  end

  test "each dashboard section renders independently" do
    account = Account.create!(name: "Dashboard Sections")
    shop = Shop.create!(shopify_domain: "sections.myshopify.com", access_token: "t", account: account)
    expected = { "products" => "Catalog health", "orders" => "Payment and fulfillment", "activity" => "Recent storefront events",
                 "actions" => "Awaiting review" }

    expected.each do |section, copy|
      get shopify_embedded_app_path, params: { shop: shop.shopify_domain, section: section }
      assert_response :ok
      assert_includes response.body, copy
    end
  end

  test "embed home tolerates missing shopify params with friendly message" do
    get shopify_embedded_app_path
    assert_response :ok
    assert_includes response.body, "Open Sellora from Shopify Admin"
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
