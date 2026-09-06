# frozen_string_literal: true

class AuditFinding < ApplicationRecord
  STATUSES = %w[open acknowledged resolved dismissed].freeze
  SEVERITIES = AuditRule::SEVERITIES

  belongs_to :account
  belongs_to :shop
  belongs_to :audit_rule
  belongs_to :catalog_product, optional: true
  belongs_to :catalog_variant, optional: true

  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :message, presence: true
  validate :account_matches_shop

  # Idempotency: unique index index_audit_findings_on_natural_key
  # Optional catalog references use COALESCE in the database index so NULLs
  # represent the same identity on PostgreSQL 14 as well as newer versions.

  scope :open_findings, -> { where(status: "open") }
  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :for_shop, ->(shop) { where(shop_id: shop.id) }

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank?
    return if shop.account_id.blank?
    return if shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end
end
