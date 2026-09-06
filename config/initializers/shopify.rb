# frozen_string_literal: true

module ShopifyConfig
  # Hard Phase A ceiling — OAuth must never accept a broader grant than this set.
  PHASE_A_SCOPES = %w[read_products read_inventory read_locations].freeze

  module_function

  def client_id
    ENV.fetch("SHOPIFY_CLIENT_ID", "")
  end

  def api_secret
    ENV.fetch("SHOPIFY_API_SECRET", "")
  end

  def app_url
    ENV.fetch("SHOPIFY_APP_URL", "http://127.0.0.1:3000").to_s.chomp("/")
  end

  # Defaults and ENV are clamped to Phase A only (never request broader scopes).
  def scopes
    requested = parse_scopes(ENV.fetch("SHOPIFY_SCOPES", PHASE_A_SCOPES.join(",")))
    allowed = requested.select { |scope| PHASE_A_SCOPES.include?(scope) }
    (allowed.presence || PHASE_A_SCOPES).join(",")
  end

  def api_version
    ENV.fetch("SHOPIFY_API_VERSION", "2025-10")
  end

  def callback_url
    "#{app_url}/auth/shopify/callback"
  end

  def configured?
    client_id.present? && api_secret.present?
  end

  # Granted scopes must be a subset of Phase A (never broader).
  def phase_a_scopes_subset?(granted)
    granted_list = parse_scopes(granted)
    return false if granted_list.empty?

    granted_list.all? { |scope| PHASE_A_SCOPES.include?(scope) }
  end

  def parse_scopes(raw)
    raw.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
