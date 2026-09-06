# frozen_string_literal: true

require "test_helper"
require "base64"
require "openssl"

class Shopify::HmacVerifierTest < ActiveSupport::TestCase
  setup do
    @secret = "test-shopify-secret"
    ENV["SHOPIFY_API_SECRET"] = @secret
  end

  teardown do
    ENV.delete("SHOPIFY_API_SECRET")
  end

  test "valid_webhook accepts matching hmac" do
    body = '{"id":1}'
    digest = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @secret, body))
    assert Shopify::HmacVerifier.valid_webhook?(raw_body: body, hmac_header: digest, secret: @secret)
  end

  test "valid_webhook rejects bad hmac" do
    assert_not Shopify::HmacVerifier.valid_webhook?(raw_body: "{}", hmac_header: "nope", secret: @secret)
  end
end
