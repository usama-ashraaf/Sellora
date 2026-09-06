Rails.application.routes.draw do
  root "marketing#show"
  resources :pilot_requests, only: :create

  # M2 fictional in-app demo (not marketing). HTTP Basic gated (DEMO_HTTP_BASIC_*).
  get "demo", to: "demo#show", as: :demo
  get "app", to: "demo#show", as: :app_demo

  # Shopify OAuth (Phase A — M3 foundation). Marketing routes stay untouched above.
  get "shopify", to: "shopify/app#show", as: :shopify_embedded_app
  get "shopify/app", to: "shopify/app#show"
  get "shopify/install", to: "shopify/auth#install", as: :shopify_install
  get "auth/shopify/callback", to: "shopify/auth#callback", as: :shopify_callback

  # Shopify webhooks (HMAC verified). Topics use underscore path segments.
  scope path: "webhooks/shopify", module: :webhooks, as: :shopify_webhooks do
    post "products_create", to: "shopify#receive", defaults: { topic: "products_create" }
    post "products_update", to: "shopify#receive", defaults: { topic: "products_update" }
    post "products_delete", to: "shopify#receive", defaults: { topic: "products_delete" }
    post "inventory_levels_update", to: "shopify#receive", defaults: { topic: "inventory_levels_update" }
    post "orders_create", to: "shopify#receive", defaults: { topic: "orders_create" }
    post "orders_updated", to: "shopify#receive", defaults: { topic: "orders_updated" }
    post "app_uninstalled", to: "shopify#receive", defaults: { topic: "app_uninstalled" }
  end

  # Web Pixel ingest (installation token or shared secret). Consent-aware; see docs/web-pixel.md.
  post "web_pixels/events", to: "web_pixels/events#create", as: :web_pixel_events
  match "web_pixels/events", to: "web_pixels/events#preflight", via: :options

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
