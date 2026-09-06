# frozen_string_literal: true

module Shopify
  # Pulls products + inventory via Admin GraphQL and upserts platform-neutral catalog rows.
  # Phase A: read_products, read_inventory, read_locations only — no writes.
  class CatalogSync
    Error = Class.new(StandardError)

    def self.call(shop)
      new(shop).call
    end

    def initialize(shop)
      @shop = shop
      @seen_product_external_ids = []
    end

    def call
      raise Error, "shop is not installed" unless @shop.installed?

      @client = AdminClient.new(@shop)

      @client.each_product_page do |nodes|
        nodes.each { |node| upsert_product!(node) }
      end

      reconcile_removed_products!

      {
        products: @seen_product_external_ids.size,
        shop_id: @shop.id
      }
    end

    private

    def upsert_product!(node)
      external_id = node.fetch("id")
      @seen_product_external_ids << external_id

      product = @shop.catalog_products.find_or_initialize_by(external_id: external_id)
      product.title = node["title"].presence || "Untitled"
      product.handle = node["handle"]
      product.status = normalize_status(node["status"])
      product.raw_attrs = {
        "platform" => "shopify",
        "status" => node["status"]
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

    def reconcile_removed_products!
      stale = if @seen_product_external_ids.empty?
        @shop.catalog_products
      else
        @shop.catalog_products.where.not(external_id: @seen_product_external_ids)
      end
      stale.find_each(&:destroy!)
    end
  end
end
