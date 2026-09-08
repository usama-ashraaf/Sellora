# frozen_string_literal: true

module Pilot
  # Converts variant demand, inventory, economics, and order outcomes into a bounded promotion decision.
  class PromotionReadiness
    EVENT_WEIGHT = {
      product_viewed: 1,
      product_added_to_cart: 3,
      checkout_started: 4,
      checkout_completed: 6,
      paid_units: 8
    }.freeze
    POPULAR_SIZE_SHARE = 0.2

    def self.ensure_policy!(shop)
      shop.promotion_policy || shop.create_promotion_policy!(account: shop.account)
    end

    def self.ensure_decisions!(shop)
      return shop.promotion_decisions.ranked.includes(:catalog_product) if shop.promotion_decisions.exists?

      call(shop: shop)
    end

    def self.call(shop:)
      new(shop: shop).call
    end

    def initialize(shop:)
      @shop = shop
      raise ArgumentError, "shop has no account" if shop.account.blank?

      @account = shop.account
      @policy = self.class.ensure_policy!(shop)
    end

    def call
      rows = Pilot::CommerceSignals.call(shop: @shop)[:products]
      active_ids = rows.map { |row| upsert_decision!(row).id }
      @shop.promotion_decisions.where.not(id: active_ids).delete_all
      attach_substitutes!
      @shop.promotion_decisions.ranked.includes(:catalog_product)
    end

    private

    def upsert_decision!(row)
      result = evaluate(row)
      decision = @shop.promotion_decisions.find_or_initialize_by(catalog_product: row[:product])
      decision.assign_attributes(
        account: @account,
        status: result.fetch(:status),
        score: result.fetch(:score),
        confidence: result.fetch(:confidence),
        metrics: result.fetch(:metrics),
        reasons: result.fetch(:reasons),
        generated_at: Time.current
      )
      decision.save!
      decision
    end

    def evaluate(row)
      demand = demand_profile(row[:variants])
      safe_orders = safe_order_capacity(demand)
      velocity = order_velocity(row)
      runway = velocity.positive? ? (safe_orders / velocity).round(1) : nil
      price = average_price(row, demand)
      economics = economics(row, demand, price)
      rates = outcome_rates(row)
      popular_stockouts = demand.select { |item| item[:share] >= POPULAR_SIZE_SHARE && item[:inventory] <= 0 }
      reasons = decision_reasons(row, demand, safe_orders, runway, economics, rates, popular_stockouts)
      score = readiness_score(row, demand, safe_orders, runway, economics, rates, popular_stockouts)
      status = decision_status(row, safe_orders, runway, economics, popular_stockouts, score)

      {
        status: status,
        score: score,
        confidence: confidence(row, demand, economics),
        reasons: reasons,
        metrics: {
          "currency" => currency_for(row[:product]),
          "inventory_units" => row[:inventory],
          "size_coverage_percent" => row[:size_coverage_percent],
          "safe_order_capacity" => safe_orders,
          "estimated_daily_orders" => velocity.round(2),
          "estimated_runway_days" => runway,
          "average_selling_price" => decimal_value(price),
          "estimated_contribution_per_order" => decimal_value(economics[:contribution]),
          "estimated_contribution_margin_percent" => economics[:margin_percent]&.round(1),
          "promotion_spend_ceiling" => decimal_value(spend_ceiling(safe_orders, price, economics[:contribution])),
          "paid_orders_30d" => row[:paid_orders],
          "paid_units_30d" => row[:paid_units],
          "cancelled_order_rate_percent" => rates[:cancelled].round(1),
          "refunded_order_rate_percent" => rates[:refunded].round(1),
          "cod_order_share_percent" => rates[:cod].round(1),
          "cod_outcome_note" => "Fulfilled is a Shopify status proxy; it does not prove courier delivery or COD cash collection.",
          "cost_coverage_percent" => row[:cost_coverage_percent],
          "demand_source" => demand.any? { |item| item[:observed] } ? "observed storefront and order signals" : "equal-share fallback; no product demand observed",
          "recommended_use" => recommended_use(status),
          "variant_capacity" => demand.map { |item| variant_capacity_metrics(item) }
        }
      }
    end

    def demand_profile(variants)
      rows = variants.map do |variant|
        signal = EVENT_WEIGHT.sum { |metric, weight| variant[metric].to_i * weight }
        variant.merge(signal: signal, observed: signal.positive?)
      end
      total = rows.sum { |row| row[:signal] }
      rows.each do |row|
        row[:share] = if total.positive?
          row[:signal].to_f / total
        elsif rows.any?
          1.0 / rows.size
        else
          0
        end
      end
      rows
    end

    def safe_order_capacity(demand)
      capacities = demand.filter_map do |item|
        next unless item[:share].positive?

        item[:inventory].to_i / item[:share]
      end
      capacities.min&.floor || 0
    end

    def order_velocity(row)
      paid = row[:paid_orders].to_f / 30
      return paid if paid.positive?

      checkout = row[:checkout_completed].to_f * 0.5 / 7
      return checkout if checkout.positive?

      row[:product_added_to_cart].to_f * 0.1 / 7
    end

    def average_price(row, demand)
      return row[:paid_revenue] / row[:paid_units] if row[:paid_units].positive?

      weighted_value(demand, :price)
    end

    def economics(row, demand, price)
      cost = weighted_value(demand, :cost, require_complete: true)
      return { contribution: nil, margin_percent: nil } unless price&.positive? && cost

      cod_share = outcome_rates(row)[:cod] / 100
      expected_cod_loss = cod_share * (@policy.expected_cod_failure_rate_percent / 100) *
                          (@policy.shipping_cost_per_order + @policy.cod_failure_cost)
      contribution = price - cost - @policy.shipping_cost_per_order - expected_cod_loss
      { contribution: contribution, margin_percent: contribution * 100 / price }
    end

    def weighted_value(demand, field, require_complete: false)
      relevant = demand.select { |item| item[:share].positive? }
      return if relevant.empty?
      return if require_complete && relevant.any? { |item| item[field].nil? || item[field] <= 0 }

      known = relevant.select { |item| item[field] }
      return if known.empty?

      share = known.sum { |item| item[:share] }
      known.sum { |item| item[field] * item[:share] } / share
    end

    def outcome_rates(row)
      outcomes = row[:paid_orders] + row[:cancelled_orders] + row[:refunded_orders]
      denominator = [ outcomes, 1 ].max.to_f
      cod_denominator = [ row[:paid_orders], row[:cod_orders], 1 ].max.to_f
      {
        cancelled: row[:cancelled_orders] * 100 / denominator,
        refunded: row[:refunded_orders] * 100 / denominator,
        cod: row[:cod_orders] * 100 / cod_denominator
      }
    end

    def spend_ceiling(safe_orders, price, contribution)
      return unless price&.positive? && contribution&.positive? && safe_orders.positive?

      limits = [ safe_orders * price / @policy.target_roas, safe_orders * contribution ]
      limits << safe_orders * @policy.target_acquisition_cost if @policy.target_acquisition_cost
      limits.min.floor(2)
    end

    def decision_status(row, safe_orders, runway, economics, popular_stockouts, score)
      return "block" if row[:inventory].zero? || popular_stockouts.any? || safe_orders < @policy.minimum_safe_orders
      return "block" if economics[:contribution] && economics[:contribution] <= 0

      limited = row[:size_coverage_percent] < 80 || runway.nil? || runway < @policy.desired_runway_days ||
                economics[:margin_percent].nil? || economics[:margin_percent] < @policy.minimum_margin_percent ||
                row[:cancelled_orders].positive? || row[:refunded_orders].positive?
      limited || score < 75 ? "limit" : "promote"
    end

    def readiness_score(row, demand, safe_orders, runway, economics, rates, popular_stockouts)
      score = 100.0
      score -= (100 - row[:size_coverage_percent]) * 0.4
      score -= 35 if popular_stockouts.any?
      score -= 35 if safe_orders < @policy.minimum_safe_orders
      score -= 15 unless demand.any? { |item| item[:observed] }
      score -= 15 if economics[:margin_percent].nil?
      score -= 25 if economics[:margin_percent] && economics[:margin_percent] < @policy.minimum_margin_percent
      score -= 25 * (1 - runway / @policy.desired_runway_days) if runway && runway < @policy.desired_runway_days
      score -= 20 if runway.nil?
      score -= [ rates[:cancelled] * 0.3, 20 ].min
      score -= [ rates[:refunded] * 0.35, 20 ].min
      score.round.clamp(0, 100)
    end

    def decision_reasons(row, demand, safe_orders, runway, economics, rates, popular_stockouts)
      reasons = []
      reasons << popular_stockout_reason(demand, popular_stockouts) if popular_stockouts.any?
      reasons << "Only #{row[:size_coverage_percent]}% of variants are currently in stock." if row[:size_coverage_percent] < 80
      reasons << "Demand-weighted inventory supports about #{safe_orders} additional orders before a needed variant runs out."
      reasons << "Estimated runway is #{runway} days, below the #{@policy.desired_runway_days}-day target." if runway && runway < @policy.desired_runway_days
      reasons << "No customer demand has been observed yet, so capacity assumes equal demand across variants." unless demand.any? { |item| item[:observed] }
      reasons << "Variant cost data is incomplete, so Sellora cannot set a responsible ad-spend ceiling." if economics[:margin_percent].nil?
      if economics[:margin_percent] && economics[:margin_percent] < @policy.minimum_margin_percent
        reasons << "Estimated contribution margin is #{economics[:margin_percent].round(1)}%, below the #{@policy.minimum_margin_percent}% floor."
      end
      reasons << "Cancelled-order rate is #{rates[:cancelled].round(1)}%; validate fulfillment before adding demand." if rates[:cancelled].positive?
      reasons << "Refunded-order rate is #{rates[:refunded].round(1)}%; investigate returns before promotion." if rates[:refunded].positive?
      reasons << "Inventory, margin, runway, and observed outcomes are within the configured limits." if reasons.one?
      reasons
    end

    def confidence(row, demand, economics)
      observed_events = row[:product_viewed] + row[:product_added_to_cart] + row[:checkout_completed]
      return "high" if row[:paid_units] >= 5 && observed_events >= 5 && economics[:margin_percent]
      return "medium" if row[:paid_units].positive? || observed_events >= 5

      "low"
    end

    def popular_stockout_reason(demand, stockouts)
      labels = stockouts.map { |item| item[:title] }.join(", ")
      return "#{labels} carry at least 20% of observed demand and are out of stock." if demand.any? { |item| item[:observed] }

      "#{labels} are out of stock under the equal-variant demand fallback."
    end

    def variant_capacity_metrics(item)
      {
        "variant_id" => item[:variant].external_id,
        "title" => item[:title],
        "sku" => item[:sku],
        "inventory" => item[:inventory],
        "demand_share_percent" => (item[:share] * 100).round(1),
        "capacity_orders" => item[:share].positive? ? (item[:inventory] / item[:share]).floor : nil,
        "paid_units_30d" => item[:paid_units],
        "cart_adds_7d" => item[:product_added_to_cart]
      }
    end

    def recommended_use(status)
      case status
      when "promote" then "Feature prominently and test in paid social within the calculated order and spend limits."
      when "limit" then "Use organic placement or a small test only after reviewing the flagged constraint."
      else "Pause featured placement and paid promotion until the hard inventory or economics constraint is fixed."
      end
    end

    def attach_substitutes!
      decisions = @shop.promotion_decisions.includes(:catalog_product).to_a
      decisions.each do |decision|
        next if decision.status == "promote"

        substitute = decisions.reject { |candidate| candidate.id == decision.id || candidate.metrics["inventory_units"].to_i.zero? }
                              .max_by { |candidate| [ candidate.status == "promote" ? 1 : 0, candidate.score ] }
        next unless substitute && substitute.score > decision.score

        decision.update_columns(metrics: decision.metrics.merge(
          "substitute_product_id" => substitute.catalog_product_id,
          "substitute_product_title" => substitute.catalog_product.title,
          "substitute_status" => substitute.status,
          "substitute_score" => substitute.score
        ), updated_at: Time.current)
      end
    end

    def currency_for(product)
      product.raw_attrs["currency"].presence || shop_currency ||
        product.raw_attrs.dig("variant_prices")&.values&.filter_map { |row| row["cost_currency"].presence }&.first
    end

    def shop_currency
      return @shop_currency if defined?(@shop_currency)

      @shop_currency = @shop.commerce_orders.where.not(currency: [ nil, "" ]).order(processed_at: :desc).pick(:currency).presence
      @shop_currency ||= @shop.activity_events.where(source: "web_pixel").order(occurred_at: :desc).limit(100)
                                    .pluck(:payload).filter_map { |payload| payload["currency"].presence }.first
    end

    def decimal_value(value)
      value&.round(2)&.to_s("F")
    end
  end
end
