# frozen_string_literal: true

module Shopify
  class OrderSyncJob < ApplicationJob
    queue_as :default

    retry_on Shopify::AdminClient::TransientError, wait: :polynomially_longer, attempts: 5
    retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT,
            wait: :polynomially_longer, attempts: 5

    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil? || !shop.installed?

      OrderSync.call(shop)
      Pilot::Recommendations.call(shop: shop)
    end
  end
end
