# frozen_string_literal: true

class CatalogInventoryLevel < ApplicationRecord
  belongs_to :catalog_variant

  validates :location_external_id, presence: true, uniqueness: { scope: :catalog_variant_id }
  validates :available, presence: true, numericality: { only_integer: true }
end
