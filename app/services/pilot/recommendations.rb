# frozen_string_literal: true

module Pilot
  # Builds read-only recommendations from open findings + simple activity/order signals (M4).
  class Recommendations
    def self.call(shop:)
      new(shop: shop).call
    end

    def initialize(shop:)
      @shop = shop
      raise ArgumentError, "shop has no account" if shop.account.blank?

      @account = shop.account
    end

    def call
      rows = []
      @shop.audit_findings.open_findings.includes(:audit_rule, :catalog_product).find_each do |finding|
        rows << upsert_from_finding!(finding)
      end
      rows.concat(traffic_intent_rows!)
      @shop.update_columns(last_recommendation_at: Time.current)
      rows
    end

    private

    def upsert_from_finding!(finding)
      kind = kind_for(finding.audit_rule.rule_key)
      rec = Recommendation.find_or_initialize_by(
        shop_id: @shop.id,
        audit_finding_id: finding.id,
        kind: kind
      )
      rec.account = @account
      rec.catalog_product = finding.catalog_product
      rec.priority = finding.severity
      rec.status = "open" if rec.new_record? || rec.status == "open"
      rec.title = finding.audit_rule.title
      rec.rationale = finding.message
      rec.suggested_action = finding.suggested_action
      rec.evidence = finding.evidence.merge("finding_id" => finding.id, "rule_key" => finding.audit_rule.rule_key)
      rec.save!
      rec
    end

    def kind_for(rule_key)
      case rule_key
      when "compare_at_anomaly" then "promotion_accuracy"
      when "size_gap", "missing_size_attr" then "availability"
      else "catalog_fix"
      end
    end

    # High views with no cart signal — investigation only, not a demand conclusion.
    def traffic_intent_rows!
      since = 7.days.ago
      views = @shop.activity_events.where(event_name: "product_viewed").where("occurred_at >= ?", since).count
      carts = @shop.activity_events.where(event_name: "product_added_to_cart").where("occurred_at >= ?", since).count
      return [] unless views >= 10 && carts.zero?

      rec = Recommendation.find_or_initialize_by(
        shop_id: @shop.id,
        audit_finding_id: nil,
        kind: "traffic_intent"
      )
      rec.account = @account
      rec.priority = "medium"
      rec.status = "open"
      rec.title = "Views without cart activity (7d)"
      rec.rationale = "Saw #{views} product_viewed and #{carts} product_added_to_cart events in 7 days. " \
                      "This warrants investigation — it is not proof of low demand or a single cause."
      rec.suggested_action = "Review product pages, size availability, and consent-limited tracking gaps with the team."
      rec.evidence = { "views" => views, "carts" => carts, "window_days" => 7, "limitation" => "pixel incomplete" }
      rec.save!
      [ rec ]
    end
  end
end
