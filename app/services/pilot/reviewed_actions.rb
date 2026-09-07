# frozen_string_literal: true

module Pilot
  # M5 reviewed-action workflow: propose → approve/reject → apply with conflict check.
  class ReviewedActions
    Error = Class.new(StandardError)
    Conflict = Class.new(Error)

    def self.propose!(recommendation:, attributes: {}, actor_email: nil)
      new(recommendation.shop).propose!(recommendation: recommendation, attributes: attributes, actor_email: actor_email)
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

    def self.retry!(action, actor_email: nil)
      new(action.shop).retry!(action, actor_email: actor_email)
    end

    def initialize(shop)
      @shop = shop
      raise Error, "shop has no account" if shop.account.blank?
    end

    def propose!(recommendation:, attributes: {}, actor_email: nil)
      raise Error, "recommendation closed" unless recommendation.status.in?(%w[open acknowledged proposed])

      existing = recommendation.reviewed_actions.pending.order(created_at: :desc).first
      return existing if existing

      product = recommendation.catalog_product
      before = snapshot_for(product)
      after = ActionPayload.build(recommendation: recommendation, attributes: attributes)
      action = ReviewedAction.create!(
        account: @shop.account,
        shop: @shop,
        recommendation: recommendation,
        audit_finding: recommendation.audit_finding,
        action_kind: after.fetch("operation"),
        status: "pending_approval",
        actor_email: actor_email,
        before_snapshot: before,
        after_snapshot: after,
        source_fingerprint: product&.then { |row| Audit::Fingerprint.for_product(row.reload) }
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
      result = Shopify::ActionExecutor.apply(shop: @shop, action: action)
      action.update!(
        status: "applied",
        applied_at: Time.current,
        actor_email: actor_email.presence || action.actor_email,
        result_message: result.fetch(:message),
        after_snapshot: result[:after] || action.after_snapshot
      )
      action.audit_finding&.update!(status: "resolved")
      action.recommendation&.update!(status: "dismissed")
      action
    rescue Conflict
      raise
    rescue StandardError => e
      action.update!(status: "failed", failed_at: Time.current, result_message: e.message)
      action.recommendation&.update!(status: "open")
      raise e if e.is_a?(Error)

      raise Error, e.message
    end

    def retry!(action, actor_email: nil)
      raise Error, "only failed or conflicted actions can be retried" unless action.status.in?(%w[failed conflict])

      product = action.recommendation&.catalog_product || action.audit_finding&.catalog_product
      action.update!(
        status: "pending_approval",
        actor_email: actor_email.presence || action.actor_email,
        before_snapshot: snapshot_for(product),
        source_fingerprint: product&.then { |row| Audit::Fingerprint.for_product(row.reload) },
        approved_at: nil,
        failed_at: nil,
        conflict_reason: nil,
        result_message: nil
      )
      action.recommendation&.update!(status: "proposed")
      action
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
  end
end
