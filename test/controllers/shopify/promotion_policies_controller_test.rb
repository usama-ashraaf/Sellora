# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "openssl"

class Shopify::PromotionPoliciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = Account.create!(name: "Planner Policy")
    @shop = Shop.create!(shopify_domain: "planner-policy.myshopify.com", access_token: "t", account: @account)
    product = @shop.catalog_products.create!(external_id: "gid://shopify/Product/1", title: "Kurti", status: "active")
    variant = product.catalog_variants.create!(external_id: "gid://shopify/ProductVariant/2", title: "M")
    variant.catalog_inventory_levels.create!(location_external_id: "location-1", available: 20)
    product.update!(raw_attrs: { "variant_prices" => { variant.external_id => {
      "price" => "3000", "unit_cost" => "1000", "cost_currency" => "PKR"
    } } })
    ENV["SHOPIFY_CLIENT_ID"] = "test-client"
    ENV["SHOPIFY_API_SECRET"] = "test-secret"
  end

  teardown do
    ENV.delete("SHOPIFY_CLIENT_ID")
    ENV.delete("SHOPIFY_API_SECRET")
  end

  test "rejects unauthenticated policy changes" do
    patch shopify_promotion_policy_path, params: { promotion_policy: { target_roas: 4 } }
    assert_response :unauthorized
  end

  test "saves merchant assumptions and refreshes decisions" do
    patch shopify_promotion_policy_path,
          params: { promotion_policy: { target_roas: 4, target_acquisition_cost: 600,
                                        shipping_cost_per_order: 250, cod_failure_cost: 300,
                                        expected_cod_failure_rate_percent: 20, desired_runway_days: 21,
                                        minimum_margin_percent: 30, minimum_safe_orders: 8 } },
          headers: authorization_header

    assert_response :success
    policy = @shop.promotion_policy.reload
    assert_equal BigDecimal("4"), policy.target_roas
    assert_equal BigDecimal("600"), policy.target_acquisition_cost
    assert_equal 21, policy.desired_runway_days
    assert_equal 1, @shop.promotion_decisions.count
    assert_includes JSON.parse(response.body).fetch("redirect_url"), "section=promotion_planner"
  end

  test "refresh is authenticated and shop scoped" do
    other = Shop.create!(shopify_domain: "other-planner.myshopify.com", access_token: "t",
                         account: Account.create!(name: "Other Planner"))

    post refresh_shopify_promotion_planner_path, headers: authorization_header

    assert_response :success
    assert_equal 1, @shop.promotion_decisions.count
    assert_equal 0, other.promotion_decisions.count
  end

  private

  def authorization_header
    header = encode(alg: "HS256", typ: "JWT")
    payload = encode(iss: "https://#{@shop.shopify_domain}/admin", dest: "https://#{@shop.shopify_domain}",
                     aud: "test-client", sub: "merchant", nbf: 1.minute.ago.to_i, exp: 1.minute.from_now.to_i)
    signature = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", "test-secret", "#{header}.#{payload}"), padding: false)
    { "Authorization" => "Bearer #{[ header, payload, signature ].join('.')}" }
  end

  def encode(value)
    Base64.urlsafe_encode64(JSON.generate(value), padding: false)
  end
end
