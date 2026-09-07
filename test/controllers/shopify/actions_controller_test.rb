# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "openssl"

class Shopify::ActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = Account.create!(name: "Merchant Actions")
    @shop = Shop.create!(shopify_domain: "merchant-actions.myshopify.com", access_token: "t", account: @account)
    @product = @shop.catalog_products.create!(external_id: "gid://shopify/Product/44", title: "Old Kurti", status: "active")
    @recommendation = @shop.recommendations.create!(
      account: @account,
      catalog_product: @product,
      kind: "catalog_fix",
      priority: "medium",
      status: "open",
      title: "Verify title",
      rationale: "Title needs merchant review"
    )
  end

  test "rejects mutation requests without a Shopify ID token" do
    post shopify_actions_path, params: { recommendation_id: @recommendation.id, change: { title: "Verified Kurti" } }
    assert_response :unauthorized
    assert_equal "1", response.headers["X-Shopify-Retry-Invalid-Session-Request"]
  end

  test "creates approves and rejects a concrete action for the authenticated shop" do
    with_config do
      post shopify_actions_path,
           params: { recommendation_id: @recommendation.id, change: { title: "Verified Kurti" } },
           headers: authorization_header
      assert_response :created
      action = @shop.reviewed_actions.find(JSON.parse(response.body).fetch("id"))
      assert_equal "product_update", action.action_kind
      assert_equal "Verified Kurti", action.after_snapshot["title"]

      post approve_shopify_action_path(action), headers: authorization_header
      assert_response :success
      assert_equal "approved", action.reload.status

      post reject_shopify_action_path(action), headers: authorization_header
      assert_response :success
      assert_equal "rejected", action.reload.status
    end
  end

  test "cannot act on another shop action" do
    other = Shop.create!(shopify_domain: "other-actions.myshopify.com", access_token: "t", account: @account)
    action = other.reviewed_actions.create!(account: @account, action_kind: "product_update", status: "pending_approval")
    with_config do
      post approve_shopify_action_path(action), headers: authorization_header
      assert_response :not_found
    end
  end

  private

  def authorization_header
    { "Authorization" => "Bearer #{id_token}" }
  end

  def id_token
    header = encode({ alg: "HS256", typ: "JWT" })
    payload = encode({
      iss: "https://#{@shop.shopify_domain}/admin",
      dest: "https://#{@shop.shopify_domain}",
      aud: "test-client",
      sub: "merchant-42",
      nbf: 1.minute.ago.to_i,
      exp: 1.minute.from_now.to_i
    })
    signature = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", "test-secret", "#{header}.#{payload}"), padding: false)
    [ header, payload, signature ].join(".")
  end

  def encode(value)
    Base64.urlsafe_encode64(JSON.generate(value), padding: false)
  end

  def with_config(&)
    with_singleton_stub(ShopifyConfig, :api_secret, -> { "test-secret" }) do
      with_singleton_stub(ShopifyConfig, :client_id, -> { "test-client" }, &)
    end
  end
end
