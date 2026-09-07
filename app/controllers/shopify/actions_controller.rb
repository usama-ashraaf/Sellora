# frozen_string_literal: true

module Shopify
  class ActionsController < ActionController::Base
    include Shopify::EmbeddedFrameHeaders

    skip_forgery_protection
    before_action :authenticate_shopify_user!
    before_action :load_action!, except: :create

    def create
      recommendation = @shop.recommendations.find(params.require(:recommendation_id))
      action = Pilot::ReviewedActions.propose!(
        recommendation: recommendation,
        attributes: action_params.to_h,
        actor_email: actor_identifier
      )
      render json: response_payload(action, "Proposal ready for review."), status: :created
    rescue ActiveRecord::RecordNotFound
      render_error("Recommendation not found", :not_found)
    rescue ActionController::ParameterMissing, Pilot::ReviewedActions::Error => e
      render_error(e.message, :unprocessable_entity)
    end

    def approve
      action = Pilot::ReviewedActions.approve!(@action, actor_email: actor_identifier)
      render json: response_payload(action, "Action approved. Apply it when you are ready.")
    rescue Pilot::ReviewedActions::Error => e
      render_error(e.message, :unprocessable_entity)
    end

    def reject
      action = Pilot::ReviewedActions.reject!(@action, actor_email: actor_identifier)
      render json: response_payload(action, "Action rejected.")
    rescue Pilot::ReviewedActions::Error => e
      render_error(e.message, :unprocessable_entity)
    end

    def apply
      action = Pilot::ReviewedActions.apply!(@action, actor_email: actor_identifier)
      render json: response_payload(action, action.result_message)
    rescue Pilot::ReviewedActions::Conflict, Pilot::ReviewedActions::Error, Shopify::AdminClient::Error => e
      render_error(e.message, :unprocessable_entity)
    end

    private

    def authenticate_shopify_user!
      token = request.authorization.to_s.delete_prefix("Bearer ").presence
      @identity = Shopify::IdTokenVerifier.verify(token)
      domain = Shop.normalize_domain(URI.parse(@identity.fetch("dest")).host)
      @shop = Shop.installed.find_by!(shopify_domain: domain)
    rescue Shopify::IdTokenVerifier::Error, ActiveRecord::RecordNotFound, KeyError, URI::InvalidURIError => e
      response.set_header("X-Shopify-Retry-Invalid-Session-Request", "1")
      render_error(e.message, :unauthorized)
    end

    def load_action!
      @action = @shop.reviewed_actions.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_error("Action not found", :not_found)
    end

    def action_params
      params.fetch(:change, {}).permit(:title, :description_html, :code, :percentage, :starts_at, :ends_at)
    end

    def actor_identifier
      "shopify-user:#{@identity.fetch('sub', 'unknown')}"
    end

    def response_payload(action, message)
      {
        id: action.id,
        status: action.status,
        message: message,
        redirect_url: shopify_embedded_app_path(shop: @shop.shopify_domain, host: params[:host], section: "actions")
      }
    end

    def render_error(message, status)
      render json: { error: message }, status: status unless performed?
    end
  end
end
