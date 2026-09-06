# frozen_string_literal: true

class CreateAuditTables < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_rule_sets do |t|
      t.string :name, null: false
      t.string :version, null: false
      t.boolean :active, null: false, default: false
      t.string :domain, null: false, default: "clothing"
      t.timestamps
    end
    add_index :audit_rule_sets, [ :domain, :version ], unique: true
    add_index :audit_rule_sets, [ :domain, :active ]

    create_table :audit_rules do |t|
      t.references :audit_rule_set, null: false, foreign_key: true
      t.string :rule_key, null: false
      t.string :severity, null: false, default: "medium"
      t.jsonb :config, null: false, default: {}
      t.string :title, null: false
      t.text :description
      t.timestamps
    end
    add_index :audit_rules, [ :audit_rule_set_id, :rule_key ], unique: true

    create_table :audit_findings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.references :audit_rule, null: false, foreign_key: true
      t.references :catalog_product, null: true, foreign_key: true
      t.references :catalog_variant, null: true, foreign_key: true
      t.string :severity, null: false
      t.string :status, null: false, default: "open"
      t.string :message, null: false
      t.jsonb :evidence, null: false, default: {}
      t.string :suggested_action
      t.timestamps
    end
    add_index :audit_findings, [ :account_id, :shop_id, :status ]
    add_index :audit_findings, [ :shop_id, :audit_rule_id ]
  end
end
