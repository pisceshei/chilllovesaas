# frozen_string_literal: true

require "rails_helper"

# 第 6 包：url_redirects＋handle 變更掛鉤（62 §B.5／§F.3）。
#
# 🔴 本檔守的核心不變量：**表裡永遠沒有鏈也沒有迴圈**。
#   兩件事合起來保證它：①寫入時鏈坍縮（A→B 存在、B 改名 C ⇒ A→B 變 A→C）
#   ②新路徑不得是既有 from_path（舊 handle 永不回收）——迴圈唯一可能的來源
#   就是「新 from＝某列的 to ∧ 新 to＝某列的 from」，②把後半永久擋掉。
RSpec.describe "Admin GraphQL handle 變更與 301", type: :request do
  let(:shop) { create(:shop, subdomain: "redir-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "redir-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  # 🔴 常數名必須全 spec 唯一：describe 區塊裡的常數其實定義在 Object 上，
  #   後載入的檔會**覆蓋**先載入的同名常數（本包實測：第一版叫 SET，撞
  #   inventory_adjust_spec 的 SET ⇒ 那邊的兩例在整套跑時拿到 productSet 文件、
  #   data 變 nil——單跑各自全綠，只有整套才炸）。
  P6_PRODUCT_SET = <<~GRAPHQL
    mutation($input: ProductSetInput!, $idempotencyKey: String) {
      productSet(input: $input, idempotencyKey: $idempotencyKey) {
        product { id handle lockVersion }
        userErrors { field message code }
      }
    }
  GRAPHQL

  def product!(handle)
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:)
      v.product.update!(handle:)
      v.product
    end
  end

  def rename!(product, new_handle)
    ActsAsTenant.with_tenant(shop) do
      post_graphql(P6_PRODUCT_SET, variables: {
        input: { id: "gid://chilllove/Product/#{product.id}", title: product.reload.title,
                 lockVersion: product.lock_version, handle: new_handle,
                 variants: [ { id: "gid://chilllove/ProductVariant/#{product.product_variants.sole.id}",
                               price: "128.00" } ] },
        idempotencyKey: SecureRandom.uuid
      })
    end
    response.parsed_body.dig("data", "productSet")
  end

  def redirects
    ActsAsTenant.with_tenant(shop) do
      UrlRedirect.order(:from_path).pluck(:from_path, :to_path, :status_code, :source)
    end
  end

  it "🔴 改名 ⇒ 同 transaction 落一列 301（handle_change）" do
    product = product!("old-tee")
    login!
    body = rename!(product, "new-tee")
    expect(body["userErrors"]).to eq([])
    expect(body.dig("product", "handle")).to eq("new-tee")
    expect(redirects).to eq([ [ "/products/old-tee", "/products/new-tee", 301, "handle_change" ] ])
  end

  it "🔴 連續改名 ⇒ 鏈坍縮（A→B、B→C 收斂成 A→C＋B→C，無鏈）" do
    product = product!("aaa")
    login!
    rename!(product, "bbb")
    rename!(product, "ccc")
    expect(redirects).to eq([
      [ "/products/aaa", "/products/ccc", 301, "handle_change" ],
      [ "/products/bbb", "/products/ccc", 301, "handle_change" ]
    ])
    # 不變量：沒有任何列的 to_path 同時是別列的 from_path（＝無鏈無迴圈）
    ActsAsTenant.with_tenant(shop) do
      froms = UrlRedirect.pluck(:from_path)
      expect(UrlRedirect.where(to_path: froms)).to be_empty
    end
  end

  it "🔴 舊 handle 永不回收：改回去（A→B 後再 B→A）被拒" do
    product = product!("first")
    login!
    rename!(product, "second")
    body = rename!(product, "first")
    err = body["userErrors"].sole
    expect(err["code"]).to eq("HANDLE_TAKEN")
    expect(err["field"]).to eq(%w[handle])
    # 沒寫出半列新 redirect、handle 沒變
    expect(redirects.length).to eq(1)
    ActsAsTenant.with_tenant(shop) { expect(product.reload.handle).to eq("second") }
  end

  it "🔴 建立商品不得佔用重導來源路徑（手填＝拒；生成＝跳號）" do
    product = product!("veteran")
    login!
    rename!(product, "veteran-2")

    # 手填撞 from_path ⇒ 拒
    ActsAsTenant.with_tenant(shop) do
      post_graphql(P6_PRODUCT_SET, variables: {
        input: { title: "新品", handle: "veteran",
                 variants: [ { price: "10.00" } ] },
        idempotencyKey: SecureRandom.uuid
      })
    end
    expect(response.parsed_body.dig("data", "productSet", "userErrors", 0, "code")).to eq("HANDLE_TAKEN")

    # 生成撞 from_path ⇒ 自動跳號（不靜默佔用）
    ActsAsTenant.with_tenant(shop) do
      post_graphql(P6_PRODUCT_SET, variables: {
        input: { title: "Veteran", variants: [ { price: "10.00" } ] },
        idempotencyKey: SecureRandom.uuid
      })
    end
    body = response.parsed_body.dig("data", "productSet")
    expect(body["userErrors"]).to eq([])
    expect(body.dig("product", "handle")).to eq("veteran-1")
  end

  it "改名撞另一個商品的現任 handle ⇒ HANDLE_TAKEN、零副作用" do
    product = product!("mine")
    product!("theirs")
    login!
    body = rename!(product, "theirs")
    expect(body["userErrors"].sole["code"]).to eq("HANDLE_TAKEN")
    expect(redirects).to eq([])
  end

  it "🔴 改名失敗（變體被拒）⇒ redirect 一併回滾（同 txn 的證明）" do
    product = product!("atomic")
    login!
    ActsAsTenant.with_tenant(shop) do
      post_graphql(P6_PRODUCT_SET, variables: {
        input: { id: "gid://chilllove/Product/#{product.id}", title: product.title,
                 lockVersion: product.lock_version, handle: "atomic-2",
                 variants: [ { id: "gid://chilllove/ProductVariant/#{product.product_variants.sole.id}",
                               price: "not-money" } ] },
        idempotencyKey: SecureRandom.uuid
      })
    end
    expect(response.parsed_body.dig("data", "productSet", "userErrors")).not_to be_empty
    expect(redirects).to eq([])
    ActsAsTenant.with_tenant(shop) { expect(product.reload.handle).to eq("atomic") }
  end

  it "系列改名 ⇒ /collections 前綴的 301" do
    collection = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "夏季", description_html: "",
                         handle: "summer", collection_type: "manual")
    end
    login!
    ActsAsTenant.with_tenant(shop) do
      result = Catalog::SaveCollection.call(shop:, input: {
        id: "gid://chilllove/Collection/#{collection.id}", title: "夏季",
        lock_version: collection.lock_version, handle: "summer-sale"
      })
      expect(result.user_errors).to eq([])
    end
    expect(redirects).to eq([ [ "/collections/summer", "/collections/summer-sale", 301, "handle_change" ] ])
  end

  it "🔴 路徑欄拒收換行／空白（第 36 包會把它放進 301 Location 標頭）" do
    # brakeman ValidationRegex（High）抓到的：只錨開頭的正則對**換行之後**的內容
    # 不設限，於是帶 CRLF 的值通得過 ⇒ 標頭注入。
    ActsAsTenant.with_tenant(shop) do
      [ "/ok\nLocation: https://evil.com", "/ok\r\nX-Injected: 1",
        "/has space", "no-slash" ].each do |bad|
        row = UrlRedirect.new(shop_id: shop.id, from_path: bad, to_path: "/products/z",
                              status_code: 301, source: "handle_change")
        expect(row).not_to be_valid, "#{bad.inspect} 竟然通過驗證"
        expect(row.errors[:from_path]).not_to be_empty
      end
    end
  end

  def login!(email: staff.email)
    post login_path, params: { email:, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end
end
