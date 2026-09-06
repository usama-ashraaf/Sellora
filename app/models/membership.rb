# frozen_string_literal: true

class Membership < ApplicationRecord
  ROLES = %w[owner admin member].freeze

  belongs_to :account
  belongs_to :user, optional: true

  validates :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :email, uniqueness: { scope: :account_id, case_sensitive: false }

  before_validation :normalize_email

  scope :owners, -> { where(role: "owner") }
  scope :admins, -> { where(role: %w[owner admin]) }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end
end
