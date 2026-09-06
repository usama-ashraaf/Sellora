# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes and validates email" do
    user = User.create!(email: "  Pat@Example.COM ", name: "Pat")
    assert_equal "pat@example.com", user.email
  end

  test "email must be unique" do
    User.create!(email: "a@example.com")
    dup = User.new(email: "a@example.com")
    assert_not dup.valid?
  end
end
