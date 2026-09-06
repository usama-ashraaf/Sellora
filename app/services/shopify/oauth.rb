# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Shopify
  class Oauth
    Error = Class.new(StandardError)

    class << self
      def authorize_url(shop:, state:, redirect_uri: ShopifyConfig.callback_url)
        domain = Shop.normalize_domain(shop)
        raise Error, "invalid shop domain" unless domain&.match?(Shop::DOMAIN_FORMAT)

        query = {
          client_id: ShopifyConfig.client_id,
          scope: ShopifyConfig.scopes,
          redirect_uri: redirect_uri,
          state: state
        }

        "https://#{domain}/admin/oauth/authorize?#{URI.encode_www_form(query)}"
      end

      # Exchanges an authorization code for an offline access token.
      # Returns a Hash with string keys: "access_token", "scope".
      def exchange_code(shop:, code:)
        domain = Shop.normalize_domain(shop)
        raise Error, "invalid shop domain" unless domain&.match?(Shop::DOMAIN_FORMAT)
        raise Error, "missing code" if code.blank?

        uri = URI("https://#{domain}/admin/oauth/access_token")
        body = {
          client_id: ShopifyConfig.client_id,
          client_secret: ShopifyConfig.api_secret,
          code: code
        }

        response = post_json(uri, body)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "token exchange failed (HTTP #{response.code})"
        end

        payload = JSON.parse(response.body)
        token = payload["access_token"]
        raise Error, "token exchange missing access_token" if token.blank?

        {
          "access_token" => token,
          "scope" => payload["scope"].to_s
        }
      end

      private

      def post_json(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(body)
        http.request(request)
      end
    end
  end
end
