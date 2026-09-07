# frozen_string_literal: true

class Shop < ApplicationRecord
  DOMAIN_FORMAT = /\A[a-z0-9][a-z0-9\-]*\.myshopify\.com\z/i

  # Offline Admin API token — encrypted at rest via Active Record encryption.
  encrypts :access_token

  belongs_to :account
  has_many :catalog_products, dependent: :destroy
  has_many :audit_findings, dependent: :destroy
  has_many :activity_events, dependent: :nullify
  has_many :commerce_orders, dependent: :destroy
  has_many :recommendations, dependent: :destroy
  has_many :reviewed_actions, dependent: :destroy
  has_many :autopilot_runs, dependent: :destroy
  has_one :autopilot_policy, dependent: :destroy

  validates :shopify_domain, presence: true, uniqueness: true, format: { with: DOMAIN_FORMAT }
  validates :account, presence: true

  before_validation :normalize_blank_access_token

  scope :installed, -> { where(uninstalled_at: nil).where.not(access_token: nil) }
  scope :for_account, ->(account) { where(account_id: account.id) }

  def installed?
    uninstalled_at.nil? && access_token.present?
  end

  # Clears the offline token and purges merchant-scoped operational data for this shop.
  # Privacy: on uninstall we do not retain catalog, findings, activity, or order rows for the shop.
  # Account / membership rows and marketing pilot_requests are separate (see docs/privacy-retention.md).
  def mark_uninstalled!
    transaction do
      purge_merchant_data!
      update!(uninstalled_at: Time.current, access_token: nil)
    end
  end

  def redact!
    self.class.transaction do
      purge_merchant_data!
      WebhookEvent.where(shopify_domain: shopify_domain).delete_all
      destroy!
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

  def purge_merchant_data!
    # Findings and reviewed actions reference catalog rows; delete them first.
    audit_findings.delete_all
    recommendations.delete_all
    reviewed_actions.delete_all
    autopilot_runs.delete_all
    autopilot_policy&.destroy!
    activity_events.delete_all
    commerce_orders.find_each(&:destroy!)
    catalog_products.find_each(&:destroy!)
  end

  def normalize_blank_access_token
    self.access_token = nil if access_token.blank?
  end
end
