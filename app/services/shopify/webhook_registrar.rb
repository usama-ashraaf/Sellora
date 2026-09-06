# frozen_string_literal: true

module Shopify
  # Registers Admin webhook subscriptions via GraphQL (idempotent).
  # Phase A catalog + uninstall; Phase B order create/update.
  class WebhookRegistrar
    Error = Class.new(StandardError)

    # GraphQL WebhookSubscriptionTopic => Rails path segment under /webhooks/shopify/
    PHASE_A_TOPICS = {
      "PRODUCTS_CREATE" => "products_create",
      "PRODUCTS_UPDATE" => "products_update",
      "PRODUCTS_DELETE" => "products_delete",
      "INVENTORY_LEVELS_UPDATE" => "inventory_levels_update",
      "APP_UNINSTALLED" => "app_uninstalled"
    }.freeze

    PHASE_B_TOPICS = {
      "ORDERS_CREATE" => "orders_create",
      "ORDERS_UPDATED" => "orders_updated"
    }.freeze

    TOPICS = PHASE_A_TOPICS.merge(PHASE_B_TOPICS).freeze

    LIST_QUERY = <<~GRAPHQL.freeze
      query SelloraWebhookSubscriptions($cursor: String) {
        webhookSubscriptions(first: 50, after: $cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            topic
            uri
            endpoint {
              __typename
              ... on WebhookHttpEndpoint {
                callbackUrl
              }
            }
          }
        }
      }
    GRAPHQL

    CREATE_MUTATION = <<~GRAPHQL.freeze
      mutation SelloraWebhookSubscriptionCreate(
        $topic: WebhookSubscriptionTopic!,
        $webhookSubscription: WebhookSubscriptionInput!
      ) {
        webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
          webhookSubscription {
            id
            topic
            uri
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    UPDATE_MUTATION = <<~GRAPHQL.freeze
      mutation SelloraWebhookSubscriptionUpdate(
        $id: ID!,
        $webhookSubscription: WebhookSubscriptionInput!
      ) {
        webhookSubscriptionUpdate(id: $id, webhookSubscription: $webhookSubscription) {
          webhookSubscription {
            id
            topic
            uri
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    def self.call(shop)
      new(shop).call
    end

    def self.callback_uri_for(path_segment)
      "#{ShopifyConfig.app_url}/webhooks/shopify/#{path_segment}"
    end

    def initialize(shop)
      @shop = shop
      raise Error, "shop is not installed" unless shop.installed?
      @client = AdminClient.new(shop)
    end

    # Returns { shop_id:, shopify_domain:, subscriptions: [ { topic:, status:, id:, uri: }, ... ] }
    # status is :created, :updated, or :already_registered
    def call
      existing_by_topic = index_existing_subscriptions
      results = TOPICS.map do |topic, path|
        ensure_topic!(topic, path, existing_by_topic[topic])
      end

      {
        shop_id: @shop.id,
        shopify_domain: @shop.shopify_domain,
        subscriptions: results
      }
    end

    private

    def ensure_topic!(topic, path, existing)
      uri = self.class.callback_uri_for(path)

      if existing
        if uris_match?(subscription_uri(existing), uri)
          return result(topic, :already_registered, existing["id"], uri)
        end

        updated = update_subscription!(existing["id"], uri)
        return result(topic, :updated, updated["id"], uri)
      end

      created, status = create_subscription!(topic, uri)
      result(topic, status, created["id"], uri)
    end

    def result(topic, status, id, uri)
      { topic: topic, status: status, id: id, uri: uri }
    end

    def index_existing_subscriptions
      list_all_subscriptions.each_with_object({}) do |node, index|
        topic = normalize_topic(node["topic"])
        next if topic.blank?
        next unless TOPICS.key?(topic)

        # Prefer keeping the first match; updates will retarget URI if needed.
        index[topic] ||= node
      end
    end

    def list_all_subscriptions
      nodes = []
      cursor = nil

      loop do
        payload = @client.graphql(LIST_QUERY, { "cursor" => cursor })
        connection = payload.fetch("webhookSubscriptions")
        nodes.concat(Array(connection["nodes"]))

        page_info = connection.fetch("pageInfo")
        break unless page_info["hasNextPage"]

        cursor = page_info["endCursor"]
        break if cursor.blank?
      end

      nodes
    end

    def create_subscription!(topic, uri)
      payload = @client.graphql(CREATE_MUTATION, {
        "topic" => topic,
        "webhookSubscription" => { "uri" => uri, "format" => "JSON" }
      })
      mutation = payload.fetch("webhookSubscriptionCreate")
      user_errors = Array(mutation["userErrors"])

      if user_errors.any?
        if already_taken?(user_errors)
          # Race / prior register: re-list and treat as already registered when URI matches.
          refreshed = index_existing_subscriptions[topic]
          if refreshed && uris_match?(subscription_uri(refreshed), uri)
            return [ refreshed, :already_registered ]
          end
        end
        raise Error, "webhookSubscriptionCreate(#{topic}): #{format_user_errors(user_errors)}"
      end

      sub = mutation["webhookSubscription"]
      raise Error, "webhookSubscriptionCreate(#{topic}) missing subscription" if sub.nil?

      [ sub, :created ]
    end

    def update_subscription!(id, uri)
      payload = @client.graphql(UPDATE_MUTATION, {
        "id" => id,
        "webhookSubscription" => { "uri" => uri, "format" => "JSON" }
      })
      mutation = payload.fetch("webhookSubscriptionUpdate")
      user_errors = Array(mutation["userErrors"])
      if user_errors.any?
        raise Error, "webhookSubscriptionUpdate(#{id}): #{format_user_errors(user_errors)}"
      end

      sub = mutation["webhookSubscription"]
      raise Error, "webhookSubscriptionUpdate(#{id}) missing subscription" if sub.nil?

      sub
    end

    def already_taken?(user_errors)
      user_errors.any? { |err| err["message"].to_s.match?(/already (been )?taken|has already been taken|address.*taken/i) }
    end

    def format_user_errors(user_errors)
      user_errors.map { |err| [ err["field"], err["message"] ].compact.join(" ") }.join("; ")
    end

    def subscription_uri(node)
      uri = node["uri"].presence
      return uri if uri.present?

      endpoint = node["endpoint"]
      return if endpoint.nil?

      endpoint["callbackUrl"].presence
    end

    def uris_match?(left, right)
      normalize_uri(left) == normalize_uri(right)
    end

    def normalize_uri(raw)
      raw.to_s.strip.chomp("/")
    end

    # GraphQL may return PRODUCTS_CREATE or products/create depending on field/version.
    def normalize_topic(raw)
      value = raw.to_s.strip
      return if value.blank?

      value.upcase.tr("/", "_").gsub(/\s+/, "_")
    end
  end
end
