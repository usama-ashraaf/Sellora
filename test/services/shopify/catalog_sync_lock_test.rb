# frozen_string_literal: true

require "test_helper"

class Shopify::CatalogSyncLockTest < ActiveSupport::TestCase
  test "holding yields and returns true when lock is free" do
    ran = false
    result = Shopify::CatalogSyncLock.holding(42_001) do
      ran = true
      :ok
    end
    assert ran
    assert_equal true, result
  end

  test "holding returns false when lock is already held" do
    shop_key = 42_002
    started = Queue.new
    release = Queue.new
    holder_result = Queue.new

    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ran = Shopify::CatalogSyncLock.holding(shop_key) do
          started << :ready
          release.pop
          :held
        end
        holder_result << ran
      end
    end

    assert_equal :ready, started.pop
    contender_ran = false
    assert_equal false, Shopify::CatalogSyncLock.holding(shop_key) { contender_ran = true }
    assert_not contender_ran

    release << :go
    thread.join
    assert_equal true, holder_result.pop
  end
end
