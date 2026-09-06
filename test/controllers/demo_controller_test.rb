# frozen_string_literal: true

require "test_helper"

class DemoControllerTest < ActionDispatch::IntegrationTest
  test "demo page shows fictional banners catalog counts and rule version" do
    account = Accounts::EnsureDemoAccount.call
    shop = Shop.create!(
      shopify_domain: "demo-page.myshopify.com",
      access_token: "t",
      scope: "read_products",
      account: account
    )
    product = shop.catalog_products.create!(external_id: "dp1", title: "Coastal Crew Tee", status: "active")
    product.catalog_variants.create!(external_id: "dv1", title: "S", option_summary: "S", sku: "SF-TEE-S")
    Audit::ClothingRulesSeed.call

    get demo_path
    assert_response :success
    assert_match(/FICTIONAL DEMO \/ ILLUSTRATIVE DATA/, response.body)
    assert_match(/ILLUSTRATIVE/, response.body)
    assert_match(/v1/, response.body)
    assert_match(/Catalog products/, response.body)
    assert_match(/Coastal Crew Tee|demo-page\.myshopify\.com|size_gap|Clothing catalog/, response.body)
  end

  test "app alias renders the same demo" do
    Accounts::EnsureDemoAccount.call
    Audit::ClothingRulesSeed.call

    get app_demo_path
    assert_response :success
    assert_match(/FICTIONAL DEMO/, response.body)
  end

  test "marketing root still renders and is distinct from demo" do
    get root_path
    assert_response :success
    assert_no_match(/FICTIONAL DEMO \/ ILLUSTRATIVE DATA/, response.body)
  end
end
