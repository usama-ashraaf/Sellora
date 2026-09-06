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

  desc "Diff catalog parity between two shops (default: Wave 1 outfitters + sapphire). Usage: sellora:catalog_parity[shop-a,shop-b]"
  task :catalog_parity, [ :shop_a, :shop_b ] => :environment do |_t, args|
    domain_a = args[:shop_a].presence || Sellora::CatalogParity::DEFAULT_DOMAINS[0]
    domain_b = args[:shop_b].presence || Sellora::CatalogParity::DEFAULT_DOMAINS[1]

    begin
      result = Sellora::CatalogParity.for_domains(domain_a, domain_b)
    rescue Sellora::CatalogParity::Error => e
      abort e.message
    end

    puts "Catalog parity: #{result.shop_a_domain} vs #{result.shop_b_domain}"
    puts "  counts_a=#{result.counts_a.inspect}"
    puts "  counts_b=#{result.counts_b.inspect}"
    puts "  sku_shared=#{result.sku_shared_count} only_a=#{result.sku_only_a.size} only_b=#{result.sku_only_b.size}"
    if result.sku_only_a.any?
      puts "  sku_only_a sample=#{result.sku_only_a.first(Sellora::CatalogParity::SAMPLE_LIMIT).inspect}"
    end
    if result.sku_only_b.any?
      puts "  sku_only_b sample=#{result.sku_only_b.first(Sellora::CatalogParity::SAMPLE_LIMIT).inspect}"
    end
    if result.sample_mismatches.any?
      puts "  sample_mismatches:"
      result.sample_mismatches.each do |m|
        puts "    sku=#{m[:sku]} handle_a=#{m[:handle_a]} handle_b=#{m[:handle_b]} diffs=#{m[:diffs].inspect}"
      end
    end
    puts result.parity? ? "PARITY_OK" : "PARITY_DIFF"
    abort "catalog parity failed" unless result.parity?
  end

  desc "Register Phase A Shopify webhooks for one shop (e.g. sellora:register_webhooks[sellora-test-outfitters-like.myshopify.com])"
  task :register_webhooks, [ :shop_domain ] => :environment do |_t, args|
    domain = Shop.normalize_domain(args[:shop_domain])
    abort "Usage: bin/rails sellora:register_webhooks[shop-domain.myshopify.com]" if domain.blank?

    shop = Shop.find_by(shopify_domain: domain)
    abort "No shop row for #{domain}" if shop.nil?
    abort "Shop #{domain} is not installed (missing token or uninstalled)" unless shop.installed?

    result = Shopify::WebhookRegistrar.call(shop)
    puts "Registered webhooks shop_id=#{result[:shop_id]} domain=#{result[:shopify_domain]}"
    result[:subscriptions].each do |sub|
      puts "  #{sub[:topic]} status=#{sub[:status]} uri=#{sub[:uri]} id=#{sub[:id]}"
    end
  end

  desc "Register Phase A Shopify webhooks for every installed shop"
  task register_webhooks_all: :environment do
    shops = Shop.installed.to_a
    abort "No installed shops" if shops.empty?

    shops.each do |shop|
      result = Shopify::WebhookRegistrar.call(shop)
      puts "Registered webhooks shop_id=#{result[:shop_id]} domain=#{result[:shopify_domain]}"
      result[:subscriptions].each do |sub|
        puts "  #{sub[:topic]} status=#{sub[:status]} uri=#{sub[:uri]} id=#{sub[:id]}"
      end
    rescue Shopify::AdminClient::Error, Shopify::WebhookRegistrar::Error => e
      warn "FAILED #{shop.shopify_domain}: #{e.message}"
    end
  end

  desc "Register / update Sellora web pixel for one shop (e.g. sellora:register_web_pixel[sellora-test-outfitters-like.myshopify.com])"
  task :register_web_pixel, [ :shop_domain ] => :environment do |_t, args|
    domain = Shop.normalize_domain(args[:shop_domain])
    abort "Usage: bin/rails sellora:register_web_pixel[shop-domain.myshopify.com]" if domain.blank?

    shop = Shop.find_by(shopify_domain: domain)
    abort "No shop row for #{domain}" if shop.nil?
    abort "Shop #{domain} is not installed (missing token or uninstalled)" unless shop.installed?

    result = Shopify::WebPixelRegistrar.call(shop)
    puts "Registered web pixel shop_id=#{result[:shop_id]} domain=#{result[:shopify_domain]} status=#{result[:status]} id=#{result[:id]}"
    puts "  settings=#{result[:settings].inspect}"
  end

  desc "Register / update Sellora web pixel for every installed shop"
  task register_web_pixel_all: :environment do
    shops = Shop.installed.to_a
    abort "No installed shops" if shops.empty?

    shops.each do |shop|
      result = Shopify::WebPixelRegistrar.call(shop)
      puts "Registered web pixel shop_id=#{result[:shop_id]} domain=#{result[:shopify_domain]} status=#{result[:status]} id=#{result[:id]}"
      puts "  settings=#{result[:settings].inspect}"
    rescue Shopify::AdminClient::Error, Shopify::WebPixelRegistrar::Error => e
      warn "FAILED #{shop.shopify_domain}: #{e.message}"
    end
  end
end
