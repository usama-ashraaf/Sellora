# frozen_string_literal: true

require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(name: "Roles Co")
  end

  test "allows owner admin member roles" do
    %w[owner admin member].each_with_index do |role, i|
      m = @account.memberships.create!(email: "u#{i}@example.com", role: role)
      assert_equal role, m.role
    end
  end

  test "rejects unknown role" do
    m = Membership.new(account: @account, email: "x@example.com", role: "superuser")
    assert_not m.valid?
  end

  test "email unique per account" do
    @account.memberships.create!(email: "dup@example.com", role: "member")
    dup = Membership.new(account: @account, email: "DUP@example.com", role: "admin")
    assert_not dup.valid?
  end

  test "user is optional for email-only invite stub" do
    m = @account.memberships.create!(email: "invite@example.com", role: "member")
    assert_nil m.user
  end
end
