# frozen_string_literal: true

module Shopify
  class CatalogSyncJob < ApplicationJob
    queue_as :default

    # Transient Admin API / transport failures — back off and retry.
    retry_on Shopify::AdminClient::TransientError, wait: :polynomially_longer, attempts: 5
    retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT,
            wait: :polynomially_longer, attempts: 5

    # perform_later(shop_id)
    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil? || !shop.installed?

      ran = CatalogSyncLock.holding(shop.id) do
        result = CatalogSync.call(shop)
        if shop.account.present?
          begin
            Audit::ClothingRulesSeed.call
            Audit::Runner.call(shop: shop)
            Pilot::Recommendations.call(shop: shop)
            Pilot::PromotionReadiness.call(shop: shop)
          rescue ArgumentError, ActiveRecord::RecordInvalid => e
            Rails.logger.warn("[catalog_sync] pilot follow-up skipped shop=#{shop.shopify_domain} error=#{e.message}")
          end
        end
        result
      end

      unless ran
        Rails.logger.info(
          "[catalog_sync] coalesce skip shop_id=#{shop.id} domain=#{shop.shopify_domain} " \
          "(full sync already in progress)"
        )
      end

      ran ? :ran : :coalesced
    end
  end
end
