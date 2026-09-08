# frozen_string_literal: true

class CreatePromotionPlanner < ActiveRecord::Migration[8.1]
  def change
    create_table :promotion_policies do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true, index: { unique: true }
      t.decimal :target_roas, precision: 6, scale: 2, null: false, default: 3
      t.decimal :target_acquisition_cost, precision: 12, scale: 2
      t.decimal :shipping_cost_per_order, precision: 12, scale: 2, null: false, default: 0
      t.decimal :cod_failure_cost, precision: 12, scale: 2, null: false, default: 0
      t.decimal :expected_cod_failure_rate_percent, precision: 5, scale: 2, null: false, default: 15
      t.integer :desired_runway_days, null: false, default: 14
      t.integer :minimum_margin_percent, null: false, default: 20
      t.integer :minimum_safe_orders, null: false, default: 5
      t.timestamps
    end

    create_table :promotion_decisions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.references :catalog_product, null: false, foreign_key: true
      t.string :status, null: false
      t.integer :score, null: false
      t.string :confidence, null: false
      t.jsonb :metrics, null: false, default: {}
      t.jsonb :reasons, null: false, default: []
      t.datetime :generated_at, null: false
      t.timestamps
    end
    add_index :promotion_decisions, [ :shop_id, :catalog_product_id ], unique: true
    add_index :promotion_decisions, [ :account_id, :status, :score ]
  end
end
