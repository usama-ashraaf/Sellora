# frozen_string_literal: true

module Pilot
  # Builds read-only recommendations from open findings + product-level commerce signals (M4).
  class Recommendations
    SIGNAL_KINDS = %w[traffic_intent conversion_review promotion_opportunity].freeze
    GROWTH_KINDS = %w[featured_product social_ad_candidate restock_before_promotion].freeze
    MIN_PRODUCT_VIEWS = 5
    MIN_PROMOTION_INVENTORY = 20
    MIN_SIZE_COVERAGE_PERCENT = 70
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
      rows.concat(signal_rows!)
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

    def signal_rows!
      signals = Pilot::CommerceSignals.call(shop: @shop)[:products]
      active = signals.filter_map do |product_signals|
        kind = signal_kind(product_signals)
        next unless kind

        upsert_signal!(product_signals, kind)
      end
      active.concat(growth_rows!(signals))
      stale = @shop.recommendations.open_items.where(kind: SIGNAL_KINDS + GROWTH_KINDS).where.not(id: active.map(&:id))
      stale.update_all(status: "dismissed", updated_at: Time.current)
      active
    end

    def growth_rows!(signals)
      sellers = signals.select { |row| row[:paid_orders].positive? }
      ready = sellers.select { |row| promotion_ready?(row) }
      rows = []
      rows << upsert_growth!(ready.max_by { |row| featured_score(row) }, "featured_product") if ready.any?
      rows << upsert_growth!(ready.max_by { |row| social_score(row) }, "social_ad_candidate") if ready.any?
      restock = sellers.reject { |row| inventory_ready?(row) }.max_by { |row| demand_score(row) }
      rows << upsert_growth!(restock, "restock_before_promotion") if restock
      rows
    end

    def promotion_ready?(signals)
      inventory_ready?(signals) && signals[:cancelled_orders].zero? && signals[:refunded_orders].zero?
    end

    def inventory_ready?(signals)
      signals[:inventory] >= MIN_PROMOTION_INVENTORY &&
        signals[:size_coverage_percent] >= MIN_SIZE_COVERAGE_PERCENT
    end

    def demand_score(signals)
      signals[:paid_orders] * 50 + signals[:paid_units] * 15 +
        signals[:product_added_to_cart] * 4 + signals[:product_viewed] -
        signals[:cancelled_orders] * 60 - signals[:refunded_orders] * 70
    end

    def featured_score(signals)
      demand_score(signals) + signals[:size_coverage_percent] * 0.3 + [ signals[:inventory], 100 ].min * 0.2
    end

    def social_score(signals)
      conversion = signals[:product_viewed].positive? ? signals[:paid_orders] * 100.0 / signals[:product_viewed] : 0
      demand_score(signals) + conversion * 0.5 + signals[:size_coverage_percent] * 0.4 +
        [ signals[:inventory], 100 ].min * 0.3
    end

    def upsert_growth!(signals, kind)
      rec = Recommendation.find_or_initialize_by(
        shop_id: @shop.id,
        catalog_product_id: signals[:product].id,
        audit_finding_id: nil,
        kind: kind
      )
      rec.account = @account
      rec.priority = kind == "restock_before_promotion" ? "high" : "medium"
      rec.status = "open"
      rec.catalog_product = signals[:product]
      rec.title, rec.rationale, rec.suggested_action = growth_copy(signals, kind)
      rec.evidence = signal_evidence(signals).merge(
        "demand_score" => demand_score(signals).round(1),
        "featured_score" => featured_score(signals).round(1),
        "social_ad_score" => social_score(signals).round(1),
        "minimum_promotion_inventory" => MIN_PROMOTION_INVENTORY,
        "minimum_size_coverage_percent" => MIN_SIZE_COVERAGE_PERCENT
      )
      rec.save!
      rec
    end

    def growth_copy(signals, kind)
      evidence = "#{signals[:paid_orders]} paid orders, #{signals[:paid_units]} units sold, " \
                 "#{signals[:inventory]} units available, and #{signals[:size_coverage_percent]}% size coverage."
      case kind
      when "featured_product"
        [ "Feature on storefront: #{signals[:title]}", evidence,
          "Place this product in a prominent homepage or collection position while inventory remains healthy." ]
      when "social_ad_candidate"
        [ "Social ad candidate: #{signals[:title]}", evidence,
          "Use this product for the next paid-social creative after checking margin, imagery, audience, and campaign policy." ]
      else
        missing = signals[:unavailable_sizes].presence&.join(", ") || "inventory depth"
        [ "Restock before promotion: #{signals[:title]}", evidence,
          "Restock #{missing} before adding more storefront or advertising demand." ]
      end
    end

    def signal_kind(signals)
      return if signals[:product_viewed] < MIN_PRODUCT_VIEWS
      return "traffic_intent" if signals[:product_added_to_cart].zero?
      return "promotion_opportunity" if signals[:paid_orders].positive? && signals[:inventory].positive? &&
                                        signals[:cancelled_orders].zero? && signals[:refunded_orders].zero?
      "conversion_review" if signals[:paid_orders].zero?
    end

    def upsert_signal!(signals, kind)
      rec = Recommendation.find_or_initialize_by(
        shop_id: @shop.id,
        catalog_product_id: signals[:product].id,
        audit_finding_id: nil,
        kind: kind
      )
      rec.account = @account
      rec.priority = kind == "promotion_opportunity" ? "high" : "medium"
      rec.status = "open"
      rec.catalog_product = signals[:product]
      rec.title, rec.rationale, rec.suggested_action = recommendation_copy(signals, kind)
      rec.evidence = signal_evidence(signals)
      rec.save!
      rec
    end

    def recommendation_copy(signals, kind)
      counts = "#{signals[:product_viewed]} views, #{signals[:product_added_to_cart]} cart adds, " \
               "#{signals[:checkout_completed]} tracked checkouts, and #{signals[:paid_orders]} paid orders in the available windows."
      case kind
      when "promotion_opportunity"
        [ "Promotion candidate: #{signals[:title]}", counts,
          "Review margin and campaign fit, then consider promoting this in-stock product. No campaign is changed automatically." ]
      when "conversion_review"
        [ "Cart interest without a paid order: #{signals[:title]}", counts,
          "Review price, shipping, checkout friction, and tracking coverage before changing the promotion." ]
      else
        [ "Views without cart activity: #{signals[:title]}", counts,
          "Review this product page, offer, size availability, and consent-limited tracking gaps." ]
      end
    end

    def signal_evidence(signals)
      signals.except(:product, :order_ids, :paid_revenue).transform_keys(&:to_s).merge(
        "paid_revenue" => signals[:paid_revenue].to_s,
        "storefront_window_days" => 7,
        "orders_window_days" => 30,
        "limitation" => "storefront events are consent-limited; revenue is not profit; COD collection is not verified"
      )
    end
  end
end
