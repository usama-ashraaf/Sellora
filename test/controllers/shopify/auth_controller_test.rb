# frozen_string_literal: true

require "test_helper"
require "openssl"

class Shopify::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["SHOPIFY_CLIENT_ID"] = "test-client-id"
    ENV["SHOPIFY_API_SECRET"] = "test-shopify-secret"
    ENV["SHOPIFY_APP_URL"] = "http://www.example.com"
  end

  teardown do
    ENV.delete("SHOPIFY_CLIENT_ID")
    ENV.delete("SHOPIFY_API_SECRET")
    ENV.delete("SHOPIFY_APP_URL")
  end

  test "install redirects to Shopify authorize URL with state" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    assert_response :redirect
    location = response.redirect_url
    assert_includes location, "https://acme.myshopify.com/admin/oauth/authorize"
    assert_includes location, "client_id=test-client-id"
    assert_includes location, "read_products"
    assert_includes location, "read_inventory"
    assert_includes location, "read_locations"
    assert_match(/state=[0-9a-f]+/, location)
  end

  test "install rejects invalid shop" do
    get shopify_install_path, params: { shop: "evil.example.com" }
    assert_response :unprocessable_entity
  end

  test "callback rejects bad state" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    assert_response :redirect

    get shopify_callback_path, params: signed_callback_params(
      shop: "acme.myshopify.com",
      code: "fake-code",
      state: "totally-wrong-state"
    )
    assert_response :unauthorized
    assert_match(/Invalid OAuth state/, response.body)
  end

  test "callback rejects shop mismatch against session" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    state = session[:shopify_oauth_state]

    get shopify_callback_path, params: signed_callback_params(
      shop: "other.myshopify.com",
      code: "auth-code",
      state: state
    )
    assert_response :unauthorized
    assert_match(/Shop mismatch/, response.body)
  end

  test "callback rejects missing or invalid HMAC when secret configured" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    state = session[:shopify_oauth_state]

    get shopify_callback_path, params: {
      shop: "acme.myshopify.com",
      code: "auth-code",
      state: state
    }
    assert_response :unauthorized
    assert_match(/Invalid OAuth HMAC/, response.body)
  end

  test "callback rejects broader than Phase A scopes" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    state = session[:shopify_oauth_state]

    fake_token = { "access_token" => "shpat_test_offline", "scope" => "read_products,write_products" }
    original = Shopify::Oauth.method(:exchange_code)
    Shopify::Oauth.define_singleton_method(:exchange_code) { |**_| fake_token }

    begin
      get shopify_callback_path, params: signed_callback_params(
        shop: "acme.myshopify.com",
        code: "auth-code",
        state: state
      )
    ensure
      Shopify::Oauth.define_singleton_method(:exchange_code, original)
    end

    assert_response :forbidden
    assert_match(/Phase A/, response.body)
    assert_nil Shop.find_by(shopify_domain: "acme.myshopify.com")
  end

  test "callback oauth_error is actionable without leaking secrets" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    state = session[:shopify_oauth_state]

    original = Shopify::Oauth.method(:exchange_code)
    Shopify::Oauth.define_singleton_method(:exchange_code) do |**_|
      raise Shopify::Oauth::Error, "token exchange failed (HTTP 400)"
    end

    begin
      get shopify_callback_path, params: signed_callback_params(
        shop: "acme.myshopify.com",
        code: "auth-code",
        state: state
      )
    ensure
      Shopify::Oauth.define_singleton_method(:exchange_code, original)
    end

    assert_response :bad_gateway
    assert_match(/OAuth token exchange failed/, response.body)
    assert_match(/Allowed redirection URL/, response.body)
    assert_match(/single-use/, response.body)
    refute_match(/auth-code|shpat_|test-shopify-secret|test-client-id/, response.body)
    assert_nil session[:shopify_oauth_state]
  end

  test "callback exchanges code and persists shop when state matches" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    state = session[:shopify_oauth_state]
    assert state.present?

    fake_token = { "access_token" => "shpat_test_offline", "scope" => "read_products,read_inventory,read_locations" }
    original = Shopify::Oauth.method(:exchange_code)
    Shopify::Oauth.define_singleton_method(:exchange_code) { |**_| fake_token }

    begin
      get shopify_callback_path, params: signed_callback_params(
        shop: "acme.myshopify.com",
        code: "auth-code",
        state: state
      )
    ensure
      Shopify::Oauth.define_singleton_method(:exchange_code, original)
    end

    assert_response :success
    shop = Shop.find_by!(shopify_domain: "acme.myshopify.com")
    assert_equal "shpat_test_offline", shop.access_token
    assert shop.installed?
    assert_nil session[:shopify_oauth_state]
    assert shop.account_id.present?, "OAuth must set account_id"
    assert_equal "Store acme.myshopify.com", shop.account.name
    refute_equal Account::DEMO_NAME, shop.account.name
  end

  test "callback re-install preserves existing account_id" do
    existing = Account.create!(name: "Existing Merchant")
    Shop.create!(
      shopify_domain: "acme.myshopify.com",
      access_token: "old",
      scope: "read_products",
      account: existing
    )

    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    state = session[:shopify_oauth_state]

    fake_token = { "access_token" => "shpat_reinstall", "scope" => "read_products,read_inventory,read_locations" }
    original = Shopify::Oauth.method(:exchange_code)
    Shopify::Oauth.define_singleton_method(:exchange_code) { |**_| fake_token }

    begin
      get shopify_callback_path, params: signed_callback_params(
        shop: "acme.myshopify.com",
        code: "auth-code",
        state: state
      )
    ensure
      Shopify::Oauth.define_singleton_method(:exchange_code, original)
    end

    assert_response :success
    shop = Shop.find_by!(shopify_domain: "acme.myshopify.com")
    assert_equal "shpat_reinstall", shop.access_token
    assert_equal existing.id, shop.account_id
  end

  private

  def signed_callback_params(shop:, code:, state:)
    params = {
      "shop" => shop,
      "code" => code,
      "state" => state,
      "timestamp" => Time.now.to_i.to_s
    }
    message = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
    params["hmac"] = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("SHOPIFY_API_SECRET"), message)
    params
  end
end
