# frozen_string_literal: true

require "test_helper"

class Audit::ClothingRulesSeedTest < ActiveSupport::TestCase
  test "seeds v1 clothing rules idempotently" do
    first = Audit::ClothingRulesSeed.call
    second = Audit::ClothingRulesSeed.call

    assert_equal first.id, second.id
    assert_equal "v1", first.version
    assert first.active?
    keys = first.audit_rules.pluck(:rule_key)
    assert_includes keys, "size_gap"
    assert_includes keys, "compare_at_anomaly"
    assert_includes keys, "missing_size_attr"
    assert_operator keys.size, :>=, 6
  end
end
