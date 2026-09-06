# frozen_string_literal: true

require "base64"
require "openssl"

module Shopify
  class HmacVerifier
    class << self
      # Verifies X-Shopify-Hmac-Sha256 against the raw request body.
      def valid_webhook?(raw_body:, hmac_header:, secret: ShopifyConfig.api_secret)
        return false if hmac_header.blank? || secret.blank?

        digest = OpenSSL::HMAC.digest("SHA256", secret, raw_body.to_s)
        expected = Base64.strict_encode64(digest)
        ActiveSupport::SecurityUtils.secure_compare(expected, hmac_header.to_s)
      rescue ArgumentError
        false
      end

      # Verifies the query-string HMAC Shopify appends to OAuth callbacks / app proxy.
      def valid_query?(params:, secret: ShopifyConfig.api_secret)
        return false if secret.blank?

        received = params["hmac"].presence || params[:hmac].presence
        return false if received.blank?

        message = params
          .except("hmac", :hmac, "signature", :signature)
          .to_h
          .stringify_keys
          .sort
          .map { |k, v| "#{k}=#{Array(v).join(",")}" }
          .join("&")

        digest = OpenSSL::HMAC.hexdigest("SHA256", secret, message)
        ActiveSupport::SecurityUtils.secure_compare(digest, received.to_s)
      rescue ArgumentError
        false
      end
    end
  end
end
