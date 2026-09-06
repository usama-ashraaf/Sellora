# frozen_string_literal: true

class CommerceOrderLine < ApplicationRecord
  belongs_to :commerce_order

  validates :external_id, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
end
