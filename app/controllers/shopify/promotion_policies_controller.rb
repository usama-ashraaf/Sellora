# frozen_string_literal: true

module Shopify
  class PromotionPoliciesController < ActionController::Base
    include Shopify::EmbeddedFrameHeaders
    include Shopify::SessionTokenAuthentication

    skip_forgery_protection
    before_action :authenticate_shopify_user!

    def update
      policy = Pilot::PromotionReadiness.ensure_policy!(@shop)
      policy.update!(policy_params)
      Pilot::PromotionReadiness.call(shop: @shop)
      render_success("Promotion assumptions saved and decisions refreshed.")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages.to_sentence, :unprocessable_entity)
    end

    def refresh
      Pilot::PromotionReadiness.call(shop: @shop)
      render_success("Promotion decisions refreshed from current Sellora data.")
    end

    private

    def authenticate_shopify_user!
      verify_shopify_session!
      @shop = Shop.installed.find_by!(shopify_domain: @shop_domain)
    rescue Shopify::IdTokenVerifier::Error, ActiveRecord::RecordNotFound, KeyError, URI::InvalidURIError => e
      response.set_header("X-Shopify-Retry-Invalid-Session-Request", "1")
      render_error(e.message, :unauthorized)
    end

    def policy_params
      params.require(:promotion_policy).permit(
        :target_roas, :target_acquisition_cost, :shipping_cost_per_order, :cod_failure_cost,
        :expected_cod_failure_rate_percent, :desired_runway_days, :minimum_margin_percent,
        :minimum_safe_orders
      )
    end

    def render_success(message)
      render json: {
        message: message,
        redirect_url: shopify_embedded_app_path(shop: @shop.shopify_domain, host: params[:host], section: "promotion_planner")
      }
    end

    def render_error(message, status)
      render json: { error: message }, status: status unless performed?
    end
  end
end
