# frozen_string_literal: true

require "spec_helper"

RSpec.describe "M0 core schema source invariants" do
  migration_path = File.expand_path("../../db/migrate/20260811000000_m0_create_core_schema.rb", __dir__)
  source = File.read(migration_path, encoding: "UTF-8")

  documented_tables = %w[
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

  # 法域 schema 聯集表（docs/research/06 §7.1；2026-08-13 移植時新增）：
  # schema 取所有 jurisdiction pack 的聯集，行為才取當前 pack。
  jurisdiction_union_tables = %w[
    einvoices einvoice_allowances jurisdiction_capability_skips
    contract_liability_entries
  ].freeze

  tenant_declarations = source.scan(/^\s{4}create_tenant_table :([a-z_]+)/).flatten

  it "declares all 47 literal table names from docs/research/06 section 7" do
    expect(documented_tables.length).to eq(47)
    expect(source.scan(/^\s{4}create_table :shops\b/).length).to eq(1)
    expect([ "shops", *tenant_declarations ].intersection(documented_tables)).to match_array(documented_tables)
  end

  it "adds only idempotency support and jurisdiction-union tables beyond the documented set" do
    expect(tenant_declarations - (documented_tables - [ "shops" ]))
      .to match_array([ "idempotency_keys", *jurisdiction_union_tables ])
    expect(tenant_declarations.length).to eq(51)
  end

  it "builds the jurisdiction union tables with the schema-level invariants from 06 section 7.1" do
    jurisdiction_union_tables.each do |table|
      expect(source).to include("create_tenant_table :#{table}")
    end

    # 🔴 一訂單多發票（55 §D G-04）：einvoices 的 (shop_id, order_id) 絕不可唯一。
    # 這是全案唯一 schema 級、上線後改不得的決定——本斷言就是它的防回歸執法點。
    expect(source).to include("tenant_index :einvoices, :order_id\n")
    expect(source).not_to match(/tenant_index :einvoices, :order_id,.*unique/)

    # 合約負債分錄的自然鍵（56 §B.3.1 J-01）。
    expect(source).to include("tenant_index :contract_liability_entries, %i[source_type source_id direction], unique: true")

    # 訂單成立即快照雙法域（06 §7.1；56 §A.0）——無 default，靜默預設＝錯法域。
    expect(source).to match(/t\.string :seller_jurisdiction, null: false, limit: 8\n\s+t\.string :buyer_jurisdiction, null: false, limit: 8/)
  end

  it "defaults all currency and timezone columns to the HK baseline ruling" do
    # 2026-08-12 裁定「基準法域＝香港」（CLAUDE.md 鐵律 11）；原骨架的 TWD／
    # Asia/Taipei 預設是裁定前殘留，不得回流。
    expect(source).not_to include('default: "TWD"')
    expect(source).not_to include("Asia/Taipei")
    expect(source).to include('t.string :store_currency, null: false, default: "HKD", limit: 3')
    expect(source).to include('default: "Asia/Hong_Kong"')
  end

  it "makes shop_id the first explicit tenant column and creates the tenant identity key" do
    expect(source).to match(/create_table name, comment: do \|table\|\s+#[^\n]+\s+table\.bigint :shop_id, null: false/m)
    expect(source).to include('tenant_index name, :id, unique: true, name: "uq_#{name}_tenant_id"')
    expect(source).to include("add_foreign_key name, :shops, column: :shop_id")
  end

  it "routes every tenant business index through the shop-prefixed helper" do
    direct_literal_indexes = source.scan(/^\s+add_index :([a-z_]+)/).flatten

    expect(direct_literal_indexes).not_to be_empty
    expect(direct_literal_indexes.uniq).to eq([ "shops" ])
    expect(source).to include("add_index table, [ :shop_id, *columns ], unique:, name: index_name")
  end

  it "keeps non-unique indexes at three columns or fewer including shop_id" do
    non_unique_indexes = source.lines.filter_map do |line|
      next if line.include?("unique: true")

      line[/tenant_index :[a-z_]+, %i\[([^\]]+)\]/, 1]
    end.compact

    expect(non_unique_indexes).not_to be_empty
    expect(non_unique_indexes.map { |columns| columns.split.length + 1 }).to all(be <= 3)
    expect(source).to include("tenant_index :products, %i[created_at id]")
  end

  it "uses composite tenant foreign keys for business relationships" do
    expect(source).to include("column: [ :shop_id, parent_id ]")
    expect(source).to include("primary_key: %i[shop_id id]")
    # 45 = 原 43 條 + einvoices→orders、einvoice_allowances→einvoices（06 §7.1，2026-08-13）
    expect(source.scan(/^\s{4}%i\[[a-z_]+ [a-z_]+ [a-z_]+\],?$/).length).to eq(45)
    expect(source).not_to match(/t\.(references|belongs_to)\b/)
    expect(source).not_to match(/add_reference\b/)
  end

  it "narrows strong_migrations bypasses to initial empty-schema foreign keys" do
    expect(source.scan(/^\s+safety_assured do$/).length).to eq(2)
    expect(source).to match(/safety_assured do\s+add_foreign_key name, :shops/m)
    expect(source).to match(/safety_assured do\s+add_foreign_key child,/m)
  end

  it "stores every cents field as bigint and contains no floating money type" do
    cents_lines = source.lines.grep(/:\w+_cents\b/)

    expect(cents_lines).not_to be_empty
    expect(cents_lines).to all(match(/t\.bigint :\w+_cents\b/))
    expect(source).not_to match(/t\.(float|decimal)\b/)
  end

  it "pairs every table containing cents with an ISO currency field" do
    table_blocks = source.scan(/create_tenant_table :([a-z_]+).*? do \|t\|(.*?)^\s{4}end/m).to_h
    money_tables = table_blocks.select { |_name, block| block.match?(/:\w+_cents\b/) }

    expect(money_tables).not_to be_empty
    money_tables.each_value do |block|
      expect(block).to match(/t\.string :(?:presentment_)?currency\b/)
    end
  end

  it "uses MySQL expression defaults instead of forbidden JSON literal defaults" do
    json_defaults = source.lines.grep(/t\.json .*default:/)

    expect(json_defaults).not_to be_empty
    expect(json_defaults).to all(match(/default: -> \{ "\(JSON_(?:OBJECT|ARRAY)\(\)\)" \}/))
    expect(source).not_to match(/t\.json .*default: (?:\{\}|\[\])/)
  end

  it "uses generated sentinels for MySQL NULL-aware business uniqueness" do
    expect(source).to include('as: "IF(`role` = \'published\', 1, NULL)"')
    expect(source).to include("tenant_index :themes, :published_slot, unique: true")
    expect(source).to include('as: "COALESCE(`line_item_id`, 0)"')
    expect(source).to include("%i[order_id discount_id line_item_scope_id]")
  end
end
