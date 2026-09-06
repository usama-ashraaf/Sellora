# frozen_string_literal: true

module ShopifyConfig
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

  def scopes
    ENV.fetch("SHOPIFY_SCOPES", "read_products,read_inventory,read_locations")
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
end
