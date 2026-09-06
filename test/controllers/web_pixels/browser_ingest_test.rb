require "test_helper"

class WebPixels::BrowserIngestTest < ActionDispatch::IntegrationTest
  setup do
    @shop = Shop.create!(shopify_domain: "browser-pixel.myshopify.com", account: Account.create!(name: "Browser Pixel"), access_token: "test-token")
    @token = Activity::PixelToken.issue(@shop)
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "browser preflight permits token header without credentials" do
    options "/web_pixels/events", headers: { "Origin" => "https://custom-store.example", "Access-Control-Request-Method" => "POST" }
    assert_response :no_content
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Access-Control-Allow-Headers"], "X-Sellora-Pixel-Token"
    assert_nil response.headers["Access-Control-Allow-Credentials"]
  end

  test "signed token routes to its shop and ignores caller account id" do
    submit(account_id: 999999)
    assert_response :created
    assert_equal @shop.account_id, ActivityEvent.last.account_id
    assert_equal @shop.id, ActivityEvent.last.shop_id
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end

  test "tampered tokens and cross-shop submissions persist nothing" do
    @token += "tamper"
    assert_no_difference("ActivityEvent.count") { submit }
    assert_response :unauthorized
    @token = Activity::PixelToken.issue(@shop)
    assert_no_difference("ActivityEvent.count") { submit(shop_domain: "other.myshopify.com") }
    assert_response :forbidden
  end

  test "reinstall timestamp invalidates old token" do
    @shop.update!(updated_at: @shop.updated_at + 1.second)
    submit
    assert_response :unauthorized
  end

  test "uninstalled shop cannot submit" do
    @shop.mark_uninstalled!
    submit
    assert_response :unauthorized
  end

  test "denied consent and oversized bodies persist nothing" do
    assert_no_difference("ActivityEvent.count") { submit(consent: { analytics_processing_allowed: false }) }
    assert_response :forbidden
    assert_no_difference("ActivityEvent.count") { submit(payload: { id: "x" * 17.kilobytes }) }
    assert_response :content_too_large
  end

  test "shop rate limit applies across client IP addresses and expires" do
    Rails.cache.write("rate-limit:web_pixels/events:pixel-shop:#{@shop.id}", 300, expires_in: 1.minute)
    assert_no_difference("ActivityEvent.count") { submit }
    assert_response :too_many_requests
    travel 61.seconds do
      submit
      assert_response :created
    end
  end

  private

  def submit(overrides = {})
    body = { shop_domain: @shop.shopify_domain, event_name: "product_viewed",
             consent: { analytics_processing_allowed: true }, payload: { id: "event-1" } }.merge(overrides)
    post "/web_pixels/events", params: body.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "Origin" => "https://custom-store.example", "X-Sellora-Pixel-Token" => @token }
  end
end
