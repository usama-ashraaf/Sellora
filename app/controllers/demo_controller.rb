# frozen_string_literal: true

# Fictional in-app demo (M2). Not the marketing page.
# HTTP Basic gated via DEMO_HTTP_BASIC_USER / DEMO_HTTP_BASIC_PASSWORD — see docs/m2-foundation.md.
class DemoController < ApplicationController
  before_action :require_demo_basic_auth!

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

  def require_demo_basic_auth!
    expected_user = ENV["DEMO_HTTP_BASIC_USER"].to_s
    expected_pass = ENV["DEMO_HTTP_BASIC_PASSWORD"].to_s

    if expected_user.blank? || expected_pass.blank?
      render plain: "Demo auth is not configured. Set DEMO_HTTP_BASIC_USER and DEMO_HTTP_BASIC_PASSWORD.",
             status: :service_unavailable
      return
    end

    authenticate_or_request_with_http_basic("Sellora Demo") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, expected_user) &
        ActiveSupport::SecurityUtils.secure_compare(password, expected_pass)
    end
  end

  def seed_sample_findings!
    shop = @shops.first
    return unless shop

    existing = AuditFinding.for_shop(shop).count
    return if existing.positive?

    Audit::Runner.call(shop: shop, rule_set: @rule_set)
  end
end
