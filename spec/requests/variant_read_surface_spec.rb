# frozen_string_literal: true

require "rails_helper"

# 第 21 包（整合規格 §4-21）：options／selectedOptions 讀取面＋variants connection。
RSpec.describe "Admin GraphQL 變體讀取面", type: :request do
  let(:shop) { create(:shop, subdomain: "vread-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "vread-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  # 造「尺寸 S/M/L」三變體商品；position 刻意與 created_at 反序（3→1）——
  # 排序鍵若誤用 created_at，第一條測試就紅（排程 §2.1③ 的缺陷形態）。
  def build_product!
    ActsAsTenant.with_tenant(shop) do
      product = create(:product_variant, shop:).product
      option = ProductOption.create!(shop_id: shop.id, product_id: product.id, name: "尺寸", position: 1)
      values = %w[S M L].each_with_index.map do |v, i|
        OptionValue.create!(shop_id: shop.id, product_option_id: option.id, value: v, position: i + 1)
      end
      base = product.product_variants.order(:position).first!
      base.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
        product_option_id: option.id, option_value_id: values[0].id)
      base.update!(position: 3, title: "S")
      [ [ "M", values[1], 2 ], [ "L", values[2], 1 ] ].each do |title, val, pos|
        v = ProductVariant.new(shop_id: shop.id, product_id: product.id,
                               title:, position: pos, currency: shop.store_currency)
        v.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
          product_option_id: option.id, option_value_id: val.id)
        v.save!
      end
      product
    end
  end

  QUERY = <<~GRAPHQL
    query($id: ID!, $first: Int, $after: String) {
      product(id: $id) {
        options { name position values { value position } }
        variants(first: $first, after: $after) {
          nodes { title position selectedOptions { name value } }
          edges { cursor }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  GRAPHQL

  it "variants 依 position 序（不是 created_at）；selectedOptions 為 name/value 對" do
    product = build_product!
    login!
    post_graphql(QUERY, variables: { id: "gid://chilllove/Product/#{product.id}" })
    data = response.parsed_body.dig("data", "product")

    expect(data["options"]).to eq([
      { "name" => "尺寸", "position" => 1,
        "values" => [ { "value" => "S", "position" => 1 }, { "value" => "M", "position" => 2 },
                      { "value" => "L", "position" => 3 } ] }
    ])
    nodes = data.dig("variants", "nodes")
    expect(nodes.map { |n| n["title"] }).to eq(%w[L M S])
    expect(nodes.map { |n| n["position"] }).to eq([ 1, 2, 3 ])
    expect(nodes.first["selectedOptions"]).to eq([ { "name" => "尺寸", "value" => "L" } ])
  end

  it "cursor 分頁沿 position 前進；隱含變體 selectedOptions 為空陣列" do
    product = build_product!
    login!
    post_graphql(QUERY, variables: { id: "gid://chilllove/Product/#{product.id}", first: 2 })
    page1 = response.parsed_body.dig("data", "product", "variants")
    expect(page1["nodes"].map { |n| n["title"] }).to eq(%w[L M])
    expect(page1.dig("pageInfo", "hasNextPage")).to be(true)

    post_graphql(QUERY, variables: { id: "gid://chilllove/Product/#{product.id}",
                                     first: 2, after: page1.dig("pageInfo", "endCursor") })
    page2 = response.parsed_body.dig("data", "product", "variants")
    expect(page2["nodes"].map { |n| n["title"] }).to eq(%w[S])
    expect(page2.dig("pageInfo", "hasNextPage")).to be(false)

    plain = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) }
    post_graphql(QUERY, variables: { id: "gid://chilllove/Product/#{plain.product_id}" })
    expect(response.parsed_body.dig("data", "product", "variants", "nodes").sole["selectedOptions"]).to eq([])
  end

  it "🔴 N+1 守衛：三變體×選項讀取的 SQL 條數固定（preload 生效）" do
    product = build_product!
    login!
    queries = []
    counter = ->(_n, _s, _f, _id, payload) { queries << payload[:sql] if payload[:sql] =~ /\ASELECT/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      post_graphql(QUERY, variables: { id: "gid://chilllove/Product/#{product.id}" })
    end
    variant_reads = queries.count { |q| q.include?("product_variant_option_values") }
    expect(variant_reads).to be <= 1
  end

  def login!(email: staff.email)
    post login_path, params: { email:, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path,
      params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end
end
