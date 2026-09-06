# frozen_string_literal: true

module Pilot
  class DiscoverShopJob < ApplicationJob
    queue_as :default

    retry_on Shopify::AdminClient::TransientError, wait: :polynomially_longer, attempts: 5

    def perform(shop_id, sync: true)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil? || !shop.installed?

      Discover.call(shop: shop, sync: sync)
    end
  end
end
