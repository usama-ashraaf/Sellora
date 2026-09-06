# frozen_string_literal: true

module Shopify
  class CatalogSyncJob < ApplicationJob
    queue_as :default

    # perform_later(shop_id)
    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil? || !shop.installed?

      CatalogSync.call(shop)
    end
  end
end
