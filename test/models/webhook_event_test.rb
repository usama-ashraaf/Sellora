# frozen_string_literal: true

require "test_helper"

class WebhookEventTest < ActiveSupport::TestCase
  test "claim records once and rejects duplicates" do
    assert WebhookEvent.claim!(shopify_domain: "acme.myshopify.com", topic: "products_create", event_key: "id:abc")
    assert_not WebhookEvent.claim!(shopify_domain: "acme.myshopify.com", topic: "products_create", event_key: "id:abc")
    assert_equal 1, WebhookEvent.where(event_key: "id:abc").count
  end
end
