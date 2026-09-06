# frozen_string_literal: true

module Pilot
  class DailyDiscoveryJob < ApplicationJob
    queue_as :default

    def perform
      Shop.installed.find_each do |shop|
        DiscoverShopJob.perform_later(shop.id, sync: true)
      end
    end
  end
end
