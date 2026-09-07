# frozen_string_literal: true

module Shopify
  class DiscountCreator
    Error = Class.new(StandardError)

    CREATE_MUTATION = <<~GRAPHQL.freeze
      mutation SelloraDiscountCodeCreate($input: DiscountCodeBasicInput!) {
        discountCodeBasicCreate(basicCodeDiscount: $input) {
          codeDiscountNode {
            id
            codeDiscount {
              ... on DiscountCodeBasic {
                title
                startsAt
                endsAt
                codes(first: 1) { nodes { code } }
              }
            }
          }
          userErrors { field message }
        }
      }
    GRAPHQL

    def self.apply(shop:, action:)
      new(shop: shop, action: action).apply
    end

    def initialize(shop:, action:)
      @shop = shop
      @payload = action.after_snapshot
    end

    def apply
      require_scope!
      response = Shopify::AdminClient.new(@shop).graphql(CREATE_MUTATION, { "input" => input })
      result = response.fetch("discountCodeBasicCreate")
      raise_user_errors!(result)
      node = result.fetch("codeDiscountNode")
      code = node.dig("codeDiscount", "codes", "nodes", 0, "code") || @payload.fetch("code")
      {
        message: "Created Shopify discount code #{code}.",
        after: @payload.merge("shopify_discount_id" => node.fetch("id"), "shopify_result" => node["codeDiscount"])
      }
    end

    private

    def input
      {
        "title" => @payload.fetch("title"),
        "code" => @payload.fetch("code"),
        "startsAt" => @payload.fetch("starts_at"),
        "endsAt" => @payload.fetch("ends_at"),
        "context" => { "all" => true },
        "customerGets" => {
          "value" => { "percentage" => @payload.fetch("percentage").to_f / 100 },
          "items" => { "products" => { "productsToAdd" => @payload.fetch("product_ids") } }
        },
        "appliesOncePerCustomer" => true
      }
    end

    def require_scope!
      return if @shop.scope.to_s.split(",").map(&:strip).include?("write_discounts")

      raise Error, "write_discounts scope missing; reconnect the Shopify app to approve it"
    end

    def raise_user_errors!(result)
      errors = Array(result["userErrors"])
      return if errors.empty?

      raise Error, errors.map { |error| error["message"] }.join("; ")
    end
  end
end
