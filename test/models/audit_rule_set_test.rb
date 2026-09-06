# frozen_string_literal: true

require "test_helper"

class AuditRuleSetTest < ActiveSupport::TestCase
  test "activate! deactivates other sets in domain" do
    a = AuditRuleSet.create!(name: "A", version: "v1", domain: "clothing", active: true)
    b = AuditRuleSet.create!(name: "B", version: "v2", domain: "clothing", active: false)
    b.activate!
    assert b.reload.active?
    assert_not a.reload.active?
  end
end
