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

  # TEMPORARY plaintext fallback: allow reading legacy unencrypted tokens written
  # before encryption was enabled; the next save re-encrypts them.
  # Plan (follow-up migration): once every Shop#access_token has been re-saved /
  # re-encrypted (verify no plaintext rows remain), set this to false and drop the
  # plaintext fallback so only ciphertext is accepted.
  config.active_record.encryption.support_unencrypted_data = true
end
