# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "openssl"

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
    assert_includes response.body, "Authenticating this Shopify session"
    assert_includes response.body, "shopifycloud/app-bridge.js"

    get shopify_dashboard_path, params: { section: "overview" }, headers: authorization_header("acme.myshopify.com")
    assert_response :ok
    assert_includes response.body, "Connect Sellora"
    assert_includes response.body, "Install or repair connection"
  end

  test "embed home via /shopify/app alias" do
    get "/shopify/app", params: { shop: "acme.myshopify.com" }
    assert_response :ok
    assert_includes response.body, "Sellora"
  end

  test "installed shop dashboard displays navigation funnel and order outcomes" do
    account = Account.create!(name: "Dashboard Merchant")
    Shop.create!(shopify_domain: "dashboard.myshopify.com", access_token: "t", account: account)

    get shopify_dashboard_path, params: { host: "abc" }, headers: authorization_header("dashboard.myshopify.com")

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

  test "overview highlights ranked growth recommendations" do
    account = Account.create!(name: "Growth Dashboard")
    shop = Shop.create!(shopify_domain: "growth.myshopify.com", access_token: "t", account: account)
    product = shop.catalog_products.create!(external_id: "gid://shopify/Product/77", title: "Ready Kurti", status: "active")
    shop.recommendations.create!(account: account, catalog_product: product, kind: "social_ad_candidate",
                                 priority: "medium", status: "open", title: "Social ad candidate: Ready Kurti",
                                 rationale: "3 paid orders, 60 units available, and 100% size coverage.")

    get shopify_dashboard_path, params: { section: "overview" }, headers: authorization_header(shop.shopify_domain)

    assert_response :ok
    assert_includes response.body, "Growth opportunities"
    assert_includes response.body, "Prepare social campaign"
    assert_includes response.body, "Ready Kurti"
  end

  test "recommendations provide real Shopify product discount and order actions" do
    account = Account.create!(name: "Actionable Dashboard")
    shop = Shop.create!(shopify_domain: "actionable.myshopify.com", access_token: "t", account: account)
    product = shop.catalog_products.create!(external_id: "gid://shopify/Product/12345", title: "Meadow Kurti", status: "active")
    shop.recommendations.create!(account: account, catalog_product: product, kind: "promotion_opportunity",
                                 priority: "high", status: "open", title: "Promotion candidate",
                                 rationale: "Matched interest and paid orders", suggested_action: "Review the campaign fit.")

    get shopify_dashboard_path, params: { host: "abc", section: "recommendations" }, headers: authorization_header(shop.shopify_domain)

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
      get shopify_dashboard_path, params: { section: section }, headers: authorization_header(shop.shopify_domain)
      assert_response :ok
      assert_includes response.body, copy
    end
  end

  test "activity section explains customer events with product and journey context" do
    account = Account.create!(name: "Activity Dashboard")
    shop = Shop.create!(shopify_domain: "activity-dashboard.myshopify.com", access_token: "t", account: account)
    product = shop.catalog_products.create!(external_id: "gid://shopify/Product/123", title: "Meadow Kurti", status: "active")
    product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/456", sku: "MK-M", option_summary: "Size: M")
    Activity::Ingest.call(account: account, shop: shop, event_name: "product_added_to_cart", source: "web_pixel",
                          payload: { "product_id" => "123", "variant_id" => "456", "sku" => "MK-M", "quantity" => 2,
                                     "amount" => "4980", "currency" => "PKR",
                                     "consent" => { "analytics_processing_allowed" => true } })

    get shopify_dashboard_path, params: { section: "activity" }, headers: authorization_header(shop.shopify_domain)

    assert_response :ok
    assert_includes response.body, "Customer activity"
    assert_includes response.body, "Journey conversion"
    assert_includes response.body, "Product added to cart"
    assert_includes response.body, "Meadow Kurti"
    assert_includes response.body, "Size: M"
    assert_includes response.body, "PKR 4980"
    assert_includes response.body, "Analytics consent"
  end

  test "actions section explains autopilot effects safeguards and skipped reasons" do
    account = Account.create!(name: "Autopilot Dashboard")
    shop = Shop.create!(shopify_domain: "autopilot-dashboard.myshopify.com", access_token: "t", account: account)
    policy = Pilot::Autopilot.ensure_policy!(shop)
    policy.autopilot_runs.create!(account: account, shop: shop, status: "completed", started_at: Time.current,
                                  finished_at: Time.current, skipped_count: 2,
                                  details: { "skip_reasons" => { "inventory_below_minimum" => 2 } })

    get shopify_dashboard_path, params: { section: "actions" }, headers: authorization_header(shop.shopify_domain)

    assert_response :ok
    assert_includes response.body, "Automatically applies eligible Shopify changes"
    assert_includes response.body, "it does not change selling prices"
    assert_includes response.body, "Run autopilot now"
    assert_includes response.body, "2 × Inventory or size coverage was too low"
  end

  test "embed home tolerates missing shopify params with friendly message" do
    get shopify_embedded_app_path
    assert_response :ok
    assert_includes response.body, "Open Sellora from Shopify Admin"
  end

  test "dashboard rejects missing identity and bootstrap contains no merchant data" do
    account = Account.create!(name: "Private Dashboard")
    Shop.create!(shopify_domain: "private.myshopify.com", access_token: "t", account: account)

    get shopify_embedded_app_path, params: { shop: "private.myshopify.com" }
    assert_response :ok
    assert_not_includes response.body, "Private Dashboard"
    assert_not_includes response.body, "private.myshopify.com"

    get shopify_dashboard_path
    assert_response :unauthorized
    assert_equal "1", response.headers["X-Shopify-Retry-Invalid-Session-Request"]
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


  private

  def authorization_header(shop_domain)
    header = encode({ alg: "HS256", typ: "JWT" })
    payload = encode({
      iss: "https://#{shop_domain}/admin",
      dest: "https://#{shop_domain}",
      aud: "test-client-id",
      sub: "merchant-42",
      nbf: 1.minute.ago.to_i,
      exp: 1.minute.from_now.to_i
    })
    signature = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", "test-shopify-secret", "#{header}.#{payload}"), padding: false)
    { "Authorization" => "Bearer #{[ header, payload, signature ].join('.')}" }
  end

  def encode(value)
    Base64.urlsafe_encode64(JSON.generate(value), padding: false)
  end
end
