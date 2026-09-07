# frozen_string_literal: true

require "set"

module Pilot
  # Normalizes consent-limited storefront events and authoritative Shopify order outcomes.
  class CommerceSignals
    STOREFRONT_EVENTS = %w[
      page_viewed product_viewed product_added_to_cart product_removed_from_cart
      checkout_started payment_info_submitted checkout_completed
    ].freeze
    PAID_STATUSES = %w[paid partially_paid].freeze
    REFUNDED_STATUSES = %w[refunded partially_refunded].freeze
    COD_PATTERN = /cash|cod|delivery/i

    def self.call(shop:, storefront_since: 7.days.ago, orders_since: 30.days.ago)
      new(shop: shop, storefront_since: storefront_since, orders_since: orders_since).call
    end

    def initialize(shop:, storefront_since:, orders_since:)
      @shop = shop
      @storefront_since = storefront_since
      @orders_since = orders_since
    end

    def call
      products = product_rows
      funnel = STOREFRONT_EVENTS.index_with { 0 }
      aggregate_events!(products, funnel)
      outcomes = aggregate_orders!(products)

      {
        funnel: funnel,
        order_outcomes: outcomes,
        products: products.values.sort_by { |row| row[:title].downcase },
        storefront_window_days: window_days(@storefront_since),
        orders_window_days: window_days(@orders_since)
      }
    end

    private

    def product_rows
      @shop.catalog_products.includes(catalog_variants: :catalog_inventory_levels).each_with_object({}) do |product, rows|
        rows[product.external_id] = {
          product: product,
          title: product.title,
          inventory: product.catalog_variants.sum { |variant| variant.catalog_inventory_levels.sum(&:available) },
          product_viewed: 0,
          product_added_to_cart: 0,
          product_removed_from_cart: 0,
          checkout_started: 0,
          payment_info_submitted: 0,
          checkout_completed: 0,
          paid_orders: 0,
          paid_units: 0,
          paid_revenue: BigDecimal("0"),
          cancelled_orders: 0,
          refunded_orders: 0,
          fulfilled_orders: 0,
          cod_orders: 0,
          order_ids: Hash.new { |hash, key| hash[key] = Set.new }
        }
      end
    end

    def aggregate_events!(products, funnel)
      @shop.activity_events.where(event_name: STOREFRONT_EVENTS).where("occurred_at >= ?", @storefront_since).find_each do |event|
        funnel[event.event_name] += 1
        product_ids(event.payload).each do |product_id|
          row = find_product_row(products, product_id)
          row[event.event_name.to_sym] += 1 if row
        end
      end
    end

    def find_product_row(products, product_id)
      products[product_id] || products["gid://shopify/Product/#{product_id}"]
    end

    def product_ids(payload)
      return [] unless payload.is_a?(Hash)

      direct = payload["product_id"]
      nested = Array(payload["line_items"]).filter_map { |line| line["product_id"] if line.is_a?(Hash) }
      ([ direct ] + nested).compact.uniq
    end

    def aggregate_orders!(products)
      outcomes = { total: 0, paid: 0, pending_payment: 0, cancelled: 0, refunded: 0, fulfilled: 0, cod: 0 }
      orders = @shop.commerce_orders.includes(:commerce_order_lines).where("processed_at >= ?", @orders_since)
      orders.find_each do |order|
        outcomes[:total] += 1
        paid = PAID_STATUSES.include?(order.financial_status)
        refunded = REFUNDED_STATUSES.include?(order.financial_status)
        cancelled = order.cancelled_at.present?
        fulfilled = order.fulfillment_status == "fulfilled"
        cod = cod_order?(order)
        outcomes[:paid] += 1 if paid
        outcomes[:pending_payment] += 1 unless paid || refunded || cancelled
        outcomes[:cancelled] += 1 if cancelled
        outcomes[:refunded] += 1 if refunded
        outcomes[:fulfilled] += 1 if fulfilled
        outcomes[:cod] += 1 if cod
        aggregate_order_lines!(products, order, paid:, refunded:, cancelled:, fulfilled:, cod:)
      end
      outcomes
    end

    def aggregate_order_lines!(products, order, paid:, refunded:, cancelled:, fulfilled:, cod:)
      order.commerce_order_lines.each do |line|
        row = products[line.product_external_id]
        next unless row

        record_order(row, :cancelled_orders, order.id) if cancelled
        record_order(row, :refunded_orders, order.id) if refunded
        record_order(row, :fulfilled_orders, order.id) if fulfilled
        record_order(row, :cod_orders, order.id) if cod
        next unless paid && !cancelled && !refunded

        record_order(row, :paid_orders, order.id)
        row[:paid_units] += line.quantity
        row[:paid_revenue] += (line.price || 0) * line.quantity
      end
    end

    def record_order(row, metric, order_id)
      return unless row[:order_ids][metric].add?(order_id)

      row[metric] += 1
    end

    def cod_order?(order)
      Array(order.raw_attrs["payment_gateway_names"]).any? { |name| name.match?(COD_PATTERN) }
    end

    def window_days(since)
      ((Time.current - since) / 1.day).round
    end
  end
end
