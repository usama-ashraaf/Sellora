# frozen_string_literal: true

class CreateCatalogTables < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_products do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :title, null: false
      t.string :handle
      t.string :status, null: false, default: "active"
      t.jsonb :raw_attrs, default: {}, null: false

      t.timestamps
    end
    add_index :catalog_products, [ :shop_id, :external_id ], unique: true
    add_index :catalog_products, [ :shop_id, :handle ]

    create_table :catalog_variants do |t|
      t.references :catalog_product, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :sku
      t.string :title
      t.string :barcode
      t.string :option_summary
      t.string :inventory_item_external_id

      t.timestamps
    end
    add_index :catalog_variants, [ :catalog_product_id, :external_id ], unique: true, name: "index_catalog_variants_on_product_and_external_id"
    add_index :catalog_variants, :sku

    create_table :catalog_inventory_levels do |t|
      t.references :catalog_variant, null: false, foreign_key: true
      t.string :location_external_id, null: false
      t.integer :available, null: false, default: 0

      t.timestamps
    end
    add_index :catalog_inventory_levels,
              [ :catalog_variant_id, :location_external_id ],
              unique: true,
              name: "index_catalog_inventory_on_variant_and_location"
  end
end
