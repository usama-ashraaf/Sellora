# frozen_string_literal: true

module Webhooks
  class ShopifyController < ActionController::Base
    # Webhooks are server-to-server; no CSRF token and no browser gate.
    skip_forgery_protection

    before_action :verify_hmac!

    # POST /webhooks/shopify/products_create
    # POST /webhooks/shopify/products_update
    # POST /webhooks/shopify/products_delete
    # POST /webhooks/shopify/inventory_levels_update
    # POST /webhooks/shopify/app_uninstalled
    def receive
      topic = params[:topic].to_s
      unless %w[products_create products_update products_delete inventory_levels_update app_uninstalled].include?(topic)
        return head :not_found
      end

      # Idempotency ledger: record once, skip duplicate deliveries.
      unless claim_webhook_event!(topic)
        Rails.logger.info("[shopify webhook] duplicate skipped topic=#{topic} shop=#{shop_domain} key=#{webhook_event_key}")
        return head :ok
      end

      case topic
      when "products_create", "products_update", "products_delete"
        handle_products_stub
      when "inventory_levels_update"
        handle_inventory_stub
      when "app_uninstalled"
        handle_app_uninstalled
      end

      head :ok
    end

    private

    def verify_hmac!
      raw = request.raw_post
      hmac = request.headers["X-Shopify-Hmac-Sha256"]
      unless Shopify::HmacVerifier.valid_webhook?(raw_body: raw, hmac_header: hmac)
        head :unauthorized
      end
    end

    def shop_domain
      request.headers["X-Shopify-Shop-Domain"].presence ||
        Shop.normalize_domain(params.dig(:shop_domain))
    end

    def webhook_event_key
      webhook_id = request.headers["X-Shopify-Webhook-Id"].presence
      return "id:#{webhook_id}" if webhook_id.present?

      # Fallback fingerprint when Shopify omits webhook id (tests / older deliveries).
      hmac = request.headers["X-Shopify-Hmac-Sha256"].to_s
      "fp:#{Digest::SHA256.hexdigest("#{shop_domain}|#{params[:topic]}|#{hmac}|#{request.raw_post}")}"
    end

    def claim_webhook_event!(topic)
      domain = Shop.normalize_domain(shop_domain).presence || "unknown"
      WebhookEvent.claim!(
        shopify_domain: domain,
        topic: topic,
        event_key: webhook_event_key
      )
    end

    def handle_products_stub
      # Phase A stub: acknowledge only. Catalog sync lands in a later slice.
      Rails.logger.info("[shopify webhook] products topic=#{params[:topic]} shop=#{shop_domain}")
    end

    def handle_inventory_stub
      Rails.logger.info("[shopify webhook] inventory_levels/update shop=#{shop_domain}")
    end

    def handle_app_uninstalled
      domain = Shop.normalize_domain(shop_domain)
      return if domain.blank?

      shop = Shop.find_by(shopify_domain: domain)
      shop&.mark_uninstalled!
    end
  end
end
