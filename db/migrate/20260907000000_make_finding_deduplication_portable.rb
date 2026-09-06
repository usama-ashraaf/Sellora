class MakeFindingDeduplicationPortable < ActiveRecord::Migration[8.1]
  def up
    remove_index :audit_findings, name: "index_audit_findings_on_natural_key"
    # PostgreSQL 14 silently omits Rails' nulls_not_distinct option. Expression
    # keys enforce the same identity for optional references on supported PG versions.
    add_index :audit_findings,
              "shop_id, audit_rule_id, COALESCE(catalog_product_id, 0), COALESCE(catalog_variant_id, 0)",
              unique: true, name: "index_audit_findings_on_natural_key"
  end

  def down
    remove_index :audit_findings, name: "index_audit_findings_on_natural_key"
    add_index :audit_findings,
              [ :shop_id, :audit_rule_id, :catalog_product_id, :catalog_variant_id ],
              unique: true, nulls_not_distinct: true, name: "index_audit_findings_on_natural_key"
  end
end
