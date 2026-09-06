# frozen_string_literal: true

require "test_helper"

class Activity::WebPixelIngestTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Pixel Co")
    @shop = Shop.create!(
      shopify_domain: "pixel.myshopify.com",
      access_token: "t",
      scope: "read_products",
      account: @account
    )
  end

  test "ingests when analytics consent is true" do
    event = Activity::WebPixelIngest.call(
      shop_domain: "pixel.myshopify.com",
      event_name: "product_viewed",
      consent: { "analytics_processing_allowed" => true, "marketing_allowed" => false },
      payload: { "id" => "e1" }
    )
    assert_equal "product_viewed", event.event_name
    assert_equal "web_pixel", event.source
    assert_equal @account.id, event.account_id
    assert_equal @shop.id, event.shop_id
    assert_equal true, event.payload["consent"]["analytics_processing_allowed"]
    assert_equal "e1", event.payload["id"]
  end

  test "accepts camelCase consent keys from Shopify privacy API" do
    event = Activity::WebPixelIngest.call(
      shop_domain: "https://pixel.myshopify.com",
      event_name: "page_viewed",
      consent: { "analyticsProcessingAllowed" => true, "marketingAllowed" => true }
    )
    assert_equal "page_viewed", event.event_name
    assert_equal true, event.payload["consent"]["analytics_processing_allowed"]
  end

  test "fail-closed when consent hash missing" do
    assert_raises(Activity::WebPixelIngest::ConsentDenied) do
      Activity::WebPixelIngest.call(
        shop_domain: "pixel.myshopify.com",
        event_name: "product_viewed",
        consent: nil
      )
    end
    assert_equal 0, ActivityEvent.where(source: "web_pixel").count
  end

  test "fail-closed when analytics flag missing" do
    assert_raises(Activity::WebPixelIngest::ConsentDenied) do
      Activity::WebPixelIngest.call(
        shop_domain: "pixel.myshopify.com",
        event_name: "product_viewed",
        consent: { "marketing_allowed" => true }
      )
    end
  end

  test "fail-closed when analytics consent false" do
    assert_raises(Activity::WebPixelIngest::ConsentDenied) do
      Activity::WebPixelIngest.call(
        shop_domain: "pixel.myshopify.com",
        event_name: "product_added_to_cart",
        consent: { "analytics_processing_allowed" => false, "marketing_allowed" => true }
      )
    end
    assert_equal 0, ActivityEvent.where(source: "web_pixel").count
  end

  test "rejects unsupported event names" do
    err = assert_raises(Activity::WebPixelIngest::Error) do
      Activity::WebPixelIngest.call(
        shop_domain: "pixel.myshopify.com",
        event_name: "checkout_completed",
        consent: { "analytics_processing_allowed" => true }
      )
    end
    assert_match(/unsupported/, err.message)
  end

  test "rejects unknown shop" do
    assert_raises(Activity::WebPixelIngest::Error) do
      Activity::WebPixelIngest.call(
        shop_domain: "missing.myshopify.com",
        event_name: "page_viewed",
        consent: { "analytics_processing_allowed" => true }
      )
    end
  end

  test "rejects shop without account" do
    orphan = Shop.create!(shopify_domain: "orphan.myshopify.com", access_token: "t", scope: "read_products")
    assert_raises(Activity::WebPixelIngest::Error) do
      Activity::WebPixelIngest.call(
        shop_domain: orphan.shopify_domain,
        event_name: "page_viewed",
        consent: { "analytics_processing_allowed" => true }
      )
    end
  end
end
