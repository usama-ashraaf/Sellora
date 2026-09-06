# frozen_string_literal: true

require "test_helper"

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

    get shopify_callback_path, params: {
      shop: "acme.myshopify.com",
      code: "fake-code",
      state: "totally-wrong-state"
    }
    assert_response :unauthorized
    assert_equal "Invalid OAuth state", response.body
  end

  test "callback exchanges code and persists shop when state matches" do
    get shopify_install_path, params: { shop: "acme.myshopify.com" }
    state = session[:shopify_oauth_state]
    assert state.present?

    fake_token = { "access_token" => "shpat_test_offline", "scope" => "read_products,read_inventory,read_locations" }
    original = Shopify::Oauth.method(:exchange_code)
    Shopify::Oauth.define_singleton_method(:exchange_code) { |**_| fake_token }

    begin
      get shopify_callback_path, params: {
        shop: "acme.myshopify.com",
        code: "auth-code",
        state: state
      }
    ensure
      Shopify::Oauth.define_singleton_method(:exchange_code, original)
    end

    assert_response :success
    shop = Shop.find_by!(shopify_domain: "acme.myshopify.com")
    assert_equal "shpat_test_offline", shop.access_token
    assert shop.installed?
    assert_nil session[:shopify_oauth_state]
  end
end
