# frozen_string_literal: true

namespace :sellora do
  desc "Sync catalog for one shop domain (e.g. sellora:sync_catalog[sellora-test-outfitters-like.myshopify.com])"
  task :sync_catalog, [ :shop_domain ] => :environment do |_t, args|
    domain = Shop.normalize_domain(args[:shop_domain])
    abort "Usage: bin/rails sellora:sync_catalog[shop-domain.myshopify.com]" if domain.blank?

    shop = Shop.find_by(shopify_domain: domain)
    abort "No shop row for #{domain}" if shop.nil?
    abort "Shop #{domain} is not installed (missing token or uninstalled)" unless shop.installed?

    result = Shopify::CatalogSync.call(shop)
    puts "Synced shop_id=#{result[:shop_id]} domain=#{domain} products=#{result[:products]}"
    puts "  catalog_products=#{shop.catalog_products.count}"
    puts "  catalog_variants=#{CatalogVariant.joins(:catalog_product).where(catalog_products: { shop_id: shop.id }).count}"
    puts "  catalog_inventory_levels=#{CatalogInventoryLevel.joins(catalog_variant: :catalog_product).where(catalog_products: { shop_id: shop.id }).count}"
  end

  desc "Sync catalog for every installed shop"
  task sync_catalog_all: :environment do
    shops = Shop.installed.to_a
    abort "No installed shops" if shops.empty?

    shops.each do |shop|
      result = Shopify::CatalogSync.call(shop)
      puts "Synced shop_id=#{result[:shop_id]} domain=#{shop.shopify_domain} products=#{result[:products]}"
    rescue Shopify::AdminClient::Error, Shopify::CatalogSync::Error => e
      warn "FAILED #{shop.shopify_domain}: #{e.message}"
    end
  end
end
