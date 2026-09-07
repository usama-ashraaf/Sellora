# frozen_string_literal: true

module Pilot
  class DailyAutopilotJob < ApplicationJob
    queue_as :default

    def perform
      AutopilotPolicy.where(enabled: true, kill_switch_at: nil).find_each do |policy|
        AutopilotShopJob.perform_later(policy.shop_id)
      end
    end
  end
end
