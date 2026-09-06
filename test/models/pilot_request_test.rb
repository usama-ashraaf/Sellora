require "test_helper"

class PilotRequestTest < ActiveSupport::TestCase
  test "normalizes a valid request" do
    request = PilotRequest.new(valid_attributes.merge(name: "  Review Brand  ", email: "  OWNER@EXAMPLE.COM  ", store_url: " https://example.com/store "))
    assert request.valid?
    assert_equal "Review Brand", request.name
    assert_equal "owner@example.com", request.email
    assert_equal "https://example.com/store", request.store_url
  end

  test "requires all four fields" do
    request = PilotRequest.new
    assert_not request.valid?
    assert_equal %i[email name platform store_url], request.errors.attribute_names.sort
  end

  test "rejects invalid email and unknown platform" do
    request = PilotRequest.new(valid_attributes.merge(email: "invalid", platform: "Unlisted"))
    assert_not request.valid?
    assert request.errors[:email].any?
    assert request.errors[:platform].any?
  end

  test "accepts every offered platform" do
    PilotRequest::PLATFORMS.each do |platform|
      assert PilotRequest.new(valid_attributes.merge(platform: platform)).valid?
    end
  end

  test "rejects non-web URLs and embedded credentials without fetching URLs" do
    [ "javascript:alert(1)", "ftp://example.com", "https:///catalog", "https://user:password@example.com", "https://", "not a URL", "https://localstore" ].each do |url|
      request = PilotRequest.new(valid_attributes.merge(store_url: url))
      assert_not request.valid?, "Accepted #{url}"
      assert request.errors[:store_url].any?
    end
  end

  test "limits the lengths of collected data" do
    request = PilotRequest.new(valid_attributes.merge(name: "a" * 101, email: "#{'a' * 250}@example.com", store_url: "https://example.com/#{'a' * 2048}"))
    assert_not request.valid?
    %i[name email store_url].each { |attribute| assert request.errors[attribute].any? }
  end

  private

  def valid_attributes
    { name: "Review Brand", email: "owner@example.com", store_url: "https://example.com", platform: "Shopify" }
  end
end
