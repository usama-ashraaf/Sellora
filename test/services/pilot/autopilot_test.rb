# frozen_string_literal: true

require "test_helper"

class Pilot::AutopilotTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Pilot Auto")
    @shop = Shop.create!(shopify_domain: "auto.myshopify.com", access_token: "t", account: @account)
    @policy = Pilot::Autopilot.ensure_policy!(@shop)
  end

  test "disabled by default kill switch semantics" do
    result = Pilot::Autopilot.call(shop: @shop)
    assert_equal "kill_switch_or_disabled", result[:skipped]
    assert_equal 0, result[:applied]
  end

  test "kill_switch disables policy" do
    @policy.update!(enabled: true, allowed_action_kinds: [ "catalog_fix" ])
    @policy.kill_switch!
    assert_not @policy.reload.enabled?
    assert @policy.kill_switch_at.present?
  end
end
