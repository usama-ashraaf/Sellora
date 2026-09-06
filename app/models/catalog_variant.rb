# frozen_string_literal: true

class CatalogVariant < ApplicationRecord
  belongs_to :catalog_product
  has_many :catalog_inventory_levels, dependent: :destroy

  validates :external_id, presence: true, uniqueness: { scope: :catalog_product_id }

  delegate :shop, to: :catalog_product
end
