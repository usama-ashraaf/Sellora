# frozen_string_literal: true

module Audit
  # Seeds the v1 clothing AuditRuleSet from product-brief / fixture themes.
  # Idempotent: safe to re-run.
  class ClothingRulesSeed
    VERSION = "v1"
    NAME = "Clothing catalog rules v1"

    RULES = [
      {
        rule_key: "size_gap",
        title: "Size gap in size matrix",
        severity: "high",
        description: "Expected contiguous clothing sizes are missing (e.g. S/L/XL without M).",
        config: {
          "expected_alpha_sizes" => %w[S M L XL XXL],
          "gap_detection" => true
        }
      },
      {
        rule_key: "compare_at_anomaly",
        title: "Compare-at price anomaly",
        severity: "high",
        description: "Selling price and compare-at relationship is invalid, blank where expected, or useless (equal).",
        config: {
          "require_compare_at_on_sale" => true,
          "reject_compare_at_lte_price" => true
        }
      },
      {
        rule_key: "missing_size_attr",
        title: "Missing size attribute",
        severity: "medium",
        description: "Garment product lacks a size option / only Default Title.",
        config: {
          "reject_default_title_only" => true
        }
      },
      {
        rule_key: "missing_description",
        title: "Missing product description",
        severity: "medium",
        description: "Product description is blank or too short for clothing merchandising.",
        config: { "min_length" => 40 }
      },
      {
        rule_key: "missing_required_garment_attrs",
        title: "Missing required garment attributes",
        severity: "medium",
        description: "Clothing-specific attributes (fit, fabric, piece count) appear incomplete.",
        config: {
          "suggested_attrs" => %w[fit fabric piece_count care]
        }
      },
      {
        rule_key: "inconsistent_piece_counts",
        title: "Inconsistent piece / stitched details",
        severity: "low",
        description: "Stitched vs unstitched or piece-count signals conflict across title and attributes.",
        config: {
          "check_title_vs_attrs" => true
        }
      }
    ].freeze

    def self.call(activate: true)
      new(activate: activate).call
    end

    def initialize(activate: true)
      @activate = activate
    end

    def call
      set = ::AuditRuleSet.find_or_initialize_by(domain: "clothing", version: VERSION)
      set.name = NAME
      set.save!

      RULES.each do |attrs|
        rule = set.audit_rules.find_or_initialize_by(rule_key: attrs[:rule_key])
        rule.title = attrs[:title]
        rule.severity = attrs[:severity]
        rule.description = attrs[:description]
        rule.config = attrs[:config]
        rule.save!
      end

      set.activate! if @activate
      set
    end
  end
end
