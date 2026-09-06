# frozen_string_literal: true

require "test_helper"

class ActivityEventTest < ActiveSupport::TestCase
  test "is append-only on update" do
    account = Account.create!(name: "Evt Co")
    event = ActivityEvent.create!(
      account: account,
      event_name: "demo.ping",
      occurred_at: Time.current,
      payload: { "ok" => true },
      source: "test"
    )
    event.payload = { "ok" => false }
    assert_not event.valid?
    assert_includes event.errors[:base].join, "append-only"
  end
end
