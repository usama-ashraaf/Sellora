# frozen_string_literal: true

module Shopify
  # Embedded app home shown inside Shopify Admin (Partner App URL target).
  # Does not use ApplicationController — avoid allow_browser / marketing layout.
  class AppController < ActionController::Base
    include Shopify::EmbeddedFrameHeaders

    SECTIONS = %w[overview recommendations products orders activity actions].freeze

    protect_from_forgery with: :exception
    layout "shopify_embedded"

    # GET /shopify  (also /shopify/app)
    def show
      @shop_domain = Shop.normalize_domain(params[:shop])
      @host = params[:host].presence
      @embedded_params_present = params[:shop].present? || params[:host].present? || params[:id_token].present?
      @shop_record = find_shop_record
      @allowed_scopes = ShopifyConfig::ALLOWED_SCOPES
      @phase_a_scopes = ShopifyConfig::PHASE_A_SCOPES # back-compat for any partials
      @app_url = ShopifyConfig.app_url
      @client_id = ShopifyConfig.client_id
      @section = params[:section].presence_in(SECTIONS) || "overview"
      load_pilot_ops! if @shop_record&.installed?
    end

    private

    def find_shop_record
      return if @shop_domain.blank? || !@shop_domain.match?(Shop::DOMAIN_FORMAT)

      Shop.find_by(shopify_domain: @shop_domain)
    end

    def load_pilot_ops!
      shop = @shop_record
      @open_findings_count = shop.audit_findings.open_findings.count
      @recommendations = shop.recommendations.open_items.includes(:catalog_product).by_priority.limit(50)
      @pending_actions = shop.reviewed_actions.includes(:recommendation).where(status: %w[pending_approval approved]).order(created_at: :desc).limit(20)
      @action_history = shop.reviewed_actions.includes(:recommendation).history.limit(20)
      @autopilot_policy = Pilot::Autopilot.ensure_policy!(shop)
      @commerce_signals = Pilot::CommerceSignals.call(shop: shop)
      @product_signals = @commerce_signals[:products].index_by { |row| row[:product].id }
      @products = shop.catalog_products.includes(catalog_variants: :catalog_inventory_levels).order(:title)
      @orders = shop.commerce_orders.includes(:commerce_order_lines).order(processed_at: :desc).limit(50)
      @recent_events = shop.activity_events.where(source: "web_pixel").order(occurred_at: :desc).limit(50)
      @pilot_ops = {
        last_discovered_at: shop.last_discovered_at,
        last_audited_at: shop.last_audited_at,
        last_recommendation_at: shop.last_recommendation_at,
        products: shop.catalog_products.count,
        orders: shop.commerce_orders.count
      }
    end
  end
end
