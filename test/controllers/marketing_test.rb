require "test_helper"

class MarketingTest < ActionDispatch::IntegrationTest
  test "homepage renders the marketing story and real pilot destination" do
    get root_path
    assert_response :success
    assert_select "html[lang=en]"
    assert_select "h1", text: /Catch catalog mistakes/
    %w[product how-it-works faq pilot privacy].each { |id| assert_select "##{id}", count: 1 }
    assert_select "form[action=?][method=post]", pilot_requests_path(anchor: "pilot")
    assert_select "input[type=email][required]"
    assert_select "input[type=url][required]"
    assert_select "[data-audit-target=step]", count: 4
    assert_select "[data-priorities-target=panel]:not([hidden])", count: 2
    assert_select "#faq details", count: 6
    assert_includes response.body, "ILLUSTRATIVE DEMO"
    assert_includes response.body, "PLANNED SHOPIFY-FIRST WORKFLOW"
    assert_includes response.body, "Local pilot interest form — requests are stored in this app"
    assert_includes response.body, "local review only and is not a public launch"
    assert_includes response.body, "does <strong>not</strong> connect a store"
    assert_includes response.body, "retained for local pilot evaluation"
    refute_includes response.body, "Please use fictional details"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "pilot records have no public index" do
    get pilot_requests_path
    assert_response :not_found
  end
end
