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
        return render plain: "Shopify app is not configured. Set SHOPIFY_CLIENT_ID and SHOPIFY_API_SECRET in the environment.", status: :service_unavailable
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
        return render plain: "Invalid OAuth state. Restart install from /shopify/install?shop=your-store.myshopify.com", status: :unauthorized
      end

      session_shop = session[:shopify_oauth_shop].to_s
      callback_shop = Shop.normalize_domain(params[:shop]).to_s
      unless shops_match?(session_shop, callback_shop)
        reset_oauth_session
        return render plain: "Shop mismatch: callback shop does not match the shop that started install.", status: :unauthorized
      end

      domain = callback_shop
      unless domain.match?(Shop::DOMAIN_FORMAT)
        reset_oauth_session
        return render plain: "Invalid shop domain on callback.", status: :unprocessable_entity
      end

      # When the API secret is configured, query HMAC is required (never optional-skip).
      if ShopifyConfig.api_secret.present?
        unless ::Shopify::HmacVerifier.valid_query?(params: request.query_parameters)
          reset_oauth_session
          return render plain: "Invalid OAuth HMAC. Confirm SHOPIFY_API_SECRET matches the Partner app Client Secret.", status: :unauthorized
        end
      end

      token_payload = ::Shopify::Oauth.exchange_code(shop: domain, code: params[:code])
      unless ShopifyConfig.phase_a_scopes_subset?(token_payload["scope"])
        reset_oauth_session
        return render plain: "OAuth grant rejected: scopes must be a subset of Phase A (#{ShopifyConfig::PHASE_A_SCOPES.join(', ')}). Got: #{token_payload['scope']}", status: :forbidden
      end

      persist_shop!(domain, token_payload)
      reset_oauth_session

      render plain: "Sellora installed on #{domain}. You can close this window.", status: :ok
    end

    private

    def valid_state?
      expected = session[:shopify_oauth_state]
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
    end

    def shops_match?(session_shop, callback_shop)
      session_shop.present? && callback_shop.present? &&
        ActiveSupport::SecurityUtils.secure_compare(session_shop, callback_shop)
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
      render plain: client_facing_oauth_error(error), status: :bad_gateway
    end

    # Actionable client text only — never echo tokens, codes, secrets, or raw upstream bodies.
    def client_facing_oauth_error(error)
      case error.message.to_s
      when /invalid shop domain/i
        "OAuth failed: invalid shop domain. Restart from /shopify/install?shop=your-store.myshopify.com"
      when /missing code/i
        "OAuth failed: missing authorization code. Restart install from /shopify/install?shop=your-store.myshopify.com"
      when /token exchange failed/i
        "OAuth token exchange failed. Confirm SHOPIFY_CLIENT_ID and SHOPIFY_API_SECRET match the Partner app, " \
          "Allowed redirection URL is …/auth/shopify/callback, and restart install (authorization codes are single-use)."
      when /missing access_token/i
        "OAuth token exchange returned no access token. Confirm Partner app credentials and restart install."
      else
        "OAuth failed. Restart from /shopify/install?shop=your-store.myshopify.com and confirm Partner app " \
          "Client ID/Secret plus Allowed redirection URL (…/auth/shopify/callback)."
      end
    end
  end
end
