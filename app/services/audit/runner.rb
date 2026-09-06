# frozen_string_literal: true

module Audit
  # Stub runner: evaluates the active clothing rule set against a shop's catalog
  # and emits AuditFinding rows. Idempotent on re-run via natural-key upsert.
  class Runner
    ALPHA_ORDER = %w[XS S M L XL XXL XXXL].freeze

    def self.call(shop:, rule_set: nil)
      new(shop: shop, rule_set: rule_set).call
    end

    def initialize(shop:, rule_set: nil)
      @shop = shop
      @account = shop.account || ::Account.demo!
      @rule_set = rule_set || ::AuditRuleSet.current_clothing
      @findings = []
    end

    def call
      raise ArgumentError, "no active clothing rule set" unless @rule_set

      rules = @rule_set.audit_rules.index_by(&:rule_key)

      @shop.catalog_products.includes(:catalog_variants).find_each do |product|
        evaluate_product!(product, rules)
      end

      @findings
    end

    private

    def evaluate_product!(product, rules)
      variants = product.catalog_variants.to_a
      sizes = variants.filter_map { |v| extract_size(v) }

      if (rule = rules["size_gap"]) && size_gap?(sizes, rule)
        record_finding!(rule, product, nil,
                        message: "Size gap detected in #{product.title}: sizes present #{sizes.uniq.sort_by { |s| ALPHA_ORDER.index(s) || 99 }.join(', ')}",
                        evidence: { "sizes" => sizes.uniq, "rule_key" => "size_gap" },
                        suggested_action: "Add the missing contiguous size(s) or document intentional gaps.")
      end

      if (rule = rules["missing_size_attr"]) && missing_size_attr?(variants, rule)
        record_finding!(rule, product, nil,
                        message: "Missing size attribute on #{product.title}",
                        evidence: { "variant_titles" => variants.map(&:title), "rule_key" => "missing_size_attr" },
                        suggested_action: "Add a Size option (or waist/numeric size) for garment variants.")
      end

      variants.each do |variant|
        next unless (rule = rules["compare_at_anomaly"])

        anomaly = compare_at_anomaly(variant, rule)
        next unless anomaly

        record_finding!(rule, product, variant,
                        message: anomaly[:message],
                        evidence: anomaly[:evidence],
                        suggested_action: "Fix selling vs compare-at so compare-at is blank or strictly greater than price.")
      end
    end

    def extract_size(variant)
      raw = variant.option_summary.presence || variant.title.to_s
      token = raw.to_s.split(" / ").first.to_s.strip.upcase
      return if token.blank? || token == "DEFAULT TITLE" || token == "DEFAULT"

      token if ALPHA_ORDER.include?(token) || token.match?(/\A\d{2,3}\z/)
    end

    def size_gap?(sizes, rule)
      alpha = sizes.map(&:upcase) & Array(rule.config["expected_alpha_sizes"] || ALPHA_ORDER)
      return false if alpha.size < 2

      indices = alpha.filter_map { |s| ALPHA_ORDER.index(s) }.sort
      return false if indices.size < 2

      (indices.first..indices.last).any? { |i| indices.exclude?(i) }
    end

    def missing_size_attr?(variants, rule)
      return true if variants.empty?

      return false unless rule.config["reject_default_title_only"]

      variants.all? do |v|
        summary = v.option_summary.to_s.strip
        title = v.title.to_s.strip
        (summary.blank? || summary.casecmp("Default Title").zero?) &&
          (title.blank? || title.casecmp("Default Title").zero?)
      end
    end

    def compare_at_anomaly(variant, rule)
      # Prices are not first-class columns yet (Phase A sync stores limited attrs).
      # Accept optional evidence from a future price sync via a lightweight JSON side-channel
      # on the product raw_attrs under "variant_prices"[external_id].
      prices = variant.catalog_product.raw_attrs.fetch("variant_prices", {})[variant.external_id]
      return nil unless prices.is_a?(Hash)

      price = prices["price"]&.to_f
      compare = prices["compare_at_price"]
      compare_f = compare.nil? || compare == "" ? nil : compare.to_f

      if rule.config["reject_compare_at_lte_price"] && compare_f && price && compare_f <= price
        return {
          message: "Compare-at anomaly on #{variant.sku || variant.title}: compare-at #{compare_f} <= price #{price}",
          evidence: { "price" => price, "compare_at_price" => compare_f, "rule_key" => "compare_at_anomaly" }
        }
      end

      nil
    end

    # Upsert on natural key (shop, rule, product, variant) so re-runs do not duplicate.
    def record_finding!(rule, product, variant, message:, evidence:, suggested_action:)
      finding = ::AuditFinding.find_or_initialize_by(
        shop_id: @shop.id,
        audit_rule_id: rule.id,
        catalog_product_id: product&.id,
        catalog_variant_id: variant&.id
      )
      finding.account = @account
      finding.severity = rule.severity
      finding.status = "open" if finding.new_record?
      finding.message = message
      finding.evidence = evidence
      finding.suggested_action = suggested_action
      finding.save!
      @findings << finding
      finding
    end
  end
end
