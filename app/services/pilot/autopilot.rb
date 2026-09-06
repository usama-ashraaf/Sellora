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
      return { skipped: "kill_switch_or_disabled", applied: 0 } unless @policy.enabled? && @policy.kill_switch_at.nil?

      applied = 0
      candidates.find_each do |rec|
        break if applied >= @policy.max_actions_per_day
        next unless @policy.allows_kind?(rec.kind)
        next unless @policy.severity_allowed?(rec.priority)
        next if cooldown_blocked?(rec)
        next if @policy.require_in_stock && out_of_stock?(rec)

        action = ReviewedActions.propose!(recommendation: rec, actor_email: "autopilot@sellora.local")
        ReviewedActions.approve!(action, actor_email: "autopilot@sellora.local")
        ReviewedActions.apply!(action, actor_email: "autopilot@sellora.local")
        applied += 1
      rescue ReviewedActions::Conflict, ReviewedActions::Error
        next
      end

      { applied: applied, policy_id: @policy.id }
    end

    private

    def candidates
      Recommendation.for_shop(@shop).open_items.by_priority
    end

    def cooldown_blocked?(rec)
      since = @policy.cooldown_hours.hours.ago
      ReviewedAction.for_shop(@shop)
                    .where(action_kind: rec.kind, status: "applied")
                    .where("applied_at >= ?", since)
                    .exists?
    end

    def out_of_stock?(rec)
      product = rec.catalog_product
      return false if product.blank?

      total = product.catalog_variants.joins(:catalog_inventory_levels).sum("catalog_inventory_levels.available")
      total.to_i <= 0
    end
  end
end
