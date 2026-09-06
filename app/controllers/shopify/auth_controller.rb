# frozen_string_literal: true

module Shopify
  class AuthController < ActionController::Base
    protect_from_forgery with: :exception

    rescue_from ::Shopify::Oauth::Error, with: :oauth_error

    # GET /shopify/install?shop=example.myshopify.com
    def install
      domain = Shop.normalize_domain(params[:shop])
      unless domain&.match?(Shop::DOMAIN_FORMAT)
        return render plain: "Missing or invalid shop parameter. Use ?shop=your-store.myshopify.com", status: :unprocessable_entity
      end

      unless ShopifyConfig.configured?
        return render plain: "Shopify app is not configured. Set SHOPIFY_CLIENT_ID and SHOPIFY_API_SECRET.", status: :service_unavailable
      end

      state = SecureRandom.hex(24)
      session[:shopify_oauth_state] = state
      session[:shopify_oauth_shop] = domain

      redirect_to ::Shopify::Oauth.authorize_url(shop: domain, state: state), allow_other_host: true
    end

    # GET /auth/shopify/callback
    def callback
      unless valid_state?
        reset_oauth_session
        return render plain: "Invalid OAuth state", status: :unauthorized
      end

      domain = Shop.normalize_domain(params[:shop]) || session[:shopify_oauth_shop]
      unless domain&.match?(Shop::DOMAIN_FORMAT)
        reset_oauth_session
        return render plain: "Invalid shop", status: :unprocessable_entity
      end

      if params[:hmac].present? && !::Shopify::HmacVerifier.valid_query?(params: request.query_parameters)
        reset_oauth_session
        return render plain: "Invalid HMAC", status: :unauthorized
      end

      token_payload = ::Shopify::Oauth.exchange_code(shop: domain, code: params[:code])
      persist_shop!(domain, token_payload)
      reset_oauth_session

      render plain: "Sellora installed on #{domain}. You can close this window.", status: :ok
    end

    private

    def valid_state?
      expected = session[:shopify_oauth_state]
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
    end

    def persist_shop!(domain, token_payload)
      shop = Shop.find_or_initialize_by(shopify_domain: domain)
      shop.access_token = token_payload["access_token"]
      shop.scope = token_payload["scope"].presence || ShopifyConfig.scopes
      shop.uninstalled_at = nil
      shop.save!
    end

    def reset_oauth_session
      session.delete(:shopify_oauth_state)
      session.delete(:shopify_oauth_shop)
    end

    def oauth_error(error)
      reset_oauth_session
      render plain: "OAuth error: #{error.message}", status: :bad_gateway
    end
  end
end
