# frozen_string_literal: true

class AuditRuleSet < ApplicationRecord
  has_many :audit_rules, dependent: :destroy

  validates :name, presence: true
  validates :version, presence: true, uniqueness: { scope: :domain }
  validates :domain, presence: true

  scope :active, -> { where(active: true) }
  scope :clothing, -> { where(domain: "clothing") }

  def self.current_clothing
    clothing.active.order(created_at: :desc).first
  end

  # Activates this set and deactivates other sets in the same domain.
  def activate!
    transaction do
      self.class.where(domain: domain).where.not(id: id).update_all(active: false)
      update!(active: true)
    end
  end
end
