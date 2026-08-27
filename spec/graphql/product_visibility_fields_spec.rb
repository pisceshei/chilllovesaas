require "rails_helper"

# `Product.purchasable` / `.discoverable` 的 GraphQL 讀取面（S6a-2）。
#
# 🔴 **這兩個欄位存在的理由是「消滅第二份真相」**：前端 `ProductDetailPage.tsx`
#   的 `STATUS_DIMENSIONS` 只看 status 硬算兩維，其註釋逐字寫著「前端沒有
#   publication 資料，硬算出來的第二個答案遲早與伺服器分岔，而分岔的症狀是
#   後台說可購買、前台買不到」。⇒ 本 spec 的每一格都在證明「伺服器的答案
#   考慮了 status **以外**的維度」——只測 status 的話，硬算版也會全綠。
RSpec.describe "Admin GraphQL product visibility fields", type: :request do
  let(:shop) { create(:shop, subdomain: "vis-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }

  before do
    host! "vis-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    online_store
    post login_path, params: { email: staff.email, password: "long-password-123" }
  end

  def product_with_variant(status:)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status:)
      create(:product_variant, product:)
      product
    end
  end

  def visibility_of(product, publication_gid: nil)
    args = publication_gid ? "(publicationId: \"#{publication_gid}\")" : ""
    post admin_graphql_path,
      params: { query: <<~GRAPHQL }.to_json,
        { product(id: "gid://chilllove/Product/#{product.id}") {
            purchasable#{args} discoverable#{args} } }
      GRAPHQL
      headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body.dig("data", "product")
  end

  # ── 狀態軸（三個值，涵蓋 UNLISTED 這個「可購買但不可發現」的關鍵格）──────
  it "ACTIVE ⇒ 兩維皆真" do
    expect(visibility_of(product_with_variant(status: "active")))
      .to eq({ "purchasable" => true, "discoverable" => true })
  end

  it "🔴 UNLISTED ⇒ 可購買但**不可被發現**（兩維不同側，這格是判準存在的理由）" do
    expect(visibility_of(product_with_variant(status: "unlisted")))
      .to eq({ "purchasable" => true, "discoverable" => false })
  end

  it "DRAFT ⇒ 兩維皆假" do
    expect(visibility_of(product_with_variant(status: "draft")))
      .to eq({ "purchasable" => false, "discoverable" => false })
  end

  # ── 🔴 發布軸：只看 status 的實作在這一格會給出**相反**的答案 ──────────────
  it "🔴 ACTIVE 但**已取消發布**（列被刪）⇒ 兩維皆假（只看 status 會答真）" do
    product = product_with_variant(status: "active")
    expect(visibility_of(product)["purchasable"]).to be(true)

    ActsAsTenant.without_tenant do
      ResourcePublication.where(shop_id: shop.id, publication_id: online_store.id).delete_all
    end

    expect(visibility_of(product)).to eq({ "purchasable" => false, "discoverable" => false })
  end

  it "🔴 ACTIVE 但發布時點在**未來**（排程未到點）⇒ 兩維皆假" do
    product = product_with_variant(status: "active")
    ActsAsTenant.without_tenant do
      ResourcePublication.where(shop_id: shop.id, publishable_type: "Product", publishable_id: product.id)
                         .update_all(published_at: 3.days.from_now)
    end

    expect(visibility_of(product)).to eq({ "purchasable" => false, "discoverable" => false })
  end

  # ── 恆等不變量（model 層是定理，這裡是它在 API 面的反向釘子）───────────────
  it "🔴 discoverable ⊆ purchasable：三種狀態下都不得出現「可發現但不可購買」" do
    %w[active unlisted draft].each do |status|
      row = visibility_of(product_with_variant(status:))
      expect(row["discoverable"] && !row["purchasable"]).to be(false),
        "status=#{status} 出現了 discoverable=true 而 purchasable=false"
    end
  end

  # ── 參數與 fail-closed ────────────────────────────────────────────────
  it "publicationId 指定不存在的管道 ⇒ 兩維皆假（fail-closed，不 raise）" do
    product = product_with_variant(status: "active")
    row = visibility_of(product, publication_gid: "gid://chilllove/Publication/999999")
    expect(row).to eq({ "purchasable" => false, "discoverable" => false })
  end

  # 直呼 `ChillloveSchema.execute`（rails runner／背景 job／內部呼叫，無 controller）
  # 也要能算出兩維。harness 與 `mutation_context_shop_spec.rb` 的冒煙格同構：
  # 包 `ActsAsTenant.with_tenant` 讓查詢層有租戶，但**不經 controller** ⇒
  # `Current.shop`（ActiveSupport::CurrentAttributes）是 nil。
  #
  # ⚠️ **誠實界定這一格證明了什麼**：它證明本欄位在無 controller 的情境下可執行，
  #   **不**證明「租戶取自 context 而非隱式租戶」——`with_tenant` 兩者都滿足。
  #   後者由同檔案 `mutation_context_shop_spec.rb` 的**靜態掃描**那一格負責
  #   （`app/graphql` 下不得出現 `Current.shop`）。兩道守衛分工，不重複宣稱。
  it "直呼 schema（無 controller）也能算出兩維" do
    product = product_with_variant(status: "active")
    result = ActsAsTenant.with_tenant(shop) do
      ChillloveSchema.execute(
        "{ product(id: \"gid://chilllove/Product/#{product.id}\") { purchasable discoverable } }",
        context: { current_shop: shop, current_staff: staff },
      ).to_h
    end

    expect(result["errors"]).to be_nil
    expect(result.dig("data", "product")).to eq({ "purchasable" => true, "discoverable" => true })
  end

  it "🔴 publicationId 指向**別間店**的管道 ⇒ 兩維皆假（租戶隔離）" do
    other = create(:shop, subdomain: "vis-other")
    other_pub = ActsAsTenant.with_tenant(other) { Publication.online_store! }
    product = product_with_variant(status: "active")

    row = visibility_of(product, publication_gid: "gid://chilllove/Publication/#{other_pub.id}")
    expect(row).to eq({ "purchasable" => false, "discoverable" => false })
  end
end
