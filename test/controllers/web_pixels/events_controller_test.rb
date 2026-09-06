# frozen_string_literal: true

require "test_helper"

class WebPixels::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "pixel-test-secret"
    ENV["WEB_PIXEL_INGEST_SECRET"] = @secret
    @account = Account.create!(name: "Pixel HTTP Co")
    @shop = Shop.create!(
      shopify_domain: "pixel-http.myshopify.com",
      access_token: "t",
      scope: "read_products",
      account: @account
    )
  end

  teardown do
    ENV.delete("WEB_PIXEL_INGEST_SECRET")
  end

  test "creates activity event with valid secret and consent" do
    post "/web_pixels/events",
         params: {
           shop_domain: @shop.shopify_domain,
           event_name: "product_viewed",
           occurred_at: "2026-09-06T10:00:00Z",
           consent: { analytics_processing_allowed: true, marketing_allowed: true },
           payload: { id: "http-1" }
         }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Sellora-Pixel-Secret" => @secret
         }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "product_viewed", body["event_name"]
    assert_equal "web_pixel", body["source"]
    assert_equal 1, ActivityEvent.where(source: "web_pixel", event_name: "product_viewed").count
  end

  test "unauthorized without secret" do
    post "/web_pixels/events",
         params: {
           shop_domain: @shop.shopify_domain,
           event_name: "page_viewed",
           consent: { analytics_processing_allowed: true }
         }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
  end

  test "forbidden when analytics consent false" do
    post "/web_pixels/events",
         params: {
           shop_domain: @shop.shopify_domain,
           event_name: "page_viewed",
           consent: { analytics_processing_allowed: false }
         }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Sellora-Pixel-Secret" => @secret
         }
    assert_response :forbidden
    assert_equal 0, ActivityEvent.where(source: "web_pixel").count
  end

  test "unprocessable for unsupported event" do
    post "/web_pixels/events",
         params: {
           shop_domain: @shop.shopify_domain,
           event_name: "checkout_completed",
           consent: { analytics_processing_allowed: true }
         }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Sellora-Pixel-Secret" => @secret
         }
    assert_response :unprocessable_entity
  end
end
