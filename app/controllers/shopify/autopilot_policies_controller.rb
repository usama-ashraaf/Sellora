# frozen_string_literal: true

module Shopify
  class AutopilotPoliciesController < ActionController::Base
    include Shopify::EmbeddedFrameHeaders
    include Shopify::SessionTokenAuthentication

    ALLOWED_KINDS = %w[promotion_accuracy promotion_opportunity social_ad_candidate].freeze

    skip_forgery_protection
    before_action :authenticate_shopify_user!

    def update
      policy = Pilot::Autopilot.ensure_policy!(@shop)
      attributes = policy_params
      attributes[:allowed_action_kinds] = Array(params.dig(:autopilot_policy, :allowed_action_kinds)) & ALLOWED_KINDS
      attributes[:kill_switch_at] = nil if ActiveModel::Type::Boolean.new.cast(attributes[:enabled])
      attributes[:kill_switch_reason] = nil if attributes[:kill_switch_at].nil?
      policy.update!(attributes)
      render_success("Autopilot limits saved.")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages.to_sentence, :unprocessable_entity)
    end

    def kill
      Pilot::Autopilot.ensure_policy!(@shop).kill_switch!
      render_success("Autopilot stopped.")
    end

    def run
      Pilot::AutopilotShopJob.perform_later(@shop.id)
      render_success("Autopilot safety check queued.")
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
      params.require(:autopilot_policy).permit(
        :enabled, :min_severity, :cooldown_hours, :max_actions_per_day, :require_in_stock,
        :minimum_evidence_count, :minimum_inventory_units, :minimum_size_coverage_percent,
        :max_discount_percentage, :max_estimated_discount_cost_per_day, :margin_floor_pct
      )
    end

    def render_success(message)
      render json: {
        message: message,
        redirect_url: shopify_embedded_app_path(shop: @shop.shopify_domain, host: params[:host], section: "actions")
      }
    end

    def render_error(message, status)
      render json: { error: message }, status: status unless performed?
    end
  end
end
