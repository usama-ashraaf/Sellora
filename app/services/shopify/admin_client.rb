# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Shopify
  # Read-only Admin GraphQL client (Phase A scopes only).
  class AdminClient
    Error = Class.new(StandardError)

    PRODUCTS_QUERY = <<~GRAPHQL.freeze
      query CatalogProducts($cursor: String) {
        products(first: 25, after: $cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            title
            handle
            status
            variants(first: 100) {
              nodes {
                id
                title
                sku
                barcode
                selectedOptions {
                  name
                  value
                }
                inventoryItem {
                  id
                  inventoryLevels(first: 20) {
                    nodes {
                      location {
                        id
                      }
                      quantities(names: ["available"]) {
                        name
                        quantity
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    def initialize(shop)
      @shop = shop
      raise Error, "shop is not installed" unless shop.installed?
      raise Error, "missing access token" if shop.access_token.blank?
    end

    # Yields each page of product nodes (Array of Hashes with string keys).
    def each_product_page
      cursor = nil

      loop do
        payload = graphql(PRODUCTS_QUERY, { "cursor" => cursor })
        connection = payload.fetch("products")
        yield connection.fetch("nodes")

        page_info = connection.fetch("pageInfo")
        break unless page_info["hasNextPage"]

        cursor = page_info["endCursor"]
        break if cursor.blank?
      end
    end

    def graphql(query, variables = {})
      uri = URI("https://#{@shop.shopify_domain}/admin/api/#{ShopifyConfig.api_version}/graphql.json")
      response = post_json(uri, { query: query, variables: variables })

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Admin API HTTP #{response.code}"
      end

      body = JSON.parse(response.body)
      if body["errors"].present?
        raise Error, "Admin API GraphQL errors: #{body['errors'].map { |e| e['message'] }.join('; ')}"
      end

      data = body["data"]
      raise Error, "Admin API missing data" if data.nil?

      data
    end

    private

    def post_json(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request["X-Shopify-Access-Token"] = @shop.access_token
      request.body = JSON.generate(body)
      http.request(request)
    end
  end
end
