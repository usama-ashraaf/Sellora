# frozen_string_literal: true

# Open fictional in-app demo (M2). Not the marketing page.
# Auth is intentionally session-free for this foundation slice — see docs/m2-foundation.md.
class DemoController < ApplicationController
  def show
    @account = Accounts::EnsureDemoAccount.call
    @shops = Shop.for_account(@account).order(:shopify_domain)
    @rule_set = AuditRuleSet.current_clothing || Audit::ClothingRulesSeed.call
    @product_count = CatalogProduct.joins(:shop).merge(Shop.for_account(@account)).count
    @variant_count = CatalogVariant.joins(catalog_product: :shop).merge(Shop.for_account(@account)).count
    @findings = AuditFinding.for_account(@account).open_findings.includes(:audit_rule, :shop, :catalog_product).order(created_at: :desc).limit(12)

    if @findings.empty? && @shops.any?
      seed_sample_findings!
      @findings = AuditFinding.for_account(@account).open_findings.includes(:audit_rule, :shop, :catalog_product).order(created_at: :desc).limit(12)
    end
  end

  private

  def seed_sample_findings!
    shop = @shops.first
    return unless shop

    existing = AuditFinding.for_shop(shop).count
    return if existing.positive?

    Audit::Runner.call(shop: shop, rule_set: @rule_set)
  end
end
