# frozen_string_literal: true

class CreateCommerceOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :commerce_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :name
      t.string :currency, null: false, default: "PKR"
      t.string :financial_status
      t.string :fulfillment_status
      t.string :cancel_reason
      t.datetime :cancelled_at
      t.datetime :processed_at
      t.decimal :total_price, precision: 12, scale: 2
      t.decimal :subtotal_price, precision: 12, scale: 2
      t.decimal :total_discounts, precision: 12, scale: 2
      t.jsonb :raw_attrs, null: false, default: {}
      t.timestamps
    end
    add_index :commerce_orders, [ :shop_id, :external_id ], unique: true
    add_index :commerce_orders, [ :account_id, :processed_at ]

    create_table :commerce_order_lines do |t|
      t.references :commerce_order, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :product_external_id
      t.string :variant_external_id
      t.string :sku
      t.string :title
      t.integer :quantity, null: false, default: 0
      t.decimal :price, precision: 12, scale: 2
      t.jsonb :raw_attrs, null: false, default: {}
      t.timestamps
    end
    add_index :commerce_order_lines, [ :commerce_order_id, :external_id ], unique: true, name: "index_commerce_order_lines_on_order_and_external"
  end
end
