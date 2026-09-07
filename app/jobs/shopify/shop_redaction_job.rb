# frozen_string_literal: true

module Shopify
  class ShopRedactionJob < ApplicationJob
    queue_as :default

    def perform(domain)
      shop = Shop.find_by(shopify_domain: Shop.normalize_domain(domain))
      shop&.redact!
    end
  end
end
