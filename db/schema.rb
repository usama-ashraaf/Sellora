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

ActiveRecord::Schema[8.1].define(version: 2026_09_07_030000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_accounts_on_name"
  end

  create_table "activity_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "shop_id"
    t.string "source", default: "internal", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "occurred_at"], name: "index_activity_events_on_account_id_and_occurred_at"
    t.index ["account_id"], name: "index_activity_events_on_account_id"
    t.index ["event_name", "occurred_at"], name: "index_activity_events_on_event_name_and_occurred_at"
    t.index ["shop_id", "event_name"], name: "index_activity_events_on_shop_id_and_event_name"
    t.index ["shop_id"], name: "index_activity_events_on_shop_id"
  end

  create_table "audit_findings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "audit_rule_id", null: false
    t.bigint "catalog_product_id"
    t.bigint "catalog_variant_id"
    t.datetime "created_at", null: false
    t.jsonb "evidence", default: {}, null: false
    t.string "message", null: false
    t.string "severity", null: false
    t.bigint "shop_id", null: false
    t.string "status", default: "open", null: false
    t.string "suggested_action"
    t.datetime "updated_at", null: false
    t.index "shop_id, audit_rule_id, COALESCE(catalog_product_id, (0)::bigint), COALESCE(catalog_variant_id, (0)::bigint)", name: "index_audit_findings_on_natural_key", unique: true
    t.index ["account_id", "shop_id", "status"], name: "index_audit_findings_on_account_id_and_shop_id_and_status"
    t.index ["account_id"], name: "index_audit_findings_on_account_id"
    t.index ["audit_rule_id"], name: "index_audit_findings_on_audit_rule_id"
    t.index ["catalog_product_id"], name: "index_audit_findings_on_catalog_product_id"
    t.index ["catalog_variant_id"], name: "index_audit_findings_on_catalog_variant_id"
    t.index ["shop_id", "audit_rule_id"], name: "index_audit_findings_on_shop_id_and_audit_rule_id"
    t.index ["shop_id"], name: "index_audit_findings_on_shop_id"
  end

  create_table "audit_rule_sets", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.string "domain", default: "clothing", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["domain", "active"], name: "index_audit_rule_sets_on_domain_and_active"
    t.index ["domain", "version"], name: "index_audit_rule_sets_on_domain_and_version", unique: true
  end

  create_table "audit_rules", force: :cascade do |t|
    t.bigint "audit_rule_set_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "rule_key", null: false
    t.string "severity", default: "medium", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["audit_rule_set_id", "rule_key"], name: "index_audit_rules_on_audit_rule_set_id_and_rule_key", unique: true
    t.index ["audit_rule_set_id"], name: "index_audit_rules_on_audit_rule_set_id"
  end

  create_table "autopilot_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "allowed_action_kinds", default: [], null: false
    t.integer "cooldown_hours", default: 24, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "kill_switch_at"
    t.string "kill_switch_reason"
    t.decimal "margin_floor_pct", precision: 5, scale: 2
    t.integer "max_actions_per_day", default: 5, null: false
    t.string "min_severity", default: "high", null: false
    t.boolean "require_in_stock", default: true, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_autopilot_policies_on_account_id"
    t.index ["shop_id"], name: "index_autopilot_policies_on_shop_id", unique: true
  end

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
    t.datetime "content_checked_at"
    t.string "content_fingerprint"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "freshness_checked_at"
    t.string "handle"
    t.jsonb "raw_attrs", default: {}, null: false
    t.string "rule_set_version"
    t.bigint "shop_id", null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "content_fingerprint"], name: "index_catalog_products_on_shop_and_fingerprint"
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

  create_table "commerce_order_lines", force: :cascade do |t|
    t.bigint "commerce_order_id", null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.decimal "price", precision: 12, scale: 2
    t.string "product_external_id"
    t.integer "quantity", default: 0, null: false
    t.jsonb "raw_attrs", default: {}, null: false
    t.string "sku"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "variant_external_id"
    t.index ["commerce_order_id", "external_id"], name: "index_commerce_order_lines_on_order_and_external", unique: true
    t.index ["commerce_order_id"], name: "index_commerce_order_lines_on_commerce_order_id"
  end

  create_table "commerce_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "cancel_reason"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "PKR", null: false
    t.string "external_id", null: false
    t.string "financial_status"
    t.string "fulfillment_status"
    t.string "name"
    t.datetime "processed_at"
    t.jsonb "raw_attrs", default: {}, null: false
    t.bigint "shop_id", null: false
    t.decimal "subtotal_price", precision: 12, scale: 2
    t.decimal "total_discounts", precision: 12, scale: 2
    t.decimal "total_price", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["account_id", "processed_at"], name: "index_commerce_orders_on_account_id_and_processed_at"
    t.index ["account_id"], name: "index_commerce_orders_on_account_id"
    t.index ["shop_id", "external_id"], name: "index_commerce_orders_on_shop_id_and_external_id", unique: true
    t.index ["shop_id"], name: "index_commerce_orders_on_shop_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["account_id", "email"], name: "index_memberships_on_account_id_and_email", unique: true
    t.index ["account_id", "role"], name: "index_memberships_on_account_id_and_role"
    t.index ["account_id"], name: "index_memberships_on_account_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
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

  create_table "recommendations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "audit_finding_id"
    t.bigint "catalog_product_id"
    t.datetime "created_at", null: false
    t.jsonb "evidence", default: {}, null: false
    t.string "kind", null: false
    t.string "priority", default: "medium", null: false
    t.text "rationale", null: false
    t.bigint "shop_id", null: false
    t.string "status", default: "open", null: false
    t.string "suggested_action"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "shop_id", "kind"], name: "index_recommendations_on_account_id_and_shop_id_and_kind"
    t.index ["account_id"], name: "index_recommendations_on_account_id"
    t.index ["audit_finding_id"], name: "index_recommendations_on_audit_finding_id"
    t.index ["catalog_product_id"], name: "index_recommendations_on_catalog_product_id"
    t.index ["shop_id", "status", "priority"], name: "index_recommendations_on_shop_id_and_status_and_priority"
    t.index ["shop_id"], name: "index_recommendations_on_shop_id"
  end

  create_table "reviewed_actions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "action_kind", null: false
    t.string "actor_email"
    t.jsonb "after_snapshot", default: {}, null: false
    t.datetime "applied_at"
    t.datetime "approved_at"
    t.bigint "audit_finding_id"
    t.jsonb "before_snapshot", default: {}, null: false
    t.string "conflict_reason"
    t.datetime "created_at", null: false
    t.datetime "failed_at"
    t.bigint "recommendation_id"
    t.datetime "rejected_at"
    t.text "result_message"
    t.bigint "shop_id", null: false
    t.string "source_fingerprint"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_reviewed_actions_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_reviewed_actions_on_account_id"
    t.index ["audit_finding_id"], name: "index_reviewed_actions_on_audit_finding_id"
    t.index ["recommendation_id"], name: "index_reviewed_actions_on_recommendation_id"
    t.index ["shop_id", "status"], name: "index_reviewed_actions_on_shop_id_and_status"
    t.index ["shop_id"], name: "index_reviewed_actions_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.text "access_token"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "last_audited_at"
    t.datetime "last_discovered_at"
    t.datetime "last_recommendation_at"
    t.string "scope"
    t.string "shopify_domain", null: false
    t.datetime "uninstalled_at"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_shops_on_account_id"
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
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

  add_foreign_key "activity_events", "accounts"
  add_foreign_key "activity_events", "shops"
  add_foreign_key "audit_findings", "accounts"
  add_foreign_key "audit_findings", "audit_rules"
  add_foreign_key "audit_findings", "catalog_products"
  add_foreign_key "audit_findings", "catalog_variants"
  add_foreign_key "audit_findings", "shops"
  add_foreign_key "audit_rules", "audit_rule_sets"
  add_foreign_key "autopilot_policies", "accounts"
  add_foreign_key "autopilot_policies", "shops"
  add_foreign_key "catalog_inventory_levels", "catalog_variants"
  add_foreign_key "catalog_products", "shops"
  add_foreign_key "catalog_variants", "catalog_products"
  add_foreign_key "commerce_order_lines", "commerce_orders"
  add_foreign_key "commerce_orders", "accounts"
  add_foreign_key "commerce_orders", "shops"
  add_foreign_key "memberships", "accounts"
  add_foreign_key "memberships", "users"
  add_foreign_key "recommendations", "accounts"
  add_foreign_key "recommendations", "audit_findings"
  add_foreign_key "recommendations", "catalog_products"
  add_foreign_key "recommendations", "shops"
  add_foreign_key "reviewed_actions", "accounts"
  add_foreign_key "reviewed_actions", "audit_findings"
  add_foreign_key "reviewed_actions", "recommendations"
  add_foreign_key "reviewed_actions", "shops"
  add_foreign_key "shops", "accounts"
end
