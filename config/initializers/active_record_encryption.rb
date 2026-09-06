# frozen_string_literal: true

# Encrypt sensitive Active Record attributes (e.g. Shop#access_token) at rest.
# Keys come from ENV — never commit real values. Generate with:
#   bin/rails db:encryption:init
# See .env.example.

Rails.application.configure do
  primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence
  deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence
  key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence

  if primary_key && deterministic_key && key_derivation_salt
    config.active_record.encryption.primary_key = primary_key
    config.active_record.encryption.deterministic_key = deterministic_key
    config.active_record.encryption.key_derivation_salt = key_derivation_salt
  elsif Rails.env.test?
    # Fixed test-only material so the suite boots without a local .env.
    config.active_record.encryption.primary_key = "sellora_test_primary_key_32b!!"
    config.active_record.encryption.deterministic_key = "sellora_test_determ_key_32b!!!"
    config.active_record.encryption.key_derivation_salt = "sellora_test_derivation_salt!!"
  end

  # Allow reading legacy plaintext tokens written before encryption was enabled;
  # next save re-encrypts them. Safe to leave on after rollout.
  config.active_record.encryption.support_unencrypted_data = true
end
