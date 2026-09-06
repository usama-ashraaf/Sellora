# frozen_string_literal: true

require "test_helper"

class Activity::IngestTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Ingest Co")
    @shop = Shop.create!(shopify_domain: "ingest.myshopify.com", access_token: "t", scope: "read_products", account: @account)
  end

  test "appends event for account and shop" do
    event = Activity::Ingest.call(
      account: @account,
      shop: @shop,
      event_name: "catalog.synced",
      payload: { "products" => 8 },
      source: "internal"
    )
    assert_equal "catalog.synced", event.event_name
    assert_equal 8, event.payload["products"]
  end

  test "rejects shop from another account" do
    other = Account.create!(name: "Other")
    assert_raises(Activity::Ingest::Error) do
      Activity::Ingest.call(account: other, shop: @shop, event_name: "x")
    end
  end
end
