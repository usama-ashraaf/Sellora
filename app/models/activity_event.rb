# frozen_string_literal: true

# Append-only activity event contract (see docs/activity-events.md).
# Do not update payload in place after insert — ingest new events instead.
class ActivityEvent < ApplicationRecord
  belongs_to :account
  belongs_to :shop, optional: true

  validates :event_name, presence: true
  validates :occurred_at, presence: true
  validates :source, presence: true

  validate :immutable_after_create, on: :update

  scope :for_account, ->(account) { where(account_id: account.id) }
  scope :named, ->(name) { where(event_name: name) }

  private

  def immutable_after_create
    errors.add(:base, "activity events are append-only; ingest a new event instead of updating")
  end
end
