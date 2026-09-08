# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Shopify
  # Admin GraphQL transport used by scoped read and merchant-approved write services.
  class AdminClient
    Error = Class.new(StandardError)
    # Transient HTTP / transport failures suitable for Active Job retry_on.
    TransientError = Class.new(Error)

    # Nested page sizes stay small to remain under Shopify's single-query cost limit (~1000).
    # Variants and inventoryLevels are paginated to completion after each product page.
    PRODUCTS_QUERY = <<~GRAPHQL.freeze
      query CatalogProducts($cursor: String) {
        shop { currencyCode }
        products(first: 10, after: $cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            title
            handle
            status
            descriptionHtml
            variants(first: 50) {
              pageInfo {
                hasNextPage
                endCursor
              }
              nodes {
                id
                title
                sku
                barcode
                price
                compareAtPrice
                selectedOptions {
                  name
                  value
                }
                inventoryItem {
                  id
                  unitCost { amount currencyCode }
                  inventoryLevels(first: 10) {
                    pageInfo {
                      hasNextPage
                      endCursor
                    }
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

    attr_reader :shop_currency

    VARIANTS_QUERY = <<~GRAPHQL.freeze
      query CatalogProductVariants($productId: ID!, $cursor: String) {
        product(id: $productId) {
          variants(first: 50, after: $cursor) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              title
              sku
              barcode
              price
              compareAtPrice
              selectedOptions {
                name
                value
              }
              inventoryItem {
                id
                unitCost { amount currencyCode }
                inventoryLevels(first: 10) {
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
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
    GRAPHQL

    INVENTORY_LEVELS_QUERY = <<~GRAPHQL.freeze
      query CatalogInventoryLevels($inventoryItemId: ID!, $cursor: String) {
        inventoryItem(id: $inventoryItemId) {
          inventoryLevels(first: 10, after: $cursor) {
            pageInfo {
              hasNextPage
              endCursor
            }
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
    GRAPHQL

    def initialize(shop)
      @shop = shop
      raise Error, "shop is not installed" unless shop.installed?
      raise Error, "missing access token" if shop.access_token.blank?
    end

    # Yields each page of product nodes (Array of Hashes with string keys).
    # Nested variants + inventoryLevels are expanded to completion before yield.
    def each_product_page
      cursor = nil

      loop do
        payload = graphql(PRODUCTS_QUERY, { "cursor" => cursor })
        @shop_currency = payload.dig("shop", "currencyCode").presence || @shop_currency
        connection = payload.fetch("products")
        nodes = connection.fetch("nodes").map { |node| expand_product_node!(node) }
        yield nodes

        page_info = connection.fetch("pageInfo")
        break unless page_info["hasNextPage"]

        cursor = page_info["endCursor"]
        break if cursor.blank?
      end
    end

    def graphql(query, variables = {})
      uri = URI("https://#{@shop.shopify_domain}/admin/api/#{ShopifyConfig.api_version}/graphql.json")
      response = post_json(uri, { query: query, variables: variables })

      code = response.code.to_i
      unless response.is_a?(Net::HTTPSuccess)
        if transient_http?(code)
          raise TransientError, "Admin API HTTP #{code}"
        end
        raise Error, "Admin API HTTP #{code}"
      end

      body = JSON.parse(response.body)
      if body["errors"].present?
        messages = body["errors"].map { |e| e["message"] }.join("; ")
        if transient_graphql?(messages)
          raise TransientError, "Admin API GraphQL errors: #{messages}"
        end
        raise Error, "Admin API GraphQL errors: #{messages}"
      end

      data = body["data"]
      raise Error, "Admin API missing data" if data.nil?

      data
    end

    private

    def expand_product_node!(node)
      variants_conn = node["variants"] || {}
      variant_nodes = Array(variants_conn["nodes"])
      page_info = variants_conn["pageInfo"] || {}

      if page_info["hasNextPage"]
        cursor = page_info["endCursor"]
        each_variant_page(node.fetch("id"), after: cursor) do |more|
          variant_nodes.concat(more)
        end
      end

      variant_nodes.each { |variant| expand_inventory_levels!(variant) }
      node["variants"] = { "nodes" => variant_nodes }
      node
    end

    def each_variant_page(product_id, after:)
      cursor = after

      loop do
        break if cursor.blank?

        payload = graphql(VARIANTS_QUERY, { "productId" => product_id, "cursor" => cursor })
        connection = payload.fetch("product").fetch("variants")
        yield connection.fetch("nodes")

        page_info = connection.fetch("pageInfo")
        break unless page_info["hasNextPage"]

        cursor = page_info["endCursor"]
      end
    end

    def expand_inventory_levels!(variant_node)
      item = variant_node["inventoryItem"]
      return if item.nil?

      levels_conn = item["inventoryLevels"] || {}
      level_nodes = Array(levels_conn["nodes"])
      page_info = levels_conn["pageInfo"] || {}

      if page_info["hasNextPage"]
        cursor = page_info["endCursor"]
        inventory_item_id = item.fetch("id")
        each_inventory_level_page(inventory_item_id, after: cursor) do |more|
          level_nodes.concat(more)
        end
      end

      item["inventoryLevels"] = { "nodes" => level_nodes }
    end

    def each_inventory_level_page(inventory_item_id, after:)
      cursor = after

      loop do
        break if cursor.blank?

        payload = graphql(INVENTORY_LEVELS_QUERY, {
          "inventoryItemId" => inventory_item_id,
          "cursor" => cursor
        })
        connection = payload.fetch("inventoryItem").fetch("inventoryLevels")
        yield connection.fetch("nodes")

        page_info = connection.fetch("pageInfo")
        break unless page_info["hasNextPage"]

        cursor = page_info["endCursor"]
      end
    end

    def transient_http?(code)
      code == 429 || code >= 500
    end

    def transient_graphql?(messages)
      messages.match?(/throttl|timeout|temporarily|try again|503|429/i)
    end

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
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError => e
      raise TransientError, "Admin API transport: #{e.class}: #{e.message}"
    end
  end
end
