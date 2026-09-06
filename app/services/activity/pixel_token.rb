# frozen_string_literal: true

module Activity
  # Public, write-only capability for one installation. This does not prove that
  # Shopify or a particular customer generated an event. Never use it for reads,
  # orders, billing, or automated merchant actions.
  class PixelToken
    PURPOSE = "sellora.pixel_ingest.v1"

    def self.issue(shop)
      verifier.generate({ "shop_id" => shop.id, "installation" => shop.updated_at.utc.iso8601(6) }, purpose: PURPOSE)
    end

    def self.resolve(token)
      return if token.blank? || token.bytesize > 2048

      claims = verifier.verified(token, purpose: PURPOSE)
      return unless claims.is_a?(Hash)

      shop = Shop.find_by(id: claims["shop_id"])
      return unless shop&.installed? && shop.account_id.present?
      return unless claims["installation"] == shop.updated_at.utc.iso8601(6)

      shop
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
