# frozen_string_literal: true

# M0 的完整多租戶資料地基。
#
# 為什麼：docs/research/06-data-model.md §7 列出的 47 個表名是 demo
# 的相容骨幹；docs/specs/11-production-baseline.md §2 另要求
# idempotency_keys。shops 是 tenant root，其他表都透過同一 helper 保證
# shop_id 為第一個顯式欄位、(shop_id, id) 可被 composite FK 引用，且不會
# 意外建立只靠全域 id 的 business FK。
#
# @see docs/research/06-data-model.md §1, §7
# @see docs/specs/11-production-baseline.md §2
# @see docs/specs/12-spec-tenancy-auth-permissions.md F4
class M0CreateCoreSchema < ActiveRecord::Migration[8.1]
  DOCUMENTED_TABLES = %i[
    shops staff_members roles role_permissions products product_options
    option_values product_variants media collections collection_products
    collection_rules inventory_items locations inventory_levels
    inventory_adjustments customers customer_addresses checkouts orders
    line_items order_transactions fulfillment_orders fulfillments refunds
    refund_line_items events discounts discount_applications themes templates
    theme_settings menus menu_items pages files shipping_profiles shipping_zones
    shipping_rates tax_settings notification_templates metafield_definitions
    metafields segments event_outbox sessions api_tokens
  ].freeze

  TENANT_TABLES = ((DOCUMENTED_TABLES - [ :shops ]) + [ :idempotency_keys ]).freeze

  # 每筆關聯都同時比對 shop_id，阻止有效的外店 id 被接到本店資料。
  TENANT_RELATIONSHIPS = [
    %i[staff_members roles role_id],
    %i[role_permissions roles role_id],
    %i[sessions staff_members staff_member_id],
    %i[api_tokens staff_members staff_member_id],
    %i[product_options products product_id],
    %i[option_values product_options product_option_id],
    %i[product_variants products product_id],
    %i[media products product_id],
    %i[media product_variants product_variant_id],
    %i[collection_products collections collection_id],
    %i[collection_products products product_id],
    %i[collection_rules collections collection_id],
    %i[inventory_items product_variants product_variant_id],
    %i[inventory_levels inventory_items inventory_item_id],
    %i[inventory_levels locations location_id],
    %i[inventory_adjustments inventory_levels inventory_level_id],
    %i[customer_addresses customers customer_id],
    %i[checkouts customers customer_id],
    %i[orders customers customer_id],
    %i[orders checkouts checkout_id],
    %i[line_items orders order_id],
    %i[line_items product_variants product_variant_id],
    %i[order_transactions orders order_id],
    %i[order_transactions order_transactions parent_transaction_id],
    %i[fulfillment_orders orders order_id],
    %i[fulfillment_orders locations location_id],
    %i[fulfillments fulfillment_orders fulfillment_order_id],
    %i[refunds orders order_id],
    %i[refunds order_transactions order_transaction_id],
    %i[refund_line_items refunds refund_id],
    %i[refund_line_items line_items line_item_id],
    %i[events orders order_id],
    %i[events staff_members staff_member_id],
    %i[discount_applications orders order_id],
    %i[discount_applications discounts discount_id],
    %i[discount_applications line_items line_item_id],
    %i[templates themes theme_id],
    %i[theme_settings themes theme_id],
    %i[menu_items menus menu_id],
    %i[menu_items menu_items parent_menu_item_id],
    %i[shipping_zones shipping_profiles shipping_profile_id],
    %i[shipping_rates shipping_zones shipping_zone_id],
    %i[metafields metafield_definitions metafield_definition_id]
  ].freeze

  # 建立 docs/research/06 §7 的完整表集及基線冪等表。
  #
  # @return [void]
  # @note 只描述資料庫結構，不執行外部 IO。
  def change
    create_shops
    create_identity_tables
    create_catalog_tables
    create_inventory_tables
    create_customer_tables
    create_commerce_tables
    create_discount_tables
    create_content_tables
    create_settings_tables
    create_extensibility_tables
    add_tenant_relationships
  end

  private

  # 建立唯一的 tenant root。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §1
  def create_shops
    create_table :shops, comment: "租戶根；依規格明確豁免 shop_id" do |t|
      t.string :name, null: false, limit: 255
      t.string :subdomain, null: false, limit: 63
      t.string :custom_domain, limit: 253
      t.string :status, null: false, default: "active", limit: 32
      t.string :store_currency, null: false, default: "TWD", limit: 3
      t.string :timezone, null: false, default: "Asia/Taipei", limit: 64
      t.string :plan, null: false, default: "basic", limit: 32
      t.json :feature_flags, null: false, default: -> { "(JSON_OBJECT())" }
      t.timestamps null: false
    end

    add_index :shops, :subdomain, unique: true, name: "uq_shops_subdomain"
    add_index :shops, :custom_domain, unique: true, name: "uq_shops_custom_domain"
    add_index :shops, :status, name: "ix_shops_status"
  end

  # 建立 staff、角色、session、API token 與冪等紀錄。
  #
  # @return [void]
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F2-F3
  def create_identity_tables
    create_tenant_table :roles, comment: "店內角色" do |t|
      t.string :name, null: false, limit: 100
      t.string :description, limit: 255
      t.boolean :system, null: false, default: false
    end
    tenant_index :roles, :name, unique: true

    create_tenant_table :staff_members, comment: "店員身分與認證資料" do |t|
      t.bigint :role_id
      t.string :email, null: false, limit: 320
      t.string :password_digest
      t.string :status, null: false, default: "invited", limit: 32
      t.boolean :owner, null: false, default: false
      t.datetime :invited_at
      t.datetime :deactivated_at
    end
    tenant_index :staff_members, :role_id
    tenant_index :staff_members, :email, unique: true
    tenant_index :staff_members, %i[status id]

    create_tenant_table :role_permissions, comment: "角色的 permission key" do |t|
      t.bigint :role_id, null: false
      t.string :permission_key, null: false, limit: 100
    end
    tenant_index :role_permissions, :role_id
    tenant_index :role_permissions, %i[role_id permission_key], unique: true

    create_tenant_table :sessions, comment: "可撤銷的 admin DB session" do |t|
      t.bigint :staff_member_id, null: false
      t.string :token_digest, null: false, limit: 64
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 1024
      t.datetime :last_active_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
    end
    tenant_index :sessions, :staff_member_id
    tenant_index :sessions, :token_digest, unique: true
    tenant_index :sessions, %i[staff_member_id revoked_at]
    tenant_index :sessions, :expires_at

    create_tenant_table :api_tokens, comment: "外部整合的雜湊 access token" do |t|
      t.bigint :staff_member_id
      t.string :name, null: false, limit: 255
      t.string :token_digest, null: false, limit: 64
      t.json :scopes, null: false, default: -> { "(JSON_ARRAY())" }
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
    end
    tenant_index :api_tokens, :staff_member_id
    tenant_index :api_tokens, :token_digest, unique: true
    tenant_index :api_tokens, %i[revoked_at expires_at]

    create_tenant_table :idempotency_keys, comment: "寫路徑冪等結果快取" do |t|
      t.string :key, null: false, limit: 255
      t.string :request_digest, limit: 64
      t.string :response_digest, limit: 64
      t.text :response_body, size: :long
      t.integer :status_code
      t.string :state, null: false, default: "processing", limit: 32
      t.string :resource_type, limit: 64
      t.bigint :resource_id
      t.datetime :expires_at
    end
    tenant_index :idempotency_keys, :key, unique: true
    tenant_index :idempotency_keys, %i[state expires_at]
    tenant_index :idempotency_keys, %i[resource_type resource_id]
  end

  # 建立商品、變體、媒體與系列資料。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §2
  # @see docs/specs/13-spec-products-inventory-media.md
  def create_catalog_tables
    create_tenant_table :products, comment: "商品主檔" do |t|
      t.string :title, null: false, limit: 255
      t.string :handle, null: false, limit: 255
      t.text :description_html, null: false, size: :medium
      t.string :vendor, limit: 255
      t.string :product_type, limit: 255
      t.string :status, null: false, default: "draft", limit: 32
      t.string :category_gid, limit: 255
      t.json :tags, null: false, default: -> { "(JSON_ARRAY())" }
      t.string :seo_title, limit: 70
      t.string :seo_description, limit: 320
      t.datetime :published_at
      t.integer :lock_version, null: false, default: 0
    end
    tenant_index :products, :handle, unique: true
    tenant_index :products, %i[created_at id]
    tenant_index :products, %i[status created_at]
    tenant_index :products, %i[published_at id]

    create_tenant_table :product_options, comment: "商品選項，配額由 limits.yml 管理" do |t|
      t.bigint :product_id, null: false
      t.string :name, null: false, limit: 255
      t.integer :position, null: false
    end
    tenant_index :product_options, :product_id
    tenant_index :product_options, %i[product_id position], unique: true
    tenant_index :product_options, %i[product_id name], unique: true

    create_tenant_table :option_values, comment: "商品選項值" do |t|
      t.bigint :product_option_id, null: false
      t.string :value, null: false, limit: 255
      t.integer :position, null: false
    end
    tenant_index :option_values, :product_option_id
    tenant_index :option_values, %i[product_option_id position], unique: true
    tenant_index :option_values, %i[product_option_id value], unique: true

    create_tenant_table :product_variants, comment: "商品變體與 integer-cents 定價" do |t|
      t.bigint :product_id, null: false
      t.string :title, null: false, limit: 255
      t.string :sku, limit: 255
      t.string :barcode, limit: 255
      t.bigint :price_cents, null: false, default: 0
      t.bigint :compare_at_price_cents
      t.bigint :cost_cents
      t.string :currency, null: false, default: "TWD", limit: 3
      t.integer :position, null: false
      t.boolean :taxable, null: false, default: true
      t.boolean :requires_shipping, null: false, default: true
      t.string :inventory_policy, null: false, default: "deny", limit: 16
      t.integer :weight_grams, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
    end
    tenant_index :product_variants, :product_id
    tenant_index :product_variants, %i[product_id position], unique: true
    tenant_index :product_variants, :sku, unique: true
    tenant_index :product_variants, :barcode

    create_tenant_table :media, comment: "商品媒體 metadata；檔案本體走 object storage" do |t|
      t.bigint :product_id, null: false
      t.bigint :product_variant_id
      t.string :media_type, null: false, default: "image", limit: 32
      t.string :source_url, null: false, limit: 2048
      t.string :alt_text, limit: 512
      t.integer :position, null: false
      t.integer :width
      t.integer :height
      t.bigint :byte_size
      t.integer :duration_ms
      t.string :status, null: false, default: "ready", limit: 32
    end
    tenant_index :media, :product_id
    tenant_index :media, :product_variant_id
    tenant_index :media, %i[product_id position], unique: true

    create_tenant_table :collections, comment: "手動或智慧系列" do |t|
      t.string :title, null: false, limit: 255
      t.string :handle, null: false, limit: 255
      t.text :description_html, null: false, size: :medium
      t.string :collection_type, null: false, default: "manual", limit: 32
      t.string :rules_match, null: false, default: "all", limit: 16
      t.string :sort_order, null: false, default: "manual", limit: 32
      t.string :seo_title, limit: 70
      t.string :seo_description, limit: 320
      t.datetime :published_at
    end
    tenant_index :collections, :handle, unique: true
    tenant_index :collections, %i[collection_type published_at]

    create_tenant_table :collection_products, comment: "手動系列與商品的租戶安全 join" do |t|
      t.bigint :collection_id, null: false
      t.bigint :product_id, null: false
      t.integer :position, null: false, default: 0
    end
    tenant_index :collection_products, :collection_id
    tenant_index :collection_products, :product_id
    tenant_index :collection_products, %i[collection_id product_id], unique: true
    tenant_index :collection_products, %i[collection_id position]

    create_tenant_table :collection_rules, comment: "智慧系列白名單條件" do |t|
      t.bigint :collection_id, null: false
      t.string :column_name, null: false, limit: 64
      t.string :relation, null: false, limit: 32
      t.string :condition_value, null: false, limit: 1024
      t.integer :position, null: false
    end
    tenant_index :collection_rules, :collection_id
    tenant_index :collection_rules, %i[collection_id position], unique: true
  end

  # 建立庫存現況與不可變 adjustment ledger。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §5
  # @see docs/specs/13-spec-products-inventory-media.md F5
  def create_inventory_tables
    create_tenant_table :inventory_items, comment: "變體對應的一對一庫存品項" do |t|
      t.bigint :product_variant_id, null: false
      t.string :sku, limit: 255
      t.boolean :tracked, null: false, default: true
      t.boolean :requires_shipping, null: false, default: true
      t.string :country_code_of_origin, limit: 2
      t.string :harmonized_system_code, limit: 16
    end
    tenant_index :inventory_items, :product_variant_id, unique: true
    tenant_index :inventory_items, :sku

    create_tenant_table :locations, comment: "庫存與出貨地點" do |t|
      t.string :name, null: false, limit: 255
      t.boolean :active, null: false, default: true
      t.boolean :fulfills_online_orders, null: false, default: true
      t.integer :priority, null: false, default: 0
      t.json :address, null: false, default: -> { "(JSON_OBJECT())" }
    end
    tenant_index :locations, :name, unique: true
    tenant_index :locations, %i[active priority]

    create_tenant_table :inventory_levels, comment: "每庫存品項、每地點的五狀態數量" do |t|
      t.bigint :inventory_item_id, null: false
      t.bigint :location_id, null: false
      t.integer :available, null: false, default: 0
      t.integer :committed, null: false, default: 0
      t.integer :on_hand, null: false, default: 0
      t.integer :unavailable, null: false, default: 0
      t.integer :incoming, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
    end
    tenant_index :inventory_levels, :inventory_item_id
    tenant_index :inventory_levels, :location_id
    tenant_index :inventory_levels, %i[inventory_item_id location_id], unique: true

    create_tenant_table :inventory_adjustments, comment: "append-only 庫存 ledger" do |t|
      t.bigint :inventory_level_id, null: false
      t.string :reason, null: false, limit: 64
      t.integer :available_delta, null: false, default: 0
      t.integer :committed_delta, null: false, default: 0
      t.integer :on_hand_delta, null: false, default: 0
      t.integer :unavailable_delta, null: false, default: 0
      t.integer :incoming_delta, null: false, default: 0
      t.string :reference_type, limit: 64
      t.bigint :reference_id
      t.string :idempotency_key, null: false, limit: 255
      t.text :note
    end
    tenant_index :inventory_adjustments, :inventory_level_id
    tenant_index :inventory_adjustments, :idempotency_key, unique: true
    tenant_index :inventory_adjustments, %i[inventory_level_id created_at]
    tenant_index :inventory_adjustments, %i[reference_type reference_id]
  end

  # 建立顧客及其地址。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §2
  def create_customer_tables
    create_tenant_table :customers, comment: "顧客主檔與隱私狀態" do |t|
      t.string :email, limit: 320
      t.string :phone, limit: 32
      t.string :first_name, limit: 255
      t.string :last_name, limit: 255
      t.string :state, null: false, default: "enabled", limit: 32
      t.boolean :email_marketing_consent, null: false, default: false
      t.boolean :sms_marketing_consent, null: false, default: false
      t.boolean :tax_exempt, null: false, default: false
      t.json :tags, null: false, default: -> { "(JSON_ARRAY())" }
      t.text :note
      t.integer :orders_count, null: false, default: 0
      t.bigint :total_spent_cents, null: false, default: 0
      t.string :currency, null: false, default: "TWD", limit: 3
      t.datetime :anonymized_at
    end
    tenant_index :customers, :email, unique: true
    tenant_index :customers, :phone
    tenant_index :customers, %i[state created_at]

    create_tenant_table :customer_addresses, comment: "顧客可重用地址" do |t|
      t.bigint :customer_id, null: false
      t.string :first_name, limit: 255
      t.string :last_name, limit: 255
      t.string :company, limit: 255
      t.string :address1, null: false, limit: 255
      t.string :address2, limit: 255
      t.string :city, null: false, limit: 255
      t.string :province, limit: 255
      t.string :postal_code, limit: 32
      t.string :country_code, null: false, limit: 2
      t.string :phone, limit: 32
      t.boolean :default_address, null: false, default: false
    end
    tenant_index :customer_addresses, :customer_id
    tenant_index :customer_addresses, %i[customer_id default_address]
  end

  # 建立 checkout、訂單、付款、履約、退款與 timeline。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §2, §4, §6
  # @see docs/specs/15-spec-cart-checkout-payments.md
  # @see docs/specs/16-spec-orders-fulfillment-refunds.md
  def create_commerce_tables
    create_tenant_table :checkouts, comment: "結帳快照及棄單來源" do |t|
      t.bigint :customer_id
      t.string :token, null: false, limit: 64
      t.string :recovery_token, limit: 64
      t.string :status, null: false, default: "active", limit: 32
      t.string :email, limit: 320
      t.json :line_items_snapshot, null: false, default: -> { "(JSON_ARRAY())" }
      t.json :shipping_address, null: false, default: -> { "(JSON_OBJECT())" }
      t.json :billing_address, null: false, default: -> { "(JSON_OBJECT())" }
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :shipping_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "TWD", limit: 3
      t.bigint :presentment_total_cents, null: false, default: 0
      t.string :presentment_currency, null: false, default: "TWD", limit: 3
      t.datetime :completed_at
      t.datetime :abandoned_at
      t.datetime :expires_at
    end
    tenant_index :checkouts, :customer_id
    tenant_index :checkouts, :token, unique: true
    tenant_index :checkouts, :recovery_token, unique: true
    tenant_index :checkouts, %i[status created_at]
    tenant_index :checkouts, %i[status expires_at]

    create_tenant_table :orders, comment: "訂單金額快照與彼此獨立的狀態機" do |t|
      t.bigint :customer_id
      t.bigint :checkout_id
      t.bigint :order_number, null: false
      t.string :name, null: false, limit: 64
      t.string :status, null: false, default: "open", limit: 32
      t.string :financial_status, null: false, default: "pending", limit: 32
      t.string :fulfillment_status, null: false, default: "unfulfilled", limit: 32
      t.string :email, limit: 320
      t.text :note
      t.json :tags, null: false, default: -> { "(JSON_ARRAY())" }
      t.json :shipping_address, null: false, default: -> { "(JSON_OBJECT())" }
      t.json :billing_address, null: false, default: -> { "(JSON_OBJECT())" }
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :shipping_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "TWD", limit: 3
      t.bigint :presentment_total_cents, null: false, default: 0
      t.string :presentment_currency, null: false, default: "TWD", limit: 3
      t.datetime :processed_at
      t.datetime :canceled_at
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0
    end
    tenant_index :orders, :customer_id
    tenant_index :orders, :checkout_id, unique: true
    tenant_index :orders, :order_number, unique: true
    tenant_index :orders, %i[status created_at]
    tenant_index :orders, %i[financial_status created_at]
    tenant_index :orders, %i[fulfillment_status created_at]

    create_tenant_table :line_items, comment: "下單當下不可回溯改寫的商品與金額快照" do |t|
      t.bigint :order_id, null: false
      t.bigint :product_variant_id
      t.string :title, null: false, limit: 255
      t.string :variant_title, limit: 255
      t.string :sku, limit: 255
      t.integer :quantity, null: false
      t.integer :fulfillable_quantity, null: false, default: 0
      t.bigint :unit_price_cents, null: false
      t.bigint :total_discount_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false
      t.string :currency, null: false, default: "TWD", limit: 3
      t.boolean :taxable, null: false, default: true
      t.boolean :requires_shipping, null: false, default: true
      t.boolean :custom, null: false, default: false
      t.json :properties, null: false, default: -> { "(JSON_OBJECT())" }
    end
    tenant_index :line_items, :order_id
    tenant_index :line_items, :product_variant_id
    tenant_index :line_items, %i[order_id id]

    create_tenant_table :order_transactions, comment: "authorization/capture/refund 的不可變交易鏈" do |t|
      t.bigint :order_id, null: false
      t.bigint :parent_transaction_id
      t.string :kind, null: false, limit: 32
      t.string :status, null: false, default: "pending", limit: 32
      t.string :gateway, null: false, limit: 64
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "TWD", limit: 3
      t.string :provider_reference, limit: 255
      t.string :idempotency_key, null: false, limit: 255
      t.string :error_code, limit: 64
      t.datetime :processed_at
    end
    tenant_index :order_transactions, :order_id
    tenant_index :order_transactions, :parent_transaction_id
    tenant_index :order_transactions, :idempotency_key, unique: true
    tenant_index :order_transactions, :provider_reference, unique: true
    tenant_index :order_transactions, %i[order_id kind]
    tenant_index :order_transactions, %i[order_id status]

    create_tenant_table :fulfillment_orders, comment: "按地點拆分的履約工作單" do |t|
      t.bigint :order_id, null: false
      t.bigint :location_id, null: false
      t.string :status, null: false, default: "open", limit: 32
      t.string :request_status, null: false, default: "unsubmitted", limit: 32
      t.string :hold_reason, limit: 64
      t.datetime :fulfill_at
      t.datetime :closed_at
    end
    tenant_index :fulfillment_orders, :order_id
    tenant_index :fulfillment_orders, :location_id
    tenant_index :fulfillment_orders, %i[status fulfill_at]
    tenant_index :fulfillment_orders, %i[order_id status]

    create_tenant_table :fulfillments, comment: "實際包裹與追蹤資料" do |t|
      t.bigint :fulfillment_order_id, null: false
      t.string :status, null: false, default: "pending", limit: 32
      t.string :tracking_company, limit: 255
      t.json :tracking_numbers, null: false, default: -> { "(JSON_ARRAY())" }
      t.boolean :customer_notified, null: false, default: true
      t.datetime :shipped_at
      t.datetime :delivered_at
    end
    tenant_index :fulfillments, :fulfillment_order_id
    tenant_index :fulfillments, %i[status created_at]

    create_tenant_table :refunds, comment: "退款業務紀錄；金流結果仍由 transaction 推導" do |t|
      t.bigint :order_id, null: false
      t.bigint :order_transaction_id
      t.string :status, null: false, default: "pending", limit: 32
      t.bigint :total_cents, null: false
      t.bigint :shipping_cents, null: false, default: 0
      t.string :currency, null: false, default: "TWD", limit: 3
      t.string :reason, limit: 255
      t.string :idempotency_key, null: false, limit: 255
      t.boolean :customer_notified, null: false, default: true
      t.datetime :processed_at
    end
    tenant_index :refunds, :order_id
    tenant_index :refunds, :order_transaction_id
    tenant_index :refunds, :idempotency_key, unique: true
    tenant_index :refunds, %i[order_id created_at]

    create_tenant_table :refund_line_items, comment: "退款逐行數量、金額與 restock 決策" do |t|
      t.bigint :refund_id, null: false
      t.bigint :line_item_id, null: false
      t.integer :quantity, null: false
      t.string :restock_type, null: false, default: "no_restock", limit: 32
      t.bigint :subtotal_cents, null: false
      t.bigint :tax_cents, null: false, default: 0
      t.string :currency, null: false, default: "TWD", limit: 3
    end
    tenant_index :refund_line_items, :refund_id
    tenant_index :refund_line_items, :line_item_id
    tenant_index :refund_line_items, %i[refund_id line_item_id], unique: true

    create_tenant_table :events, comment: "訂單 timeline；業務上 append-only" do |t|
      t.bigint :order_id
      t.bigint :staff_member_id
      t.string :subject_type, limit: 64
      t.bigint :subject_id
      t.string :kind, null: false, limit: 64
      t.text :message
      t.json :metadata, null: false, default: -> { "(JSON_OBJECT())" }
      t.datetime :happened_at, null: false
      t.datetime :editable_until
    end
    tenant_index :events, :order_id
    tenant_index :events, :staff_member_id
    tenant_index :events, %i[subject_type subject_id]
    tenant_index :events, %i[order_id happened_at]
  end

  # 建立折扣定義與訂單分攤快照。
  #
  # @return [void]
  # @see docs/specs/17-spec-discounts-engine.md
  def create_discount_tables
    create_tenant_table :discounts, comment: "碼或自動折扣規則" do |t|
      t.string :title, null: false, limit: 255
      t.string :code, limit: 255
      t.string :method, null: false, default: "code", limit: 32
      t.string :discount_class, null: false, default: "product", limit: 32
      t.string :status, null: false, default: "draft", limit: 32
      t.string :value_type, null: false, default: "percentage", limit: 32
      t.integer :percentage_basis_points
      t.bigint :value_cents
      t.string :currency, null: false, default: "TWD", limit: 3
      t.datetime :starts_at
      t.datetime :ends_at
      t.integer :usage_limit
      t.integer :times_used, null: false, default: 0
      t.boolean :once_per_customer, null: false, default: false
      t.boolean :combines_product, null: false, default: false
      t.boolean :combines_order, null: false, default: false
      t.boolean :combines_shipping, null: false, default: false
      t.json :conditions, null: false, default: -> { "(JSON_OBJECT())" }
      t.integer :lock_version, null: false, default: 0
    end
    tenant_index :discounts, :code, unique: true
    tenant_index :discounts, %i[method status]
    tenant_index :discounts, %i[status starts_at]
    tenant_index :discounts, %i[status ends_at]

    create_tenant_table :discount_applications, comment: "下單當下的折扣分攤快照" do |t|
      t.bigint :order_id, null: false
      t.bigint :discount_id, null: false
      t.bigint :line_item_id
      # MySQL unique index 允許多筆 NULL；以 0 sentinel 才能阻止同一 order-level
      # application 重複，真實 line_items.id 由 auto increment 從 1 起。
      t.virtual :line_item_scope_id,
        type: :bigint,
        as: "COALESCE(`line_item_id`, 0)",
        stored: true
      t.string :allocation_method, null: false, default: "across", limit: 32
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "TWD", limit: 3
    end
    tenant_index :discount_applications, :order_id
    tenant_index :discount_applications, :discount_id
    tenant_index :discount_applications, :line_item_id
    tenant_index :discount_applications,
      %i[order_id discount_id line_item_scope_id],
      unique: true,
      name: "uq_discount_apps_order_discount_line_scope"
  end

  # 建立主題、導覽、頁面與檔案資產 metadata。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §3
  # @see docs/research/25-liquid-compat-spec.md
  def create_content_tables
    create_tenant_table :themes, comment: "主題庫項目；主題是資料而非可執行程式碼" do |t|
      t.string :name, null: false, limit: 255
      t.string :role, null: false, default: "draft", limit: 32
      # 只有 published 產生非 NULL marker；MySQL unique 對 draft 的 NULL 不判重，
      # 同店 published marker=1 則保證 docs/research/06 §4 的單一發佈主題。
      t.virtual :published_slot,
        type: :integer,
        as: "IF(`role` = 'published', 1, NULL)",
        stored: true
      t.string :source, null: false, default: "first_party", limit: 32
      t.boolean :license_attested, null: false, default: false
      t.string :version, limit: 64
      t.datetime :published_at
    end
    tenant_index :themes, :name, unique: true
    tenant_index :themes, :published_slot, unique: true
    tenant_index :themes, %i[role updated_at]

    create_tenant_table :templates, comment: "Liquid JSON template" do |t|
      t.bigint :theme_id, null: false
      t.string :key, null: false, limit: 255
      t.string :template_type, null: false, limit: 64
      t.json :content, null: false, default: -> { "(JSON_OBJECT())" }
    end
    tenant_index :templates, :theme_id
    tenant_index :templates, %i[theme_id key], unique: true

    create_tenant_table :theme_settings, comment: "主題全域 settings_data" do |t|
      t.bigint :theme_id, null: false
      t.json :settings, null: false, default: -> { "(JSON_OBJECT())" }
    end
    tenant_index :theme_settings, :theme_id, unique: true

    create_tenant_table :menus, comment: "前台 navigation menu" do |t|
      t.string :title, null: false, limit: 255
      t.string :handle, null: false, limit: 255
    end
    tenant_index :menus, :handle, unique: true

    create_tenant_table :menu_items, comment: "可巢狀導覽項目" do |t|
      t.bigint :menu_id, null: false
      t.bigint :parent_menu_item_id
      t.string :title, null: false, limit: 255
      t.string :item_type, null: false, default: "http", limit: 32
      t.string :url, limit: 2048
      t.string :resource_type, limit: 64
      t.bigint :resource_id
      t.integer :position, null: false
    end
    tenant_index :menu_items, :menu_id
    tenant_index :menu_items, :parent_menu_item_id
    tenant_index :menu_items, %i[menu_id position]
    tenant_index :menu_items, %i[parent_menu_item_id position]
    tenant_index :menu_items, %i[resource_type resource_id]

    create_tenant_table :pages, comment: "前台自訂頁面" do |t|
      t.string :title, null: false, limit: 255
      t.string :handle, null: false, limit: 255
      t.text :body_html, null: false, size: :long
      t.string :seo_title, limit: 70
      t.string :seo_description, limit: 320
      t.datetime :published_at
    end
    tenant_index :pages, :handle, unique: true
    tenant_index :pages, %i[published_at id]

    create_tenant_table :files, comment: "上傳檔案 metadata" do |t|
      t.string :filename, null: false, limit: 255
      t.string :storage_key, null: false, limit: 255
      t.string :content_type, null: false, limit: 255
      t.bigint :byte_size, null: false
      t.string :checksum, null: false, limit: 64
      t.string :status, null: false, default: "uploaded", limit: 32
      t.string :alt_text, limit: 512
      t.integer :width
      t.integer :height
    end
    tenant_index :files, :storage_key, unique: true
    tenant_index :files, %i[status created_at]
  end

  # 建立物流、稅與通知設定域。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §3
  def create_settings_tables
    create_tenant_table :shipping_profiles, comment: "一般與自訂運送設定檔" do |t|
      t.string :name, null: false, limit: 255
      t.boolean :general, null: false, default: false
      t.boolean :active, null: false, default: true
    end
    tenant_index :shipping_profiles, :name, unique: true
    tenant_index :shipping_profiles, %i[active id]

    create_tenant_table :shipping_zones, comment: "運送設定檔的國家區域" do |t|
      t.bigint :shipping_profile_id, null: false
      t.string :name, null: false, limit: 255
      t.json :country_codes, null: false, default: -> { "(JSON_ARRAY())" }
    end
    tenant_index :shipping_zones, :shipping_profile_id
    tenant_index :shipping_zones, %i[shipping_profile_id name], unique: true

    create_tenant_table :shipping_rates, comment: "固定或條件式運費，金額使用 cents" do |t|
      t.bigint :shipping_zone_id, null: false
      t.string :name, null: false, limit: 255
      t.string :rate_type, null: false, default: "flat", limit: 32
      t.bigint :price_cents, null: false, default: 0
      t.string :currency, null: false, default: "TWD", limit: 3
      t.bigint :minimum_order_cents
      t.bigint :maximum_order_cents
      t.integer :minimum_weight_grams
      t.integer :maximum_weight_grams
      t.boolean :active, null: false, default: true
    end
    tenant_index :shipping_rates, :shipping_zone_id
    tenant_index :shipping_rates, %i[shipping_zone_id active]

    create_tenant_table :tax_settings, comment: "區域稅率與含稅價設定" do |t|
      t.string :country_code, null: false, limit: 2
      t.string :region_code, null: false, default: "*", limit: 16
      t.integer :rate_basis_points, null: false, default: 0
      t.boolean :include_in_prices, null: false, default: false
      t.boolean :tax_shipping, null: false, default: false
      t.boolean :active, null: false, default: true
      t.json :overrides, null: false, default: -> { "(JSON_ARRAY())" }
    end
    tenant_index :tax_settings, %i[country_code region_code], unique: true
    tenant_index :tax_settings, %i[active country_code]

    create_tenant_table :notification_templates, comment: "交易通知模板" do |t|
      t.string :key, null: false, limit: 100
      t.string :name, null: false, limit: 255
      t.string :channel, null: false, default: "email", limit: 32
      t.string :subject, null: false, limit: 255
      t.text :body, null: false, size: :long
      t.boolean :enabled, null: false, default: true
    end
    tenant_index :notification_templates, %i[channel key], unique: true
    tenant_index :notification_templates, %i[enabled channel]
  end

  # 建立 metafield、segment 與 transaction outbox 橫切資料。
  #
  # @return [void]
  # @see docs/research/06-data-model.md §3
  # @see docs/specs/18-spec-messaging-events-webhooks.md
  def create_extensibility_tables
    create_tenant_table :metafield_definitions, comment: "metafield namespace/key 型別與驗證" do |t|
      t.string :owner_type, null: false, limit: 64
      t.string :namespace, null: false, limit: 64
      t.string :key, null: false, limit: 64
      t.string :name, null: false, limit: 255
      t.string :value_type, null: false, limit: 64
      t.json :validations, null: false, default: -> { "(JSON_ARRAY())" }
      t.boolean :pinned, null: false, default: false
    end
    tenant_index :metafield_definitions, %i[owner_type namespace key], unique: true
    tenant_index :metafield_definitions, %i[owner_type pinned]

    create_tenant_table :metafields, comment: "租戶資源上的 typed custom value" do |t|
      t.bigint :metafield_definition_id, null: false
      t.string :owner_type, null: false, limit: 64
      t.bigint :owner_id, null: false
      t.json :value, null: false
    end
    tenant_index :metafields, :metafield_definition_id
    tenant_index :metafields, %i[owner_type owner_id metafield_definition_id], unique: true

    create_tenant_table :segments, comment: "顧客分群查詢定義" do |t|
      t.string :name, null: false, limit: 255
      t.text :query, null: false
      t.string :status, null: false, default: "ready", limit: 32
      t.datetime :last_calculated_at
    end
    tenant_index :segments, :name, unique: true
    tenant_index :segments, %i[status updated_at]

    create_tenant_table :event_outbox, comment: "與業務寫入同 transaction 的 at-least-once outbox" do |t|
      t.string :event_id, null: false, limit: 36
      t.string :topic, null: false, limit: 100
      t.string :aggregate_type, null: false, limit: 64
      t.bigint :aggregate_id, null: false
      t.json :payload, null: false
      t.string :status, null: false, default: "pending", limit: 32
      t.integer :attempts, null: false, default: 0
      t.datetime :available_at, null: false
      t.datetime :locked_at
      t.datetime :published_at
      t.text :last_error
    end
    tenant_index :event_outbox, :event_id, unique: true
    tenant_index :event_outbox, %i[status available_at]
    tenant_index :event_outbox, %i[aggregate_type aggregate_id]
  end

  # 建立含租戶鍵的表，統一加入租戶根 FK 與 composite tenant key。
  #
  # @param name [Symbol] 資料表名稱
  # @param comment [String] 資料表用途
  # @yieldparam table [ActiveRecord::ConnectionAdapters::TableDefinition]
  # @return [void]
  def create_tenant_table(name, comment:)
    create_table name, comment: do |table|
      # shop_id 必須是第一個顯式欄位；見 AGENTS.md 技術鐵律 #2。
      table.bigint :shop_id, null: false
      yield table
      table.timestamps null: false
    end

    tenant_index name, :id, unique: true, name: "uq_#{name}_tenant_id"
    # 這是 M0 空 schema 的同一支初始化 migration，尚無資料可掃描或鎖住；
    # 僅對此 FK DDL 窄幅解除 strong_migrations，後續加 FK 仍須 validate 分段流程。
    safety_assured do
      add_foreign_key name, :shops, column: :shop_id, name: "fk_#{name}_shop"
    end
  end

  # 建立一律以 shop_id 開頭的業務索引。
  #
  # @param table [Symbol] 資料表名稱
  # @param columns [Symbol, Array<Symbol>] shop_id 後方的索引欄位
  # @param unique [Boolean] 是否為唯一索引
  # @param name [String, nil] 顯式索引名稱
  # @return [void]
  def tenant_index(table, columns, unique: false, name: nil)
    columns = Array(columns)
    index_name = name || "#{unique ? 'uq' : 'ix'}_#{table}_#{columns.join('_')}"
    add_index table, [ :shop_id, *columns ], unique:, name: index_name
  end

  # 套用所有 composite tenant FK。
  #
  # 為什麼：只以 parent_id 做 FK 雖能保證存在，卻不能證明 parent 屬於同一店；
  # (shop_id, parent_id) → (shop_id, id) 才能在 DB 層拒絕跨租戶連結。
  #
  # @return [void]
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F4
  def add_tenant_relationships
    TENANT_RELATIONSHIPS.each do |child, parent, parent_id|
      # M0 建立的表仍為空表；safety_assured 僅包住單一 composite FK DDL，
      # 不會掩蓋索引、欄位或未來資料 migration 的安全檢查（specs/11 §2）。
      safety_assured do
        add_foreign_key child,
          parent,
          column: [ :shop_id, parent_id ],
          primary_key: %i[shop_id id],
          name: "fk_#{child}_#{parent_id}"
      end
    end
  end
end
