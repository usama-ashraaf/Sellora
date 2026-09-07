# frozen_string_literal: true

require "test_helper"

class Pilot::ActionPayloadTest < ActiveSupport::TestCase
  setup do
    account = Account.create!(name: "Payloads")
    @shop = Shop.create!(shopify_domain: "payloads.myshopify.com", access_token: "t", account: account)
    @product = @shop.catalog_products.create!(
      external_id: "gid://shopify/Product/123456",
      title: "Meadow Kurti",
      status: "active",
      raw_attrs: { "description_html" => "<p>Current copy</p>" }
    )
  end

  test "builds a bounded product-specific discount" do
    recommendation = recommendation!("promotion_opportunity")
    payload = Pilot::ActionPayload.build(
      recommendation: recommendation,
      attributes: { code: " meadow 10! ", percentage: "10", starts_at: "2026-09-08 09:00", ends_at: "2026-09-15 09:00" }
    )

    assert_equal "discount_code_create", payload["operation"]
    assert_equal "MEADOW10", payload["code"]
    assert_equal 10, payload["percentage"]
    assert_equal [ @product.external_id ], payload["product_ids"]
  end

  test "rejects a discount outside the allowed percentage" do
    error = assert_raises(Pilot::ActionPayload::Error) do
      Pilot::ActionPayload.build(recommendation: recommendation!("promotion_opportunity"), attributes: { percentage: 90 })
    end
    assert_match(/between 1 and 80/, error.message)
  end

  test "requires a concrete product content change" do
    recommendation = recommendation!("catalog_fix")
    assert_raises(Pilot::ActionPayload::Error) do
      Pilot::ActionPayload.build(recommendation: recommendation, attributes: { title: @product.title })
    end

    payload = Pilot::ActionPayload.build(recommendation: recommendation, attributes: { title: "Verified Meadow Kurti" })
    assert_equal "product_update", payload["operation"]
    assert_equal "Verified Meadow Kurti", payload["title"]
  end

  private

  def recommendation!(kind)
    @shop.recommendations.create!(
      account: @shop.account,
      catalog_product: @product,
      kind: kind,
      priority: "high",
      status: "open",
      title: "Review Meadow Kurti",
      rationale: "Evidence"
    )
  end
end
