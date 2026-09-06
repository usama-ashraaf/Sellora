# frozen_string_literal: true

module Pilot
  # Daily / on-demand discovery for one shop: sync → audit → recommendations (M4).
  class Discover
    def self.call(shop:, sync: true)
      new(shop: shop, sync: sync).call
    end

    def initialize(shop:, sync: true)
      @shop = shop
      @sync = sync
    end

    def call
      raise ArgumentError, "shop is not installed" unless @shop.installed?
      raise ArgumentError, "shop has no account" if @shop.account.blank?

      sync_result = @sync ? Shopify::CatalogSync.call(@shop) : { products: @shop.catalog_products.count, shop_id: @shop.id }
      audit_result = Audit::Runner.call(shop: @shop)
      recs = Recommendations.call(shop: @shop)
      @shop.update_columns(last_discovered_at: Time.current)

      {
        shop_id: @shop.id,
        sync: sync_result,
        audit_findings: audit_result.findings.size,
        audit_skipped: audit_result.skipped,
        recommendations: recs.size
      }
    end
  end
end
