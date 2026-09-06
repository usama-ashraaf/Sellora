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

  # Idempotency: unique index index_audit_findings_on_natural_key
  # (shop_id, audit_rule_id, catalog_product_id, catalog_variant_id) NULLS NOT DISTINCT.

  scope :open_findings, -> { where(status: "open") }
  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :for_shop, ->(shop) { where(shop_id: shop.id) }
end
