# frozen_string_literal: true

module Accounts
  # Ensures the default "Sellora Demo" account exists, owns Wave 1 shops,
  # and has an owner membership stub. Session-free M2 foundation helper.
  class EnsureDemoAccount
    DEMO_OWNER_EMAIL = "demo-owner@sellora.local"
    DEMO_OWNER_NAME = "Demo Owner"

    def self.call
      new.call
    end

    def call
      account = ::Account.demo!
      user = ::User.find_or_initialize_by(email: DEMO_OWNER_EMAIL)
      user.name ||= DEMO_OWNER_NAME
      user.save!

      membership = account.memberships.find_or_initialize_by(email: DEMO_OWNER_EMAIL)
      membership.user = user
      membership.role = "owner"
      membership.save!

      ::Shop.where(account_id: nil).find_each do |shop|
        shop.update!(account: account)
      end

      account
    end
  end
end
