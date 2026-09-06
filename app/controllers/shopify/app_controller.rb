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
      @phase_a_scopes = ShopifyConfig::PHASE_A_SCOPES
      @app_url = ShopifyConfig.app_url
      @client_id = ShopifyConfig.client_id
    end

    private

    def find_shop_record
      return if @shop_domain.blank? || !@shop_domain.match?(Shop::DOMAIN_FORMAT)

      Shop.find_by(shopify_domain: @shop_domain)
    end
  end
end
