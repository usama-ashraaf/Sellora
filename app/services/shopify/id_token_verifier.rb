# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "uri"

module Shopify
  class IdTokenVerifier
    Error = Class.new(StandardError)
    CLOCK_SKEW = 5

    def self.verify(token)
      new(token).verify
    end

    def initialize(token)
      @token = token.to_s
    end

    def verify
      header_segment, payload_segment, signature_segment = @token.split(".", 3)
      raise Error, "Malformed Shopify ID token" if [ header_segment, payload_segment, signature_segment ].any?(&:blank?)

      header = decode_json(header_segment)
      payload = decode_json(payload_segment)
      raise Error, "Unsupported Shopify ID token algorithm" unless header["alg"] == "HS256"

      verify_signature!(header_segment, payload_segment, signature_segment)
      verify_claims!(payload)
      payload
    rescue JSON::ParserError, ArgumentError, URI::InvalidURIError
      raise Error, "Malformed Shopify ID token"
    end

    private

    def decode_json(segment)
      JSON.parse(Base64.urlsafe_decode64(segment.ljust((segment.length + 3) / 4 * 4, "=")))
    end

    def verify_signature!(header_segment, payload_segment, signature_segment)
      secret = ShopifyConfig.api_secret
      raise Error, "Shopify app secret is not configured" if secret.blank?

      digest = OpenSSL::HMAC.digest("SHA256", secret, "#{header_segment}.#{payload_segment}")
      expected = Base64.urlsafe_encode64(digest, padding: false)
      valid = signature_segment.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(signature_segment, expected)
      raise Error, "Invalid Shopify ID token signature" unless valid
    end

    def verify_claims!(payload)
      now = Time.now.to_i
      raise Error, "Expired Shopify ID token" unless payload["exp"].to_i > now
      raise Error, "Shopify ID token is not active" if payload["nbf"].to_i > now + CLOCK_SKEW
      raise Error, "Invalid Shopify ID token audience" unless Array(payload["aud"]).include?(ShopifyConfig.client_id)

      issuer_host = URI.parse(payload.fetch("iss")).host
      destination_host = URI.parse(payload.fetch("dest")).host
      raise Error, "Shopify ID token shop mismatch" if issuer_host.blank? || issuer_host != destination_host
      raise Error, "Invalid Shopify ID token destination" unless destination_host.match?(Shop::DOMAIN_FORMAT)
    end
  end
end
