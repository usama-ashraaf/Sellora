# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_06_160000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "catalog_inventory_levels", force: :cascade do |t|
    t.integer "available", default: 0, null: false
    t.bigint "catalog_variant_id", null: false
    t.datetime "created_at", null: false
    t.string "location_external_id", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_variant_id", "location_external_id"], name: "index_catalog_inventory_on_variant_and_location", unique: true
    t.index ["catalog_variant_id"], name: "index_catalog_inventory_levels_on_catalog_variant_id"
  end

  create_table "catalog_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "handle"
    t.jsonb "raw_attrs", default: {}, null: false
    t.bigint "shop_id", null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "external_id"], name: "index_catalog_products_on_shop_id_and_external_id", unique: true
    t.index ["shop_id", "handle"], name: "index_catalog_products_on_shop_id_and_handle"
    t.index ["shop_id"], name: "index_catalog_products_on_shop_id"
  end

  create_table "catalog_variants", force: :cascade do |t|
    t.string "barcode"
    t.bigint "catalog_product_id", null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "inventory_item_external_id"
    t.string "option_summary"
    t.string "sku"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["catalog_product_id", "external_id"], name: "index_catalog_variants_on_product_and_external_id", unique: true
    t.index ["catalog_product_id"], name: "index_catalog_variants_on_catalog_product_id"
    t.index ["sku"], name: "index_catalog_variants_on_sku"
  end

  create_table "pilot_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", limit: 254, null: false
    t.string "name", limit: 100, null: false
    t.string "platform", limit: 40, null: false
    t.string "store_url", limit: 2048, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_pilot_requests_on_created_at"
    t.index ["email"], name: "index_pilot_requests_on_email"
  end

  create_table "shops", force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.string "scope"
    t.string "shopify_domain", null: false
    t.datetime "uninstalled_at"
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_key", null: false
    t.datetime "processed_at", null: false
    t.string "shopify_domain", null: false
    t.string "topic", null: false
    t.datetime "updated_at", null: false
    t.index ["event_key"], name: "index_webhook_events_on_event_key", unique: true
    t.index ["shopify_domain", "topic"], name: "index_webhook_events_on_shopify_domain_and_topic"
  end

  add_foreign_key "catalog_inventory_levels", "catalog_variants"
  add_foreign_key "catalog_products", "shops"
  add_foreign_key "catalog_variants", "catalog_products"
end
