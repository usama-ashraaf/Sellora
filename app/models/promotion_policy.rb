# frozen_string_literal: true

# Merchant assumptions used to turn current demand and inventory into promotion limits.
class PromotionPolicy < ApplicationRecord
  belongs_to :account
  belongs_to :shop

  validates :target_roas, numericality: { greater_than: 0 }
  validates :target_acquisition_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :shipping_cost_per_order, :cod_failure_cost, numericality: { greater_than_or_equal_to: 0 }
  validates :expected_cod_failure_rate_percent, numericality: { in: 0..100 }
  validates :desired_runway_days, :minimum_safe_orders, numericality: { only_integer: true, greater_than: 0 }
  validates :minimum_margin_percent, numericality: { only_integer: true, in: 0..100 }
  validate :account_matches_shop

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank? || shop.account_id.blank?
    return if shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end
end
