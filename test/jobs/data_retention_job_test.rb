# frozen_string_literal: true

require "test_helper"

class DataRetentionJobTest < ActiveJob::TestCase
  test "prunes expired ledgers requests and uninstalled shops" do
    now = Time.zone.parse("2026-09-08 12:00:00")
    old_event = WebhookEvent.create!(shopify_domain: "old.myshopify.com", topic: "test", event_key: "old", processed_at: now - 31.days)
    new_event = WebhookEvent.create!(shopify_domain: "new.myshopify.com", topic: "test", event_key: "new", processed_at: now - 29.days)
    old_request = PilotRequest.create!(name: "Old", email: "old@example.com", store_url: "https://old.example.com", platform: "Shopify", created_at: now - 366.days)
    new_request = PilotRequest.create!(name: "New", email: "new@example.com", store_url: "https://new.example.com", platform: "Shopify", created_at: now - 364.days)
    account = Account.create!(name: "Expired Shop")
    old_shop = Shop.create!(shopify_domain: "expired.myshopify.com", account: account, uninstalled_at: now - 91.days)

    DataRetentionJob.perform_now(now: now)

    assert_not WebhookEvent.exists?(old_event.id)
    assert WebhookEvent.exists?(new_event.id)
    assert_not PilotRequest.exists?(old_request.id)
    assert PilotRequest.exists?(new_request.id)
    assert_not Shop.exists?(old_shop.id)
  end
end
