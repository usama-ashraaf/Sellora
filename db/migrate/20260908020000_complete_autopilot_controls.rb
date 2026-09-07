# frozen_string_literal: true

class CompleteAutopilotControls < ActiveRecord::Migration[8.1]
  def change
    change_table :autopilot_policies, bulk: true do |t|
      t.integer :minimum_evidence_count, null: false, default: 1
      t.integer :minimum_inventory_units, null: false, default: 20
      t.integer :minimum_size_coverage_percent, null: false, default: 70
      t.integer :max_discount_percentage, null: false, default: 20
      t.decimal :max_estimated_discount_cost_per_day, precision: 12, scale: 2, null: false, default: 10_000
    end

    create_table :autopilot_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.references :autopilot_policy, null: false, foreign_key: true
      t.string :status, null: false
      t.integer :candidates_count, null: false, default: 0
      t.integer :applied_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.jsonb :details, null: false, default: {}
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :autopilot_runs, [ :shop_id, :created_at ]
  end
end
