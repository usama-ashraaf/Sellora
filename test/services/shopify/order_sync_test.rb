# frozen_string_literal: true

require "test_helper"

class Shopify::OrderSyncTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Order Merchant")
    @shop = Shop.create!(
      shopify_domain: "orders-shop.myshopify.com",
      access_token: "shpat_orders",
      scope: "read_orders",
      account: @account
    )
  end

  test "upserts order headers and lines from GraphQL pages" do
    pages = [
      {
        "orders" => {
          "pageInfo" => { "hasNextPage" => false, "endCursor" => nil },
          "nodes" => [
            {
              "id" => "gid://shopify/Order/1",
              "name" => "#1001",
              "currencyCode" => "PKR",
              "displayFinancialStatus" => "PAID",
              "displayFulfillmentStatus" => "UNFULFILLED",
              "paymentGatewayNames" => [ "Cash on Delivery (COD)" ],
              "cancelReason" => nil,
              "cancelledAt" => nil,
              "processedAt" => "2026-09-07T10:00:00Z",
              "totalPriceSet" => { "shopMoney" => { "amount" => "2500.00", "currencyCode" => "PKR" } },
              "subtotalPriceSet" => { "shopMoney" => { "amount" => "2500.00", "currencyCode" => "PKR" } },
              "totalDiscountsSet" => { "shopMoney" => { "amount" => "0.00", "currencyCode" => "PKR" } },
              "lineItems" => {
                "nodes" => [
                  {
                    "id" => "gid://shopify/LineItem/11",
                    "name" => "Linen Kurta - M",
                    "sku" => "SF-KURTA-M",
                    "quantity" => 1,
                    "originalUnitPriceSet" => { "shopMoney" => { "amount" => "2500.00", "currencyCode" => "PKR" } },
                    "variant" => { "id" => "gid://shopify/ProductVariant/201" },
                    "product" => { "id" => "gid://shopify/Product/101" }
                  }
                ]
              }
            }
          ]
        }
      }
    ]

    stub_graphql_pages(pages) do
      result = Shopify::OrderSync.call(@shop)
      assert_equal 1, result[:orders]
    end

    order = @shop.commerce_orders.find_by!(external_id: "gid://shopify/Order/1")
    assert_equal @account.id, order.account_id
    assert_equal "#1001", order.name
    assert_equal "PKR", order.currency
    assert_equal "paid", order.financial_status
    assert_equal BigDecimal("2500.00"), order.total_price
    assert_equal [ "Cash on Delivery (COD)" ], order.raw_attrs["payment_gateway_names"]
    assert_equal 1, order.commerce_order_lines.count
    line = order.commerce_order_lines.first
    assert_equal "SF-KURTA-M", line.sku
    assert_equal "gid://shopify/ProductVariant/201", line.variant_external_id
  end

  test "rejects shop without account" do
    @shop.update_columns(account_id: nil)
    assert_raises(Shopify::OrderSync::Error, match: /no account/) do
      Shopify::OrderSync.call(@shop)
    end
  end

  private

  ORIGINAL_ADMIN_CLIENT_NEW = Shopify::AdminClient.method(:new)

  def stub_graphql_pages(payloads)
    queue = payloads.dup
    expected_shop_id = @shop.id
    client = Object.new
    client.define_singleton_method(:graphql) do |_query, _variables = {}|
      raise "unexpected GraphQL call" if queue.empty?

      queue.shift
    end

    Shopify::AdminClient.define_singleton_method(:new) do |shop|
      raise "unexpected shop" unless shop.id == expected_shop_id
      client
    end

    yield
  ensure
    Shopify::AdminClient.define_singleton_method(:new, ORIGINAL_ADMIN_CLIENT_NEW)
  end
end
