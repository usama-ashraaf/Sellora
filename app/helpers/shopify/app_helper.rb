# frozen_string_literal: true

module Shopify::AppHelper
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
    when "conversion_review" then "Improve product and checkout"
    when "traffic_intent" then "Review product page"
    else "Fix product details"
    end
  end
end
