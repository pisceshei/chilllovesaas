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

  tenant_declarations = source.scan(/^\s{4}create_tenant_table :([a-z_]+)/).flatten

  it "declares all 47 literal table names from docs/research/06 section 7" do
    expect(documented_tables.length).to eq(47)
    expect(source.scan(/^\s{4}create_table :shops\b/).length).to eq(1)
    expect([ "shops", *tenant_declarations ].intersection(documented_tables)).to match_array(documented_tables)
  end

  it "adds only the baseline idempotency support table beyond the documented tenant tables" do
    expect(tenant_declarations - (documented_tables - [ "shops" ])).to eq([ "idempotency_keys" ])
    expect(tenant_declarations.length).to eq(47)
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
    expect(source.scan(/^\s{4}%i\[[a-z_]+ [a-z_]+ [a-z_]+\],?$/).length).to eq(43)
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
