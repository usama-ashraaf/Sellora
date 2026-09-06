# frozen_string_literal: true

class Shop < ApplicationRecord
  DOMAIN_FORMAT = /\A[a-z0-9][a-z0-9\-]*\.myshopify\.com\z/i

  validates :shopify_domain, presence: true, uniqueness: true, format: { with: DOMAIN_FORMAT }

  scope :installed, -> { where(uninstalled_at: nil).where.not(access_token: [nil, ""]) }

  def installed?
    uninstalled_at.nil? && access_token.present?
  end

  def mark_uninstalled!
    update!(uninstalled_at: Time.current, access_token: nil)
  end

  def self.normalize_domain(raw)
    return if raw.blank?

    host = raw.to_s.strip.downcase
    host = host.delete_prefix("https://").delete_prefix("http://")
    host = host.split("/").first.to_s
    host = host.split("?").first.to_s
    host.presence
  end
end
