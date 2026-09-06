# frozen_string_literal: true

require "json"

module Shopify
  # Registers / updates the app web pixel via GraphQL (idempotent).
  # Requires write_pixels + read_customer_events on the shop offline token.
  class WebPixelRegistrar
    Error = Class.new(StandardError)

    LIST_QUERY = <<~GRAPHQL.freeze
      query SelloraWebPixel {
        webPixel {
          id
          settings
        }
      }
    GRAPHQL

    CREATE_MUTATION = <<~GRAPHQL.freeze
      mutation SelloraWebPixelCreate($webPixel: WebPixelInput!) {
        webPixelCreate(webPixel: $webPixel) {
          webPixel {
            id
            settings
          }
          userErrors {
            field
            message
            code
          }
        }
      }
    GRAPHQL

    UPDATE_MUTATION = <<~GRAPHQL.freeze
      mutation SelloraWebPixelUpdate($id: ID!, $webPixel: WebPixelInput!) {
        webPixelUpdate(id: $id, webPixel: $webPixel) {
          webPixel {
            id
            settings
          }
          userErrors {
            field
            message
            code
          }
        }
      }
    GRAPHQL

    def self.call(shop)
      new(shop).call
    end

    def self.ingest_url
      "#{ShopifyConfig.app_url}/web_pixels/events"
    end

    def self.settings_for(shop)
      account_id = shop.account_id.presence || shop.id
      {
        "accountID" => account_id.to_s,
        "ingestUrl" => ingest_url
      }
    end

    def initialize(shop)
      @shop = shop
      raise Error, "shop is not installed" unless shop.installed?
      @client = AdminClient.new(shop)
    end

    # Returns { shop_id:, shopify_domain:, status:, id:, settings: }
    # status is :created, :updated, or :already_registered
    def call
      desired = self.class.settings_for(@shop)
      existing = fetch_web_pixel

      if existing
        if settings_match?(existing["settings"], desired)
          return result(:already_registered, existing["id"], desired)
        end

        updated = update_web_pixel!(existing["id"], desired)
        return result(:updated, updated["id"], desired)
      end

      created, status = create_web_pixel!(desired)
      result(status, created["id"], desired)
    end

    private

    def result(status, id, settings)
      {
        shop_id: @shop.id,
        shopify_domain: @shop.shopify_domain,
        status: status,
        id: id,
        settings: settings
      }
    end

    def fetch_web_pixel
      payload = @client.graphql(LIST_QUERY)
      payload["webPixel"]
    end

    def create_web_pixel!(settings)
      payload = @client.graphql(CREATE_MUTATION, {
        "webPixel" => { "settings" => settings }
      })
      mutation = payload.fetch("webPixelCreate")
      user_errors = Array(mutation["userErrors"])

      if user_errors.any?
        if already_exists?(user_errors)
          refreshed = fetch_web_pixel
          if refreshed && settings_match?(refreshed["settings"], settings)
            return [ refreshed, :already_registered ]
          end
          if refreshed
            updated = update_web_pixel!(refreshed["id"], settings)
            return [ updated, :updated ]
          end
        end
        raise Error, "webPixelCreate: #{format_user_errors(user_errors)}"
      end

      pixel = mutation["webPixel"]
      raise Error, "webPixelCreate missing webPixel" if pixel.nil?

      [ pixel, :created ]
    end

    def update_web_pixel!(id, settings)
      payload = @client.graphql(UPDATE_MUTATION, {
        "id" => id,
        "webPixel" => { "settings" => settings }
      })
      mutation = payload.fetch("webPixelUpdate")
      user_errors = Array(mutation["userErrors"])
      if user_errors.any?
        raise Error, "webPixelUpdate(#{id}): #{format_user_errors(user_errors)}"
      end

      pixel = mutation["webPixel"]
      raise Error, "webPixelUpdate(#{id}) missing webPixel" if pixel.nil?

      pixel
    end

    def already_exists?(user_errors)
      user_errors.any? do |err|
        code = err["code"].to_s.upcase
        message = err["message"].to_s
        code.include?("TAKEN") || code.include?("EXISTS") ||
          message.match?(/already (been )?(taken|exists|created)|has already been taken/i)
      end
    end

    def format_user_errors(user_errors)
      user_errors.map { |err| [ err["code"], err["field"], err["message"] ].compact.join(" ") }.join("; ")
    end

    def settings_match?(raw, desired)
      parse_settings(raw) == desired.transform_keys(&:to_s)
    end

    def parse_settings(raw)
      case raw
      when Hash
        raw.transform_keys(&:to_s)
      when String
        JSON.parse(raw)
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end
  end
end
