# frozen_string_literal: true

require "set"

module Sellora
  # Diff catalog shape between two installed shops after sync (Wave 1 dual-shop QA).
  # Compares counts, SKU sets, and sample field mismatches for shared SKUs.
  class CatalogParity
    Error = Class.new(StandardError)

    DEFAULT_DOMAINS = [
      "sellora-test-outfitters-like.myshopify.com",
      "sellora-test-sapphire-like.myshopify.com"
    ].freeze

    SAMPLE_LIMIT = 10

    Result = Struct.new(
      :shop_a_domain, :shop_b_domain,
      :counts_a, :counts_b,
      :sku_only_a, :sku_only_b, :sku_shared_count,
      :sample_mismatches, :parity?,
      keyword_init: true
    )

    def self.call(shop_a:, shop_b:)
      new(shop_a: shop_a, shop_b: shop_b).call
    end

    def self.for_domains(domain_a = DEFAULT_DOMAINS[0], domain_b = DEFAULT_DOMAINS[1])
      a = Shop.find_by(shopify_domain: Shop.normalize_domain(domain_a))
      b = Shop.find_by(shopify_domain: Shop.normalize_domain(domain_b))
      raise Error, "missing shop row for #{domain_a}" if a.nil?
      raise Error, "missing shop row for #{domain_b}" if b.nil?

      call(shop_a: a, shop_b: b)
    end

    def initialize(shop_a:, shop_b:)
      @shop_a = shop_a
      @shop_b = shop_b
    end

    def call
      counts_a = counts_for(@shop_a)
      counts_b = counts_for(@shop_b)
      map_a = sku_map_for(@shop_a)
      map_b = sku_map_for(@shop_b)
      skus_a = map_a.keys.to_set
      skus_b = map_b.keys.to_set
      only_a = (skus_a - skus_b).to_a.sort
      only_b = (skus_b - skus_a).to_a.sort
      shared = (skus_a & skus_b).to_a.sort
      mismatches = sample_mismatches(shared, map_a, map_b)

      counts_match = counts_a == counts_b
      sku_match = only_a.empty? && only_b.empty?
      parity = counts_match && sku_match && mismatches.empty?

      Result.new(
        shop_a_domain: @shop_a.shopify_domain,
        shop_b_domain: @shop_b.shopify_domain,
        counts_a: counts_a,
        counts_b: counts_b,
        sku_only_a: only_a,
        sku_only_b: only_b,
        sku_shared_count: shared.size,
        sample_mismatches: mismatches,
        parity?: parity
      )
    end

    private

    def counts_for(shop)
      variants = CatalogVariant.joins(:catalog_product).where(catalog_products: { shop_id: shop.id })
      levels = CatalogInventoryLevel.joins(catalog_variant: :catalog_product)
        .where(catalog_products: { shop_id: shop.id })
      {
        products: shop.catalog_products.count,
        variants: variants.count,
        inventory_levels: levels.count,
        skus: variants.where.not(sku: [ nil, "" ]).count
      }
    end

    # sku => { option_summary:, variant_title:, product_handle:, inventory_sum: }
    def sku_map_for(shop)
      rows = CatalogVariant
        .joins(:catalog_product)
        .where(catalog_products: { shop_id: shop.id })
        .where.not(sku: [ nil, "" ])
        .includes(:catalog_inventory_levels, :catalog_product)

      map = {}
      rows.find_each do |variant|
        sku = variant.sku
        next if sku.blank?

        map[sku] = {
          option_summary: variant.option_summary,
          variant_title: variant.title,
          product_handle: variant.catalog_product.handle,
          inventory_sum: variant.catalog_inventory_levels.sum(:available)
        }
      end
      map
    end

    def sample_mismatches(shared_skus, map_a, map_b)
      mismatches = []
      shared_skus.each do |sku|
        a = map_a[sku]
        b = map_b[sku]
        diffs = {}
        %i[option_summary variant_title inventory_sum].each do |key|
          diffs[key] = { a: a[key], b: b[key] } if a[key] != b[key]
        end
        next if diffs.empty?

        mismatches << { sku: sku, diffs: diffs, handle_a: a[:product_handle], handle_b: b[:product_handle] }
        break if mismatches.size >= SAMPLE_LIMIT
      end
      mismatches
    end
  end
end
