# frozen_string_literal: true

module Activity
  # Consent-aware ingest for storefront web pixel events (source: "web_pixel").
  # Fail-closed: missing or non-true analytics consent never persists an event.
  # See docs/web-pixel.md and docs/activity-events.md.
  class WebPixelIngest
    Error = Class.new(StandardError)
    ConsentDenied = Class.new(Error)

    ALLOWED_EVENTS = %w[
      page_viewed
      product_viewed
      product_added_to_cart
    ].freeze

    def self.call(shop_domain:, event_name:, consent:, occurred_at: Time.current, payload: {})
      new(
        shop_domain: shop_domain,
        event_name: event_name,
        consent: consent,
        occurred_at: occurred_at,
        payload: payload
      ).call
    end

    def initialize(shop_domain:, event_name:, consent:, occurred_at:, payload:)
      @shop_domain = shop_domain
      @event_name = event_name
      @consent = consent
      @occurred_at = occurred_at
      @payload = payload
    end

    def call
      domain = Shop.normalize_domain(@shop_domain)
      raise Error, "shop_domain required" if domain.blank?

      name = @event_name.to_s.strip
      raise Error, "event_name required" if name.blank?
      raise Error, "unsupported event_name: #{name}" unless ALLOWED_EVENTS.include?(name)

      assert_consent_allows!

      shop = Shop.find_by(shopify_domain: domain)
      raise Error, "unknown or uninstalled shop" unless shop&.installed?
      raise Error, "shop has no account" if shop.account.blank?

      safe_payload = sanitize_payload(@payload).merge("consent" => consent_snapshot)

      Activity::Ingest.call(
        account: shop.account,
        shop: shop,
        event_name: name,
        occurred_at: @occurred_at.presence || Time.current,
        payload: safe_payload,
        source: "web_pixel"
      )
    end

    private

    def assert_consent_allows!
      unless @consent.is_a?(Hash)
        raise ConsentDenied, "consent flags required"
      end

      analytics = truthy_flag(@consent, "analytics_processing_allowed", "analyticsProcessingAllowed")
      if analytics.nil?
        raise ConsentDenied, "analytics consent flag missing"
      end
      unless analytics
        raise ConsentDenied, "analytics consent not granted"
      end
    end

    # Returns true/false when present, nil when missing (fail-closed for missing).
    def truthy_flag(hash, *keys)
      keys.each do |key|
        return true if hash.key?(key) && cast_bool(hash[key]) == true
        return false if hash.key?(key) && cast_bool(hash[key]) == false
        sym = key.to_sym
        return true if hash.key?(sym) && cast_bool(hash[sym]) == true
        return false if hash.key?(sym) && cast_bool(hash[sym]) == false
      end
      nil
    end

    def cast_bool(value)
      case value
      when true, false then value
      when "true", "1", 1 then true
      when "false", "0", 0 then false
      else
        # Unknown shapes treated as not granted (fail-closed) when key was present.
        false
      end
    end

    def consent_snapshot
      {
        "analytics_processing_allowed" => truthy_flag(@consent, "analytics_processing_allowed", "analyticsProcessingAllowed") == true,
        "marketing_allowed" => truthy_flag(@consent, "marketing_allowed", "marketingAllowed") == true,
        "preferences_processing_allowed" => truthy_flag(@consent, "preferences_processing_allowed", "preferencesProcessingAllowed") == true,
        "sale_of_data_allowed" => truthy_flag(@consent, "sale_of_data_allowed", "saleOfDataAllowed") == true
      }
    end

    def sanitize_payload(raw)
      return {} unless raw.is_a?(Hash)

      raw.stringify_keys.except("access_token", "token", "secret", "hmac", "authorization")
    end
  end
end
