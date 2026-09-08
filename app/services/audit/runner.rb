# frozen_string_literal: true

module Audit
  # Evaluates the active clothing rule set against a shop's catalog.
  # Change-aware: skips content rules when fingerprint + rule version match (M4).
  # Freshness (stock/price) always re-checks. Idempotent finding upserts.
  class Runner
    ALPHA_ORDER = %w[XS S M L XL XXL XXXL].freeze
    CONTENT_RULES = %w[
      size_gap
      missing_size_attr
      missing_description
      missing_required_garment_attrs
      inconsistent_piece_counts
    ].freeze
    FRESHNESS_RULES = %w[compare_at_anomaly low_stock_promoted].freeze

    Result = Struct.new(:findings, :skipped, keyword_init: true)

    def self.call(shop:, rule_set: nil, force: false)
      new(shop: shop, rule_set: rule_set, force: force).call
    end

    def initialize(shop:, rule_set: nil, force: false)
      @shop = shop
      raise ArgumentError, "shop has no account" if shop.account.blank?

      @account = shop.account
      @rule_set = rule_set || ::AuditRuleSet.current_clothing
      @force = force
      @findings = []
      @skipped = 0
    end

    def call
      raise ArgumentError, "no active clothing rule set" unless @rule_set

      rules = @rule_set.audit_rules.index_by(&:rule_key)

      @shop.catalog_products.includes(catalog_variants: :catalog_inventory_levels).find_each do |product|
        evaluate_product!(product, rules)
      end

      @shop.update_columns(last_audited_at: Time.current)
      Result.new(findings: @findings, skipped: @skipped)
    end

    private

    def evaluate_product!(product, rules)
      fingerprint = Fingerprint.for_product(product)
      content_unchanged = !@force &&
        product.content_fingerprint == fingerprint &&
        product.rule_set_version == @rule_set.version

      if content_unchanged
        @skipped += 1
        evaluate_freshness_rules!(product, rules)
        resolve_stale_findings!(product, rules.slice(*FRESHNESS_RULES))
      else
        evaluate_content_rules!(product, rules)
        evaluate_freshness_rules!(product, rules)
        resolve_stale_findings!(product, rules.slice(*(CONTENT_RULES + FRESHNESS_RULES)))
        product.update_columns(
          content_fingerprint: fingerprint,
          rule_set_version: @rule_set.version,
          content_checked_at: Time.current,
          freshness_checked_at: Time.current
        )
      end
    end

    def evaluate_content_rules!(product, rules)
      variants = product.catalog_variants.to_a
      sizes = variants.filter_map { |v| extract_size(v) }

      if (rule = rules["size_gap"]) && size_gap?(sizes, rule)
        record_finding!(rule, product, nil,
                        message: "Size gap detected in #{product.title}: sizes present #{sizes.uniq.sort_by { |s| ALPHA_ORDER.index(s) || 99 }.join(', ')}",
                        evidence: { "sizes" => sizes.uniq, "rule_key" => "size_gap" },
                        suggested_action: "Verify whether the missing size(s) should be added or documented as intentional.")
      end

      if (rule = rules["missing_size_attr"]) && missing_size_attr?(variants, rule)
        record_finding!(rule, product, nil,
                        message: "Missing size attribute on #{product.title}",
                        evidence: { "variant_titles" => variants.map(&:title), "rule_key" => "missing_size_attr" },
                        suggested_action: "Confirm Size (or waist/numeric) options for garment variants.")
      end

      if (rule = rules["missing_description"]) && missing_description?(product, rule)
        record_finding!(rule, product, nil,
                        message: "Description looks missing or too short for #{product.title}",
                        evidence: { "rule_key" => "missing_description", "length" => description_text(product).length },
                        suggested_action: "Team should verify the storefront description — Sellora does not invent garment copy.")
      end

      if (rule = rules["missing_required_garment_attrs"]) && missing_garment_attrs?(product, rule)
        missing = Array(rule.config["suggested_attrs"]) - present_attr_keys(product)
        record_finding!(rule, product, nil,
                        message: "Garment attributes may be incomplete on #{product.title}",
                        evidence: { "rule_key" => "missing_required_garment_attrs", "missing" => missing },
                        suggested_action: "Verify fit/fabric/piece count/care with the merchant catalog — do not invent facts.")
      end

      if (rule = rules["inconsistent_piece_counts"]) && inconsistent_piece_counts?(product, rule)
        record_finding!(rule, product, nil,
                        message: "Possible stitched/piece-count conflict on #{product.title}",
                        evidence: { "rule_key" => "inconsistent_piece_counts", "title" => product.title },
                        suggested_action: "Have the team verify piece count and stitched vs unstitched details against the product.")
      end
    end

    def evaluate_freshness_rules!(product, rules)
      product.catalog_variants.each do |variant|
        next unless (rule = rules["compare_at_anomaly"])

        anomaly = compare_at_anomaly(variant, rule)
        next unless anomaly

        record_finding!(rule, product, variant,
                        message: anomaly[:message],
                        evidence: anomaly[:evidence],
                        suggested_action: "Verify selling vs compare-at so compare-at is blank or strictly greater than price.")
      end

      product.update_columns(freshness_checked_at: Time.current) if product.content_fingerprint.present?
    end

    def description_text(product)
      product.raw_attrs["description"].to_s.strip
    end

    def missing_description?(product, rule)
      description_text(product).length < (rule.config["min_length"] || 40).to_i
    end

    def present_attr_keys(product)
      attrs = product.raw_attrs.fetch("garment_attrs", {})
      return [] unless attrs.is_a?(Hash)

      attrs.select { |_k, v| v.present? }.keys.map(&:to_s)
    end

    def missing_garment_attrs?(product, rule)
      suggested = Array(rule.config["suggested_attrs"]).map(&:to_s)
      return false if suggested.empty?

      (suggested - present_attr_keys(product)).size >= 2
    end

    def inconsistent_piece_counts?(product, rule)
      return false unless rule.config["check_title_vs_attrs"]

      title = product.title.to_s.downcase
      attrs = product.raw_attrs.fetch("garment_attrs", {})
      pieces = attrs.is_a?(Hash) ? attrs["piece_count"].to_s : ""
      title_two = title.include?("2 piece") || title.include?("two piece") || title.include?("2-piece")
      title_three = title.include?("3 piece") || title.include?("three piece") || title.include?("3-piece")
      return true if title_two && pieces == "3"
      return true if title_three && pieces == "2"

      stitched = attrs.is_a?(Hash) ? attrs["stitched"].to_s.downcase : ""
      title_unstitched = title.include?("unstitched")
      title_stitched = title.match?(/\bstitched\b/) && !title_unstitched
      return true if title_unstitched && stitched == "true"
      return true if title_stitched && stitched == "false"

      false
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

    def record_finding!(rule, product, variant, message:, evidence:, suggested_action:)
      finding = ::AuditFinding.find_or_initialize_by(
        shop_id: @shop.id,
        audit_rule_id: rule.id,
        catalog_product_id: product&.id,
        catalog_variant_id: variant&.id
      )
      finding.account = @account
      finding.severity = rule.severity
      finding.status = "open" if finding.new_record? || finding.status == "resolved"
      finding.message = message
      finding.evidence = evidence
      finding.suggested_action = suggested_action
      finding.save!
      @findings << finding
      finding
    end

    def resolve_stale_findings!(product, evaluated_rules)
      rule_ids = evaluated_rules.values.compact.map(&:id)
      return if rule_ids.empty?

      active_ids = @findings.filter_map do |finding|
        finding.id if finding.catalog_product_id == product.id && rule_ids.include?(finding.audit_rule_id)
      end
      stale = product.shop.audit_findings
                     .where(catalog_product_id: product.id, audit_rule_id: rule_ids, status: %w[open acknowledged])
      stale = stale.where.not(id: active_ids) if active_ids.any?
      stale.update_all(status: "resolved", updated_at: Time.current)
    end
  end
end
