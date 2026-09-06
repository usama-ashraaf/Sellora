# frozen_string_literal: true

require "test_helper"

class Pilot::RecommendationsTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Pilot Recs")
    @shop = Shop.create!(shopify_domain: "recs.myshopify.com", access_token: "t", account: @account)
    @rules = Audit::ClothingRulesSeed.call
  end

  test "builds recommendations from open findings" do
    product = @shop.catalog_products.create!(external_id: "p1", title: "Hoodie", status: "active")
    %w[S L XL].each_with_index { |size, i| product.catalog_variants.create!(external_id: "v#{i}", title: size, option_summary: size) }
    Audit::Runner.call(shop: @shop, rule_set: @rules)

    recs = Pilot::Recommendations.call(shop: @shop)
    assert recs.any?
    assert @shop.recommendations.open_items.exists?
    assert_equal "availability", @shop.recommendations.where(kind: "availability").first&.kind ||
                                  @shop.recommendations.first.kind
  end
end
