# frozen_string_literal: true

class CreatePilotOpsM4M5M6 < ActiveRecord::Migration[8.1]
  def change
    change_table :catalog_products, bulk: true do |t|
      t.string :content_fingerprint
      t.string :rule_set_version
      t.datetime :content_checked_at
      t.datetime :freshness_checked_at
    end
    add_index :catalog_products, [ :shop_id, :content_fingerprint ], name: "index_catalog_products_on_shop_and_fingerprint"

    change_table :shops, bulk: true do |t|
      t.datetime :last_discovered_at
      t.datetime :last_audited_at
      t.datetime :last_recommendation_at
    end

    create_table :recommendations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.references :audit_finding, foreign_key: true
      t.references :catalog_product, foreign_key: true
      t.string :kind, null: false
      t.string :priority, null: false, default: "medium"
      t.string :status, null: false, default: "open"
      t.string :title, null: false
      t.text :rationale, null: false
      t.string :suggested_action
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end
    add_index :recommendations, [ :shop_id, :status, :priority ]
    add_index :recommendations, [ :account_id, :shop_id, :kind ]

    create_table :reviewed_actions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.references :recommendation, foreign_key: true
      t.references :audit_finding, foreign_key: true
      t.string :action_kind, null: false
      t.string :status, null: false, default: "draft"
      t.string :actor_email
      t.jsonb :before_snapshot, null: false, default: {}
      t.jsonb :after_snapshot, null: false, default: {}
      t.string :source_fingerprint
      t.string :conflict_reason
      t.text :result_message
      t.datetime :approved_at
      t.datetime :rejected_at
      t.datetime :applied_at
      t.datetime :failed_at
      t.timestamps
    end
    add_index :reviewed_actions, [ :shop_id, :status ]
    add_index :reviewed_actions, [ :account_id, :created_at ]

    create_table :autopilot_policies do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.jsonb :allowed_action_kinds, null: false, default: []
      t.string :min_severity, null: false, default: "high"
      t.integer :cooldown_hours, null: false, default: 24
      t.integer :max_actions_per_day, null: false, default: 5
      t.boolean :require_in_stock, null: false, default: true
      t.decimal :margin_floor_pct, precision: 5, scale: 2
      t.datetime :kill_switch_at
      t.string :kill_switch_reason
      t.timestamps
    end
  end
end
