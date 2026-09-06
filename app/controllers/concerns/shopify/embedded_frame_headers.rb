# frozen_string_literal: true

module Shopify
  # Allow Shopify Admin to iframe embed pages. Rails defaults to
  # X-Frame-Options: SAMEORIGIN which blanks the admin iframe.
  module EmbeddedFrameHeaders
    extend ActiveSupport::Concern

    FRAME_ANCESTORS_CSP =
      "frame-ancestors https://admin.shopify.com https://*.myshopify.com;"

    included do
      after_action :apply_shopify_embedded_frame_headers
    end

    private

    def apply_shopify_embedded_frame_headers
      # Omit X-Frame-Options entirely (do not set DENY / SAMEORIGIN).
      response.headers.delete("X-Frame-Options")
      response.headers["Content-Security-Policy"] = FRAME_ANCESTORS_CSP
    end
  end
end
