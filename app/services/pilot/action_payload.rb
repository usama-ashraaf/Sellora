# frozen_string_literal: true

module Pilot
  class ActionPayload
    Error = Class.new(StandardError)
    DEFAULT_DISCOUNT_PERCENTAGE = 10
    DISCOUNT_DURATION = 7.days

    def self.build(recommendation:, attributes: {})
      new(recommendation, attributes.stringify_keys).build
    end

    def initialize(recommendation, attributes)
      @recommendation = recommendation
      @attributes = attributes
      @product = recommendation.catalog_product
    end

    def build
      raise Error, "This recommendation is not connected to a product" if @product.blank?

      if @recommendation.kind.in?(%w[promotion_opportunity social_ad_candidate])
        discount_payload
      elsif clear_compare_at_price?
        compare_at_payload
      else
        product_payload
      end
    end

    private

    def discount_payload
      percentage = integer_attribute(:percentage, default: DEFAULT_DISCOUNT_PERCENTAGE)
      raise Error, "Discount percentage must be between 1 and 80" unless percentage.between?(1, 80)

      starts_at = time_attribute(:starts_at, default: Time.current)
      ends_at = time_attribute(:ends_at, default: starts_at + DISCOUNT_DURATION)
      raise Error, "Discount end must be after its start" unless ends_at > starts_at

      code = @attributes["code"].presence || default_discount_code
      code = code.to_s.upcase.gsub(/[^A-Z0-9_-]/, "").first(40)
      raise Error, "Discount code must contain letters or numbers" if code.blank?

      {
        "operation" => "discount_code_create",
        "title" => "Sellora: #{@product.title} #{percentage}% off",
        "code" => code,
        "percentage" => percentage,
        "starts_at" => starts_at.iso8601,
        "ends_at" => ends_at.iso8601,
        "product_ids" => [ @product.external_id ],
        "estimated_discount_cost" => estimated_discount_cost(percentage).to_s
      }
    end

    def clear_compare_at_price?
      @recommendation.kind == "promotion_accuracy" &&
        @recommendation.audit_finding&.catalog_variant.present?
    end

    def compare_at_payload
      variant = @recommendation.audit_finding.catalog_variant
      {
        "operation" => "variant_compare_at_clear",
        "product_id" => @product.external_id,
        "variants" => [ { "id" => variant.external_id, "compare_at_price" => nil } ]
      }
    end

    def product_payload
      title = @attributes["title"].to_s.strip
      description_html = @attributes["description_html"].to_s.strip
      current_title = @product.title.to_s
      current_description = @product.raw_attrs["description_html"].to_s
      changes = {}
      changes["title"] = title if title.present? && title != current_title
      changes["description_html"] = description_html if description_html.present? && description_html != current_description
      raise Error, "Enter a changed title or product description before preparing the action" if changes.empty?

      { "operation" => "product_update", "product_id" => @product.external_id }.merge(changes)
    end

    def default_discount_code
      suffix = @product.external_id.to_s.split("/").last
      "SELLORA#{suffix.to_s.last(6)}"
    end

    def estimated_discount_cost(percentage)
      inventory_value = BigDecimal(@recommendation.evidence.fetch("inventory_retail_value", 0).to_s)
      (inventory_value * percentage / 100).round(2)
    rescue ArgumentError
      BigDecimal("0")
    end

    def integer_attribute(key, default:)
      raw = @attributes[key.to_s]
      raw.present? ? Integer(raw.to_s, 10) : default
    rescue ArgumentError
      raise Error, "#{key.to_s.humanize} must be a whole number"
    end

    def time_attribute(key, default:)
      raw = @attributes[key.to_s]
      value = raw.present? ? Time.zone.parse(raw) : default
      raise ArgumentError if value.nil?

      value
    rescue ArgumentError, TypeError
      raise Error, "#{key.to_s.humanize} is invalid"
    end
  end
end
