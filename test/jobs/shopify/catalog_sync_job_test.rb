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
      result = Shopify::CatalogSyncJob.perform_now(@shop.id)
      assert_equal :ran, result
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

  test "coalesces when another full sync holds the per-shop lock" do
    calls = 0
    original = Shopify::CatalogSync.method(:call)
    Shopify::CatalogSync.define_singleton_method(:call) do |_shop|
      calls += 1
      { products: 0, shop_id: 0 }
    end

    begin
      held = Shopify::CatalogSyncLock.holding(@shop.id) do
        result = Shopify::CatalogSyncJob.perform_now(@shop.id)
        assert_equal :coalesced, result
        assert_equal 0, calls
      end
      assert held

      # After lock release, sync runs normally.
      result = Shopify::CatalogSyncJob.perform_now(@shop.id)
      assert_equal :ran, result
      assert_equal 1, calls
    ensure
      Shopify::CatalogSync.define_singleton_method(:call, original)
    end
  end

  test "retry_on is configured for AdminClient TransientError" do
    retries = Shopify::CatalogSyncJob.rescue_handlers.select do |handler|
      handler.first == "Shopify::AdminClient::TransientError" ||
        (handler.first.is_a?(Class) && handler.first <= Shopify::AdminClient::TransientError)
    end
    # Rails stores handler as [exception_class_name_or_class, options_or_block]
    configured = Shopify::CatalogSyncJob.rescue_handlers.any? do |klass, _handler|
      name = klass.is_a?(String) ? klass : klass.name
      name == "Shopify::AdminClient::TransientError"
    end
    assert configured, "CatalogSyncJob should retry_on Shopify::AdminClient::TransientError"
  end
end
