# frozen_string_literal: true

class AddAuditFindingNaturalKey < ActiveRecord::Migration[8.1]
  def change
    # Natural key for idempotent audit re-runs. NULL catalog_variant_id is product-scoped.
    add_index :audit_findings,
              [ :shop_id, :audit_rule_id, :catalog_product_id, :catalog_variant_id ],
              unique: true,
              nulls_not_distinct: true,
              name: "index_audit_findings_on_natural_key"
  end
end
