# frozen_string_literal: true

module Shopify
  module SessionTokenAuthentication
    private

    def verify_shopify_session!
      token = request.authorization.to_s.delete_prefix("Bearer ").presence
      @identity = Shopify::IdTokenVerifier.verify(token)
      domain = Shop.normalize_domain(URI.parse(@identity.fetch("dest")).host)
      raise Shopify::IdTokenVerifier::Error, "Invalid Shopify ID token destination" unless domain&.match?(Shop::DOMAIN_FORMAT)

      @shop_domain = domain
    end
  end
end
