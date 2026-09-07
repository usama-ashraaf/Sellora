# frozen_string_literal: true

module Webhooks
  class ShopifyPrivacyController < ActionController::Base
    TOPICS = %w[customers/data_request customers/redact shop/redact].freeze

    skip_forgery_protection
    before_action :verify_hmac!

    def receive
      topic = request.headers["X-Shopify-Topic"].to_s
      return head :not_found unless topic.in?(TOPICS)
      return head :ok unless claim_delivery!(topic)

      Shopify::ShopRedactionJob.perform_later(shop_domain) if topic == "shop/redact"
      head :ok
    end

    private

    def verify_hmac!
      return if Shopify::HmacVerifier.valid_webhook?(
        raw_body: request.raw_post,
        hmac_header: request.headers["X-Shopify-Hmac-Sha256"]
      )

      head :unauthorized
    end

    def shop_domain
      Shop.normalize_domain(request.headers["X-Shopify-Shop-Domain"].presence || parsed_payload["shop_domain"])
    end

    def parsed_payload
      @parsed_payload ||= JSON.parse(request.raw_post)
    rescue JSON::ParserError
      {}
    end

    def claim_delivery!(topic)
      delivery_id = request.headers["X-Shopify-Webhook-Id"].presence
      event_key = delivery_id ? "id:#{delivery_id}" : "fp:#{Digest::SHA256.hexdigest(request.raw_post)}"
      WebhookEvent.claim!(shopify_domain: shop_domain || "unknown", topic: topic, event_key: event_key)
    end
  end
end
