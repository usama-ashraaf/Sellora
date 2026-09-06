# frozen_string_literal: true

module Activity
  # Append-only ingestion interface for ActivityEvent.
  # See docs/activity-events.md.
  class Ingest
    Error = Class.new(StandardError)

    def self.call(account:, event_name:, occurred_at: Time.current, payload: {}, source: "internal", shop: nil)
      new(
        account: account,
        event_name: event_name,
        occurred_at: occurred_at,
        payload: payload,
        source: source,
        shop: shop
      ).call
    end

    def initialize(account:, event_name:, occurred_at:, payload:, source:, shop:)
      @account = account
      @event_name = event_name
      @occurred_at = occurred_at
      @payload = payload
      @source = source
      @shop = shop
    end

    def call
      raise Error, "account required" if @account.blank?
      raise Error, "event_name required" if @event_name.blank?
      if @shop && @shop.account_id && @shop.account_id != @account.id
        raise Error, "shop does not belong to account"
      end

      ::ActivityEvent.create!(
        account: @account,
        shop: @shop,
        event_name: @event_name.to_s,
        occurred_at: @occurred_at,
        payload: @payload.is_a?(Hash) ? @payload : {},
        source: @source.to_s
      )
    end
  end
end
