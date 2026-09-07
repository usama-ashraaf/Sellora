# frozen_string_literal: true

module Pilot
  # Bounded autopilot (M6): only merchant-selected kinds, with evidence/cooldown/cap/kill switch.
  class Autopilot
    Error = Class.new(StandardError)

    def self.call(shop:)
      new(shop: shop).call
    end

    def self.ensure_policy!(shop)
      policy = AutopilotPolicy.find_or_initialize_by(shop_id: shop.id)
      policy.account = shop.account
      policy.allowed_action_kinds = [] if policy.new_record?
      policy.save!
      policy
    end

    def initialize(shop:)
      @shop = shop
      raise Error, "shop has no account" if shop.account.blank?

      @policy = self.class.ensure_policy!(shop)
    end

    def call
      run = @policy.autopilot_runs.create!(account: @shop.account, shop: @shop, status: "running", started_at: Time.current)
      unless @policy.enabled? && @policy.kill_switch_at.nil?
        run.update!(status: "skipped", finished_at: Time.current, details: { "reason" => "kill_switch_or_disabled" })
        return { skipped: "kill_switch_or_disabled", applied: 0, run_id: run.id }
      end

      candidate_rows = candidates.to_a
      applied = 0
      skipped = 0
      skip_reasons = Hash.new(0)
      remaining_actions = [ @policy.max_actions_per_day - actions_applied_today, 0 ].max
      estimated_cost_used = estimated_discount_cost_today
      candidate_rows.each do |rec|
        reason, payload = skip_reason(rec, applied:, remaining_actions:, estimated_cost_used:)
        if reason
          skipped += 1
          skip_reasons[reason] += 1
          next
        end

        action = ReviewedActions.propose!(recommendation: rec, actor_email: "autopilot@sellora.local")
        ReviewedActions.approve!(action, actor_email: "autopilot@sellora.local")
        ReviewedActions.apply!(action, actor_email: "autopilot@sellora.local")
        estimated_cost_used += discount_cost(payload)
        applied += 1
      rescue ReviewedActions::Conflict, ReviewedActions::Error, Shopify::AdminClient::Error => e
        skipped += 1
        skip_reasons[e.class.name] += 1
        Rails.logger.warn("[autopilot] skipped shop_id=#{@shop.id} recommendation_id=#{rec.id} error=#{e.class}: #{e.message}")
      end

      run.update!(status: "completed", candidates_count: candidate_rows.size, applied_count: applied,
                  skipped_count: skipped, details: { "skip_reasons" => skip_reasons }, finished_at: Time.current)
      { applied: applied, skipped: skipped, policy_id: @policy.id, run_id: run.id }
    rescue StandardError => e
      run&.update!(status: "failed", finished_at: Time.current, details: { "error_class" => e.class.name, "message" => e.message })
      raise
    end

    private

    def candidates
      Recommendation.for_shop(@shop).open_items.by_priority
    end

    def cooldown_blocked?(rec)
      since = @policy.cooldown_hours.hours.ago
      ReviewedAction.for_shop(@shop)
                    .joins(:recommendation)
                    .where(recommendations: { kind: rec.kind }, status: "applied")
                    .where("applied_at >= ?", since)
                    .exists?
    end

    def skip_reason(rec, applied:, remaining_actions:, estimated_cost_used:)
      return [ "daily_action_cap", nil ] if applied >= remaining_actions
      return [ "kind_not_allowed", nil ] unless @policy.allows_kind?(rec.kind)
      return [ "severity_below_minimum", nil ] unless @policy.severity_allowed?(rec.priority)
      return [ "insufficient_evidence", nil ] if evidence_count(rec) < @policy.minimum_evidence_count
      return [ "cooldown", nil ] if cooldown_blocked?(rec)
      return [ "inventory_below_minimum", nil ] if inventory_blocked?(rec)

      payload = ActionPayload.build(recommendation: rec)
      return [ "discount_above_maximum", nil ] if discount_percentage(payload) > @policy.max_discount_percentage
      return [ "margin_unknown_or_below_floor", nil ] unless margin_allowed?(rec, payload)
      return [ "daily_discount_cost_cap", nil ] if estimated_cost_used + discount_cost(payload) > @policy.max_estimated_discount_cost_per_day

      [ nil, payload ]
    rescue ActionPayload::Error
      [ "action_requires_merchant_input", nil ]
    end

    def evidence_count(rec)
      keys = %w[product_viewed product_added_to_cart checkout_started checkout_completed paid_orders paid_units]
      count = keys.sum { |key| rec.evidence[key].to_i }
      count.positive? ? count : (rec.audit_finding_id.present? ? 1 : 0)
    end

    def inventory_blocked?(rec)
      return false unless @policy.require_in_stock

      evidence = rec.evidence
      evidence.fetch("inventory", 0).to_i < @policy.minimum_inventory_units ||
        evidence.fetch("size_coverage_percent", 0).to_i < @policy.minimum_size_coverage_percent
    end

    def margin_allowed?(rec, payload)
      return true unless payload["operation"] == "discount_code_create" && @policy.margin_floor_pct.present?

      return false unless rec.evidence["cost_coverage_percent"].to_i == 100
      return false if rec.evidence["minimum_margin_percent"].blank?

      base_margin = BigDecimal(rec.evidence["minimum_margin_percent"].to_s) / 100
      discount = BigDecimal(payload["percentage"].to_s) / 100
      return false if discount >= 1

      post_discount_margin = (1 - (1 - base_margin) / (1 - discount)) * 100
      post_discount_margin >= @policy.margin_floor_pct
    rescue ArgumentError
      false
    end

    def discount_percentage(payload)
      payload["operation"] == "discount_code_create" ? payload["percentage"].to_i : 0
    end

    def discount_cost(payload)
      return BigDecimal("0") unless payload["operation"] == "discount_code_create"

      BigDecimal(payload.fetch("estimated_discount_cost", 0).to_s)
    rescue ArgumentError
      BigDecimal("0")
    end

    def actions_applied_today
      ReviewedAction.for_shop(@shop).where(status: "applied", applied_at: Time.current.all_day).count
    end

    def estimated_discount_cost_today
      ReviewedAction.for_shop(@shop).where(status: "applied", applied_at: Time.current.all_day).sum do |action|
        discount_cost(action.after_snapshot)
      end
    end
  end
end
