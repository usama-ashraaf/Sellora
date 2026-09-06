# frozen_string_literal: true

module Shopify
  # Optional Admin write for approved reviewed actions (M5). Disabled unless SELLORA_ALLOW_WRITES.
  class ProductPatch
    Error = Class.new(StandardError)

    def self.apply(shop:, action:)
      new(shop: shop, action: action).apply
    end

    def initialize(shop:, action:)
      @shop = shop
      @action = action
    end

    def apply
      raise Error, "write_products scope missing" unless @shop.scope.to_s.include?("write_products")
      raise Error, "SELLORA_ALLOW_WRITES not enabled" unless ENV["SELLORA_ALLOW_WRITES"].to_s == "true"

      # Intentionally minimal: no autonomous pricing. Only records intent for catalog_fix kinds.
      {
        message: "Write path acknowledged for #{@action.action_kind} (no autonomous pricing). " \
                 "Implement concrete productUpdate payloads per approved action kind carefully.",
        after: @action.after_snapshot
      }
    end
  end
end
