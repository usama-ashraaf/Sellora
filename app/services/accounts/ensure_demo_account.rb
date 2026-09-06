# frozen_string_literal: true

module Accounts
  # Ensures the default "Sellora Demo" account exists for the fictional demo
  # workspace only, with an owner membership stub. Session-free M2 helper.
  #
  # Does NOT vacuum orphan / nil-account shops onto Demo — real OAuth installs
  # get their own Account in Shopify::AuthController#persist_shop!.
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

      account
    end
  end
end
