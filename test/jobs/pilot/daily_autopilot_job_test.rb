# frozen_string_literal: true

require "test_helper"

class Pilot::DailyAutopilotJobTest < ActiveJob::TestCase
  test "queues only enabled policies whose kill switch is clear" do
    account = Account.create!(name: "Scheduled Pilot")
    enabled_shop = Shop.create!(shopify_domain: "enabled-auto.myshopify.com", access_token: "token", account: account)
    disabled_shop = Shop.create!(shopify_domain: "disabled-auto.myshopify.com", access_token: "token", account: account)
    stopped_shop = Shop.create!(shopify_domain: "stopped-auto.myshopify.com", access_token: "token", account: account)
    Pilot::Autopilot.ensure_policy!(enabled_shop).update!(enabled: true)
    Pilot::Autopilot.ensure_policy!(disabled_shop)
    Pilot::Autopilot.ensure_policy!(stopped_shop).update!(enabled: true, kill_switch_at: Time.current)

    assert_enqueued_with(job: Pilot::AutopilotShopJob, args: [ enabled_shop.id ]) do
      Pilot::DailyAutopilotJob.perform_now
    end
    assert_enqueued_jobs 1, only: Pilot::AutopilotShopJob
  end
end
