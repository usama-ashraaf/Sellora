require "uri"

class PilotRequest < ApplicationRecord
  PLATFORMS = [ "Shopify", "WooCommerce", "Custom store", "Other" ].freeze

  normalizes :name, :store_url, with: ->(value) { value.strip }
  normalizes :email, with: ->(value) { value.strip.downcase }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :store_url, presence: true, length: { maximum: 2048 }
  validates :platform, inclusion: { in: PLATFORMS }
  validate :store_url_is_public_web_address

  private

  def store_url_is_public_web_address
    return if store_url.blank?

    uri = URI.parse(store_url)
    unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.host.include?(".") && uri.userinfo.nil?
      errors.add(:store_url, "must be an http:// or https:// store address without login details")
    end
  rescue URI::InvalidURIError
    errors.add(:store_url, "must be a valid http:// or https:// store address")
  end
end
