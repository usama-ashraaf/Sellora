# frozen_string_literal: true

module WebPixels
  # POST /web_pixels/events — consent-aware storefront pixel ingest.
  # Browser auth: X-Sellora-Pixel-Token (installation-scoped, write-only).
  # Server/test auth: X-Sellora-Pixel-Secret (WEB_PIXEL_INGEST_SECRET). See docs/web-pixel.md.
  class EventsController < ActionController::Base
    skip_forgery_protection

    before_action :cors_headers
    before_action :limit_body!, only: :create
    before_action :limit_ip!, only: :create
    before_action :verify_ingest_access!, only: :create
    before_action :limit_shop!, only: :create

    def preflight
      head :no_content
    end

    def create
      event = Activity::WebPixelIngest.call(
        shop_domain: @pixel_shop.shopify_domain,
        event_name: permitted[:event_name],
        consent: consent_param,
        occurred_at: parse_occurred_at(permitted[:occurred_at]),
        payload: payload_param
      )
      render json: { id: event.id, event_name: event.event_name, source: event.source }, status: :created
    rescue Activity::WebPixelIngest::ConsentDenied => e
      render json: { error: e.message }, status: :forbidden
    rescue Activity::WebPixelIngest::Error, Activity::Ingest::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def cors_headers
      response.set_header("Access-Control-Allow-Origin", "*")
      response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
      response.set_header("Access-Control-Allow-Headers", "Content-Type, X-Sellora-Pixel-Token")
      response.set_header("Access-Control-Max-Age", "600")
      response.set_header("Cache-Control", "no-store")
    end

    def limit_body!
      head :content_too_large if request.raw_post.to_s.bytesize > 16.kilobytes
    end

    def limit_ip!
      rate_limiting(to: 1200, within: 1.minute, by: -> { request.remote_ip },
                    with: -> { head :too_many_requests }, store: Rails.cache, name: "pixel-ip", scope: controller_path)
    end

    def limit_shop!
      rate_limiting(to: 300, within: 1.minute, by: -> { @pixel_shop.id },
                    with: -> { head :too_many_requests }, store: Rails.cache, name: "pixel-shop", scope: controller_path)
    end

    def verify_ingest_access!
      token = request.headers["X-Sellora-Pixel-Token"].to_s
      if token.present?
        @pixel_shop = Activity::PixelToken.resolve(token)
      elsif valid_shared_secret?
        @pixel_shop = Shop.find_by(shopify_domain: Shop.normalize_domain(permitted[:shop_domain]))
      end
      unless @pixel_shop&.installed? && @pixel_shop.account_id.present?
        return head :unauthorized
      end
      requested_domain = Shop.normalize_domain(permitted[:shop_domain])
      head :forbidden if requested_domain.present? && requested_domain != @pixel_shop.shopify_domain
    end

    def valid_shared_secret?
      expected = ShopifyConfig.web_pixel_ingest_secret
      provided = request.headers["X-Sellora-Pixel-Secret"].to_s
      secret_match?(expected, provided)
    end

    def secret_match?(expected, provided)
      return false if expected.blank? || provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(expected, provided)
    rescue ArgumentError
      false
    end

    def permitted
      params.permit(:shop_domain, :event_name, :occurred_at, :account_id, consent: {}, payload: {})
    end

    def consent_param
      raw = params[:consent]
      return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      return raw if raw.is_a?(Hash)

      nil
    end

    def payload_param
      raw = params[:payload]
      return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      return raw if raw.is_a?(Hash)

      {}
    end

    def parse_occurred_at(raw)
      return Time.current if raw.blank?

      Time.iso8601(raw.to_s)
    rescue ArgumentError
      Time.current
    end
  end
end
