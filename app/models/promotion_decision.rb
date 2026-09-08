# frozen_string_literal: true

# Latest explainable promotion-readiness snapshot for one product.
class PromotionDecision < ApplicationRecord
  STATUSES = %w[promote limit block].freeze
  CONFIDENCE_LEVELS = %w[high medium low].freeze

  belongs_to :account
  belongs_to :shop
  belongs_to :catalog_product

  validates :status, inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCE_LEVELS }
  validates :score, numericality: { only_integer: true, in: 0..100 }
  validates :generated_at, presence: true
  validate :account_matches_shop
  validate :product_matches_shop

  scope :ranked, -> { order(Arel.sql("CASE status WHEN 'promote' THEN 0 WHEN 'limit' THEN 1 ELSE 2 END"), score: :desc) }

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank? || shop.account_id.blank?
    return if shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end

  def product_matches_shop
    return if shop.blank? || catalog_product.blank?
    return if catalog_product.shop_id == shop_id

    errors.add(:catalog_product_id, "must belong to shop")
  end
end
