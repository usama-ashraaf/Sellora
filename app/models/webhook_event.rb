# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  validates :shopify_domain, presence: true
  validates :topic, presence: true
  validates :event_key, presence: true, uniqueness: true

  # Returns true when this delivery is new and was recorded; false when duplicate.
  def self.claim!(shopify_domain:, topic:, event_key:)
    create!(
      shopify_domain: shopify_domain,
      topic: topic,
      event_key: event_key,
      processed_at: Time.current
    )
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end
end
