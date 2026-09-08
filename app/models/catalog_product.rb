# frozen_string_literal: true

class CatalogProduct < ApplicationRecord
  belongs_to :shop
  has_many :catalog_variants, dependent: :destroy
  has_one :promotion_decision, dependent: :destroy

  validates :external_id, presence: true, uniqueness: { scope: :shop_id }
  validates :title, presence: true
  validates :status, presence: true
end
