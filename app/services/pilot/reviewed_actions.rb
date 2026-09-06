# frozen_string_literal: true

module Pilot
  # M5 reviewed-action workflow: propose → approve/reject → apply with conflict check.
  class ReviewedActions
    Error = Class.new(StandardError)
    Conflict = Class.new(Error)

    def self.propose!(recommendation:, actor_email: nil)
      new(recommendation.shop).propose!(recommendation: recommendation, actor_email: actor_email)
    end

    def self.approve!(action, actor_email: nil)
      new(action.shop).approve!(action, actor_email: actor_email)
    end

    def self.reject!(action, actor_email: nil)
      new(action.shop).reject!(action, actor_email: actor_email)
    end

    def self.apply!(action, actor_email: nil)
      new(action.shop).apply!(action, actor_email: actor_email)
    end

    def initialize(shop)
      @shop = shop
      raise Error, "shop has no account" if shop.account.blank?
    end

    def propose!(recommendation:, actor_email: nil)
      raise Error, "recommendation closed" unless recommendation.status.in?(%w[open acknowledged proposed])

      product = recommendation.catalog_product
      before = snapshot_for(product)
      action = ReviewedAction.create!(
        account: @shop.account,
        shop: @shop,
        recommendation: recommendation,
        audit_finding: recommendation.audit_finding,
        action_kind: recommendation.kind,
        status: "pending_approval",
        actor_email: actor_email,
        before_snapshot: before,
        after_snapshot: proposed_after(recommendation, before),
        source_fingerprint: product&.content_fingerprint
      )
      recommendation.update!(status: "proposed")
      action
    end

    def approve!(action, actor_email: nil)
      raise Error, "not pending" unless action.pending_approval?

      detect_conflict!(action)
      action.update!(status: "approved", approved_at: Time.current, actor_email: actor_email.presence || action.actor_email)
      action.recommendation&.update!(status: "approved")
      action
    end

    def reject!(action, actor_email: nil)
      action.update!(status: "rejected", rejected_at: Time.current, actor_email: actor_email.presence || action.actor_email)
      action.recommendation&.update!(status: "dismissed")
      action
    end

    def apply!(action, actor_email: nil)
      raise Error, "must be approved" unless action.approved?

      detect_conflict!(action)
      # Wave 1: record execution without silent Admin writes. Real writes need write_products + explicit allow.
      if write_allowed?
        result = Shopify::ProductPatch.apply(shop: @shop, action: action)
        action.update!(
          status: "applied",
          applied_at: Time.current,
          actor_email: actor_email.presence || action.actor_email,
          result_message: result[:message],
          after_snapshot: result[:after] || action.after_snapshot
        )
      else
        action.update!(
          status: "applied",
          applied_at: Time.current,
          actor_email: actor_email.presence || action.actor_email,
          result_message: "Recorded as applied locally (Shopify write not enabled). " \
                          "Set SELLORA_ALLOW_WRITES=true and grant write_products to push source changes."
        )
      end
      action.audit_finding&.update!(status: "resolved")
      action
    rescue Conflict
      raise
    rescue StandardError => e
      action.update!(status: "failed", failed_at: Time.current, result_message: e.message)
      raise
    end

    private

    def detect_conflict!(action)
      product = action.recommendation&.catalog_product || action.audit_finding&.catalog_product
      return if product.blank? || action.source_fingerprint.blank?

      current = Audit::Fingerprint.for_product(product.reload)
      return if current == action.source_fingerprint

      action.update!(status: "conflict", conflict_reason: "Catalog source changed since proposal", failed_at: Time.current)
      raise Conflict, "source changed since proposal"
    end

    def snapshot_for(product)
      return {} if product.blank?

      {
        "external_id" => product.external_id,
        "title" => product.title,
        "handle" => product.handle,
        "fingerprint" => product.content_fingerprint,
        "raw_attrs" => product.raw_attrs
      }
    end

    def proposed_after(recommendation, before)
      before.merge(
        "proposed_action" => recommendation.suggested_action,
        "note" => "Preview only until approved and applied. Team must verify facts."
      )
    end

    def write_allowed?
      ENV["SELLORA_ALLOW_WRITES"].to_s == "true" &&
        @shop.scope.to_s.split(",").map(&:strip).include?("write_products")
    end
  end
end
