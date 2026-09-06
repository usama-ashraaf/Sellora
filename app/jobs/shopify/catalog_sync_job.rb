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
        CatalogSync.call(shop)
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
