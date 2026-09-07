# frozen_string_literal: true

module Shopify
  class ActionExecutor
    Error = Class.new(StandardError)

    def self.apply(shop:, action:)
      raise Error, "Shopify writes are disabled" unless ShopifyConfig.allow_writes?

      operation = action.after_snapshot.fetch("operation")
      case operation
      when "product_update", "variant_compare_at_clear"
        ProductPatch.apply(shop: shop, action: action)
      when "discount_code_create"
        DiscountCreator.apply(shop: shop, action: action)
      else
        raise Error, "Unsupported action operation: #{operation}"
      end
    rescue KeyError
      raise Error, "Action has no operation"
    end
  end
end
