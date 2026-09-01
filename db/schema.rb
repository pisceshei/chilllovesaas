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

ActiveRecord::Schema[8.1].define(version: 2026_09_01_190000) do
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

  create_table "app_installations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "app 在本店的安裝狀態（本尊 AppInstallation）", force: :cascade do |t|
    t.string "app_handle", limit: 64, null: false, comment: "指向 platform_apps.handle"
    t.datetime "created_at", null: false
    t.datetime "installed_at", null: false, comment: "? ours：本尊 AppInstallation 沒有時間戳"
    t.bigint "shop_id", null: false
    t.datetime "uninstalled_at", comment: "? ours：軟刪。NULL＝仍安裝中。讀取端一律帶 installed scope"
    t.datetime "updated_at", null: false
    t.index ["app_handle"], name: "fk_app_installations_app_handle"
    t.index ["shop_id", "app_handle"], name: "uq_app_installations_app", unique: true
    t.index ["shop_id", "id"], name: "uq_app_installations_tenant_id", unique: true
  end

  create_table "article_comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "文章留言（三態；Liquid 只見 published）", force: :cascade do |t|
    t.bigint "article_id", null: false
    t.string "author_name", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "email", limit: 320, null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 12, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "fk_rails_67982717fa"
    t.index ["shop_id", "article_id", "status"], name: "ix_article_comments_status"
    t.index ["shop_id", "id"], name: "uq_article_comments_tenant_id", unique: true
  end

  create_table "articles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "部落格文章（98 §1/§4；published_at NULL＝Hidden）", force: :cascade do |t|
    t.string "author_name", comment: "顯示名（98 §4 byline『By KEN LEE』形；不掛 staff FK）"
    t.bigint "blog_id", null: false
    t.text "body_html", size: :long, null: false
    t.datetime "created_at", null: false
    t.text "excerpt_html", comment: "摘要（官方 summary/excerpt——列表與 excerpt_or_content 用）"
    t.string "handle", null: false
    t.datetime "published_at", comment: "NULL＝Hidden；未來時刻＝排程（Page.visible 同紀律）"
    t.bigint "shop_id", null: false
    t.json "tags", default: -> { "(json_array())" }, null: false
    t.string "template_suffix"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["blog_id"], name: "fk_rails_5fea85476e"
    t.index ["shop_id", "blog_id", "handle"], name: "uq_articles_handle", unique: true
    t.index ["shop_id", "blog_id", "published_at"], name: "ix_articles_published"
    t.index ["shop_id", "id"], name: "uq_articles_tenant_id", unique: true
  end

  create_table "blogs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "部落格（98 §3；comment_policy 官方三值）", force: :cascade do |t|
    t.string "comment_policy", limit: 20, default: "closed", null: false
    t.datetime "created_at", null: false
    t.string "handle", null: false
    t.bigint "shop_id", null: false
    t.string "template_suffix"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "handle"], name: "uq_blogs_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_blogs_tenant_id", unique: true
  end

  create_table "cart_line_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "購物車行（specs/15 F1 #1/#5；merge_key_hash 承重合併）", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.datetime "created_at", null: false
    t.string "merge_key_hash", limit: 64, null: false, comment: "SHA-256(variant＋properties＋selling_plan＋單價＋parent)——全同才併行"
    t.bigint "parent_id", comment: "bundle 父行（Q-44 未決前暫定入鍵；v1 恆 NULL）"
    t.bigint "product_variant_id", null: false
    t.json "properties", null: false, comment: "客製屬性（合併鍵承重輸入；同 variant 不同屬性＝合法多行）"
    t.integer "quantity", default: 1, null: false
    t.bigint "selling_plan_id", comment: "訂閱方案（功能未落地；合併鍵承重輸入，恆 NULL）"
    t.bigint "shop_id", null: false
    t.bigint "unit_price_cents", null: false, comment: "加入當下價（合併鍵承重輸入；顯示用即時價另查——F1 #3）"
    t.datetime "updated_at", null: false
    t.index ["cart_id"], name: "fk_cart_line_items_cart"
    t.index ["product_variant_id"], name: "fk_cart_line_items_variant"
    t.index ["shop_id", "cart_id", "merge_key_hash"], name: "uq_cart_line_items_merge_key", unique: true
    t.index ["shop_id", "cart_id"], name: "ix_cart_line_items_cart"
    t.index ["shop_id", "id"], name: "uq_cart_line_items_tenant_id", unique: true
    t.index ["shop_id", "product_variant_id"], name: "ix_cart_line_items_variant"
  end

  create_table "carts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "買家購物車（specs/15 F1；token 進 _cl_buyer 簽名 cookie）", force: :cascade do |t|
    t.json "attributes_json", null: false, comment: "Ajax cart 契約的 attributes（clear 不清除）"
    t.datetime "created_at", null: false
    t.text "note", comment: "Ajax cart 契約的 note（clear 不清除——官方語義）"
    t.bigint "shop_id", null: false
    t.string "token", limit: 64, null: false, comment: "cookie 攜帶的識別（SecureRandom；不可枚舉）"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_carts_tenant_id", unique: true
    t.index ["shop_id", "token"], name: "uq_carts_token", unique: true
    t.index ["shop_id", "updated_at"], name: "ix_carts_updated_at", comment: "90 天未動 purge job 的掃描鍵（F1 #4）"
  end

  create_table "channels", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "銷售管道身分（本尊 Channel）：handle 的權威來源", force: :cascade do |t|
    t.bigint "app_installation_id", comment: "可 NULL：agentic 型管道無安裝實體（82 §10.1 實測）。⚠️ 本尊 Channel.app 是非 null"
    t.string "channel_type", limit: 24, default: "app", null: false, comment: "app／agentic（對位本尊 Channel vs AgenticChannel 兩個不同型別）"
    t.datetime "created_at", null: false
    t.string "handle", limit: 64, null: false, comment: "本尊 Channel.handle（String!／\"...identifier for the channel within the shop\"）；每店唯一、可帶後綴"
    t.bigint "publication_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "app_installation_id"], name: "fk_channels_app_installation_id"
    t.index ["shop_id", "handle"], name: "uq_channels_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_channels_tenant_id", unique: true
    t.index ["shop_id", "publication_id"], name: "uq_channels_publication", unique: true
  end

  create_table "checkouts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "結帳快照及棄單來源", force: :cascade do |t|
    t.datetime "abandoned_at"
    t.json "billing_address", default: -> { "(json_object())" }, null: false
    t.boolean "buyer_accepts_marketing", default: false, null: false, comment: "買家勾選行銷訂閱（87 §3；對位 Order API buyer_accepts_marketing）"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "customer_id"
    t.json "discount_applications_snapshot", comment: "求值結果快照 [{discount_id,title,class,amount_cents,allocations}]（成單時回放成 discount_applications 列）"
    t.bigint "discount_cents", default: 0, null: false
    t.string "discount_code", limit: 64, comment: "結帳輸入的折扣碼（正規化後快照；NULL＝未輸入）"
    t.string "email", limit: 320
    t.datetime "expires_at"
    t.json "line_items_snapshot", default: -> { "(json_array())" }, null: false
    t.json "payment_method_snapshot", default: -> { "(json_object())" }, null: false, comment: "選定付款方式快照：{id,method_type,name,additional_details,payment_instructions}"
    t.string "presentment_currency", limit: 3, default: "HKD", null: false
    t.bigint "presentment_total_cents", default: 0, null: false
    t.string "psp_intent_id", comment: "PSP payment intent id（輪詢／對帳引用；request_id 冪等使同 checkout 恆同 intent）"
    t.datetime "recovery_email_sent_at", comment: "挽回信寄出時間（NULL＝未寄；列表 Email status 徽章）"
    t.string "recovery_token", limit: 64
    t.json "shipping_address", default: -> { "(json_object())" }, null: false
    t.bigint "shipping_cents", default: 0, null: false
    t.json "shipping_lines", default: -> { "(json_array())" }, null: false, comment: "選定運費快照：[{shipment_index,profile_id,rate_id,name,price_cents}]"
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "open", null: false
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

  create_table "collection_memberships", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "物化成員（前台唯一查詢對象；13 §F4.6-1）。智慧成員禁入 collection_products", force: :cascade do |t|
    t.bigint "collection_id", null: false
    t.datetime "created_at", null: false
    t.string "origin", limit: 24, default: "conditions", null: false, comment: "conditions / manual / nested_collection / app（13 §F4.1）"
    t.bigint "origin_source_id"
    t.integer "position", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "rebuilt_at", comment: "本輪 rebuild 的世代戳（掃尾依據）"
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id", comment: "NULL＝整商品；非 NULL＝variants 目標（v1 恆 NULL）"
    t.virtual "variant_key", type: :bigint, as: "coalesce(`variant_id`,0)", stored: true
    t.index ["shop_id", "collection_id", "position"], name: "ix_collection_memberships_position"
    t.index ["shop_id", "collection_id", "product_id", "variant_key"], name: "uq_collection_memberships_member", unique: true
    t.index ["shop_id", "product_id"], name: "ix_collection_memberships_product"
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

  create_table "collection_source_rules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "typed-value 條件（金額一律 value_cents——鐵律 3；13 §F4.1 修訂形）", force: :cascade do |t|
    t.string "block", limit: 12, null: false, comment: "inclusion / exclusion"
    t.bigint "collection_source_id", null: false
    t.string "condition_type", limit: 64, null: false, comment: "開放集：未知型別原樣保留（condition_unknown_passthrough）"
    t.datetime "created_at", null: false
    t.bigint "metafield_definition_id", comment: "metafield 條件（v1 不收，欄位先就位）"
    t.integer "position", default: 0, null: false
    t.json "raw_payload", comment: "unknown 型別的原樣保存（passthrough 載體）"
    t.string "relation", limit: 32, comment: "已知型別必填；unknown 可 NULL"
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.boolean "value_bool"
    t.bigint "value_cents", comment: "金額規則值唯一合法欄（鐵律 3）"
    t.bigint "value_int"
    t.string "value_text"
    t.index ["shop_id", "block", "condition_type", "value_int"], name: "ix_collection_source_rules_reference"
    t.index ["shop_id", "collection_source_id", "block", "position"], name: "uq_collection_source_rules_position", unique: true
  end

  create_table "collection_sources", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "系列來源（sources 模型；limits collection.source_types）", force: :cascade do |t|
    t.bigint "app_id", comment: "app 是 source 的欄位不是型別（95 §1.1）；v1 恆 NULL"
    t.bigint "collection_id", null: false
    t.datetime "created_at", null: false
    t.string "exclusion_match", limit: 8, comment: "all / any / NULL（三態；三道裁定 :58-59）"
    t.string "inclusion_match", limit: 8, default: "all", null: false, comment: "all / any（per block）"
    t.integer "position", default: 0, null: false
    t.bigint "referenced_collection_id", comment: "僅 sub_collections 型：被引用的系列"
    t.boolean "shareable", comment: "95 §1.1 記載的真實維度；語義未取證（P11 登記），v1 不寫"
    t.bigint "shop_id", null: false
    t.string "source_type", limit: 32, null: false, comment: "conditions / sub_collections"
    t.string "target_type", limit: 16, comment: "products / variants（僅 conditions 型；v1 只收 products）"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "collection_id", "position"], name: "ix_collection_sources_collection"
    t.index ["shop_id", "source_type", "referenced_collection_id"], name: "ix_collection_sources_referenced"
  end

  create_table "collections", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "手動或智慧系列", force: :cascade do |t|
    t.string "collection_type", limit: 32, default: "manual", null: false
    t.datetime "created_at", null: false
    t.text "description_html", size: :medium, null: false
    t.string "handle", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "products_updated_at", comment: "成員集合最後變動時刻（cache stamp；14 §F1）"
    t.string "rebuild_status", limit: 12, comment: "OK / PENDING / ERROR（13 §F4.1；NULL＝從未 rebuild 過＝manual 或未啟用）"
    t.datetime "rebuilt_at", comment: "最後一次成功 rebuild 完成時刻"
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

  create_table "customer_marketing_consents", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "行銷同意事件（append-only；快取在 customers 狀態欄）", force: :cascade do |t|
    t.string "channel", limit: 16, null: false, comment: "email/sms（WhatsApp 隨後續）"
    t.datetime "consent_updated_at", null: false, comment: "官方 latest-wins 合併鍵（缺值時＝寫入當下，官方同規則）"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "opt_in_level", limit: 32, comment: "single_opt_in/confirmed_opt_in/unknown（官方三值）"
    t.bigint "shop_id", null: false
    t.string "source", limit: 32, null: false, comment: "checkout/admin/api（08 §C.4）"
    t.string "state", limit: 32, null: false, comment: "官方 enum 小寫形（subscribed/unsubscribed/pending/not_subscribed/redacted/invalid）"
    t.index ["customer_id"], name: "fk_rails_fda6406f2c"
    t.index ["shop_id", "customer_id", "channel", "consent_updated_at"], name: "ix_cmc_customer_channel_time"
  end

  create_table "customer_otps", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "登入驗證碼（74 §7 六位；digest＋attempts）", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.string "code_digest", limit: 64, null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.string "email", limit: 320, null: false, comment: "正規化後（normalize_email 同一定義點）"
    t.datetime "expires_at", null: false
    t.bigint "shop_id", null: false
    t.index ["shop_id", "email"], name: "ix_customer_otps_email"
  end

  create_table "customer_sessions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "買家登入 session（365 天；token digest）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.datetime "expires_at", null: false
    t.bigint "shop_id", null: false
    t.string "token_digest", limit: 64, null: false
    t.index ["customer_id"], name: "fk_rails_213ac6f490"
    t.index ["shop_id", "customer_id"], name: "ix_customer_sessions_customer"
    t.index ["token_digest"], name: "uq_customer_sessions_token", unique: true
  end

  create_table "customers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "顧客主檔與隱私狀態", force: :cascade do |t|
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.string "email", limit: 320
    t.boolean "email_marketing_consent", default: false, null: false
    t.string "email_marketing_consent_source", limit: 32, comment: "email 同意最後變更來源（08 §C.4 source；如 checkout）"
    t.datetime "email_marketing_consent_updated_at", comment: "email 同意最後變更時間（08 §C.4 consentUpdatedAt）"
    t.string "email_marketing_state", limit: 32, default: "not_subscribed", null: false, comment: "email 同意狀態快取（事件表 latest-wins 投影；官方六值）"
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_order_at", comment: "最新訂單時間（16 §F6.1 統計欄；訂單成立增量維護）"
    t.string "locale", limit: 16, comment: "通知語言（BCP-47；NULL＝店預設。Edit customer modal 的 Language 欄）"
    t.text "note"
    t.integer "orders_count", default: 0, null: false
    t.string "phone", limit: 32
    t.datetime "redaction_scheduled_at", comment: "個資抹除排程時點（官方 10 天可取消；RedactDueJob 到點執行）"
    t.bigint "shop_id", null: false
    t.boolean "sms_marketing_consent", default: false, null: false
    t.string "sms_marketing_state", limit: 32, default: "not_subscribed", null: false, comment: "SMS 同意狀態快取（官方五值）"
    t.string "state", limit: 32, default: "enabled", null: false
    t.json "tags", default: -> { "(json_array())" }, null: false
    t.boolean "tax_exempt", default: false, null: false
    t.bigint "total_spent_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "email"], name: "uq_customers_email", unique: true
    t.index ["shop_id", "id"], name: "uq_customers_tenant_id", unique: true
    t.index ["shop_id", "phone"], name: "uq_customers_phone", unique: true
    t.index ["shop_id", "state", "created_at"], name: "ix_customers_state_created_at"
  end

  create_table "daily_rollups", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "分析日聚合（19-F2；upsert 冪等；金額=cents 計數=原值）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false, comment: "shop 時區的日界線（19-F2 坑：不是 UTC）"
    t.string "dimension", limit: 64, default: "", null: false, comment: "維度值（如 product_id；無維度＝空字串——uq 需非 NULL）"
    t.string "metric", limit: 64, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "value", default: 0, null: false
    t.index ["shop_id", "date", "metric", "dimension"], name: "uq_daily_rollups_key", unique: true
    t.index ["shop_id", "metric", "date"], name: "ix_daily_rollups_metric_date"
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

  create_table "discount_redemptions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "折扣兌換帳（once_per_customer 唯一索引硬保證；17-F3）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "customer_key", limit: 128, null: false, comment: "customer_id 或正規化 email 的 sha256（17-F3：正規化後再 hash）"
    t.bigint "discount_id", null: false
    t.bigint "order_id", null: false
    t.bigint "shop_id", null: false
    t.index ["discount_id"], name: "fk_rails_7e73f632da"
    t.index ["shop_id", "discount_id", "customer_key"], name: "uq_discount_redemptions_customer", unique: true
    t.index ["shop_id", "order_id"], name: "ix_discount_redemptions_order"
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

  create_table "domains", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "網域（實測 2026-08-31 Settings→Domains）：host→shop 解析的權威表（步 2 消費）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain_type", limit: 16, default: "primary", null: false, comment: "primary|redirect|alias（實測 Change domain type 對話恰三值，逐字 Primary/Redirecting/Alias domain）"
    t.string "host", limit: 253, null: false, comment: "小寫 FQDN，不含 scheme／port"
    t.virtual "primary_guard", type: :integer, as: "if((`domain_type` = _utf8mb4'primary'),1,NULL)", stored: true
    t.bigint "shop_id", null: false
    t.string "status", limit: 16, default: "active", null: false, comment: "pending|active（本尊列表 Status=Connected；DNS 驗證 ops 隨 bt3 配套，v1 先兩值）"
    t.datetime "updated_at", null: false
    t.index ["host"], name: "uq_domains_host", unique: true
    t.index ["shop_id", "id"], name: "uq_domains_tenant_id", unique: true
    t.index ["shop_id", "primary_guard"], name: "uq_domains_single_primary", unique: true
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

  create_table "event_deliveries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "event × consumer 投遞帳（逐消費者重放隔離）", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.string "consumer", limit: 100, null: false
    t.datetime "created_at", null: false
    t.string "event_id", limit: 36, null: false
    t.text "last_error"
    t.bigint "shop_id", null: false
    t.string "state", limit: 32, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "event_id", "consumer"], name: "uq_event_deliveries_event_consumer", unique: true
    t.index ["shop_id", "id"], name: "uq_event_deliveries_tenant_id", unique: true
    t.index ["shop_id", "state"], name: "ix_event_deliveries_state"
  end

  create_table "event_outbox", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "與業務寫入同 transaction 的 at-least-once outbox", force: :cascade do |t|
    t.bigint "aggregate_id", null: false
    t.string "aggregate_type", limit: 64, null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "available_at", null: false
    t.integer "coalesced_count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "dedupe_key", limit: 191
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
    t.index ["shop_id", "dedupe_key"], name: "uq_event_outbox_dedupe_key", unique: true
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

  create_table "file_usages", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "檔案引用（file × owner 恰一列；引用計數的唯一來源）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "file_id", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", limit: 64, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "file_id", "owner_type", "owner_id"], name: "uq_file_usages_file_owner", unique: true
    t.index ["shop_id", "id"], name: "uq_file_usages_tenant_id", unique: true
    t.index ["shop_id", "owner_type", "owner_id"], name: "ix_file_usages_owner"
  end

  create_table "files", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "上傳檔案 metadata", force: :cascade do |t|
    t.string "alt_source", limit: 16, comment: "alt 的來源稽核（ai／human／imported；62 §F.1）。null＝立欄前的存量"
    t.string "alt_text", limit: 512
    t.bigint "byte_size", null: false
    t.string "checksum", limit: 64, null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.json "derivatives"
    t.string "filename", null: false
    t.integer "height"
    t.text "processing_error"
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "uploaded", null: false
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["shop_id", "byte_size"], name: "ix_files_byte_size"
    t.index ["shop_id", "created_at"], name: "ix_files_created_at"
    t.index ["shop_id", "filename"], name: "ix_files_filename"
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
    t.json "line_items_snapshot", null: false, comment: "出貨行項明細 [{line_item_id, quantity}]（cancel 回加與 UI 顯示的依據）"
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
    t.bigint "product_variant_id"
    t.boolean "requires_shipping", default: true, null: false
    t.bigint "shop_id", null: false
    t.string "sku"
    t.boolean "tracked", default: true, null: false
    t.datetime "updated_at", null: false
    t.datetime "variant_deleted_at", comment: "變體被刪除的時點（B1 稽核欄；NULL＝變體仍在）"
    t.index ["shop_id", "created_at", "id"], name: "ix_inventory_items_keyset"
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

  create_table "market_regions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "市場的 region conditions（29 §1.4）：active 市場不得重疊（model 層驗證）", force: :cascade do |t|
    t.string "country_code", limit: 2, null: false, comment: "ISO 3166-1 alpha-2，大寫"
    t.datetime "created_at", null: false
    t.bigint "market_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["market_id"], name: "fk_market_regions_market"
    t.index ["shop_id", "country_code"], name: "ix_market_regions_by_country", comment: "「這個國家屬於哪些市場」——active 重疊驗證與 buyer 命中都走這裡"
    t.index ["shop_id", "market_id", "country_code"], name: "uq_market_regions_country", unique: true
  end

  create_table "market_web_presence_locales", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "per-market 語言白名單（67 §C.8）。? 粒度是 presence 不是 market：市場的開放語言＝resolved presences 的聯集，任何 UPDATE ... WHERE market_id 形態的寫入都是 bug", force: :cascade do |t|
    t.datetime "closed_at", comment: "關閉時點——關閉是狀態轉換不是刪除（67 §C.8：404 與失效掛鉤要用）"
    t.datetime "created_at", null: false
    t.virtual "default_guard", type: :integer, as: "if(`is_market_default`,1,NULL)", stored: true
    t.boolean "is_market_default", default: false, null: false, comment: "＝(locale_tag == presence.default_shop_locale)；為進複合唯一索引而物化（67 §C.8(b)）"
    t.string "locale_tag", limit: 35, null: false
    t.bigint "market_web_presence_id", null: false
    t.boolean "open_to_buyers", default: true, null: false, comment: "白名單開關本身（67 §A.5）"
    t.integer "position", default: 0, null: false, comment: "切換器顯示順序（商家唯一的排序控制點，鐵律 7）"
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["market_web_presence_id"], name: "fk_mwpl_presence"
    t.index ["shop_id", "locale_tag"], name: "ix_mwpl_by_locale", comment: "「這個語言開給了哪些市場」（關語言前的影響評估，67 §C.8）"
    t.index ["shop_id", "market_web_presence_id", "default_guard"], name: "uq_mwpl_single_default", unique: true
    t.index ["shop_id", "market_web_presence_id", "locale_tag"], name: "uq_mwpl_locale", unique: true
  end

  create_table "market_web_presences", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "市場的網站呈現（29 §1.2）：domain XOR subfolder；沿 lineage 累加繼承（additive）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_shop_locale", limit: 35, null: false, comment: "該 presence 的預設 locale（29 §1.4 欄名沿用）；mwpl.is_market_default 與它同一真相（67 §C.8(b)）"
    t.bigint "domain_id", comment: "獨立網域／子網域策略時指向 domains；與 subfolder_suffix 互斥"
    t.bigint "market_id", null: false
    t.bigint "shop_id", null: false
    t.string "subfolder_suffix", limit: 8, comment: "子資料夾策略的識別字（小寫）；多國市場它兼任前綴 region 來源（67 §F.1(b-2) 暫案 C，V-225）"
    t.datetime "updated_at", null: false
    t.index ["domain_id"], name: "fk_mwp_domain"
    t.index ["market_id"], name: "fk_mwp_market"
    t.index ["shop_id", "default_shop_locale"], name: "fk_mwp_default_locale"
    t.index ["shop_id", "domain_id", "subfolder_suffix"], name: "ix_mwp_domain_suffix"
    t.index ["shop_id", "id"], name: "uq_mwp_tenant_id", unique: true
    t.index ["shop_id", "market_id"], name: "ix_mwp_market"
    t.check_constraint "(`domain_id` is null) <> (`subfolder_suffix` is null)", name: "ck_mwp_domain_xor_subfolder"
  end

  create_table "markets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "市場（29 §1.1）：conditions 決定命中；parent 由推導不由欄位", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "derived_parent_market_id", comment: "? 推導快取不是權威欄位（29 §1.5(a)）：conditions 變更即重算；不得手動指定"
    t.string "handle", null: false
    t.boolean "is_primary", default: false, null: false, comment: "primary market：恰含一國、不可刪（29 §1.1）。29 原文欄名 primary＝MySQL 保留字，改 is_primary"
    t.string "market_type", limit: 32, default: "region", null: false, comment: "region|company_location|location|channel|none（29 §1.1 MarketType；實測 Market conditions 四類＝Regions/POS locations/Company locations/Channels）"
    t.string "name", null: false
    t.virtual "primary_guard", type: :integer, as: "if(`is_primary`,1,NULL)", stored: true
    t.bigint "shop_id", null: false
    t.string "status", limit: 16, default: "active", null: false, comment: "active|draft（實測 2026-08-31：New market 表單原生 select 恰兩值 DRAFT/ACTIVE）"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "handle"], name: "uq_markets_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_markets_tenant_id", unique: true
    t.index ["shop_id", "primary_guard"], name: "uq_markets_single_primary", unique: true
    t.index ["shop_id", "status"], name: "ix_markets_status"
  end

  create_table "media", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "商品媒體 metadata；檔案本體走 object storage", force: :cascade do |t|
    t.string "alt_text", limit: 512
    t.bigint "byte_size"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "external_host", limit: 16, comment: "外嵌影片平台（youtube／vimeo，小寫；對齊 Liquid external_video.host 值域）"
    t.string "external_id", limit: 32, comment: "平台的影片 ID（string——YouTube 非數字）"
    t.bigint "file_id"
    t.integer "height"
    t.string "media_type", limit: 32, default: "image", null: false
    t.integer "position", null: false
    t.bigint "product_id", null: false
    t.bigint "product_variant_id"
    t.bigint "shop_id", null: false
    t.string "source_url", limit: 2048, null: false
    t.string "status", limit: 32, default: "uploaded", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["shop_id", "external_host", "external_id"], name: "ix_media_external_ref"
    t.index ["shop_id", "file_id"], name: "ix_media_file_id"
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
    t.boolean "buyer_accepts_marketing", default: false, null: false, comment: "成單當下的行銷勾選快照（checkout 同名欄傳導；對位 Order API）"
    t.string "buyer_jurisdiction", limit: 8, null: false
    t.datetime "canceled_at"
    t.bigint "captured_total_cents", default: 0, null: false, comment: "Σ success 的 sale/capture 交易額（16 F5.1 軟上限的分母；nightly 與明細對帳）"
    t.bigint "checkout_id"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "HKD", null: false
    t.bigint "customer_id"
    t.bigint "discount_cents", default: 0, null: false
    t.string "email", limit: 320
    t.string "financial_status", limit: 32, default: "pending", null: false
    t.string "fulfillment_status", limit: 32, default: "unfulfilled", null: false
    t.string "locale_snapshot", limit: 35, comment: "訂單成立當下的顧客語言（BCP-47；寫入者在 M3）"
    t.integer "lock_version", default: 0, null: false
    t.string "name", limit: 64, null: false
    t.text "note"
    t.bigint "order_number", null: false
    t.string "presentment_currency", limit: 3, default: "HKD", null: false
    t.bigint "presentment_total_cents", default: 0, null: false
    t.datetime "processed_at"
    t.bigint "refunded_total_cents", default: 0, null: false, comment: "Σ 已退金額（16 F5.1 條件式 UPDATE 的累計欄；不加 DB CHECK——軟上限）"
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
    t.string "template_suffix"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "handle"], name: "uq_pages_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_pages_tenant_id", unique: true
    t.index ["shop_id", "published_at", "id"], name: "ix_pages_published_at_id"
  end

  create_table "platform_apps", primary_key: "handle", id: { type: :string, limit: 64, comment: "本尊 App.handle（String／\"Handle of the app.\"）；我方作自然主鍵故 NOT NULL" }, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "平台 app 字典（跨租戶共用；非租戶資料，無 shop_id——鐵律 2 平台字典表）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "developer_name", comment: "本尊 App.developerName（String／\"The name of the app developer.\"）"
    t.boolean "shopify_developed", default: false, null: false, comment: "本尊 App.shopifyDeveloped（Boolean!／\"Whether the app was developed by Shopify.\"）；我方文檔慣稱「第一方」"
    t.string "title", null: false, comment: "本尊 App.title（String!／\"Name of the app.\"）"
    t.datetime "updated_at", null: false
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

  create_table "price_lists", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "catalog 的價格表（本尊 PriceList；百分比層，變體固定價隨 M5 另表）", force: :cascade do |t|
    t.integer "adjustment_basis_points", default: 0, null: false, comment: "調整幅度（basis points，1bp=0.01%）；decrease 側數學上限 10000（低於零價不存在）"
    t.string "adjustment_type", limit: 24, null: false, comment: "percentage_decrease／percentage_increase（本尊 PriceListAdjustmentType 恰二值）"
    t.string "compare_at_mode", limit: 16, default: "adjusted", null: false, comment: "adjusted／nullify（本尊 PriceListCompareAtMode；admin 預設開 Include compare-at price ⇒ adjusted，82 §9.5c）"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false, comment: "固定價所用幣別（官方 currency!）"
    t.string "name", null: false, comment: "顯示名（官方 priceListCreate name!）"
    t.bigint "sales_catalog_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_price_lists_tenant_id", unique: true
    t.index ["shop_id", "sales_catalog_id"], name: "uq_price_lists_catalog", unique: true
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

  create_table "product_tags", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "商品標籤正規化表（13 §F4.4）：display 顯示、key 比對", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.bigint "shop_id", null: false
    t.string "tag_display", null: false, comment: "商家原字串（同 key 只留首次寫入的）"
    t.string "tag_key", null: false, collation: "utf8mb4_bin", comment: "正規化鍵（Tags::Normalize 唯一實作）；比對一律用這欄"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "product_id", "tag_key"], name: "ix_product_tags_product"
    t.index ["shop_id", "tag_key", "product_id"], name: "uq_product_tags_key_product", unique: true
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
    t.datetime "media_updated_at", comment: "媒體（含衍生尺寸與檔案層 alt）最後變動時刻（cache stamp）"
    t.string "product_type"
    t.datetime "publications_updated_at", comment: "發布狀態最後變動時刻（cache stamp；寫入者隨第 12 包）"
    t.string "seo_description", limit: 320
    t.string "seo_title", limit: 70
    t.bigint "shipping_profile_id", comment: "自訂運送設定檔歸屬；NULL＝General 補集（85 §2）"
    t.bigint "shop_id", null: false
    t.string "status", limit: 32, default: "draft", null: false
    t.json "tags", default: -> { "(json_array())" }, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.datetime "variants_updated_at", comment: "變體樹最後變動時刻（cache stamp；null＝立欄前未變動過）"
    t.string "vendor"
    t.index ["shipping_profile_id"], name: "fk_rails_d39e4d6fd1"
    t.index ["shop_id", "created_at", "id"], name: "ix_products_created_at_id"
    t.index ["shop_id", "handle"], name: "uq_products_handle", unique: true
    t.index ["shop_id", "id"], name: "uq_products_tenant_id", unique: true
    t.index ["shop_id", "shipping_profile_id"], name: "ix_products_shipping_profile"
    t.index ["shop_id", "status", "created_at"], name: "ix_products_status_created_at"
  end

  create_table "psp_webhook_events", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "PSP webhook 收件匣（驗簽後收錄；event_id 冪等；消費在 G6-1b）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_id", null: false, comment: "PSP 側事件 id（冪等鍵；重複投遞被 UNIQUE 擋）"
    t.string "event_type", null: false, comment: "如 payment_intent.succeeded（值域＝PSP 側，不做 enum）"
    t.json "payload", null: false, comment: "原始事件 JSON（? 金額欄位消費時走 Money.from_psp_amount）"
    t.datetime "processed_at"
    t.string "provider", null: false, comment: "pack 代碼（airwallex／paypal）"
    t.bigint "shop_id", null: false
    t.string "status", default: "received", null: false, comment: "received|processed|failed（model 驗）"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_psp_webhook_events_tenant_id", unique: true
    t.index ["shop_id", "provider", "event_id"], name: "uq_psp_webhook_events_event", unique: true
    t.index ["shop_id", "status"], name: "ix_psp_webhook_events_status"
  end

  create_table "publications", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "銷售管道在本店的發布容器（Publication）", force: :cascade do |t|
    t.boolean "auto_publish", default: true, null: false, comment: "新建的 publishable 是否自動納入本管道"
    t.string "channel_handle", limit: 64, null: false, comment: "管道識別（online_store／point_of_sale／agentic…）"
    t.datetime "created_at", null: false
    t.string "name", null: false, comment: "顯示名（線上商店／門市 POS／代理式）"
    t.string "operation_status", limit: 16, comment: "進行中的發布操作：created／active／complete；NULL＝無（本尊 ResourceOperationStatus 恰三值，無 failed）"
    t.bigint "sales_catalog_id", comment: "三層 AND 的第三層；M5 建 catalogs 時補外鍵"
    t.bigint "shop_id", null: false
    t.boolean "supports_bundles", default: true, null: false, comment: "本管道是否支援組合商品（bundle）"
    t.boolean "supports_combined_listings", default: true, null: false, comment: "本管道是否支援 combined listing"
    t.boolean "supports_future_publishing", default: true, null: false, comment: "本管道是否支援排程發布"
    t.boolean "supports_publication_for_unlisted_products", default: true, null: false, comment: "本管道是否接受 UNLISTED 狀態的商品"
    t.boolean "supports_subscriptions", default: true, null: false, comment: "本管道是否支援訂閱商品"
    t.boolean "supports_variant_fixed_bundles", default: true, null: false, comment: "本管道是否支援變體固定組合"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "channel_handle"], name: "uq_publications_channel", unique: true
    t.index ["shop_id", "id"], name: "uq_publications_tenant_id", unique: true
    t.index ["shop_id", "sales_catalog_id"], name: "fk_publications_sales_catalog_id"
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

  create_table "sales_catalogs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "本尊 Catalog interface 的我方對位：publication 與 price list 的容器", force: :cascade do |t|
    t.boolean "auto_include_new_products", default: true, null: false, comment: "新商品是否自動納入本 catalog（本尊表單 Automatically include new products，預設開）"
    t.string "catalog_type", limit: 24, default: "app", null: false, comment: "app／market／company_location（本尊 CatalogType；none 不落庫）"
    t.datetime "created_at", null: false
    t.bigint "shop_id", null: false
    t.string "status", limit: 16, default: "active", null: false, comment: "active／archived／draft（本尊 CatalogStatus 三值；admin UI 只曝露前二）"
    t.string "title", null: false, comment: "顯示名的權威來源（本尊 Publication.name 已 deprecated → Catalog.title）"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "catalog_type", "status"], name: "ix_sales_catalogs_type"
    t.index ["shop_id", "id"], name: "uq_sales_catalogs_tenant_id", unique: true
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
    t.bigint "max_transit_seconds"
    t.bigint "maximum_order_cents"
    t.integer "maximum_weight_grams"
    t.bigint "min_transit_seconds", comment: "運達區間下限（秒；85 §3 base64 JSON {min,max}）；與 max 同 NULL＝None"
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

  create_table "shop_payment_methods", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "manual 付款方式（86 §3；PSP 方式不落表——15-F4.2 capability 查詢）", force: :cascade do |t|
    t.boolean "active", default: true, null: false, comment: "停用不刪列（86 §3 Deactivate 語義）"
    t.text "additional_details", comment: "checkout 選擇付款方式時顯示（86 §3 helper①）"
    t.virtual "builtin_guard", type: :string, limit: 32, comment: "內建型別每店唯一的物化 guard（custom 多列合法）", as: "if((`method_type` = _utf8mb4'custom'),NULL,`method_type`)", stored: true
    t.datetime "created_at", null: false
    t.string "method_type", limit: 32, null: false, comment: "恰四值 bank_deposit/money_order/cash_on_delivery/custom（86 §3 DOM）"
    t.string "name", null: false, comment: "顯示名；內建型別＝正典名，custom＝商家自訂（保留名單擋）"
    t.text "payment_instructions", comment: "下單確認頁顯示（86 §3 helper②）"
    t.integer "position", default: 0, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "active", "position"], name: "ix_shop_payment_methods_active_position"
    t.index ["shop_id", "builtin_guard"], name: "uq_shop_payment_methods_builtin", unique: true
    t.index ["shop_id", "id"], name: "uq_shop_payment_methods_tenant_id", unique: true
    t.index ["shop_id", "name"], name: "uq_shop_payment_methods_name", unique: true
  end

  create_table "shop_payment_providers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "PSP provider 的租戶側憑證與偏好（G6-3 前半；祕密欄一律 AR encryption 密文，37 §6.3）", force: :cascade do |t|
    t.text "api_secret", comment: "? AR encryption 密文（Airwallex API key／PayPal client secret）；UI 永不回讀明文"
    t.string "api_secret_fingerprint", limit: 16, comment: "SHA-256 前 16 hex（37 §6.3：UI 只顯示指紋）；祕密未設時 NULL"
    t.json "available_methods", default: -> { "(json_array())" }, null: false, comment: "PSP capability API 回報的 active oneoff 方法名快取（原樣 name；15-F4.2 條件 2）"
    t.datetime "capabilities_synced_at", comment: "上次成功同步 capability 的時點；NULL＝從未成功（UI 顯示未同步態）"
    t.string "client_id", comment: "非祕密識別（Airwallex x-client-id／PayPal client_id）；明文可回讀"
    t.datetime "created_at", null: false
    t.json "enabled_methods", default: -> { "(json_array())" }, null: false, comment: "商家啟用的 method code 白名單（86 詳情頁逐方法 toggle 的落點；空陣列＝尚未挑選）"
    t.string "environment", default: "sandbox", null: false, comment: "sandbox|production（limits psp_credentials.environment_enum；跨環境禁用同 carrier 慣例）"
    t.string "provider", null: false, comment: "pack 代碼（值域＝config/limits.yml psp_packs 的鍵；model 驗 inclusion）"
    t.bigint "shop_id", null: false
    t.string "status", default: "inactive", null: false, comment: "inactive|active；本切片恆 inactive——activation 狀態機（86 §1 一家 credit-card provider）隨 G6-3"
    t.datetime "updated_at", null: false
    t.string "webhook_id", comment: "非祕密識別（PayPal webhook_id，驗簽輸入之一；Airwallex 不用）"
    t.text "webhook_secret", comment: "? AR encryption 密文（Airwallex webhook HMAC secret；PayPal 不用，留空）"
    t.string "webhook_secret_fingerprint", limit: 16, comment: "同上"
    t.index ["shop_id", "id"], name: "uq_shop_payment_providers_tenant_id", unique: true
    t.index ["shop_id", "provider"], name: "uq_shop_payment_providers_provider", unique: true
  end

  create_table "shops", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "租戶根；依規格明確豁免 shop_id", force: :cascade do |t|
    t.integer "cart_item_limit", default: 50, null: false, comment: "cart 總件數上限（A2；建議值 50＝limits cart.item_limit_suggested）"
    t.boolean "cart_item_limit_enabled", default: true, null: false, comment: "上限開關（limits cart.item_limit_enabled_default）"
    t.bigint "catalog_version", default: 1, null: false, comment: "目錄級版本（市場／價格表變動時 bump；寫入者隨第 32 包）"
    t.datetime "created_at", null: false
    t.string "custom_domain", limit: 253
    t.json "feature_flags", default: -> { "(json_object())" }, null: false
    t.string "name", null: false
    t.bigint "order_counter", default: 1000, null: false, comment: "每店訂單連號計數器（15-F5；取號＝交易內 +1 後讀回，鎖序首位）"
    t.string "payment_capture_method", limit: 40, default: "automatic_at_checkout", null: false, comment: "請款模式（limits capture.modes；86 §2 modal 三值 UI＋enum 四值保留）"
    t.string "plan", limit: 32, default: "basic", null: false
    t.string "sender_email", limit: 320, comment: "通知信 From 位址（89 §6；NULL＝未設定走平台預設）"
    t.boolean "split_shipping_enabled", default: true, null: false, comment: "split shipping（85 §5.3 Manage split shipping；預設 On）"
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
    t.integer "lock_version", default: 0, null: false
    t.bigint "shop_id", null: false
    t.string "template_type", limit: 64, null: false
    t.bigint "theme_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_templates_tenant_id", unique: true
    t.index ["shop_id", "theme_id", "key"], name: "uq_templates_theme_id_key", unique: true
    t.index ["shop_id", "theme_id"], name: "ix_templates_theme_id"
  end

  create_table "theme_file_overlays", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "主題檔案 DB 覆寫層（code editor）", force: :cascade do |t|
    t.text "content", size: :medium, null: false
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "path", limit: 512, null: false, comment: "主題相對路徑（top_dir/檔名）"
    t.bigint "shop_id", null: false
    t.bigint "theme_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_theme_file_overlays_tenant_id", unique: true
    t.index ["shop_id", "theme_id", "path"], name: "uq_theme_file_overlays_path", unique: true
    t.index ["theme_id"], name: "fk_rails_89a5ce9fba"
  end

  create_table "theme_import_reports", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "主題 zip 匯入報告（99 §5；含相容掃描）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_code", limit: 40, comment: "失敗碼（INVALID_ZIP 等——對齊官方碼形）"
    t.json "report", null: false, comment: "相容掃描（檔數/警告/未知 tag/Liquid 錯誤）"
    t.bigint "shop_id", null: false
    t.string "status", limit: 12, null: false, comment: "ok / failed"
    t.bigint "theme_id", comment: "成功建立的主題；失敗為 NULL"
    t.string "zip_filename", null: false
    t.index ["shop_id", "created_at"], name: "ix_theme_import_reports_created"
    t.index ["shop_id", "id"], name: "uq_theme_import_reports_tenant_id", unique: true
  end

  create_table "theme_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "主題全域 settings_data", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.json "settings", default: -> { "(json_object())" }, null: false
    t.bigint "shop_id", null: false
    t.bigint "theme_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "id"], name: "uq_theme_settings_tenant_id", unique: true
    t.index ["shop_id", "theme_id"], name: "uq_theme_settings_theme_id", unique: true
  end

  create_table "themes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "主題庫項目；主題是資料而非可執行程式碼", force: :cascade do |t|
    t.string "content_checksum", limit: 64, comment: "匯入主題的內容 SHA-256（storage/themes/{checksum}；first_party 為 NULL）"
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

  create_table "url_redirects", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "路徑級重導（62 §B.5）；from/to 為無前綴正規路徑", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "from_path", limit: 512, null: false
    t.bigint "shop_id", null: false
    t.string "source", limit: 32, null: false
    t.integer "status_code", default: 301, null: false
    t.string "to_path", limit: 512, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "from_path"], name: "uq_url_redirects_from_path", unique: true
    t.index ["shop_id", "to_path"], name: "ix_url_redirects_to_path"
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

  create_table "webhook_deliveries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "webhook 投遞紀錄（7 天除錯窗——18 F4）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "event_id", limit: 36, null: false
    t.string "response_excerpt", limit: 1024, comment: "截斷回應（讀取上限 64KB、存 1KB）"
    t.bigint "shop_id", null: false
    t.string "state", limit: 16, null: false, comment: "sent | failed"
    t.integer "status_code"
    t.bigint "webhook_subscription_id", null: false
    t.index ["created_at"], name: "ix_webhook_deliveries_purge"
    t.index ["shop_id", "id"], name: "uq_webhook_deliveries_tenant_id", unique: true
    t.index ["shop_id", "webhook_subscription_id", "created_at"], name: "ix_webhook_deliveries_sub"
    t.index ["webhook_subscription_id"], name: "fk_rails_c0876b906b"
  end

  create_table "webhook_subscriptions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", comment: "對外 webhook 訂閱（28 §15／18 F4）", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "failure_count", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "secret", limit: 64, null: false, comment: "per-subscription HMAC 簽章密鑰"
    t.bigint "shop_id", null: false
    t.string "status", limit: 16, default: "active", null: false
    t.string "topic", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.string "url", limit: 1024, null: false
    t.index ["shop_id", "id"], name: "uq_webhook_subscriptions_tenant_id", unique: true
    t.index ["shop_id", "topic", "status"], name: "ix_webhook_subscriptions_topic"
  end

  add_foreign_key "api_tokens", "shops", name: "fk_api_tokens_shop"
  add_foreign_key "api_tokens", "staff_members", name: "fk_api_tokens_staff_member_id"
  add_foreign_key "app_installations", "platform_apps", column: "app_handle", primary_key: "handle", name: "fk_app_installations_app_handle"
  add_foreign_key "app_installations", "shops", name: "fk_app_installations_shop"
  add_foreign_key "article_comments", "articles"
  add_foreign_key "articles", "blogs"
  add_foreign_key "cart_line_items", "carts", name: "fk_cart_line_items_cart", on_delete: :cascade
  add_foreign_key "cart_line_items", "product_variants", name: "fk_cart_line_items_variant", on_delete: :cascade
  add_foreign_key "carts", "shops", name: "fk_carts_shop"
  add_foreign_key "channels", "app_installations", column: ["shop_id", "app_installation_id"], primary_key: ["shop_id", "id"], name: "fk_channels_app_installation_id"
  add_foreign_key "channels", "publications", column: ["shop_id", "publication_id"], primary_key: ["shop_id", "id"], name: "fk_channels_publication_id"
  add_foreign_key "channels", "shops", name: "fk_channels_shop"
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
  add_foreign_key "customer_marketing_consents", "customers"
  add_foreign_key "customer_sessions", "customers"
  add_foreign_key "customers", "shops", name: "fk_customers_shop"
  add_foreign_key "daily_rollups", "shops"
  add_foreign_key "discount_applications", "discounts", column: ["shop_id", "discount_id"], primary_key: ["shop_id", "id"], name: "fk_discount_applications_discount_id"
  add_foreign_key "discount_applications", "line_items", column: ["shop_id", "line_item_id"], primary_key: ["shop_id", "id"], name: "fk_discount_applications_line_item_id"
  add_foreign_key "discount_applications", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_discount_applications_order_id"
  add_foreign_key "discount_applications", "shops", name: "fk_discount_applications_shop"
  add_foreign_key "discount_redemptions", "discounts"
  add_foreign_key "discounts", "shops", name: "fk_discounts_shop"
  add_foreign_key "domains", "shops", name: "fk_domains_shop"
  add_foreign_key "einvoice_allowances", "einvoices", column: ["shop_id", "einvoice_id"], primary_key: ["shop_id", "id"], name: "fk_einvoice_allowances_einvoice_id"
  add_foreign_key "einvoice_allowances", "shops", name: "fk_einvoice_allowances_shop"
  add_foreign_key "einvoices", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_einvoices_order_id"
  add_foreign_key "einvoices", "shops", name: "fk_einvoices_shop"
  add_foreign_key "event_deliveries", "event_outbox", column: ["shop_id", "event_id"], primary_key: ["shop_id", "event_id"], name: "fk_event_deliveries_event", on_delete: :cascade
  add_foreign_key "event_deliveries", "shops", name: "fk_event_deliveries_shop"
  add_foreign_key "event_outbox", "shops", name: "fk_event_outbox_shop"
  add_foreign_key "events", "orders", column: ["shop_id", "order_id"], primary_key: ["shop_id", "id"], name: "fk_events_order_id"
  add_foreign_key "events", "shops", name: "fk_events_shop"
  add_foreign_key "events", "staff_members", name: "fk_events_staff_member_id"
  add_foreign_key "file_usages", "files", column: ["shop_id", "file_id"], primary_key: ["shop_id", "id"], name: "fk_file_usages_file_id"
  add_foreign_key "file_usages", "shops", name: "fk_file_usages_shop"
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
  add_foreign_key "market_regions", "markets", name: "fk_market_regions_market", on_delete: :cascade
  add_foreign_key "market_web_presence_locales", "market_web_presences", name: "fk_mwpl_presence", on_delete: :cascade
  add_foreign_key "market_web_presence_locales", "shop_locales", column: ["shop_id", "locale_tag"], primary_key: ["shop_id", "locale_tag"], name: "fk_mwpl_shop_locale"
  add_foreign_key "market_web_presences", "domains", name: "fk_mwp_domain"
  add_foreign_key "market_web_presences", "markets", name: "fk_mwp_market", on_delete: :cascade
  add_foreign_key "market_web_presences", "shop_locales", column: ["shop_id", "default_shop_locale"], primary_key: ["shop_id", "locale_tag"], name: "fk_mwp_default_locale"
  add_foreign_key "markets", "shops", name: "fk_markets_shop"
  add_foreign_key "media", "files", column: ["shop_id", "file_id"], primary_key: ["shop_id", "id"], name: "fk_media_file_id"
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
  add_foreign_key "price_lists", "sales_catalogs", column: ["shop_id", "sales_catalog_id"], primary_key: ["shop_id", "id"], name: "fk_price_lists_sales_catalog"
  add_foreign_key "price_lists", "shops", name: "fk_price_lists_shop"
  add_foreign_key "product_options", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_product_options_product_id"
  add_foreign_key "product_options", "shops", name: "fk_product_options_shop"
  add_foreign_key "product_variant_option_values", "option_values", column: ["shop_id", "product_option_id", "option_value_id"], primary_key: ["shop_id", "product_option_id", "id"], name: "fk_pvov_value"
  add_foreign_key "product_variant_option_values", "product_options", column: ["shop_id", "product_id", "product_option_id"], primary_key: ["shop_id", "product_id", "id"], name: "fk_pvov_option"
  add_foreign_key "product_variant_option_values", "product_variants", column: ["shop_id", "product_id", "product_variant_id"], primary_key: ["shop_id", "product_id", "id"], name: "fk_pvov_variant"
  add_foreign_key "product_variant_option_values", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_pvov_product"
  add_foreign_key "product_variant_option_values", "shops", name: "fk_pvov_shop"
  add_foreign_key "product_variants", "products", column: ["shop_id", "product_id"], primary_key: ["shop_id", "id"], name: "fk_product_variants_product_id"
  add_foreign_key "product_variants", "shops", name: "fk_product_variants_shop"
  add_foreign_key "products", "shipping_profiles", on_delete: :nullify
  add_foreign_key "products", "shops", name: "fk_products_shop"
  add_foreign_key "psp_webhook_events", "shops", name: "fk_psp_webhook_events_shop"
  add_foreign_key "publications", "sales_catalogs", column: ["shop_id", "sales_catalog_id"], primary_key: ["shop_id", "id"], name: "fk_publications_sales_catalog_id"
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
  add_foreign_key "sales_catalogs", "shops", name: "fk_sales_catalogs_shop"
  add_foreign_key "segments", "shops", name: "fk_segments_shop"
  add_foreign_key "sessions", "staff_members", name: "fk_sessions_staff_member_id"
  add_foreign_key "shipping_profiles", "shops", name: "fk_shipping_profiles_shop"
  add_foreign_key "shipping_rates", "shipping_zones", column: ["shop_id", "shipping_zone_id"], primary_key: ["shop_id", "id"], name: "fk_shipping_rates_shipping_zone_id"
  add_foreign_key "shipping_rates", "shops", name: "fk_shipping_rates_shop"
  add_foreign_key "shipping_zones", "shipping_profiles", column: ["shop_id", "shipping_profile_id"], primary_key: ["shop_id", "id"], name: "fk_shipping_zones_shipping_profile_id"
  add_foreign_key "shipping_zones", "shops", name: "fk_shipping_zones_shop"
  add_foreign_key "shop_locales", "platform_locales", column: "locale_tag", primary_key: "tag", name: "fk_shop_locales_locale"
  add_foreign_key "shop_locales", "shops", name: "fk_shop_locales_shop"
  add_foreign_key "shop_payment_providers", "shops", name: "fk_shop_payment_providers_shop"
  add_foreign_key "tax_settings", "shops", name: "fk_tax_settings_shop"
  add_foreign_key "templates", "shops", name: "fk_templates_shop"
  add_foreign_key "templates", "themes", column: ["shop_id", "theme_id"], primary_key: ["shop_id", "id"], name: "fk_templates_theme_id"
  add_foreign_key "theme_file_overlays", "themes"
  add_foreign_key "theme_settings", "shops", name: "fk_theme_settings_shop"
  add_foreign_key "theme_settings", "themes", column: ["shop_id", "theme_id"], primary_key: ["shop_id", "id"], name: "fk_theme_settings_theme_id"
  add_foreign_key "themes", "shops", name: "fk_themes_shop"
  add_foreign_key "translation_status", "shops", name: "fk_translation_status_shop"
  add_foreign_key "translations", "platform_locales", column: "locale_tag", primary_key: "tag", name: "fk_translations_locale"
  add_foreign_key "translations", "shops", name: "fk_translations_shop"
  add_foreign_key "user_store_assignments", "roles", name: "fk_usa_role_id"
  add_foreign_key "user_store_assignments", "shops", name: "fk_usa_shop_id"
  add_foreign_key "user_store_assignments", "staff_members", name: "fk_usa_staff_member_id"
  add_foreign_key "webhook_deliveries", "webhook_subscriptions", on_delete: :cascade
end
