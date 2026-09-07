# frozen_string_literal: true

require "test_helper"

class Pilot::ReviewedActionsTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Pilot Actions")
    @shop = Shop.create!(shopify_domain: "actions.myshopify.com", access_token: "t", account: @account)
    @rules = Audit::ClothingRulesSeed.call
    product = @shop.catalog_products.create!(external_id: "p1", title: "Kurta", status: "active")
    %w[S L].each_with_index { |size, i| product.catalog_variants.create!(external_id: "v#{i}", title: size, option_summary: size) }
    Audit::Runner.call(shop: @shop, rule_set: @rules)
    Pilot::Recommendations.call(shop: @shop)
    @rec = @shop.recommendations.open_items.first
  end

  test "propose approve apply executes the reviewed payload" do
    action = Pilot::ReviewedActions.propose!(
      recommendation: @rec,
      attributes: { title: "Verified Kurta" },
      actor_email: "owner@example.com"
    )
    assert_equal "pending_approval", action.status
    assert action.before_snapshot.present?
    assert_equal "product_update", action.action_kind
    assert_equal "Verified Kurta", action.after_snapshot["title"]

    Pilot::ReviewedActions.approve!(action, actor_email: "owner@example.com")
    assert_equal "approved", action.reload.status

    result = { message: "Updated in Shopify.", after: action.after_snapshot.merge("shopify_result" => { "id" => "p1" }) }
    applied = with_singleton_stub(Shopify::ActionExecutor, :apply, ->(shop:, action:) { result }) do
      Pilot::ReviewedActions.apply!(action)
    end
    assert_equal "applied", applied.status
    assert_equal "Updated in Shopify.", applied.result_message
    assert_equal "dismissed", @rec.reload.status
  end

  test "detects source conflict when fingerprint drifts" do
    action = Pilot::ReviewedActions.propose!(recommendation: @rec, attributes: { title: "Verified Kurta" })
    product = @rec.catalog_product
    product.update!(title: "#{product.title} changed")
    product.update_columns(content_fingerprint: "stale-not-matching")

    error = assert_raises(Pilot::ReviewedActions::Conflict) do
      Pilot::ReviewedActions.approve!(action)
    end
    assert_match(/source changed/, error.message)
    assert_equal "conflict", action.reload.status
  end
end
