# frozen_string_literal: true

require "test_helper"
require "base64"
require "json"
require "openssl"

class Shopify::IdTokenVerifierTest < ActiveSupport::TestCase
  test "verifies signature audience lifetime and shop claims" do
    token = token_for("verified.myshopify.com")
    payload = with_config { Shopify::IdTokenVerifier.verify(token) }
    assert_equal "https://verified.myshopify.com", payload["dest"]
    assert_equal "42", payload["sub"]
  end

  test "rejects a token signed with another secret" do
    token = token_for("verified.myshopify.com", secret: "wrong")
    assert_raises(Shopify::IdTokenVerifier::Error) { with_config { Shopify::IdTokenVerifier.verify(token) } }
  end

  private

  def token_for(domain, secret: "test-secret")
    header = encode({ alg: "HS256", typ: "JWT" })
    payload = encode({
      iss: "https://#{domain}/admin",
      dest: "https://#{domain}",
      aud: "test-client",
      sub: "42",
      nbf: 1.minute.ago.to_i,
      exp: 1.minute.from_now.to_i
    })
    signature = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", secret, "#{header}.#{payload}"), padding: false)
    [ header, payload, signature ].join(".")
  end

  def encode(value)
    Base64.urlsafe_encode64(JSON.generate(value), padding: false)
  end

  def with_config(&)
    with_singleton_stub(ShopifyConfig, :api_secret, -> { "test-secret" }) do
      with_singleton_stub(ShopifyConfig, :client_id, -> { "test-client" }, &)
    end
  end
end
