# frozen_string_literal: true

module WebPixels
  # POST /web_pixels/events — minimal storefront pixel ingest stub.
  # Auth: shared secret header (X-Sellora-Pixel-Secret). App proxy later — see docs/web-pixel.md.
  class EventsController < ActionController::Base
    skip_forgery_protection

    before_action :verify_shared_secret!

    def create
      event = Activity::WebPixelIngest.call(
        shop_domain: permitted[:shop_domain],
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

    def verify_shared_secret!
      expected = ShopifyConfig.web_pixel_ingest_secret
      provided = request.headers["X-Sellora-Pixel-Secret"].to_s
      unless secret_match?(expected, provided)
        head :unauthorized
      end
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
