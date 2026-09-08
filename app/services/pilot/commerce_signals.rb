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
        variants = product.catalog_variants.to_a
        availability = variants.to_h do |variant|
          [ variant, variant.catalog_inventory_levels.sum(&:available) ]
        end
        available_variants = availability.count { |_variant, available| available.positive? }
        total_variants = variants.size
        economics = product_economics(product, variants, availability)
        variant_rows = variants.map do |variant|
          variant_economics = economics.fetch(:variants).fetch(variant.external_id)
          {
            variant: variant,
            title: variant.option_summary.presence || variant.title.presence || "Unnamed variant",
            sku: variant.sku,
            inventory: availability.fetch(variant, 0),
            price: variant_economics[:price],
            cost: variant_economics[:cost],
            margin_percent: variant_economics[:margin_percent],
            product_viewed: 0,
            product_added_to_cart: 0,
            product_removed_from_cart: 0,
            checkout_started: 0,
            payment_info_submitted: 0,
            checkout_completed: 0,
            paid_orders: 0,
            paid_units: 0,
            cancelled_orders: 0,
            refunded_orders: 0,
            fulfilled_orders: 0,
            cod_orders: 0,
            order_ids: Hash.new { |hash, key| hash[key] = Set.new }
          }
        end
        rows[product.external_id] = {
          product: product,
          title: product.title,
          inventory: availability.values.sum,
          total_variants: total_variants,
          available_variants: available_variants,
          size_coverage_percent: total_variants.positive? ? (available_variants * 100.0 / total_variants).round : 0,
          available_sizes: size_labels(availability.select { |_variant, available| available.positive? }.keys),
          unavailable_sizes: size_labels(availability.reject { |_variant, available| available.positive? }.keys),
          cost_coverage_percent: economics[:cost_coverage_percent],
          minimum_margin_percent: economics[:minimum_margin_percent],
          inventory_retail_value: economics[:inventory_retail_value],
          variants: variant_rows,
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

    def size_labels(variants)
      variants.filter_map { |variant| variant.option_summary.presence || variant.title.presence }.uniq
    end

    def product_economics(product, variants, availability)
      rows = product.raw_attrs.fetch("variant_prices", {})
      variant_rows = variants.to_h do |variant|
        values = rows[variant.external_id] || {}
        price = decimal(values["price"])
        cost = decimal(values["unit_cost"])
        margin = ((price - cost) * 100 / price).round(2) if price&.positive? && cost
        [ variant.external_id, { price: price, cost: cost, margin_percent: margin,
                                 inventory: availability.fetch(variant, 0) } ]
      end
      priced = variant_rows.values.select { |row| row[:price]&.positive? }
      costed = priced.select { |row| row[:cost]&.positive? }
      margins = costed.map { |row| row[:margin_percent] }
      {
        variants: variant_rows,
        cost_coverage_percent: variants.any? ? (costed.size * 100.0 / variants.size).round : 0,
        minimum_margin_percent: margins.min,
        inventory_retail_value: priced.sum { |row| row[:price] * row[:inventory] }
      }
    end

    def decimal(value)
      BigDecimal(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def aggregate_events!(products, funnel)
      @shop.activity_events.where(event_name: STOREFRONT_EVENTS).where("occurred_at >= ?", @storefront_since).find_each do |event|
        funnel[event.event_name] += 1
        event_items(event.payload).group_by { |item| item[:product_id] }.each do |product_id, items|
          row = find_product_row(products, product_id)
          row[event.event_name.to_sym] += 1 if row
          items.filter_map { |item| item[:variant_id] }.uniq.each do |variant_id|
            variant_row = find_variant_row(row, variant_id)
            variant_row[event.event_name.to_sym] += 1 if variant_row
          end
        end
      end
    end

    def find_product_row(products, product_id)
      products[product_id] || products["gid://shopify/Product/#{product_id}"]
    end

    def event_items(payload)
      return [] unless payload.is_a?(Hash)

      direct = { product_id: payload["product_id"], variant_id: payload["variant_id"] } if payload["product_id"].present?
      nested = Array(payload["line_items"]).filter_map do |line|
        next unless line.is_a?(Hash) && line["product_id"].present?

        { product_id: line["product_id"], variant_id: line["variant_id"] }
      end
      [ direct, *nested ].compact
    end

    def find_variant_row(product_row, variant_id)
      return unless product_row

      product_row[:variants].find do |row|
        external_id_matches?(row[:variant].external_id, variant_id)
      end
    end

    def external_id_matches?(stored_id, incoming_id)
      stored_id.to_s == incoming_id.to_s || stored_id.to_s.split("/").last == incoming_id.to_s.split("/").last
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

        variant_row = find_variant_row(row, line.variant_external_id)

        record_order(row, :cancelled_orders, order.id) if cancelled
        record_order(variant_row, :cancelled_orders, order.id) if cancelled && variant_row
        record_order(row, :refunded_orders, order.id) if refunded
        record_order(variant_row, :refunded_orders, order.id) if refunded && variant_row
        record_order(row, :fulfilled_orders, order.id) if fulfilled
        record_order(variant_row, :fulfilled_orders, order.id) if fulfilled && variant_row
        record_order(row, :cod_orders, order.id) if cod
        record_order(variant_row, :cod_orders, order.id) if cod && variant_row
        next unless paid && !cancelled && !refunded

        record_order(row, :paid_orders, order.id)
        row[:paid_units] += line.quantity
        row[:paid_revenue] += (line.price || 0) * line.quantity
        if variant_row
          record_order(variant_row, :paid_orders, order.id)
          variant_row[:paid_units] += line.quantity
        end
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
