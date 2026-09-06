# frozen_string_literal: true

module Audit
  # Content fingerprint for change-aware audits (M4).
  class Fingerprint
    def self.for_product(product)
      variants = product.catalog_variants.sort_by(&:external_id).map do |v|
        [ v.external_id, v.title, v.option_summary, v.sku ]
      end
      payload = {
        "title" => product.title,
        "handle" => product.handle,
        "status" => product.status,
        "raw" => normalize(product.raw_attrs.except("variant_prices")),
        "variants" => variants
      }
      Digest::SHA256.hexdigest(payload.to_json)
    end

    def self.freshness_signature(product)
      levels = product.catalog_variants.flat_map do |v|
        v.catalog_inventory_levels.sort_by(&:location_external_id).map { |l| [ v.external_id, l.location_external_id, l.available ] }
      end
      prices = normalize(product.raw_attrs["variant_prices"])
      Digest::SHA256.hexdigest({ "inventory" => levels, "prices" => prices }.to_json)
    end

    def self.normalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.index_with { |k| normalize(value[k] || value[k.to_sym]) }
      when Array
        value.map { |v| normalize(v) }
      else
        value
      end
    end
    private_class_method :normalize
  end
end
