# frozen_string_literal: true

# Merchant-reviewed change proposal (M5). Apply is gated; never silent write.
class ReviewedAction < ApplicationRecord
  STATUSES = %w[
    draft
    pending_approval
    approved
    rejected
    applied
    failed
    cancelled
    conflict
  ].freeze

  belongs_to :account
  belongs_to :shop
  belongs_to :recommendation, optional: true
  belongs_to :audit_finding, optional: true

  validates :action_kind, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :account_matches_shop

  scope :for_shop, ->(shop) { where(shop_id: shop.id) }
  scope :pending, -> { where(status: %w[draft pending_approval approved]) }
  scope :history, -> { where(status: %w[applied failed rejected cancelled conflict]).order(updated_at: :desc) }

  def pending_approval?
    status == "pending_approval"
  end

  def approved?
    status == "approved"
  end

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank? || shop.account_id.blank?
    return if shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end
end
