# frozen_string_literal: true

class Shop < ApplicationRecord
  DOMAIN_FORMAT = /\A[a-z0-9][a-z0-9\-]*\.myshopify\.com\z/i

  # Offline Admin API token — encrypted at rest via Active Record encryption.
  encrypts :access_token

  belongs_to :account, optional: true
  has_many :catalog_products, dependent: :destroy
  has_many :audit_findings, dependent: :destroy
  has_many :activity_events, dependent: :nullify

  validates :shopify_domain, presence: true, uniqueness: true, format: { with: DOMAIN_FORMAT }

  before_validation :normalize_blank_access_token

  scope :installed, -> { where(uninstalled_at: nil).where.not(access_token: nil) }
  scope :for_account, ->(account) { where(account_id: account.id) }

  def installed?
    uninstalled_at.nil? && access_token.present?
  end

  # Clears the offline token and purges platform-neutral catalog rows for this shop.
  # Privacy: on uninstall we do not retain catalog_products / variants / inventory_levels.
  def mark_uninstalled!
    transaction do
      catalog_products.find_each(&:destroy!)
      update!(uninstalled_at: Time.current, access_token: nil)
    end
  end

  def self.normalize_domain(raw)
    return if raw.blank?

    host = raw.to_s.strip.downcase
    host = host.delete_prefix("https://").delete_prefix("http://")
    host = host.split("/").first.to_s
    host = host.split("?").first.to_s
    host.presence
  end

  private

  def normalize_blank_access_token
    self.access_token = nil if access_token.blank?
  end
end
