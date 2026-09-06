# frozen_string_literal: true

# Platform-neutral order header. A placed order is not proof of payment or COD collection.
class CommerceOrder < ApplicationRecord
  belongs_to :account
  belongs_to :shop
  has_many :commerce_order_lines, dependent: :destroy

  validates :external_id, presence: true
  validates :currency, presence: true
  validate :account_matches_shop

  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :for_shop, ->(shop) { where(shop_id: shop.id) }

  private

  def account_matches_shop
    return if shop.blank? || account_id.blank? || shop.account_id.blank?
    return if shop.account_id == account_id

    errors.add(:account_id, "must match shop account")
  end
end
