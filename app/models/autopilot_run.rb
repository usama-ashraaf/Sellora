# frozen_string_literal: true

class AutopilotRun < ApplicationRecord
  STATUSES = %w[running skipped completed failed].freeze

  belongs_to :account
  belongs_to :shop
  belongs_to :autopilot_policy

  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true
  validate :account_matches_shop

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank? || shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end
end
