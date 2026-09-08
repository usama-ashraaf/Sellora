# frozen_string_literal: true

module Shopify::AppHelper
  ACTIVITY_EVENT_COPY = {
    "page_viewed" => [ "Storefront page viewed", "Awareness", "A consented visitor loaded a storefront page." ],
    "product_viewed" => [ "Product viewed", "Interest", "A shopper opened this product and showed product-level interest." ],
    "product_added_to_cart" => [ "Product added to cart", "Intent", "A shopper added this item to their cart, indicating purchase intent." ],
    "product_removed_from_cart" => [ "Product removed from cart", "Friction", "A shopper removed this item; review price, sizing, shipping, or product clarity if this repeats." ],
    "checkout_started" => [ "Checkout started", "Checkout", "A shopper moved from cart into checkout." ],
    "payment_info_submitted" => [ "Payment information submitted", "Payment", "A shopper reached the payment step. Sellora does not collect payment details." ],
    "checkout_completed" => [ "Checkout completed", "Conversion", "The storefront reported a completed checkout; synchronized orders provide the authoritative payment outcome." ]
  }.freeze

  def shopify_admin_url(shop, path)
    store = shop.shopify_domain.delete_suffix(".myshopify.com")
    "https://admin.shopify.com/store/#{store}/#{path.to_s.delete_prefix('/')}"
  end

  def shopify_admin_product_url(shop, product)
    external_id = product.external_id.to_s.split("/").last
    shopify_admin_url(shop, "products/#{external_id}")
  end

  def recommendation_badge_class(priority)
    { "high" => "danger", "medium" => "warning", "low" => "neutral" }.fetch(priority, "neutral")
  end

  def recommendation_action_label(recommendation)
    case recommendation.kind
    when "promotion_opportunity" then "Review promotion setup"
    when "featured_product" then "Feature on storefront"
    when "social_ad_candidate" then "Prepare social campaign"
    when "restock_before_promotion" then "Restock before promotion"
    when "conversion_review" then "Improve product and checkout"
    when "traffic_intent" then "Review product page"
    else "Fix product details"
    end
  end

  def activity_event_presentation(event)
    payload = event.payload.is_a?(Hash) ? event.payload : {}
    copy = ACTIVITY_EVENT_COPY.fetch(event.event_name, [ event.event_name.titleize, "Storefront", "A consented storefront event was received." ])
    product_ids = ([ payload["product_id"] ] + Array(payload["line_items"]).filter_map { |line| line["product_id"] if line.is_a?(Hash) }).compact.uniq
    products = product_ids.filter_map { |id| @activity_products[id.to_s] }.uniq
    variant = @activity_variants[payload["variant_id"].to_s]
    line_quantity = Array(payload["line_items"]).sum { |line| line.is_a?(Hash) ? line["quantity"].to_i : 0 }
    quantity = payload["quantity"].presence || (line_quantity if line_quantity.positive?)
    amount = activity_money(payload["amount"], payload["currency"])

    {
      title: copy[0],
      stage: copy[1],
      explanation: copy[2],
      products: products,
      product_reference: products.empty? ? product_ids.first : nil,
      variant: variant,
      sku: payload["sku"].presence || variant&.sku,
      quantity: quantity,
      amount: amount,
      checkout_reference: payload["checkout_token"].presence || payload["order_id"].presence,
      analytics_consent: payload.dig("consent", "analytics_processing_allowed") == true
    }
  end

  def activity_conversion_rate(numerator, denominator)
    return "—" if denominator.to_i.zero?

    number_to_percentage(numerator.to_f * 100 / denominator, precision: 1)
  end

  def autopilot_skip_reason(reason)
    {
      "kind_not_allowed" => "Recommendation type was not allowed",
      "severity_below_minimum" => "Priority was below the configured minimum",
      "insufficient_evidence" => "Not enough supporting events",
      "cooldown" => "A similar action is still cooling down",
      "inventory_below_minimum" => "Inventory or size coverage was too low",
      "discount_above_maximum" => "Discount exceeded the configured maximum",
      "margin_unknown_or_below_floor" => "Margin was unknown or below the floor",
      "daily_action_cap" => "Daily action limit was reached",
      "daily_discount_cost_cap" => "Daily estimated discount cost limit was reached",
      "action_requires_merchant_input" => "The action still needs merchant input"
    }.fetch(reason.to_s, reason.to_s.humanize)
  end

  def promotion_status_class(status)
    { "promote" => "ready", "limit" => "warning", "block" => "danger" }.fetch(status, "neutral")
  end

  def promotion_money(value, currency)
    return "Not available" if value.blank?

    [ currency.presence, number_with_delimiter(number_with_precision(value, precision: 0)) ].compact.join(" ")
  end

  private

  def activity_money(amount, currency)
    return if amount.blank?

    value = BigDecimal(amount.to_s)
    [ currency.presence, number_with_precision(value, precision: 2, strip_insignificant_zeros: true) ].compact.join(" ")
  rescue ArgumentError
    nil
  end
end
