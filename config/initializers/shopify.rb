# frozen_string_literal: true

module ShopifyConfig
  # Phase A catalog reads — foundation for install + catalog sync.
  PHASE_A_SCOPES = %w[read_products read_inventory read_locations].freeze

  # Wave 1 web pixel activation (Usama approved 2026-09-06).
  PIXEL_SCOPES = %w[write_pixels read_customer_events].freeze

  # Phase B order records (M3) — financial/fulfillment labels only; not COD collection.
  PHASE_B_SCOPES = %w[read_orders].freeze

  # Phase C reviewed actions (M5) — optional; still never silent-write without SELLORA_ALLOW_WRITES.
  PHASE_C_SCOPES = %w[write_products].freeze

  # Hard OAuth ceiling — never accept a broader grant than this set.
  ALLOWED_SCOPES = (PHASE_A_SCOPES + PIXEL_SCOPES + PHASE_B_SCOPES + PHASE_C_SCOPES).freeze

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

  # Defaults and ENV are clamped to ALLOWED_SCOPES (Phase A + pixel + Phase B orders).
  def scopes
    requested = parse_scopes(ENV.fetch("SHOPIFY_SCOPES", ALLOWED_SCOPES.join(",")))
    allowed = requested.select { |scope| ALLOWED_SCOPES.include?(scope) }
    (allowed.presence || ALLOWED_SCOPES).join(",")
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

  # Shared secret for POST /web_pixels/events (pixel ingest stub). Not a Shopify scope.
  # Storefront JS cannot hold this safely long-term — migrate to app proxy later.
  def web_pixel_ingest_secret
    ENV.fetch("WEB_PIXEL_INGEST_SECRET", "")
  end

  # Granted scopes must be a subset of ALLOWED_SCOPES (never broader).
  def allowed_scopes_subset?(granted)
    granted_list = parse_scopes(granted)
    return false if granted_list.empty?

    granted_list.all? { |scope| ALLOWED_SCOPES.include?(scope) }
  end

  # Back-compat alias — ceiling is PHASE_A + PIXEL + PHASE_B (see ALLOWED_SCOPES).
  def phase_a_scopes_subset?(granted)
    allowed_scopes_subset?(granted)
  end

  def parse_scopes(raw)
    raw.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
