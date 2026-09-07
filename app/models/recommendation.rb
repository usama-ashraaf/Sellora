# frozen_string_literal: true

class Recommendation < ApplicationRecord
  KINDS = %w[
    catalog_fix
    availability
    promotion_accuracy
    promotion_opportunity
    featured_product
    social_ad_candidate
    restock_before_promotion
    traffic_intent
    conversion_review
    verify_manual
  ].freeze
  PRIORITIES = %w[high medium low].freeze
  STATUSES = %w[open acknowledged proposed approved dismissed].freeze

  belongs_to :account
  belongs_to :shop
  belongs_to :audit_finding, optional: true
  belongs_to :catalog_product, optional: true
  has_many :reviewed_actions, dependent: :nullify

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :priority, presence: true, inclusion: { in: PRIORITIES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :title, :rationale, presence: true
  validate :account_matches_shop

  scope :open_items, -> { where(status: "open") }
  scope :for_shop, ->(shop) { where(shop_id: shop.id) }
  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :by_priority, -> {
    order(Arel.sql("CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END"), created_at: :desc)
  }

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank? || shop.account_id.blank?
    return if shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end
end
