# frozen_string_literal: true

# Minimal user stub for M2 foundation — no Devise / session auth yet.
# Memberships can also be email-only (invite stub) until a User is linked.
class User < ApplicationRecord
  has_many :memberships, dependent: :nullify
  has_many :accounts, through: :memberships

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_validation :normalize_email

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end
end
