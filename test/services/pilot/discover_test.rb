# frozen_string_literal: true

require "test_helper"

class Pilot::DiscoverTest < ActiveSupport::TestCase
  setup do
    account = Account.create!(name: "Discovery")
    @shop = Shop.create!(shopify_domain: "discover.myshopify.com", access_token: "t",
                         scope: "read_products,read_orders", account: account)
  end

  test "syncs catalog and orders before audit and recommendations" do
    calls = []
    shop = @shop
    audit_result = Struct.new(:findings, :skipped).new([], 0)

    with_stub(Shopify::CatalogSync, :call, ->(_shop) { calls << :catalog; { products: 2, shop_id: shop.id } }) do
      with_stub(Shopify::OrderSync, :call, ->(_shop) { calls << :orders; { orders: 1, shop_id: shop.id } }) do
        with_stub(Audit::Runner, :call, ->(shop:) { calls << :audit; audit_result }) do
          with_stub(Pilot::Recommendations, :call, ->(shop:) { calls << :recommendations; [] }) do
            result = Pilot::Discover.call(shop: @shop)
            assert_equal 1, result.dig(:order_sync, :orders)
          end
        end
      end
    end

    assert_equal %i[catalog orders audit recommendations], calls
  end

  test "does not request orders when read_orders was not granted" do
    @shop.update!(scope: "read_products")
    shop = @shop
    with_stub(Shopify::CatalogSync, :call, ->(_shop) { { products: 0, shop_id: shop.id } }) do
      with_stub(Audit::Runner, :call, ->(shop:) { Struct.new(:findings, :skipped).new([], 0) }) do
        with_stub(Pilot::Recommendations, :call, ->(shop:) { [] }) do
          result = Pilot::Discover.call(shop: @shop)
          assert_equal true, result.dig(:order_sync, :skipped)
        end
      end
    end
  end

  private

  def with_stub(owner, method_name, implementation)
    original = owner.method(method_name)
    owner.define_singleton_method(method_name, implementation)
    yield
  ensure
    owner.define_singleton_method(method_name, original)
  end
end
