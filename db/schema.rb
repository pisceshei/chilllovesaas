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

ActiveRecord::Schema[8.1].define(version: 2026_08_24_110000) do
  create_table "api_tokens", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "外部整合的雜湊 access token", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.json "scopes", default: -> { "(json_array())" }, null: false
    t.bigint "shop_id", null: false
    t.bigint "staff_member_id"
    t.string "token_digest", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_api_tokens_tenant_id", unique: true
    t.index ["shop_id", "revoked_at", "expires_at"], name: "ix_api_tokens_revoked_at_expires_at"
    t.index ["shop_id", "staff_member_id"], name: "ix_api_tokens_staff_member_id"
    t.index ["shop_id", "token_digest"], name: "uq_api_tokens_token_digest", unique: true
    t.index ["staff_member_id"], name: "fk_api_tokens_staff_member_id"
  end

  create_table "checkouts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "結帳快照及棄單來源", force: :cascade do |t|
    t.datetime "abandoned_at"
    t.json "billing_address", default: -> { "(json_object())" }, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "customer_id"
    t.bigint "discount_cents", default: 0, null: false
    t.string "email", limit: 320
    t.datetime "expires_at"
    t.json "line_items_snapshot", default: -> { "(json_array())" }, null: false
    t.string "presentment_currency", limit: 3, default: "HKD", null: false
    t.bigint "presentment_total_cents", default: 0, null: false
    t.string "recovery_token", limit: 64
    t.json "shipping_address", default: -> { "(json_object())" }, null: false
    t.bigint "shipping_cents", default: 0, null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "active", null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.string "token", limit: 64, null: false
    t.bigint "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "customer_id"], name: "ix_checkouts_customer_id"
    t.index ["shop_id", "id"], name: "uq_checkouts_tenant_id", unique: true
    t.index ["shop_id", "recovery_token"], name: "uq_checkouts_recovery_token", unique: true
    t.index ["shop_id", "status", "created_at"], name: "ix_checkouts_status_created_at"
    t.index ["shop_id", "status", "expires_at"], name: "ix_checkouts_status_expires_at"
    t.index ["shop_id", "token"], name: "uq_checkouts_token", unique: true
  end

  create_table "collection_products", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "手動系列與商品的租戶安全 join", force: :cascade do |t|
    t.bigint "collection_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "collection_id", "position"], name: "ix_collection_products_collection_id_position"
    t.index ["shop_id", "collection_id", "product_id"], name: "uq_collection_products_collection_id_product_id", unique: true
    t.index ["shop_id", "collection_id"], name: "ix_collection_products_collection_id"
    t.index ["shop_id", "id"], name: "uq_collection_products_tenant_id", unique: true
    t.index ["shop_id", "product_id"], name: "ix_collection_products_product_id"
  end

  create_table "collection_rules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "智慧系列白名單條件", force: :cascade do |t|
    t.bigint "collection_id", null: false
    t.string "column_name", limit: 64, null: false
    t.string "condition_value", limit: 1024, null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.string "relation", limit: 32, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "collection_id", "position"], name: "uq_collection_rules_collection_id_position", unique: true
    t.index ["shop_id", "collection_id"], name: "ix_collection_rules_collection_id"
    t.index ["shop_id", "id"], name: "uq_collection_rules_tenant_id", unique: true
  end

  create_table "collections", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "手動或智慧系列", force: :cascade do |t|
    t.string "collection_type", limit: 32, default: "manual", null: false
    t.datetime "created_at", null: false
    t.text "description_html", size: :medium, null: false
    t.string "handle", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "rules_match", limit: 16, default: "all", null: false
    t.string "seo_description", limit: 320
    t.string "seo_title", limit: 70
    t.bigint "shop_id", null: false
    t.string "sort_order", limit: 32, default: "manual", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "collection_type"], name: "ix_collections_collection_type"
    t.index ["shop_id", "handle"], name: "uq_collections_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_collections_tenant_id", unique: true
  end

  create_table "contract_liability_entries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "合約負債分錄（HK 首發即使用，56 §B.3.1 J-01）", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.string "basis", limit: 128, null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.string "direction", limit: 16, null: false
    t.datetime "recognised_at", null: false
    t.bigint "shop_id", null: false
    t.bigint "source_id", null: false
    t.string "source_type", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_contract_liability_entries_tenant_id", unique: true
    t.index ["shop_id", "source_type", "source_id", "direction"], name: "uq_contract_liability_entries_source_type_source_id_direction", unique: true
  end

  create_table "customer_addresses", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "顧客可重用地址", force: :cascade do |t|
    t.string "address1", null: false
    t.string "address2"
    t.string "city", null: false
    t.string "company"
    t.string "country_code", limit: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.boolean "default_address", default: false, null: false
    t.string "first_name"
    t.string "last_name"
    t.string "phone", limit: 32
    t.string "postal_code", limit: 32
    t.string "province"
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "customer_id", "default_address"], name: "ix_customer_addresses_customer_id_default_address"
    t.index ["shop_id", "customer_id"], name: "ix_customer_addresses_customer_id"
    t.index ["shop_id", "id"], name: "uq_customer_addresses_tenant_id", unique: true
  end

  create_table "customers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "顧客主檔與隱私狀態", force: :cascade do |t|
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.string "email", limit: 320
    t.boolean "email_marketing_consent", default: false, null: false
    t.string "first_name"
    t.string "last_name"
    t.text "note"
    t.integer "orders_count", default: 0, null: false
    t.string "phone", limit: 32
    t.bigint "shop_id", null: false
    t.boolean "sms_marketing_consent", default: false, null: false
    t.string "state", limit: 32, default: "enabled", null: false
    t.json "tags", default: -> { "(json_array())" }, null: false
    t.boolean "tax_exempt", default: false, null: false
    t.bigint "total_spent_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "email"], name: "uq_customers_email", unique: true
    t.index ["shop_id", "id"], name: "uq_customers_tenant_id", unique: true
    t.index ["shop_id", "phone"], name: "ix_customers_phone"
    t.index ["shop_id", "state", "created_at"], name: "ix_customers_state_created_at"
  end

  create_table "discount_applications", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "下單當下的折扣分攤快照", force: :cascade do |t|
    t.string "allocation_method", limit: 32, default: "across", null: false
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "discount_id", null: false
    t.bigint "line_item_id"
    t.virtual "line_item_scope_id", type: :bigint, as: "coalesce(`line_item_id`,0)", stored: true
    t.bigint "order_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "discount_id"], name: "ix_discount_applications_discount_id"
    t.index ["shop_id", "id"], name: "uq_discount_applications_tenant_id", unique: true
    t.index ["shop_id", "line_item_id"], name: "ix_discount_applications_line_item_id"
    t.index ["shop_id", "order_id", "discount_id", "line_item_scope_id"], name: "uq_discount_apps_order_discount_line_scope", unique: true
    t.index ["shop_id", "order_id"], name: "ix_discount_applications_order_id"
  end

  create_table "discounts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "碼或自動折扣規則", force: :cascade do |t|
    t.string "code"
    t.boolean "combines_order", default: false, null: false
    t.boolean "combines_product", default: false, null: false
    t.boolean "combines_shipping", default: false, null: false
    t.json "conditions", default: -> { "(json_object())" }, null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.string "discount_class", limit: 32, default: "product", null: false
    t.datetime "ends_at"
    t.integer "lock_version", default: 0, null: false
    t.string "method", limit: 32, default: "code", null: false
    t.boolean "once_per_customer", default: false, null: false
    t.integer "percentage_basis_points"
    t.bigint "shop_id", null: false
    t.datetime "starts_at"
    t.string "status", limit: 32, default: "draft", null: false
    t.integer "times_used", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_limit"
    t.bigint "value_cents"
    t.string "value_type", limit: 32, default: "percentage", null: false
    t.index ["shop_id", "code"], name: "uq_discounts_code", unique: true
    t.index ["shop_id", "id"], name: "uq_discounts_tenant_id", unique: true
    t.index ["shop_id", "method", "status"], name: "ix_discounts_method_status"
    t.index ["shop_id", "status", "ends_at"], name: "ix_discounts_status_ends_at"
    t.index ["shop_id", "status", "starts_at"], name: "ix_discounts_status_starts_at"
  end

  create_table "einvoice_allowances", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "發票折讓（HK 恆空；tw pack 用）", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "einvoice_id", null: false
    t.string "reason"
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "einvoice_id"], name: "ix_einvoice_allowances_einvoice_id"
    t.index ["shop_id", "id"], name: "uq_einvoice_allowances_tenant_id", unique: true
  end

  create_table "einvoices", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "政府稅務憑證（HK 恆空；tw pack 用）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.string "document_number", limit: 64
    t.datetime "issued_at"
    t.string "jurisdiction", limit: 8, null: false
    t.bigint "order_id", null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "pending", null: false
    t.bigint "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.datetime "voided_at"
    t.index ["shop_id", "id"], name: "uq_einvoices_tenant_id", unique: true
    t.index ["shop_id", "jurisdiction", "status"], name: "ix_einvoices_jurisdiction_status"
    t.index ["shop_id", "order_id"], name: "ix_einvoices_order_id"
  end

  create_table "event_outbox", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "與業務寫入同 transaction 的 at-least-once outbox", force: :cascade do |t|
    t.bigint "aggregate_id", null: false
    t.string "aggregate_type", limit: 64, null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "available_at", null: false
    t.datetime "created_at", null: false
    t.string "event_id", limit: 36, null: false
    t.text "last_error"
    t.datetime "locked_at"
    t.json "payload", null: false
    t.datetime "published_at"
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "pending", null: false
    t.string "topic", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "aggregate_type", "aggregate_id"], name: "ix_event_outbox_aggregate_type_aggregate_id"
    t.index ["shop_id", "event_id"], name: "uq_event_outbox_event_id", unique: true
    t.index ["shop_id", "id"], name: "uq_event_outbox_tenant_id", unique: true
    t.index ["shop_id", "status", "available_at"], name: "ix_event_outbox_status_available_at"
  end

  create_table "events", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "訂單 timeline；業務上 append-only", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "editable_until"
    t.datetime "happened_at", null: false
    t.string "kind", limit: 64, null: false
    t.text "message"
    t.json "metadata", default: -> { "(json_object())" }, null: false
    t.bigint "order_id"
    t.bigint "shop_id", null: false
    t.bigint "staff_member_id"
    t.bigint "subject_id"
    t.string "subject_type", limit: 64
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_events_tenant_id", unique: true
    t.index ["shop_id", "order_id", "happened_at"], name: "ix_events_order_id_happened_at"
    t.index ["shop_id", "order_id"], name: "ix_events_order_id"
    t.index ["shop_id", "staff_member_id"], name: "ix_events_staff_member_id"
    t.index ["shop_id", "subject_type", "subject_id"], name: "ix_events_subject_type_subject_id"
    t.index ["staff_member_id"], name: "fk_events_staff_member_id"
  end

  create_table "files", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "上傳檔案 metadata", force: :cascade do |t|
    t.string "alt_text", limit: 512
    t.bigint "byte_size", null: false
    t.string "checksum", limit: 64, null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.integer "height"
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "uploaded", null: false
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["shop_id", "id"], name: "uq_files_tenant_id", unique: true
    t.index ["shop_id", "status", "created_at"], name: "ix_files_status_created_at"
    t.index ["shop_id", "storage_key"], name: "uq_files_storage_key", unique: true
  end

  create_table "fulfillment_orders", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "按地點拆分的履約工作單", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "fulfill_at"
    t.string "hold_reason", limit: 64
    t.bigint "location_id", null: false
    t.bigint "order_id", null: false
    t.string "request_status", limit: 32, default: "unsubmitted", null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_fulfillment_orders_tenant_id", unique: true
    t.index ["shop_id", "location_id"], name: "ix_fulfillment_orders_location_id"
    t.index ["shop_id", "order_id", "status"], name: "ix_fulfillment_orders_order_id_status"
    t.index ["shop_id", "order_id"], name: "ix_fulfillment_orders_order_id"
    t.index ["shop_id", "status", "fulfill_at"], name: "ix_fulfillment_orders_status_fulfill_at"
  end

  create_table "fulfillments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "實際包裹與追蹤資料", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "customer_notified", default: true, null: false
    t.datetime "delivered_at"
    t.bigint "fulfillment_order_id", null: false
    t.datetime "shipped_at"
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "pending", null: false
    t.string "tracking_company"
    t.json "tracking_numbers", default: -> { "(json_array())" }, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "fulfillment_order_id"], name: "ix_fulfillments_fulfillment_order_id"
    t.index ["shop_id", "id"], name: "uq_fulfillments_tenant_id", unique: true
    t.index ["shop_id", "status", "created_at"], name: "ix_fulfillments_status_created_at"
  end

  create_table "idempotency_keys", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "寫路徑冪等結果快取", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "key", null: false
    t.string "mutation_name", null: false
    t.string "params_fingerprint", limit: 64, null: false
    t.bigint "resource_id"
    t.string "resource_type", limit: 64
    t.bigint "shop_id", null: false
    t.string "state", limit: 32, default: "processing", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_idempotency_keys_tenant_id", unique: true
    t.index ["shop_id", "key"], name: "uq_idempotency_keys_key", unique: true
    t.index ["shop_id", "resource_type", "resource_id"], name: "ix_idempotency_keys_resource_type_resource_id"
    t.index ["shop_id", "state", "expires_at"], name: "ix_idempotency_keys_state_expires_at"
  end

  create_table "inventory_adjustment_groups", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "一次庫存異動呼叫的批次頭（＝本尊 InventoryAdjustmentGroup）", force: :cascade do |t|
    t.integer "changes_count", default: 0, null: false
    t.string "client_source", limit: 32
    t.datetime "created_at", null: false
    t.string "idempotency_key", null: false
    t.string "mutation_kind", limit: 16, null: false
    t.string "quantity_name", limit: 32, null: false
    t.string "reason", limit: 64, null: false
    t.string "reference_document_uri"
    t.bigint "reference_id"
    t.string "reference_type", limit: 64
    t.bigint "shop_id", null: false
    t.bigint "staff_member_id"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "created_at"], name: "ix_inventory_adjustment_groups_created_at"
    t.index ["shop_id", "id"], name: "uq_inventory_adjustment_groups_tenant_id", unique: true
    t.index ["shop_id", "idempotency_key"], name: "uq_inventory_adjustment_groups_idem_key", unique: true
    t.index ["shop_id", "reference_type", "reference_id"], name: "ix_inventory_adjustment_groups_reference"
    t.index ["shop_id", "staff_member_id"], name: "ix_inventory_adjustment_groups_staff"
  end

  create_table "inventory_adjustments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "append-only 庫存 ledger", force: :cascade do |t|
    t.integer "available_delta", default: 0, null: false
    t.integer "committed_delta", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "damaged_delta", default: 0, null: false
    t.integer "incoming_delta", default: 0, null: false
    t.bigint "inventory_adjustment_group_id", null: false
    t.bigint "inventory_level_id", null: false
    t.string "ledger_document_uri"
    t.text "note"
    t.virtual "on_hand_delta", type: :integer, null: false, as: "(((((`available_delta` + `committed_delta`) + `reserved_delta`) + `damaged_delta`) + `safety_stock_delta`) + `quality_control_delta`)", stored: true
    t.integer "position", default: 0, null: false
    t.integer "quality_control_delta", default: 0, null: false
    t.integer "reserved_delta", default: 0, null: false
    t.integer "safety_stock_delta", default: 0, null: false
    t.bigint "shop_id", null: false
    t.virtual "unavailable_delta", type: :integer, null: false, as: "(((`reserved_delta` + `damaged_delta`) + `safety_stock_delta`) + `quality_control_delta`)", stored: true
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_inventory_adjustments_tenant_id", unique: true
    t.index ["shop_id", "inventory_adjustment_group_id", "inventory_level_id"], name: "uq_inv_adjustments_group_level", unique: true
    t.index ["shop_id", "inventory_level_id", "created_at"], name: "ix_inventory_adjustments_inventory_level_id_created_at"
    t.index ["shop_id", "inventory_level_id"], name: "ix_inventory_adjustments_inventory_level_id"
  end

  create_table "inventory_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "變體對應的一對一庫存品項", force: :cascade do |t|
    t.string "country_code_of_origin", limit: 2
    t.datetime "created_at", null: false
    t.string "harmonized_system_code", limit: 16
    t.bigint "product_variant_id", null: false
    t.boolean "requires_shipping", default: true, null: false
    t.bigint "shop_id", null: false
    t.string "sku"
    t.boolean "tracked", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_inventory_items_tenant_id", unique: true
    t.index ["shop_id", "product_variant_id"], name: "uq_inventory_items_product_variant_id", unique: true
    t.index ["shop_id", "sku"], name: "ix_inventory_items_sku"
  end

  create_table "inventory_levels", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "每庫存品項、每地點的五狀態數量", force: :cascade do |t|
    t.integer "available", default: 0, null: false
    t.integer "committed", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "damaged", default: 0, null: false
    t.integer "incoming", default: 0, null: false
    t.bigint "inventory_item_id", null: false
    t.bigint "location_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.virtual "on_hand", type: :integer, null: false, as: "(((((`available` + `committed`) + `reserved`) + `damaged`) + `safety_stock`) + `quality_control`)", stored: true
    t.integer "quality_control", default: 0, null: false
    t.integer "reserved", default: 0, null: false
    t.integer "safety_stock", default: 0, null: false
    t.bigint "shop_id", null: false
    t.virtual "unavailable", type: :integer, null: false, as: "(((`reserved` + `damaged`) + `safety_stock`) + `quality_control`)", stored: true
    t.datetime "updated_at", null: false
    t.index ["shop_id", "available"], name: "ix_inventory_levels_available"
    t.index ["shop_id", "id"], name: "uq_inventory_levels_tenant_id", unique: true
    t.index ["shop_id", "inventory_item_id", "location_id"], name: "uq_inventory_levels_inventory_item_id_location_id", unique: true
    t.index ["shop_id", "inventory_item_id"], name: "ix_inventory_levels_inventory_item_id"
    t.index ["shop_id", "location_id"], name: "ix_inventory_levels_location_id"
    t.index ["shop_id", "on_hand"], name: "ix_inventory_levels_on_hand"
  end

  create_table "jurisdiction_capability_skips", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "法域能力 documented_no_op 記錄（HK 首發即大量寫入）", force: :cascade do |t|
    t.string "capability", limit: 64, null: false
    t.datetime "created_at", null: false
    t.string "event_kind", limit: 64, null: false
    t.string "jurisdiction", limit: 8, null: false
    t.datetime "occurred_at", null: false
    t.string "reason", null: false
    t.bigint "shop_id", null: false
    t.string "source_write_point", limit: 128, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "event_kind", "occurred_at"], name: "ix_jurisdiction_capability_skips_event_kind_occurred_at"
    t.index ["shop_id", "id"], name: "uq_jurisdiction_capability_skips_tenant_id", unique: true
    t.index ["shop_id", "jurisdiction", "capability"], name: "ix_jurisdiction_capability_skips_jurisdiction_capability"
  end

  create_table "line_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "下單當下不可回溯改寫的商品與金額快照", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.boolean "custom", default: false, null: false
    t.integer "fulfillable_quantity", default: 0, null: false
    t.bigint "order_id", null: false
    t.string "product_type", comment: "售出時的產品類型（快照，不隨商品編輯而變）"
    t.bigint "product_variant_id"
    t.json "properties", default: -> { "(json_object())" }, null: false
    t.integer "quantity", null: false
    t.boolean "requires_shipping", default: true, null: false
    t.bigint "shop_id", null: false
    t.string "sku"
    t.bigint "tax_cents", default: 0, null: false
    t.boolean "taxable", default: true, null: false
    t.string "title", null: false
    t.bigint "total_cents", null: false
    t.bigint "total_discount_cents", default: 0, null: false
    t.bigint "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.string "variant_title"
    t.string "vendor", comment: "售出時的產品廠商（快照，不隨商品編輯而變）"
    t.index ["shop_id", "id"], name: "uq_line_items_tenant_id", unique: true
    t.index ["shop_id", "order_id", "id"], name: "ix_line_items_order_id_id"
    t.index ["shop_id", "order_id"], name: "ix_line_items_order_id"
    t.index ["shop_id", "product_variant_id"], name: "ix_line_items_product_variant_id"
  end

  create_table "locations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "庫存與出貨地點", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.json "address", default: -> { "(json_object())" }, null: false
    t.datetime "created_at", null: false
    t.boolean "fulfills_online_orders", default: true, null: false
    t.string "name", null: false
    t.integer "priority", default: 0, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "active", "priority"], name: "ix_locations_active_priority"
    t.index ["shop_id", "id"], name: "uq_locations_tenant_id", unique: true
    t.index ["shop_id", "name"], name: "uq_locations_name", unique: true
  end

  create_table "media", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "商品媒體 metadata；檔案本體走 object storage", force: :cascade do |t|
    t.string "alt_text", limit: 512
    t.bigint "byte_size"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.integer "height"
    t.string "media_type", limit: 32, default: "image", null: false
    t.integer "position", null: false
    t.bigint "product_id", null: false
    t.bigint "product_variant_id"
    t.bigint "shop_id", null: false
    t.string "source_url", limit: 2048, null: false
    t.string "status", limit: 32, default: "ready", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["shop_id", "id"], name: "uq_media_tenant_id", unique: true
    t.index ["shop_id", "product_id", "position"], name: "uq_media_product_id_position", unique: true
    t.index ["shop_id", "product_id"], name: "ix_media_product_id"
    t.index ["shop_id", "product_variant_id"], name: "ix_media_product_variant_id"
  end

  create_table "menu_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "可巢狀導覽項目", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "item_type", limit: 32, default: "http", null: false
    t.bigint "menu_id", null: false
    t.bigint "parent_menu_item_id"
    t.integer "position", null: false
    t.bigint "resource_id"
    t.string "resource_type", limit: 64
    t.bigint "shop_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", limit: 2048
    t.index ["shop_id", "id"], name: "uq_menu_items_tenant_id", unique: true
    t.index ["shop_id", "menu_id", "position"], name: "ix_menu_items_menu_id_position"
    t.index ["shop_id", "menu_id"], name: "ix_menu_items_menu_id"
    t.index ["shop_id", "parent_menu_item_id", "position"], name: "ix_menu_items_parent_menu_item_id_position"
    t.index ["shop_id", "parent_menu_item_id"], name: "ix_menu_items_parent_menu_item_id"
    t.index ["shop_id", "resource_type", "resource_id"], name: "ix_menu_items_resource_type_resource_id"
  end

  create_table "menus", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "前台 navigation menu", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "handle", null: false
    t.bigint "shop_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "handle"], name: "uq_menus_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_menus_tenant_id", unique: true
  end

  create_table "metafield_definitions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "metafield namespace/key 型別與驗證", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", limit: 64, null: false
    t.string "name", null: false
    t.string "namespace", limit: 64, null: false
    t.string "owner_type", limit: 64, null: false
    t.boolean "pinned", default: false, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.json "validations", default: -> { "(json_array())" }, null: false
    t.string "value_type", limit: 64, null: false
    t.index ["shop_id", "id"], name: "uq_metafield_definitions_tenant_id", unique: true
    t.index ["shop_id", "owner_type", "namespace", "key"], name: "uq_metafield_definitions_owner_type_namespace_key", unique: true
    t.index ["shop_id", "owner_type", "pinned"], name: "ix_metafield_definitions_owner_type_pinned"
  end

  create_table "metafields", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "租戶資源上的 typed custom value", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "metafield_definition_id", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", limit: 64, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.json "value", null: false
    t.index ["shop_id", "id"], name: "uq_metafields_tenant_id", unique: true
    t.index ["shop_id", "metafield_definition_id"], name: "ix_metafields_metafield_definition_id"
    t.index ["shop_id", "owner_type", "owner_id", "metafield_definition_id"], name: "uq_metafields_owner_type_owner_id_metafield_definition_id", unique: true
  end

  create_table "notification_templates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "交易通知模板", force: :cascade do |t|
    t.text "body", size: :long, null: false
    t.string "channel", limit: 32, default: "email", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "key", limit: 100, null: false
    t.string "name", null: false
    t.bigint "shop_id", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "channel", "key"], name: "uq_notification_templates_channel_key", unique: true
    t.index ["shop_id", "enabled", "channel"], name: "ix_notification_templates_enabled_channel"
    t.index ["shop_id", "id"], name: "uq_notification_templates_tenant_id", unique: true
  end

  create_table "option_values", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "商品選項值", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.bigint "product_option_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.index ["shop_id", "id"], name: "uq_option_values_tenant_id", unique: true
    t.index ["shop_id", "product_option_id", "id"], name: "uq_option_values_option_scoped_id", unique: true
    t.index ["shop_id", "product_option_id", "position"], name: "uq_option_values_product_option_id_position", unique: true
    t.index ["shop_id", "product_option_id", "value"], name: "uq_option_values_product_option_id_value", unique: true
    t.index ["shop_id", "product_option_id"], name: "ix_option_values_product_option_id"
  end

  create_table "order_transactions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "authorization/capture/refund 的不可變交易鏈", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.string "error_code", limit: 64
    t.string "gateway", limit: 64, null: false
    t.string "idempotency_key", null: false
    t.string "kind", limit: 32, null: false
    t.bigint "order_id", null: false
    t.bigint "parent_transaction_id"
    t.datetime "processed_at"
    t.string "provider_reference"
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_order_transactions_tenant_id", unique: true
    t.index ["shop_id", "idempotency_key"], name: "uq_order_transactions_idempotency_key", unique: true
    t.index ["shop_id", "order_id", "kind"], name: "ix_order_transactions_order_id_kind"
    t.index ["shop_id", "order_id", "status"], name: "ix_order_transactions_order_id_status"
    t.index ["shop_id", "order_id"], name: "ix_order_transactions_order_id"
    t.index ["shop_id", "parent_transaction_id"], name: "ix_order_transactions_parent_transaction_id"
    t.index ["shop_id", "provider_reference"], name: "uq_order_transactions_provider_reference", unique: true
  end

  create_table "orders", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "訂單金額快照與彼此獨立的狀態機", force: :cascade do |t|
    t.datetime "archived_at"
    t.json "billing_address", default: -> { "(json_object())" }, null: false
    t.string "buyer_jurisdiction", limit: 8, null: false
    t.datetime "canceled_at"
    t.bigint "checkout_id"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "customer_id"
    t.bigint "discount_cents", default: 0, null: false
    t.string "email", limit: 320
    t.string "financial_status", limit: 32, default: "pending", null: false
    t.string "fulfillment_status", limit: 32, default: "unfulfilled", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", limit: 64, null: false
    t.text "note"
    t.bigint "order_number", null: false
    t.string "presentment_currency", limit: 3, default: "HKD", null: false
    t.bigint "presentment_total_cents", default: 0, null: false
    t.datetime "processed_at"
    t.string "seller_jurisdiction", limit: 8, null: false
    t.json "shipping_address", default: -> { "(json_object())" }, null: false
    t.bigint "shipping_cents", default: 0, null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "open", null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.json "tags", default: -> { "(json_array())" }, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "checkout_id"], name: "uq_orders_checkout_id", unique: true
    t.index ["shop_id", "customer_id"], name: "ix_orders_customer_id"
    t.index ["shop_id", "financial_status", "created_at"], name: "ix_orders_financial_status_created_at"
    t.index ["shop_id", "fulfillment_status", "created_at"], name: "ix_orders_fulfillment_status_created_at"
    t.index ["shop_id", "id"], name: "uq_orders_tenant_id", unique: true
    t.index ["shop_id", "order_number"], name: "uq_orders_order_number", unique: true
    t.index ["shop_id", "status", "created_at"], name: "ix_orders_status_created_at"
  end

  create_table "pages", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "前台自訂頁面", force: :cascade do |t|
    t.text "body_html", size: :long, null: false
    t.datetime "created_at", null: false
    t.string "handle", null: false
    t.datetime "published_at"
    t.string "seo_description", limit: 320
    t.string "seo_title", limit: 70
    t.bigint "shop_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "handle"], name: "uq_pages_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_pages_tenant_id", unique: true
    t.index ["shop_id", "published_at", "id"], name: "ix_pages_published_at_id"
  end

  create_table "platform_locales", primary_key: "tag", id: { type: :string, limit: 35, comment: "BCP-47，寫入層正規化：zh-Hant / zh-Hans / en / ja / fr" }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "平台語言字典（跨租戶共用；非租戶資料，無 shop_id——鐵律 2 平台字典表）", force: :cascade do |t|
    t.string "collation", limit: 64, null: false, comment: "該語言排序用 collation（67 §C.7）"
    t.datetime "created_at", null: false
    t.string "date_format_id", limit: 32, default: "default", null: false
    t.string "direction", limit: 3, default: "ltr", null: false, comment: "ltr / rtl"
    t.string "endonym", limit: 64, null: false, comment: "語言自稱：繁體中文 / English（切換器顯示這個）"
    t.string "language", limit: 3, null: false, comment: "ISO 639-1（必要時 639-3）"
    t.string "number_format_id", limit: 32, default: "default", null: false
    t.string "plural_rule", limit: 32, null: false, comment: "複數類別集合識別字（Intl.PluralRules 的 locale）"
    t.string "region", limit: 2, comment: "ISO 3166-1 alpha-2；通常 NULL（地區屬市場，67 §C.1 規則 1）"
    t.string "script", limit: 4, comment: "ISO 15924：Hant / Hans；拉丁文字留 NULL"
    t.string "status", limit: 16, default: "available", null: false, comment: "available / deprecated"
    t.datetime "updated_at", null: false
  end

  create_table "product_options", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "商品選項，配額由 limits.yml 管理", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.bigint "product_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_product_options_tenant_id", unique: true
    t.index ["shop_id", "product_id", "id"], name: "uq_product_options_product_scoped_id", unique: true
    t.index ["shop_id", "product_id", "name"], name: "uq_product_options_product_id_name", unique: true
    t.index ["shop_id", "product_id", "position"], name: "uq_product_options_product_id_position", unique: true
    t.index ["shop_id", "product_id"], name: "ix_product_options_product_id"
  end

  create_table "product_variant_option_values", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "變體 × 選項的座標（每個變體對每個選項恰好一列）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "option_value_id", null: false
    t.bigint "product_id", null: false
    t.bigint "product_option_id", null: false
    t.bigint "product_variant_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_pvov_tenant_id", unique: true
    t.index ["shop_id", "option_value_id"], name: "ix_pvov_by_value"
    t.index ["shop_id", "product_id", "product_option_id"], name: "ix_pvov_product_option"
    t.index ["shop_id", "product_id", "product_variant_id"], name: "ix_pvov_product_variant"
    t.index ["shop_id", "product_option_id", "option_value_id"], name: "ix_pvov_option_value"
    t.index ["shop_id", "product_variant_id", "product_option_id"], name: "uq_pvov_variant_option", unique: true
  end

  create_table "product_variants", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "商品變體與 integer-cents 定價", force: :cascade do |t|
    t.string "barcode"
    t.bigint "compare_at_price_cents"
    t.bigint "cost_cents"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.string "inventory_policy", limit: 16, default: "deny", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "option_values_digest", limit: 40, null: false, comment: "選項值組合的 SHA1（13 §F1-2／D12）；輸入是 option_value_id 不是字串；我方內部欄，不得對外曝露"
    t.integer "position", null: false
    t.bigint "price_cents", default: 0, null: false
    t.bigint "product_id", null: false
    t.boolean "requires_shipping", default: true, null: false
    t.bigint "shop_id", null: false
    t.string "sku"
    t.boolean "taxable", default: true, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "weight_grams", default: 0, null: false
    t.index ["shop_id", "barcode"], name: "ix_product_variants_barcode"
    t.index ["shop_id", "id"], name: "uq_product_variants_tenant_id", unique: true
    t.index ["shop_id", "product_id", "id"], name: "uq_product_variants_product_scoped_id", unique: true
    t.index ["shop_id", "product_id", "option_values_digest"], name: "uq_product_variants_option_values_digest", unique: true
    t.index ["shop_id", "product_id", "position"], name: "uq_product_variants_product_id_position", unique: true
    t.index ["shop_id", "product_id"], name: "ix_product_variants_product_id"
    t.index ["shop_id", "sku"], name: "ix_product_variants_sku"
  end

  create_table "products", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "商品主檔", force: :cascade do |t|
    t.string "category_gid"
    t.datetime "created_at", null: false
    t.text "description_html", size: :medium, null: false
    t.string "handle", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "product_type"
    t.string "seo_description", limit: 320
    t.string "seo_title", limit: 70
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "draft", null: false
    t.json "tags", default: -> { "(json_array())" }, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "vendor"
    t.index ["shop_id", "created_at", "id"], name: "ix_products_created_at_id"
    t.index ["shop_id", "handle"], name: "uq_products_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_products_tenant_id", unique: true
    t.index ["shop_id", "status", "created_at"], name: "ix_products_status_created_at"
  end

  create_table "publications", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "銷售管道在本店的發布容器（Publication）", force: :cascade do |t|
    t.boolean "auto_publish", default: true, null: false, comment: "新建的 publishable 是否自動納入本管道"
    t.bigint "catalog_id", comment: "三層 AND 的第三層；M5 建 catalogs 時補外鍵"
    t.string "channel_handle", limit: 64, null: false, comment: "管道識別（online_store／point_of_sale／agentic…）"
    t.datetime "created_at", null: false
    t.string "name", null: false, comment: "顯示名（線上商店／門市 POS／代理式）"
    t.bigint "shop_id", null: false
    t.boolean "supports_future_publishing", default: true, null: false, comment: "本管道是否支援排程發布"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "channel_handle"], name: "uq_publications_channel", unique: true
    t.index ["shop_id", "id"], name: "uq_publications_tenant_id", unique: true
  end

  create_table "refund_line_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "退款逐行數量、金額與 restock 決策", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "line_item_id", null: false
    t.integer "quantity", null: false
    t.bigint "refund_id", null: false
    t.string "restock_type", limit: 32, default: "no_restock", null: false
    t.bigint "shop_id", null: false
    t.bigint "subtotal_cents", null: false
    t.bigint "tax_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_refund_line_items_tenant_id", unique: true
    t.index ["shop_id", "line_item_id"], name: "ix_refund_line_items_line_item_id"
    t.index ["shop_id", "refund_id", "line_item_id"], name: "uq_refund_line_items_refund_id_line_item_id", unique: true
    t.index ["shop_id", "refund_id"], name: "ix_refund_line_items_refund_id"
  end

  create_table "refunds", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "退款業務紀錄；金流結果仍由 transaction 推導", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.boolean "customer_notified", default: true, null: false
    t.string "idempotency_key", null: false
    t.bigint "order_id", null: false
    t.bigint "order_transaction_id"
    t.datetime "processed_at"
    t.string "reason"
    t.bigint "shipping_cents", default: 0, null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "pending", null: false
    t.bigint "total_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_refunds_tenant_id", unique: true
    t.index ["shop_id", "idempotency_key"], name: "uq_refunds_idempotency_key", unique: true
    t.index ["shop_id", "order_id", "created_at"], name: "ix_refunds_order_id_created_at"
    t.index ["shop_id", "order_id"], name: "ix_refunds_order_id"
    t.index ["shop_id", "order_transaction_id"], name: "ix_refunds_order_transaction_id"
  end

  create_table "resource_publications", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "Publishable × Publication 的發布關聯", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "publication_id", null: false
    t.bigint "publishable_id", null: false
    t.string "publishable_type", limit: 32, null: false, comment: "Product／Collection／ProductVariant"
    t.datetime "published_at", comment: "NULL=未發布；未來時間=排程發布"
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_res_pub_tenant_id", unique: true
    t.index ["shop_id", "publication_id", "publishable_type", "publishable_id"], name: "uq_res_pub_target", unique: true
    t.index ["shop_id", "publication_id", "published_at"], name: "ix_res_pub_published_at"
    t.index ["shop_id", "publishable_type", "publishable_id"], name: "ix_res_pub_publishable"
  end

  create_table "role_permissions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "角色的 permission key", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "permission_key", limit: 100, null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id", "permission_key"], name: "uq_role_permissions_key", unique: true
  end

  create_table "roles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "店內角色", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", limit: 100, null: false
    t.boolean "system", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "uq_roles_name", unique: true
  end

  create_table "segments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "顧客分群查詢定義", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_calculated_at"
    t.string "name", null: false
    t.text "query", null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "ready", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_segments_tenant_id", unique: true
    t.index ["shop_id", "name"], name: "uq_segments_name", unique: true
    t.index ["shop_id", "status", "updated_at"], name: "ix_segments_status_updated_at"
  end

  create_table "sessions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "可撤銷的 admin DB session", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address", limit: 45
    t.datetime "last_active_at", null: false
    t.datetime "revoked_at"
    t.bigint "staff_member_id", null: false
    t.string "token_digest", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 1024
    t.index ["expires_at"], name: "ix_sessions_expires_at"
    t.index ["staff_member_id", "revoked_at"], name: "ix_sessions_member_revoked"
    t.index ["token_digest"], name: "uq_sessions_token_digest", unique: true
  end

  create_table "shipping_profiles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "一般與自訂運送設定檔", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "general", default: false, null: false
    t.string "name", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "active", "id"], name: "ix_shipping_profiles_active_id"
    t.index ["shop_id", "id"], name: "uq_shipping_profiles_tenant_id", unique: true
    t.index ["shop_id", "name"], name: "uq_shipping_profiles_name", unique: true
  end

  create_table "shipping_rates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "固定或條件式運費，金額使用 cents", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "maximum_order_cents"
    t.integer "maximum_weight_grams"
    t.bigint "minimum_order_cents"
    t.integer "minimum_weight_grams"
    t.string "name", null: false
    t.bigint "price_cents", default: 0, null: false
    t.string "rate_type", limit: 32, default: "flat", null: false
    t.bigint "shipping_zone_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_shipping_rates_tenant_id", unique: true
    t.index ["shop_id", "shipping_zone_id", "active"], name: "ix_shipping_rates_shipping_zone_id_active"
    t.index ["shop_id", "shipping_zone_id"], name: "ix_shipping_rates_shipping_zone_id"
  end

  create_table "shipping_zones", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "運送設定檔的國家區域", force: :cascade do |t|
    t.json "country_codes", default: -> { "(json_array())" }, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "shipping_profile_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_shipping_zones_tenant_id", unique: true
    t.index ["shop_id", "shipping_profile_id", "name"], name: "uq_shipping_zones_shipping_profile_id_name", unique: true
    t.index ["shop_id", "shipping_profile_id"], name: "ix_shipping_zones_shipping_profile_id"
  end

  create_table "shop_locales", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "租戶啟用的語言（67 §C.1）：恆一列 is_source", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false, comment: "false＝下架但譯文保留（加回即復原）"
    t.boolean "is_source", default: false, null: false, comment: "來源語言：base 資料表的文字語言；每店恰一列"
    t.string "locale_tag", limit: 35, null: false
    t.integer "position", default: 0, null: false, comment: "切換器與堆疊欄位排序"
    t.boolean "published", default: false, null: false, comment: "前台可見；未發布＝只能預覽連結"
    t.bigint "shop_id", null: false
    t.virtual "source_guard", type: :integer, as: "if(`is_source`,1,NULL)", stored: true
    t.datetime "updated_at", null: false
    t.index ["locale_tag"], name: "fk_shop_locales_locale"
    t.index ["shop_id", "enabled", "position"], name: "ix_shop_locales_enabled_position"
    t.index ["shop_id", "id"], name: "uq_shop_locales_tenant_id", unique: true
    t.index ["shop_id", "locale_tag"], name: "uq_shop_locales_locale_tag", unique: true
    t.index ["shop_id", "source_guard"], name: "uq_shop_locales_single_source", unique: true
  end

  create_table "shops", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "租戶根；依規格明確豁免 shop_id", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_domain", limit: 253
    t.json "feature_flags", default: -> { "(json_object())" }, null: false
    t.string "name", null: false
    t.string "plan", limit: 32, default: "basic", null: false
    t.string "status", limit: 32, default: "active", null: false
    t.string "store_currency", limit: 3, default: "HKD", null: false
    t.string "subdomain", limit: 63, null: false
    t.string "timezone", limit: 64, default: "Asia/Hong_Kong", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_domain"], name: "uq_shops_custom_domain", unique: true
    t.index ["status"], name: "ix_shops_status"
    t.index ["subdomain"], name: "uq_shops_subdomain", unique: true
  end

  create_table "staff_members", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "店員身分與認證資料", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.string "email", limit: 320, null: false
    t.datetime "invited_at"
    t.string "locale", limit: 16, default: "en", null: false
    t.boolean "owner", default: false, null: false
    t.string "password_digest"
    t.string "status", limit: 32, default: "invited", null: false
    t.string "timezone", limit: 64, default: "Asia/Hong_Kong", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "uq_staff_members_email", unique: true
    t.index ["status"], name: "ix_staff_members_status"
  end

  create_table "tax_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "區域稅率與含稅價設定", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "country_code", limit: 2, null: false
    t.datetime "created_at", null: false
    t.boolean "include_in_prices", default: false, null: false
    t.json "overrides", default: -> { "(json_array())" }, null: false
    t.integer "rate_basis_points", default: 0, null: false
    t.string "region_code", limit: 16, default: "*", null: false
    t.bigint "shop_id", null: false
    t.boolean "tax_shipping", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "active", "country_code"], name: "ix_tax_settings_active_country_code"
    t.index ["shop_id", "country_code", "region_code"], name: "uq_tax_settings_country_code_region_code", unique: true
    t.index ["shop_id", "id"], name: "uq_tax_settings_tenant_id", unique: true
  end

  create_table "templates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "Liquid JSON template", force: :cascade do |t|
    t.json "content", default: -> { "(json_object())" }, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.bigint "shop_id", null: false
    t.string "template_type", limit: 64, null: false
    t.bigint "theme_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_templates_tenant_id", unique: true
    t.index ["shop_id", "theme_id", "key"], name: "uq_templates_theme_id_key", unique: true
    t.index ["shop_id", "theme_id"], name: "ix_templates_theme_id"
  end

  create_table "theme_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "主題全域 settings_data", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "settings", default: -> { "(json_object())" }, null: false
    t.bigint "shop_id", null: false
    t.bigint "theme_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_theme_settings_tenant_id", unique: true
    t.index ["shop_id", "theme_id"], name: "uq_theme_settings_theme_id", unique: true
  end

  create_table "themes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "主題庫項目；主題是資料而非可執行程式碼", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "license_attested", default: false, null: false
    t.string "name", null: false
    t.datetime "published_at"
    t.virtual "published_slot", type: :integer, as: "if((`role` = _utf8mb4'published'),1,NULL)", stored: true
    t.string "role", limit: 32, default: "draft", null: false
    t.bigint "shop_id", null: false
    t.string "source", limit: 32, default: "first_party", null: false
    t.datetime "updated_at", null: false
    t.string "version", limit: 64
    t.index ["shop_id", "id"], name: "uq_themes_tenant_id", unique: true
    t.index ["shop_id", "name"], name: "uq_themes_name", unique: true
    t.index ["shop_id", "published_slot"], name: "uq_themes_published_slot", unique: true
    t.index ["shop_id", "role", "updated_at"], name: "ix_themes_role_updated_at"
  end

  create_table "translation_status", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "翻譯進度物化（67 §C.6；鐵律 7：進度數字唯一來源）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "locale_tag", limit: 35, null: false
    t.integer "outdated_count", default: 0, null: false
    t.integer "required_fields", default: 0, null: false
    t.bigint "resource_id", null: false
    t.string "resource_type", limit: 48, null: false
    t.integer "review_pending", default: 0, null: false
    t.bigint "shop_id", null: false
    t.integer "translated_fields", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_translation_status_tenant_id", unique: true
    t.index ["shop_id", "locale_tag", "translated_fields"], name: "ix_translation_status_locale_progress"
    t.index ["shop_id", "resource_type", "resource_id", "locale_tag"], name: "uq_translation_status_resource_locale", unique: true
  end

  create_table "translations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "內容譯文（67 §C.2）：一列＝一個 (resource, locale, field)；base row 永遠是來源語言", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "field_key", null: false, comment: "title / body_html / meta_title / meta_description"
    t.string "locale_tag", limit: 35, null: false
    t.boolean "outdated", default: false, null: false
    t.string "outdated_severity", limit: 8, default: "none", null: false, comment: "none / minor / major"
    t.bigint "resource_id", null: false
    t.string "resource_type", limit: 48, null: false, comment: "PRODUCT / COLLECTION /（後續）…"
    t.boolean "review_required", default: false, null: false, comment: "machine / script_conversion 一律 true"
    t.bigint "shop_id", null: false
    t.string "source_digest", limit: 64, null: false, comment: "來源文字正規化後 SHA-256（67 §C.5 過期偵測）"
    t.string "source_locale_tag", limit: 35, null: false, comment: "這條譯文是從哪個語言翻的（改來源語言時用）"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_staff_id"
    t.text "value", size: :medium, null: false
    t.string "value_source", limit: 24, null: false, comment: "human / machine / script_conversion / import"
    t.index ["locale_tag"], name: "fk_translations_locale"
    t.index ["shop_id", "id"], name: "uq_translations_tenant_id", unique: true
    t.index ["shop_id", "locale_tag", "outdated", "resource_type"], name: "ix_translations_locale_outdated"
    t.index ["shop_id", "locale_tag", "review_required"], name: "ix_translations_locale_review"
    t.index ["shop_id", "resource_type", "resource_id", "locale_tag", "field_key"], name: "uq_translations_resource_locale_field", unique: true
    t.index ["shop_id", "resource_type", "resource_id", "locale_tag"], name: "ix_translations_resource_locale"
  end

  create_table "user_store_assignments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "role_id"
    t.bigint "shop_id", null: false
    t.bigint "staff_member_id", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "ix_usa_role_id"
    t.index ["shop_id", "staff_member_id"], name: "ix_usa_shop_member"
    t.index ["staff_member_id", "shop_id"], name: "uq_usa_member_shop", unique: true
  end

  add_foreign_key "api_tokens", "shops", name: "fk_api_tokens_shop"
  add_foreign_key "api_tokens", "staff_members", name: "fk_api_tokens_staff_member_id"
  add_foreign_key "checkouts", "customers", column: ["shop_id", "customer_id"], primary_key: ["shop_id", "id"], name: "fk_checkouts_customer_id"
  add_foreign_key "checkouts", "shops", name: "fk_checkouts_shop"
  add_foreign_key "collection_products", "collections", column: ["shop_id", "collection_id"], primary_key: ["shop_id", "id"], name: "fk_collection_products_collection_id"
  add_foreign_key "collection_products", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_collection_products_product_id"
  add_foreign_key "collection_products", "shops", name: "fk_collection_products_shop"
  add_foreign_key "collection_rules", "collections", column: ["shop_id", "collection_id"], primary_key: ["shop_id", "id"], name: "fk_collection_rules_collection_id"
  add_foreign_key "collection_rules", "shops", name: "fk_collection_rules_shop"
  add_foreign_key "collections", "shops", name: "fk_collections_shop"
  add_foreign_key "contract_liability_entries", "shops", name: "fk_contract_liability_entries_shop"
  add_foreign_key "customer_addresses", "customers", column: ["shop_id", "customer_id"], primary_key: ["shop_id", "id"], name: "fk_customer_addresses_customer_id"
  add_foreign_key "customer_addresses", "shops", name: "fk_customer_addresses_shop"
  add_foreign_key "customers", "shops", name: "fk_customers_shop"
  add_foreign_key "discount_applications", "discounts", column: ["shop_id", "discount_id"], primary_key: ["shop_id", "id"], name: "fk_discount_applications_discount_id"
  add_foreign_key "discount_applications", "line_items", column: ["shop_id", "line_item_id"], primary_key: ["shop_id", "id"], name: "fk_discount_applications_line_item_id"
  add_foreign_key "discount_applications", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_discount_applications_order_id"
  add_foreign_key "discount_applications", "shops", name: "fk_discount_applications_shop"
  add_foreign_key "discounts", "shops", name: "fk_discounts_shop"
  add_foreign_key "einvoice_allowances", "einvoices", column: ["shop_id", "einvoice_id"], primary_key: ["shop_id", "id"], name: "fk_einvoice_allowances_einvoice_id"
  add_foreign_key "einvoice_allowances", "shops", name: "fk_einvoice_allowances_shop"
  add_foreign_key "einvoices", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_einvoices_order_id"
  add_foreign_key "einvoices", "shops", name: "fk_einvoices_shop"
  add_foreign_key "event_outbox", "shops", name: "fk_event_outbox_shop"
  add_foreign_key "events", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_events_order_id"
  add_foreign_key "events", "shops", name: "fk_events_shop"
  add_foreign_key "events", "staff_members", name: "fk_events_staff_member_id"
  add_foreign_key "files", "shops", name: "fk_files_shop"
  add_foreign_key "fulfillment_orders", "locations", column: ["shop_id", "location_id"], primary_key: ["shop_id", "id"], name: "fk_fulfillment_orders_location_id"
  add_foreign_key "fulfillment_orders", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_fulfillment_orders_order_id"
  add_foreign_key "fulfillment_orders", "shops", name: "fk_fulfillment_orders_shop"
  add_foreign_key "fulfillments", "fulfillment_orders", column: ["shop_id", "fulfillment_order_id"], primary_key: ["shop_id", "id"], name: "fk_fulfillments_fulfillment_order_id"
  add_foreign_key "fulfillments", "shops", name: "fk_fulfillments_shop"
  add_foreign_key "idempotency_keys", "shops", name: "fk_idempotency_keys_shop"
  add_foreign_key "inventory_adjustment_groups", "shops", name: "fk_inventory_adjustment_groups_shop"
  add_foreign_key "inventory_adjustments", "inventory_adjustment_groups", column: ["shop_id", "inventory_adjustment_group_id"], primary_key: ["shop_id", "id"], name: "fk_inventory_adjustments_group_id"
  add_foreign_key "inventory_adjustments", "inventory_levels", column: ["shop_id", "inventory_level_id"], primary_key: ["shop_id", "id"], name: "fk_inventory_adjustments_inventory_level_id"
  add_foreign_key "inventory_adjustments", "shops", name: "fk_inventory_adjustments_shop"
  add_foreign_key "inventory_items", "product_variants", column: ["shop_id", "product_variant_id"], primary_key: ["shop_id", "id"], name: "fk_inventory_items_product_variant_id"
  add_foreign_key "inventory_items", "shops", name: "fk_inventory_items_shop"
  add_foreign_key "inventory_levels", "inventory_items", column: ["shop_id", "inventory_item_id"], primary_key: ["shop_id", "id"], name: "fk_inventory_levels_inventory_item_id"
  add_foreign_key "inventory_levels", "locations", column: ["shop_id", "location_id"], primary_key: ["shop_id", "id"], name: "fk_inventory_levels_location_id"
  add_foreign_key "inventory_levels", "shops", name: "fk_inventory_levels_shop"
  add_foreign_key "jurisdiction_capability_skips", "shops", name: "fk_jurisdiction_capability_skips_shop"
  add_foreign_key "line_items", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_line_items_order_id"
  add_foreign_key "line_items", "product_variants", column: ["shop_id", "product_variant_id"], primary_key: ["shop_id", "id"], name: "fk_line_items_product_variant_id"
  add_foreign_key "line_items", "shops", name: "fk_line_items_shop"
  add_foreign_key "locations", "shops", name: "fk_locations_shop"
  add_foreign_key "media", "product_variants", column: ["shop_id", "product_variant_id"], primary_key: ["shop_id", "id"], name: "fk_media_product_variant_id"
  add_foreign_key "media", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_media_product_id"
  add_foreign_key "media", "shops", name: "fk_media_shop"
  add_foreign_key "menu_items", "menu_items", column: ["shop_id", "parent_menu_item_id"], primary_key: ["shop_id", "id"], name: "fk_menu_items_parent_menu_item_id"
  add_foreign_key "menu_items", "menus", column: ["shop_id", "menu_id"], primary_key: ["shop_id", "id"], name: "fk_menu_items_menu_id"
  add_foreign_key "menu_items", "shops", name: "fk_menu_items_shop"
  add_foreign_key "menus", "shops", name: "fk_menus_shop"
  add_foreign_key "metafield_definitions", "shops", name: "fk_metafield_definitions_shop"
  add_foreign_key "metafields", "metafield_definitions", column: ["shop_id", "metafield_definition_id"], primary_key: ["shop_id", "id"], name: "fk_metafields_metafield_definition_id"
  add_foreign_key "metafields", "shops", name: "fk_metafields_shop"
  add_foreign_key "notification_templates", "shops", name: "fk_notification_templates_shop"
  add_foreign_key "option_values", "product_options", column: ["shop_id", "product_option_id"], primary_key: ["shop_id", "id"], name: "fk_option_values_product_option_id"
  add_foreign_key "option_values", "shops", name: "fk_option_values_shop"
  add_foreign_key "order_transactions", "order_transactions", column: ["shop_id", "parent_transaction_id"], primary_key: ["shop_id", "id"], name: "fk_order_transactions_parent_transaction_id"
  add_foreign_key "order_transactions", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_order_transactions_order_id"
  add_foreign_key "order_transactions", "shops", name: "fk_order_transactions_shop"
  add_foreign_key "orders", "checkouts", column: ["shop_id", "checkout_id"], primary_key: ["shop_id", "id"], name: "fk_orders_checkout_id"
  add_foreign_key "orders", "customers", column: ["shop_id", "customer_id"], primary_key: ["shop_id", "id"], name: "fk_orders_customer_id"
  add_foreign_key "orders", "shops", name: "fk_orders_shop"
  add_foreign_key "pages", "shops", name: "fk_pages_shop"
  add_foreign_key "product_options", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_product_options_product_id"
  add_foreign_key "product_options", "shops", name: "fk_product_options_shop"
  add_foreign_key "product_variant_option_values", "option_values", column: ["shop_id", "product_option_id", "option_value_id"], primary_key: ["shop_id", "product_option_id", "id"], name: "fk_pvov_value"
  add_foreign_key "product_variant_option_values", "product_options", column: ["shop_id", "product_id", "product_option_id"], primary_key: ["shop_id", "product_id", "id"], name: "fk_pvov_option"
  add_foreign_key "product_variant_option_values", "product_variants", column: ["shop_id", "product_id", "product_variant_id"], primary_key: ["shop_id", "product_id", "id"], name: "fk_pvov_variant"
  add_foreign_key "product_variant_option_values", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_pvov_product"
  add_foreign_key "product_variant_option_values", "shops", name: "fk_pvov_shop"
  add_foreign_key "product_variants", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_product_variants_product_id"
  add_foreign_key "product_variants", "shops", name: "fk_product_variants_shop"
  add_foreign_key "products", "shops", name: "fk_products_shop"
  add_foreign_key "publications", "shops", name: "fk_publications_shop"
  add_foreign_key "refund_line_items", "line_items", column: ["shop_id", "line_item_id"], primary_key: ["shop_id", "id"], name: "fk_refund_line_items_line_item_id"
  add_foreign_key "refund_line_items", "refunds", column: ["shop_id", "refund_id"], primary_key: ["shop_id", "id"], name: "fk_refund_line_items_refund_id"
  add_foreign_key "refund_line_items", "shops", name: "fk_refund_line_items_shop"
  add_foreign_key "refunds", "order_transactions", column: ["shop_id", "order_transaction_id"], primary_key: ["shop_id", "id"], name: "fk_refunds_order_transaction_id"
  add_foreign_key "refunds", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_refunds_order_id"
  add_foreign_key "refunds", "shops", name: "fk_refunds_shop"
  add_foreign_key "resource_publications", "publications", column: ["shop_id", "publication_id"], primary_key: ["shop_id", "id"], name: "fk_res_pub_publication_id"
  add_foreign_key "resource_publications", "shops", name: "fk_res_pub_shop"
  add_foreign_key "role_permissions", "roles", name: "fk_role_permissions_role_id"
  add_foreign_key "segments", "shops", name: "fk_segments_shop"
  add_foreign_key "sessions", "staff_members", name: "fk_sessions_staff_member_id"
  add_foreign_key "shipping_profiles", "shops", name: "fk_shipping_profiles_shop"
  add_foreign_key "shipping_rates", "shipping_zones", column: ["shop_id", "shipping_zone_id"], primary_key: ["shop_id", "id"], name: "fk_shipping_rates_shipping_zone_id"
  add_foreign_key "shipping_rates", "shops", name: "fk_shipping_rates_shop"
  add_foreign_key "shipping_zones", "shipping_profiles", column: ["shop_id", "shipping_profile_id"], primary_key: ["shop_id", "id"], name: "fk_shipping_zones_shipping_profile_id"
  add_foreign_key "shipping_zones", "shops", name: "fk_shipping_zones_shop"
  add_foreign_key "shop_locales", "platform_locales", column: "locale_tag", primary_key: "tag", name: "fk_shop_locales_locale"
  add_foreign_key "shop_locales", "shops", name: "fk_shop_locales_shop"
  add_foreign_key "tax_settings", "shops", name: "fk_tax_settings_shop"
  add_foreign_key "templates", "shops", name: "fk_templates_shop"
  add_foreign_key "templates", "themes", column: ["shop_id", "theme_id"], primary_key: ["shop_id", "id"], name: "fk_templates_theme_id"
  add_foreign_key "theme_settings", "shops", name: "fk_theme_settings_shop"
  add_foreign_key "theme_settings", "themes", column: ["shop_id", "theme_id"], primary_key: ["shop_id", "id"], name: "fk_theme_settings_theme_id"
  add_foreign_key "themes", "shops", name: "fk_themes_shop"
  add_foreign_key "translation_status", "shops", name: "fk_translation_status_shop"
  add_foreign_key "translations", "platform_locales", column: "locale_tag", primary_key: "tag", name: "fk_translations_locale"
  add_foreign_key "translations", "shops", name: "fk_translations_shop"
  add_foreign_key "user_store_assignments", "roles", name: "fk_usa_role_id"
  add_foreign_key "user_store_assignments", "shops", name: "fk_usa_shop_id"
  add_foreign_key "user_store_assignments", "staff_members", name: "fk_usa_staff_member_id"
end
