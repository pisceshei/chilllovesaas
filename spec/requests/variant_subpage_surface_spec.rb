# frozen_string_literal: true

require "rails_helper"

# 第 29 包（整合規格 §4-29）：變體子頁需要的讀寫面。
#
# 子頁本身是**組裝**（庫存調整列、選項與變體表、變體圖格都已存在），但它要的三樣
# 資料在讀取面不存在：①運送兩欄 ②變體圖 ③**全地點**庫存。
# 🔴 第三樣是形狀問題不是欄位問題：`inventoryItems(locationId:)` 是單地點視角
#   （商品頁庫存卡因此有地點選擇器），子頁要的是同一變體的全部地點一次看完
#   （93 §2 實測「庫存卡（per-location 表）」）。
RSpec.describe "Admin GraphQL 變體子頁讀寫面", type: :request do
  let(:shop) { create(:shop, subdomain: "vsub-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "vsub-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  SUBPAGE_QUERY = <<~GRAPHQL
    query($id: ID!) {
      product(id: $id) {
        title
        variants(first: 50) {
          nodes {
            id title position weightGrams requiresShipping
            image { url thumbUrl alt }
            inventoryLevels {
              inventoryItemId
              location { id name }
              quantities { available onHand committed }
            }
          }
        }
      }
    }
  GRAPHQL

  SET_MUTATION = <<~GRAPHQL
    mutation($input: ProductSetInput!, $idempotencyKey: String) {
      productSet(input: $input, idempotencyKey: $idempotencyKey) {
        product { id lockVersion variants(first: 50) { nodes { id weightGrams requiresShipping } } }
        userErrors { field message code }
      }
    }
  GRAPHQL

  def product_with_variant!
    ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product }
  end

  def gid(product) = "gid://chilllove/Product/#{product.id}"

  it "🔴 inventoryLevels 一次回全部地點（不是單地點視角）" do
    product = product_with_variant!
    variant = ActsAsTenant.with_tenant(shop) { product.product_variants.sole }
    ActsAsTenant.with_tenant(shop) do
      # 建店即有預設地點「Shop location」（priority 0）、建變體即有 InventoryItem
      # ——這裡只再加一個 priority 較後的地點，驗「全部回、且照 priority 排」。
      item = variant.inventory_item || InventoryItem.create!(shop_id: shop.id,
                                                             product_variant_id: variant.id, tracked: true)
      item.inventory_levels.first&.update!(available: 10)
      # `Location#after_create` 已為每個既有品項補一列 0 量 level（反方向在
      # `ProductVariant#after_create`）——所以這裡是 update 不是 create。
      second = Location.create!(shop_id: shop.id, name: "倉庫乙", priority: 9)
      InventoryLevel.find_by!(inventory_item_id: item.id, location_id: second.id)
                    .update!(available: 20)
    end
    login!

    post_graphql(SUBPAGE_QUERY, variables: { id: gid(product) })
    levels = response.parsed_body.dig("data", "product", "variants", "nodes").sole["inventoryLevels"]
    expect(levels.size).to eq(2)
    # priority 序：預設地點在前、倉庫乙（priority 9）在後
    expect(levels.last.dig("location", "name")).to eq("倉庫乙")
    expect(levels.map { |l| l.dig("quantities", "available") }).to eq([ 10, 20 ])
    # 調整用的品項 GID 必須帶出來——沒有它，庫存卡的 ✓ 送不出去
    expect(levels.first["inventoryItemId"]).to match(%r{\Agid://chilllove/InventoryItem/\d+\z})
  end

  it "沒有庫存品項的變體回空陣列（不是 null、不是例外）" do
    product = product_with_variant!
    # 建變體即建 InventoryItem 是常態；本例刻意拿掉，驗**沒有**品項時的回傳形狀。
    ActsAsTenant.with_tenant(shop) do
      item = product.product_variants.sole.inventory_item
      if item
        InventoryLevel.where(inventory_item_id: item.id).delete_all
        item.delete
      end
    end
    login!

    post_graphql(SUBPAGE_QUERY, variables: { id: gid(product) })
    expect(response.parsed_body.dig("data", "product", "variants", "nodes").sole["inventoryLevels"]).to eq([])
  end

  it "🔴 運送兩欄可讀可寫（weightGrams 是公克整數，不是公斤浮點）" do
    product = product_with_variant!
    login!

    post_graphql(SUBPAGE_QUERY, variables: { id: gid(product) })
    node = response.parsed_body.dig("data", "product", "variants", "nodes").sole
    expect(node["weightGrams"]).to eq(0)
    expect(node["requiresShipping"]).to be(true)

    ActsAsTenant.with_tenant(shop) do
      post_graphql(SET_MUTATION, variables: {
        input: { id: gid(product), title: product.title, lockVersion: product.lock_version,
                 variants: [ { id: node["id"], price: "128.00",
                               weightGrams: 1250, requiresShipping: false } ] },
        idempotencyKey: SecureRandom.uuid
      })
    end
    body = response.parsed_body.dig("data", "productSet")
    expect(body["userErrors"]).to be_empty
    saved = body.dig("product", "variants", "nodes").sole
    expect(saved["weightGrams"]).to eq(1250)
    expect(saved["requiresShipping"]).to be(false)
  end

  it "🔴 沒送運送欄＝回落預設（0／true），不得寫入 nil 撞 not-null" do
    product = product_with_variant!
    variant = ActsAsTenant.with_tenant(shop) { product.product_variants.sole }
    ActsAsTenant.with_tenant(shop) { variant.update!(weight_grams: 900, requires_shipping: false) }
    login!

    ActsAsTenant.with_tenant(shop) do
      post_graphql(SET_MUTATION, variables: {
        input: { id: gid(product), title: product.title, lockVersion: product.reload.lock_version,
                 variants: [ { id: "gid://chilllove/ProductVariant/#{variant.id}", price: "128.00" } ] },
        idempotencyKey: SecureRandom.uuid
      })
    end
    expect(response.parsed_body.dig("data", "productSet", "userErrors")).to be_empty
    saved = response.parsed_body.dig("data", "productSet", "product", "variants", "nodes").sole
    # 🔴 宣告式全量：沒送的欄位回落預設而不是保留舊值——這與 sku/barcode 同語義。
    #    子頁必須整份回送（含運送欄），否則使用者在別處設的重量會被清掉。
    expect(saved["weightGrams"]).to eq(0)
    expect(saved["requiresShipping"]).to be(true)
  end

  it "變體圖：掛上之後 image 有值，未掛為 null" do
    product = product_with_variant!
    variant = ActsAsTenant.with_tenant(shop) { product.product_variants.sole }
    login!

    post_graphql(SUBPAGE_QUERY, variables: { id: gid(product) })
    expect(response.parsed_body.dig("data", "product", "variants", "nodes").sole["image"]).to be_nil

    ActsAsTenant.with_tenant(shop) do
      key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
      Storage::LocalDisk.write(key, StringIO.new("BYTES"))
      file = StoredFile.create!(filename: "v.png", content_type: "image/png", byte_size: 5,
                                checksum: SecureRandom.hex(32), storage_key: key, status: "ready")
      Media.create!(shop_id: shop.id, product_id: product.id, product_variant_id: variant.id,
                    file_id: file.id, media_type: "image", position: 1,
                    source_url: "/admin/files/#{file.id}/blob", alt_text: "變體圖", status: "ready")
    end

    post_graphql(SUBPAGE_QUERY, variables: { id: gid(product) })
    image = response.parsed_body.dig("data", "product", "variants", "nodes").sole["image"]
    expect(image["url"]).to be_present
    # alt 取媒體列的（不是 files 的）——第 26／27 包裁定
    expect(image["alt"]).to eq("變體圖")
  end

  it "🔴 多變體不得 N+1：新增的三個欄位都已 preload" do
    product = product_with_variant!
    ActsAsTenant.with_tenant(shop) do
      # 🔴 座標必須在**存檔之前**掛上（factory 檔頭：在已有選項的商品上先存無座標
      #    變體是不合法的中間狀態）。這裡照 variant_read_surface_spec 的可行配方。
      option = ProductOption.create!(shop_id: shop.id, product_id: product.id, name: "尺寸", position: 1)
      values = %w[S M L].each_with_index.map do |v, i|
        OptionValue.create!(shop_id: shop.id, product_option_id: option.id, value: v, position: i + 1)
      end
      base = product.product_variants.sole
      base.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
        product_option_id: option.id, option_value_id: values[0].id)
      base.update!(title: "S", position: 1)
      [ [ "M", values[1], 2 ], [ "L", values[2], 3 ] ].each do |title, val, pos|
        v = ProductVariant.new(shop_id: shop.id, product_id: product.id, title:, position: pos,
                               currency: shop.store_currency)
        v.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
          product_option_id: option.id, option_value_id: val.id)
        v.save!
        # `ProductVariant` 的 after_create 已自動建 InventoryItem＋每地點一列 level
        # ——這裡只改數量，再建一次會撞 product_variant 唯一驗證。
        v.inventory_item.inventory_levels.each { |level| level.update!(available: 7) }
      end
    end
    login!

    queries = 0
    counter = ->(_n, _s, _f, _i, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      post_graphql(SUBPAGE_QUERY, variables: { id: gid(product) })
    end
    expect(response.parsed_body.dig("data", "product", "variants", "nodes").size).to eq(3)
    # 三個變體各自的 levels/location/media 若沒 preload，查詢數會隨變體數線性成長。
    # 判準取寬鬆上界：只要不是「每變體多幾條」即可（精確值會隨 auth/session 查詢漂移）。
    expect(queries).to be < 40
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
