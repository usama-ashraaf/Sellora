# frozen_string_literal: true

require "set"

module Shopify
  # Per-shop lock so only one full catalog sync runs at a time.
  # Combines an in-process Set (handles same-connection advisory reentrancy + threads)
  # with PostgreSQL pg_try_advisory_lock (cross-process). Contending callers coalesce.
  class CatalogSyncLock
    # App-specific namespace so shop ids do not collide with other advisory locks.
    NAMESPACE = 872_014_001

    @mutex = Mutex.new
    @held = Set.new

    class << self
      # Yields while holding the lock. Returns true if the block ran, false if coalesced (busy).
      def holding(shop_id)
        key = Integer(shop_id)
        return false unless claim_in_process!(key)

        begin
          ActiveRecord::Base.connection_pool.with_connection do |conn|
            unless try_lock(conn, key)
              return false
            end

            begin
              yield
              true
            ensure
              unlock(conn, key)
            end
          end
        ensure
          release_in_process!(key)
        end
      end

      private

      def claim_in_process!(key)
        @mutex.synchronize { @held.add?(key) }
      end

      def release_in_process!(key)
        @mutex.synchronize { @held.delete(key) }
      end

      def try_lock(conn, key)
        cast_bool(
          conn.select_value(
            ActiveRecord::Base.sanitize_sql_array(
              [ "SELECT pg_try_advisory_lock(?, ?)", NAMESPACE, key ]
            )
          )
        )
      end

      def unlock(conn, key)
        conn.execute(
          ActiveRecord::Base.sanitize_sql_array(
            [ "SELECT pg_advisory_unlock(?, ?)", NAMESPACE, key ]
          )
        )
      end

      def cast_bool(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
