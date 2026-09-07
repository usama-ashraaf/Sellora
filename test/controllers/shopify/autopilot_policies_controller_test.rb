# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "openssl"

class Shopify::AutopilotPoliciesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @shop = Shop.create!(shopify_domain: "policy.myshopify.com", access_token: "t", account: Account.create!(name: "Policy"))
    ENV["SHOPIFY_CLIENT_ID"] = "test-client"
    ENV["SHOPIFY_API_SECRET"] = "test-secret"
  end

  teardown do
    ENV.delete("SHOPIFY_CLIENT_ID")
    ENV.delete("SHOPIFY_API_SECRET")
  end

  test "rejects unauthenticated policy changes" do
    patch shopify_autopilot_policy_path, params: { autopilot_policy: { enabled: true } }
    assert_response :unauthorized
  end

  test "saves bounded policy fields and clamps action kinds" do
    patch shopify_autopilot_policy_path,
          params: { autopilot_policy: { enabled: true, allowed_action_kinds: [ "social_ad_candidate", "catalog_fix" ],
                                        max_actions_per_day: 2, minimum_inventory_units: 25, margin_floor_pct: 40 } },
          headers: authorization_header
    assert_response :success

    policy = @shop.autopilot_policy.reload
    assert policy.enabled?
    assert_equal [ "social_ad_candidate" ], policy.allowed_action_kinds
    assert_equal 2, policy.max_actions_per_day
    assert_equal 25, policy.minimum_inventory_units
    assert_equal BigDecimal("40"), policy.margin_floor_pct
  end

  test "kill switch and manual run are authenticated" do
    policy = Pilot::Autopilot.ensure_policy!(@shop)
    policy.update!(enabled: true)

    post kill_shopify_autopilot_path, headers: authorization_header
    assert_response :success
    assert_not policy.reload.enabled?

    assert_enqueued_with(job: Pilot::AutopilotShopJob, args: [ @shop.id ]) do
      post run_shopify_autopilot_path, headers: authorization_header
    end
    assert_response :success
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
