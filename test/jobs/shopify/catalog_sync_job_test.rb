# frozen_string_literal: true

require "test_helper"

class Shopify::CatalogSyncJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @shop = Shop.create!(
      shopify_domain: "job-shop.myshopify.com",
      access_token: "shpat_job",
      scope: "read_products,read_inventory,read_locations"
    )
  end

  test "perform calls CatalogSync for installed shop" do
    called_with = nil
    original = Shopify::CatalogSync.method(:call)
    Shopify::CatalogSync.define_singleton_method(:call) do |shop|
      called_with = shop.id
      { products: 0, shop_id: shop.id }
    end

    begin
      Shopify::CatalogSyncJob.perform_now(@shop.id)
    ensure
      Shopify::CatalogSync.define_singleton_method(:call, original)
    end

    assert_equal @shop.id, called_with
  end

  test "perform no-ops for missing or uninstalled shop" do
    calls = 0
    original = Shopify::CatalogSync.method(:call)
    Shopify::CatalogSync.define_singleton_method(:call) do |_shop|
      calls += 1
      { products: 0, shop_id: 0 }
    end

    begin
      Shopify::CatalogSyncJob.perform_now(-1)
      @shop.mark_uninstalled!
      Shopify::CatalogSyncJob.perform_now(@shop.id)
    ensure
      Shopify::CatalogSync.define_singleton_method(:call, original)
    end

    assert_equal 0, calls
  end
end
