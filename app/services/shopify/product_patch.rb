# frozen_string_literal: true

module Shopify
  class ProductPatch
    Error = Class.new(StandardError)

    PRODUCT_UPDATE = <<~GRAPHQL.freeze
      mutation SelloraProductUpdate($product: ProductUpdateInput!) {
        productUpdate(product: $product) {
          product { id title descriptionHtml status }
          userErrors { field message }
        }
      }
    GRAPHQL

    VARIANT_UPDATE = <<~GRAPHQL.freeze
      mutation SelloraVariantUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
        productVariantsBulkUpdate(productId: $productId, variants: $variants) {
          product { id }
          productVariants { id compareAtPrice }
          userErrors { field message }
        }
      }
    GRAPHQL

    def self.apply(shop:, action:)
      new(shop: shop, action: action).apply
    end

    def initialize(shop:, action:)
      @shop = shop
      @action = action
      @payload = action.after_snapshot
      @client = Shopify::AdminClient.new(shop)
    end

    def apply
      require_scope!("write_products")
      case @payload.fetch("operation")
      when "product_update" then update_product!
      when "variant_compare_at_clear" then update_variants!
      else raise Error, "Unsupported product operation"
      end
    end

    private

    def update_product!
      product_input = { "id" => @payload.fetch("product_id") }
      product_input["title"] = @payload["title"] if @payload["title"].present?
      product_input["descriptionHtml"] = @payload["description_html"] if @payload["description_html"].present?
      payload = @client.graphql(PRODUCT_UPDATE, { "product" => product_input }).fetch("productUpdate")
      raise_user_errors!(payload)
      product = payload.fetch("product")
      update_local_product!(product)
      { message: "Updated #{product.fetch('title')} in Shopify.", after: @payload.merge("shopify_result" => product) }
    end

    def update_variants!
      variants = @payload.fetch("variants").map do |variant|
        { "id" => variant.fetch("id"), "compareAtPrice" => variant["compare_at_price"] }
      end
      payload = @client.graphql(VARIANT_UPDATE, {
        "productId" => @payload.fetch("product_id"),
        "variants" => variants
      }).fetch("productVariantsBulkUpdate")
      raise_user_errors!(payload)
      updated = payload.fetch("productVariants")
      update_local_variant_prices!(updated)
      { message: "Cleared invalid compare-at pricing for #{updated.size} variant(s) in Shopify.",
        after: @payload.merge("shopify_result" => updated) }
    end

    def update_local_product!(result)
      product = @shop.catalog_products.find_by!(external_id: result.fetch("id"))
      description_html = result["descriptionHtml"].to_s
      attrs = product.raw_attrs.merge(
        "description_html" => description_html,
        "description" => ActionView::Base.full_sanitizer.sanitize(description_html),
        "status" => result["status"]
      )
      product.update!(title: result.fetch("title"), status: result["status"].to_s.downcase, raw_attrs: attrs)
    end

    def update_local_variant_prices!(variants)
      product = @shop.catalog_products.find_by!(external_id: @payload.fetch("product_id"))
      prices = product.raw_attrs.fetch("variant_prices", {}).deep_dup
      variants.each do |variant|
        row = prices[variant.fetch("id")] || {}
        row["compare_at_price"] = variant["compareAtPrice"]
        prices[variant.fetch("id")] = row
      end
      product.update!(raw_attrs: product.raw_attrs.merge("variant_prices" => prices))
    end

    def require_scope!(scope)
      return if @shop.scope.to_s.split(",").map(&:strip).include?(scope)

      raise Error, "#{scope} scope missing; reconnect the Shopify app to approve it"
    end

    def raise_user_errors!(payload)
      errors = Array(payload["userErrors"])
      return if errors.empty?

      raise Error, errors.map { |error| error["message"] }.join("; ")
    end
  end
end
