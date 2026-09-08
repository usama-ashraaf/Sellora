# frozen_string_literal: true

module Shopify
  # Pulls products + inventory via Admin GraphQL and upserts platform-neutral catalog rows.
  # Phase A: read_products, read_inventory, read_locations only — no writes.
  class CatalogSync
    Error = Class.new(StandardError)
    # Raised when a full sync sees zero products but the shop already has catalog rows.
    # Fail-closed: never wipe an existing catalog on an empty/unexpected zero-product response.
    EmptySeenError = Class.new(Error)

    def self.call(shop)
      new(shop).call
    end

    def initialize(shop)
      @shop = shop
      @seen_product_external_ids = []
      @pages_seen = 0
    end

    def call
      raise Error, "shop is not installed" unless @shop.installed?

      @client = AdminClient.new(@shop)

      @client.each_product_page do |nodes|
        @pages_seen += 1
        # An empty first page with no subsequent pages is a legitimate empty catalog.
        # An empty page after we already saw products would be unexpected; treat as hard error
        # before reconcile so we never delete based on a truncated/glitched response.
        if nodes.empty? && @seen_product_external_ids.any?
          raise EmptySeenError,
                "unexpected empty products page after seeing #{@seen_product_external_ids.size} " \
                "products for shop #{@shop.shopify_domain} — aborting (fail-closed)"
        end

        nodes.each { |node| upsert_product!(node) }
      end

      reconcile_removed_products!

      result = {
        products: @seen_product_external_ids.size,
        shop_id: @shop.id
      }
      emit_catalog_synced!(result[:products])
      result
    end

    private

    def emit_catalog_synced!(product_count)
      return if @shop.account.blank?

      Activity::Ingest.call(
        account: @shop.account,
        shop: @shop,
        event_name: "catalog.synced",
        occurred_at: Time.current,
        payload: { "products" => product_count },
        source: "shopify_sync"
      )
    rescue Activity::Ingest::Error => e
      Rails.logger.warn("[catalog_sync] activity emit skipped shop=#{@shop.shopify_domain} error=#{e.message}")
    end

    def upsert_product!(node)
      external_id = node.fetch("id")
      @seen_product_external_ids << external_id

      product = @shop.catalog_products.find_or_initialize_by(external_id: external_id)
      product.title = node["title"].presence || "Untitled"
      product.handle = node["handle"]
      product.status = normalize_status(node["status"])
      variant_prices = Array(node.dig("variants", "nodes")).to_h do |variant|
        [
          variant.fetch("id"),
          {
            "price" => variant["price"],
            "compare_at_price" => variant["compareAtPrice"],
            "unit_cost" => variant.dig("inventoryItem", "unitCost", "amount"),
            "cost_currency" => variant.dig("inventoryItem", "unitCost", "currencyCode")
          }
        ]
      end
      description_html = node["descriptionHtml"].to_s
      description = ActionView::Base.full_sanitizer.sanitize(description_html)
      product.raw_attrs = {
        "platform" => "shopify",
        "status" => node["status"],
        "currency" => current_shop_currency,
        "description_html" => description_html,
        "description" => description,
        "garment_attrs" => garment_attributes_from(description_html),
        "variant_prices" => variant_prices
      }
      product.save!

      seen_variant_ids = []
      Array(node.dig("variants", "nodes")).each do |variant_node|
        seen_variant_ids << upsert_variant!(product, variant_node)
      end

      product.catalog_variants.where.not(external_id: seen_variant_ids).find_each(&:destroy!)
      product
    end

    def upsert_variant!(product, node)
      external_id = node.fetch("id")
      variant = product.catalog_variants.find_or_initialize_by(external_id: external_id)
      variant.sku = node["sku"].presence
      variant.title = node["title"].presence
      variant.barcode = node["barcode"].presence
      variant.option_summary = option_summary_for(node)
      variant.inventory_item_external_id = node.dig("inventoryItem", "id")
      variant.save!

      upsert_inventory_levels!(variant, node.dig("inventoryItem", "inventoryLevels", "nodes"))
      external_id
    end

    def upsert_inventory_levels!(variant, level_nodes)
      seen_locations = []

      Array(level_nodes).each do |level|
        location_id = level.dig("location", "id")
        next if location_id.blank?

        seen_locations << location_id
        available = available_quantity(level)

        row = variant.catalog_inventory_levels.find_or_initialize_by(location_external_id: location_id)
        row.available = available
        row.save!
      end

      variant.catalog_inventory_levels.where.not(location_external_id: seen_locations).find_each(&:destroy!)
    end

    def available_quantity(level)
      quantities = Array(level["quantities"])
      entry = quantities.find { |q| q["name"] == "available" }
      entry ? entry["quantity"].to_i : 0
    end

    def option_summary_for(node)
      options = Array(node["selectedOptions"]).filter_map do |opt|
        value = opt["value"].to_s
        next if value.blank? || value == "Default Title"

        value
      end
      return options.join(" / ") if options.any?

      node["title"].presence
    end

    def normalize_status(raw)
      raw.to_s.downcase.presence || "active"
    end

    def garment_attributes_from(description_html)
      labels = {
        "fit" => "fit",
        "fabric" => "fabric",
        "piece count" => "piece_count",
        "care" => "care",
        "stitched" => "stitched"
      }
      labeled_text = description_html.to_s
                                     .gsub(/<br\s*\/?\s*>/i, "\n")
                                     .gsub(%r{</(?:p|div|li)>}i, "\n")
      labeled_text = ActionView::Base.full_sanitizer.sanitize(labeled_text)
      labeled_text.each_line.filter_map do |line|
        match = line.strip.match(/\A(Fit|Fabric|Piece count|Care|Stitched):\s*(.+)\z/i)
        next unless match

        [ labels.fetch(match[1].downcase), match[2].strip ]
      end.to_h
    end

    def current_shop_currency
      @client.shop_currency if @client.respond_to?(:shop_currency)
    end

    def reconcile_removed_products!
      if @seen_product_external_ids.empty?
        existing = @shop.catalog_products.count
        if existing.positive?
          Rails.logger.error(
            "[catalog_sync] fail-closed empty reconcile shop=#{@shop.shopify_domain} " \
            "shop_id=#{@shop.id} seen=0 existing=#{existing} pages=#{@pages_seen}"
          )
          raise EmptySeenError,
                "empty catalog sync for shop #{@shop.shopify_domain}: saw 0 products but " \
                "#{existing} exist locally — aborting reconcile (fail-closed)"
        end
        return
      end

      stale = @shop.catalog_products.where.not(external_id: @seen_product_external_ids)
      stale.find_each(&:destroy!)
    end
  end
end
