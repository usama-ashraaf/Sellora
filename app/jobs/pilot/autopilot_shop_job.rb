# frozen_string_literal: true

module Pilot
  class AutopilotShopJob < ApplicationJob
    queue_as :default

    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil? || !shop.installed?

      Autopilot.call(shop: shop)
    end
  end
end
