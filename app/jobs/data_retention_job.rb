# frozen_string_literal: true

class DataRetentionJob < ApplicationJob
  queue_as :default

  WEBHOOK_RETENTION = 30.days
  PILOT_REQUEST_RETENTION = 365.days
  UNINSTALLED_SHOP_RETENTION = 90.days

  def perform(now: Time.current)
    WebhookEvent.where("processed_at < ?", now - WEBHOOK_RETENTION).delete_all
    PilotRequest.where("created_at < ?", now - PILOT_REQUEST_RETENTION).delete_all
    Shop.where.not(uninstalled_at: nil).where("uninstalled_at < ?", now - UNINSTALLED_SHOP_RETENTION).find_each(&:redact!)
  end
end
