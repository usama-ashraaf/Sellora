# frozen_string_literal: true

require "test_helper"

class AuditFindingTest < ActiveSupport::TestCase
  test "database rejects duplicate product findings with no variant" do
    account = Account.create!(name: "Finding Test")
    shop = Shop.create!(account: account, shopify_domain: "finding-test.myshopify.com")
    product = shop.catalog_products.create!(external_id: "p-1", title: "Shirt")
    rules = Audit::ClothingRulesSeed.call
    attributes = { account: account, shop: shop, catalog_product: product,
                   audit_rule: rules.audit_rules.first, severity: "medium", message: "Missing size" }
    AuditFinding.create!(attributes)
    assert_raises(ActiveRecord::RecordNotUnique) do
      AuditFinding.transaction(requires_new: true) { AuditFinding.create!(attributes) }
    end
    assert_equal 1, shop.audit_findings.count
  end

  test "rejects finding when account does not match shop account" do
    account = Account.create!(name: "Owner")
    other = Account.create!(name: "Other")
    shop = Shop.create!(account: account, shopify_domain: "finding-mismatch.myshopify.com")
    rules = Audit::ClothingRulesSeed.call
    finding = AuditFinding.new(
      account: other, shop: shop, audit_rule: rules.audit_rules.first,
      severity: "medium", message: "Mismatch"
    )
    assert_not finding.valid?
    assert_includes finding.errors[:account_id], "must match shop account"
  end
end
