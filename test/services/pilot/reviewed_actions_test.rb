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

  test "propose approve apply records local execution without silent writes" do
    action = Pilot::ReviewedActions.propose!(recommendation: @rec, actor_email: "owner@example.com")
    assert_equal "pending_approval", action.status
    assert action.before_snapshot.present?

    Pilot::ReviewedActions.approve!(action, actor_email: "owner@example.com")
    assert_equal "approved", action.reload.status

    ENV.delete("SELLORA_ALLOW_WRITES")
    applied = Pilot::ReviewedActions.apply!(action)
    assert_equal "applied", applied.status
    assert_match(/Shopify write not enabled/, applied.result_message)
  end

  test "detects source conflict when fingerprint drifts" do
    action = Pilot::ReviewedActions.propose!(recommendation: @rec)
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
