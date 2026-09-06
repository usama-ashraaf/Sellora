# frozen_string_literal: true

# Per-shop bounded autopilot settings (M6). enabled=false is the kill switch.
class AutopilotPolicy < ApplicationRecord
  SEVERITIES = %w[high medium low].freeze

  belongs_to :account
  belongs_to :shop

  validates :min_severity, inclusion: { in: SEVERITIES }
  validates :cooldown_hours, numericality: { greater_than_or_equal_to: 1 }
  validates :max_actions_per_day, numericality: { greater_than_or_equal_to: 0 }
  validate :account_matches_shop

  def kill_switch!
    update!(enabled: false, kill_switch_at: Time.current, kill_switch_reason: "manual_kill_switch")
  end

  def allows_kind?(kind)
    enabled? && Array(allowed_action_kinds).include?(kind.to_s)
  end

  def severity_allowed?(severity)
    rank = { "high" => 0, "medium" => 1, "low" => 2 }
    (rank[severity.to_s] || 99) <= (rank[min_severity] || 99)
  end

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank? || shop.account_id.blank?
    return if shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end
end
