# frozen_string_literal: true

module Shopify
  # Embedded app home shown inside Shopify Admin (Partner App URL target).
  # Does not use ApplicationController — avoid allow_browser / marketing layout.
  class AppController < ActionController::Base
    include Shopify::EmbeddedFrameHeaders

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
      @recommendations = shop.recommendations.open_items.by_priority.limit(8)
      @pending_actions = shop.reviewed_actions.where(status: %w[pending_approval approved]).order(created_at: :desc).limit(5)
      @action_history = shop.reviewed_actions.history.limit(5)
      @autopilot_policy = Pilot::Autopilot.ensure_policy!(shop)
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
