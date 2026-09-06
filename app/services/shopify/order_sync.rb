# frozen_string_literal: true

module Shopify
  # Syncs order headers + line items via Admin GraphQL (Phase B read_orders).
  # Financial/fulfillment status are Shopify labels — not COD collection or profit.
  class OrderSync
    Error = Class.new(StandardError)

    ORDERS_QUERY = <<~GRAPHQL.freeze
      query SelloraOrders($cursor: String) {
        orders(first: 25, after: $cursor, sortKey: PROCESSED_AT, reverse: true) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            name
            currencyCode
            displayFinancialStatus
            displayFulfillmentStatus
            cancelReason
            cancelledAt
            processedAt
            totalPriceSet { shopMoney { amount currencyCode } }
            subtotalPriceSet { shopMoney { amount currencyCode } }
            totalDiscountsSet { shopMoney { amount currencyCode } }
            lineItems(first: 50) {
              nodes {
                id
                name
                sku
                quantity
                originalUnitPriceSet { shopMoney { amount currencyCode } }
                variant { id }
                product { id }
              }
            }
          }
        }
      }
    GRAPHQL

    def self.call(shop)
      new(shop).call
    end

    def initialize(shop)
      @shop = shop
      raise Error, "shop is not installed" unless shop.installed?
      raise Error, "shop has no account" if shop.account.blank?
    end

    def call
      @client = AdminClient.new(@shop)
      count = 0
      each_order_node { |node| upsert_order!(node); count += 1 }
      {
        orders: count,
        shop_id: @shop.id
      }
    end

    private

    def each_order_node
      cursor = nil
      loop do
        payload = @client.graphql(ORDERS_QUERY, { "cursor" => cursor })
        connection = payload.fetch("orders")
        Array(connection["nodes"]).each { |node| yield node }
        page_info = connection.fetch("pageInfo")
        break unless page_info["hasNextPage"]

        cursor = page_info["endCursor"]
        break if cursor.blank?
      end
    end

    def upsert_order!(node)
      external_id = node.fetch("id")
      order = @shop.commerce_orders.find_or_initialize_by(external_id: external_id)
      order.account = @shop.account
      order.name = node["name"]
      order.currency = money_currency(node, "totalPriceSet") || node["currencyCode"].presence || "PKR"
      order.financial_status = node["displayFinancialStatus"].to_s.downcase.presence
      order.fulfillment_status = node["displayFulfillmentStatus"].to_s.downcase.presence
      order.cancel_reason = node["cancelReason"].presence
      order.cancelled_at = parse_time(node["cancelledAt"])
      order.processed_at = parse_time(node["processedAt"])
      order.total_price = money_amount(node, "totalPriceSet")
      order.subtotal_price = money_amount(node, "subtotalPriceSet")
      order.total_discounts = money_amount(node, "totalDiscountsSet")
      order.raw_attrs = {
        "platform" => "shopify",
        "financial_status" => node["displayFinancialStatus"],
        "fulfillment_status" => node["displayFulfillmentStatus"]
      }
      order.save!

      seen = []
      Array(node.dig("lineItems", "nodes")).each do |line_node|
        seen << upsert_line!(order, line_node)
      end
      order.commerce_order_lines.where.not(external_id: seen).find_each(&:destroy!)
      order
    end

    def upsert_line!(order, node)
      external_id = node.fetch("id")
      line = order.commerce_order_lines.find_or_initialize_by(external_id: external_id)
      line.title = node["name"]
      line.sku = node["sku"].presence
      line.quantity = node["quantity"].to_i
      line.price = money_amount(node, "originalUnitPriceSet")
      line.variant_external_id = node.dig("variant", "id")
      line.product_external_id = node.dig("product", "id")
      line.raw_attrs = { "platform" => "shopify" }
      line.save!
      external_id
    end

    def money_amount(node, key)
      raw = node.dig(key, "shopMoney", "amount")
      return if raw.blank?

      BigDecimal(raw.to_s)
    rescue ArgumentError
      nil
    end

    def money_currency(node, key)
      node.dig(key, "shopMoney", "currencyCode").presence
    end

    def parse_time(raw)
      return if raw.blank?

      Time.iso8601(raw.to_s)
    rescue ArgumentError
      nil
    end
  end
end
