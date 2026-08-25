# frozen_string_literal: true

require "rails_helper"

# productSet 的 request 層契約（63 §B.4 建立態 v1 ＋ 11 §2.1 claim/replay）。
RSpec.describe "Admin GraphQL productSet", type: :request do
  let(:shop) { create(:shop, subdomain: "productset-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  MUTATION = <<~GRAPHQL
    mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
      productSet(input: $input, idempotencyKey: $idempotencyKey) {
        product { id handle status title lockVersion }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "productset-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def base_input(overrides = {})
    {
      title: "奶茶色寬版帽T",
      descriptionHtml: "<p>秋冬款</p>",
      variants: [ { price: "128.00" } ]
    }.merge(overrides)
  end

  describe "建立（快樂路徑）" do
    it "建立商品＋隱含變體＋outbox 事件，金額轉 integer cents" do
      login!
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: SecureRandom.uuid })

      payload = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(payload["errors"]).to be_nil
      data = payload.dig("data", "productSet")
      expect(data["userErrors"]).to eq([])
      expect(data.dig("product", "status")).to eq("DRAFT")

      ActsAsTenant.with_tenant(shop) do
        product = Product.find_by!(title: "奶茶色寬版帽T")
        # handle 由標題生成：純 CJK 過不了品質閘門 ⇒ 確定性 fallback（product-token8）
        expect(product.handle).to match(/\Aproduct-[0-9a-z]{8}\z/)
        variant = product.product_variants.sole
        expect(variant.title).to eq(Limits.fetch(:catalog_flow, :default_variant_liquid_title))
        expect(variant.price_cents).to eq(12_800)
        expect(variant.currency).to eq("HKD")
        expect(EventOutbox.where(topic: "products/create", aggregate_id: product.id)).to exist
        expect(IdempotencyKey.sole.state).to eq("succeeded")
      end
    end

    it "英文標題生成語義 handle；未帶 status 預設 DRAFT（小寫落庫）" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(title: "Bob's Burgers Tee"), idempotencyKey: SecureRandom.uuid
      })

      ActsAsTenant.with_tenant(shop) do
        product = Product.find_by!(title: "Bob's Burgers Tee")
        expect(product.handle).to eq("bobs-burgers-tee")
        expect(product.status).to eq("draft")
      end
    end

    it "生成 handle 衝突時自 -1 起算尾碼（不是 -2）" do
      login!
      ActsAsTenant.with_tenant(shop) do
        create(:product, shop:, title: "Potion", handle: "potion")
      end
      post_graphql(MUTATION, variables: {
        input: base_input(title: "Potion"), idempotencyKey: SecureRandom.uuid
      })

      data = response.parsed_body.dig("data", "productSet")
      expect(data["userErrors"]).to eq([])
      expect(data.dig("product", "handle")).to eq("potion-1")
    end
  end

  describe "冪等（11 §2.1）" do
    it "同 key 同輸入回放：不建第二個商品，回同一個 GID" do
      login!
      key = SecureRandom.uuid
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      first_id = response.parsed_body.dig("data", "productSet", "product", "id")

      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      replay_id = response.parsed_body.dig("data", "productSet", "product", "id")

      expect(replay_id).to eq(first_id)
      ActsAsTenant.with_tenant(shop) { expect(Product.count).to eq(1) }
    end

    it "同 key 不同輸入 ⇒ IDEMPOTENCY_KEY_PARAMETER_MISMATCH（userErrors，field null）" do
      login!
      key = SecureRandom.uuid
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      post_graphql(MUTATION, variables: {
        input: base_input(title: "換了標題"), idempotencyKey: key
      })

      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("IDEMPOTENCY_KEY_PARAMETER_MISMATCH")
      expect(error["field"]).to be_nil
    end

    it "processing 撞車 ⇒ IDEMPOTENCY_CONCURRENT_REQUEST" do
      login!
      key = SecureRandom.uuid
      ActsAsTenant.with_tenant(shop) do
        IdempotencyKey.create!(
          # mutation_name＝mutation 類別的 graphql_name（"ProductSet"），不是欄位名。
          key:, mutation_name: "ProductSet", state: "processing",
          # 指紋必須與 mutation 端同形：resolver 對 `input.to_h`（snake_case 鍵）
          # deep_stringify 後取指紋——照 GraphQL 線上格式（camelCase）算會 MISMATCH。
          params_fingerprint: Idempotency::CanonicalJson.fingerprint(
            { "title" => "奶茶色寬版帽T", "description_html" => "<p>秋冬款</p>",
              "variants" => [ { "price" => "128.00" } ] }
          ),
          expires_at: 1.hour.from_now
        )
      end

      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("IDEMPOTENCY_CONCURRENT_REQUEST")
    end

    it "failed 列＝視為未執行：同 key 重試成功（11 §2.1(b)，不發 PREVIOUS_ATTEMPT_FAILED）" do
      login!
      key = SecureRandom.uuid
      # 第一次：業務失敗（空 title）⇒ claim 記 failed
      post_graphql(MUTATION, variables: {
        input: base_input(title: ""), idempotencyKey: key
      })
      expect(response.parsed_body.dig("data", "productSet", "userErrors", 0, "code")).to eq("BLANK")
      ActsAsTenant.with_tenant(shop) { expect(IdempotencyKey.sole.state).to eq("failed") }

      # 同 key、**修正後**輸入重試 ⇒ 成功（failed 分流先於指紋比對——
      # 「視為未執行」的重試帶的正是修正後參數，指紋隨新嘗試重置）。
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      expect(response.parsed_body.dig("data", "productSet", "userErrors")).to eq([])
      ActsAsTenant.with_tenant(shop) do
        expect(Product.count).to eq(1)
        expect(IdempotencyKey.sole.state).to eq("succeeded")
      end
    end

    it "建立態缺 idempotencyKey ⇒ top-level IDEMPOTENCY_KEY_REQUIRED（不是 userErrors）" do
      login!
      post_graphql(MUTATION, variables: { input: base_input })

      payload = response.parsed_body
      expect(payload.dig("data", "productSet")).to be_nil
      expect(payload.dig("errors", 0, "extensions", "code")).to eq("IDEMPOTENCY_KEY_REQUIRED")
    end
  end

  describe "驗證與錯誤轉譯" do
    it "空 title ⇒ userErrors field:[\"title\"] code:BLANK（HTTP 200、無 top-level errors）" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(title: "  "), idempotencyKey: SecureRandom.uuid
      })

      payload = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(payload["errors"]).to be_nil
      error = payload.dig("data", "productSet", "userErrors", 0)
      # 訊息依員工介面語言（ML-1）；factory 員工預設 en ⇒ 英文。繁中版在 spec/requests/staff_locale_update_spec.rb。
      expect(error).to eq({ "field" => [ "title" ], "message" => I18n.t("errors.product.title_blank", locale: :en), "code" => "BLANK" })
    end

    it "金額非嚴格兩位小數字串 ⇒ INVALID（不 round、不補位）" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(variants: [ { price: "128.5" } ]), idempotencyKey: SecureRandom.uuid
      })

      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("INVALID")
      expect(error["field"]).to eq([ "variants", "0", "price" ])
    end

    it "手填 handle 衝突 ⇒ HANDLE_TAKEN（拒絕，不自動加尾碼）" do
      login!
      ActsAsTenant.with_tenant(shop) do
        create(:product, shop:, title: "既有品", handle: "taken-handle")
      end
      post_graphql(MUTATION, variables: {
        input: base_input(handle: "taken-handle"), idempotencyKey: SecureRandom.uuid
      })

      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("HANDLE_TAKEN")
      ActsAsTenant.with_tenant(shop) { expect(Product.where(handle: "taken-handle").count).to eq(1) }
    end

    it "descriptionHtml 依白名單 sanitize（script 剝除、javascript: href 拔屬性）" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(
          descriptionHtml: %(<p>好</p><script>alert(1)</script><a href="javascript:x">連</a>)
        ),
        idempotencyKey: SecureRandom.uuid
      })

      ActsAsTenant.with_tenant(shop) do
        html = Product.sole.description_html
        expect(html).not_to include("<script")
        expect(html).not_to include("javascript:")
        expect(html).to include("<p>好</p>")
      end
    end

    # 🔴 紅色回歸釘（對抗審查 confirmed #2）：尾隨換行曾穿過行錨點 regex、
    # 在 to_storage 炸 Money::ExcessPrecision 成 HTTP 500。
    it "金額帶尾隨換行 ⇒ INVALID userError（不是 500）" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(variants: [ { price: "128.00
" } ]), idempotencyKey: SecureRandom.uuid
      })

      payload = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(payload["errors"]).to be_nil
      expect(payload.dig("data", "productSet", "userErrors", 0, "code")).to eq("INVALID")
    end

    it "手填 handle 撞保留字（new）⇒ INVALID" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(handle: "new"), idempotencyKey: SecureRandom.uuid
      })

      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("INVALID")
      expect(error["field"]).to eq([ "handle" ])
    end
  end

  describe "v1 射程守門（對抗審查 confirmed #13）" do
    # 歷史：v1 曾整段拒絕更新態（INVALID）；更新分支落地後，守門縮小為
    # 「缺 lockVersion 不得更新」（BLANK）——同輸入的行為演進在此釘住。
    it "帶 id 但缺 lockVersion ⇒ BLANK，不動任何資料" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(id: "gid://chilllove/Product/1"), idempotencyKey: SecureRandom.uuid
      })

      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("BLANK")
      expect(error["field"]).to eq([ "lockVersion" ])
      ActsAsTenant.with_tenant(shop) { expect(Product.count).to eq(0) }
    end

    it "variants 缺席 ⇒ INVALID（隱含變體必須恰一筆）" do
      login!
      post_graphql(MUTATION, variables: {
        input: { title: "無變體" }, idempotencyKey: SecureRandom.uuid
      })

      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("INVALID")
      expect(error["field"]).to eq([ "variants" ])
    end

    it "多筆 variants ⇒ INVALID（具名選項屬後續包）" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(variants: [ { price: "128.00" }, { price: "158.00" } ]),
        idempotencyKey: SecureRandom.uuid
      })

      expect(response.parsed_body.dig("data", "productSet", "userErrors", 0, "code")).to eq("INVALID")
    end
  end

  describe "更新態（帶 id ＋ lockVersion）" do
    def create_via_api!(key: SecureRandom.uuid)
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      response.parsed_body.dig("data", "productSet", "product")
    end

    it "宣告式覆寫：改標題／狀態／價格，lockVersion bump 並回傳" do
      login!
      created = create_via_api!

      post_graphql(MUTATION, variables: {
        input: base_input(
          id: created["id"], lockVersion: 0, title: "改名後", status: "ACTIVE",
          variants: [ { price: "199.00", sku: "SKU-9" } ]
        )
      })

      payload = response.parsed_body
      expect(payload["errors"]).to be_nil
      data = payload.dig("data", "productSet")
      expect(data["userErrors"]).to eq([])
      expect(data.dig("product", "title")).to eq("改名後")
      expect(data.dig("product", "status")).to eq("ACTIVE")
      expect(data.dig("product", "lockVersion")).to be > 0

      ActsAsTenant.with_tenant(shop) do
        product = Product.sole
        expect(product.title).to eq("改名後")
        expect(product.status).to eq("active")
        variant = product.product_variants.sole
        expect(variant.price_cents).to eq(19_900)
        expect(variant.sku).to eq("SKU-9")
        expect(EventOutbox.where(topic: "products/update", aggregate_id: product.id)).to exist
      end
    end

    it "過期 lockVersion ⇒ STALE_OBJECT（field null），資料不動" do
      login!
      created = create_via_api!
      # 先成功更新一次（版本前進）
      post_graphql(MUTATION, variables: {
        input: base_input(id: created["id"], lockVersion: 0, title: "第一次改")
      })
      expect(response.parsed_body.dig("data", "productSet", "userErrors")).to eq([])

      # 再用舊版本 0 儲存 ⇒ 輸
      post_graphql(MUTATION, variables: {
        input: base_input(id: created["id"], lockVersion: 0, title: "第二次改")
      })
      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("STALE_OBJECT")
      expect(error["field"]).to be_nil
      ActsAsTenant.with_tenant(shop) { expect(Product.sole.title).to eq("第一次改") }
    end

    it "缺 lockVersion ⇒ BLANK（更新必帶，防最後寫入者贏）" do
      login!
      created = create_via_api!
      post_graphql(MUTATION, variables: { input: base_input(id: created["id"]) })

      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("BLANK")
      expect(error["field"]).to eq([ "lockVersion" ])
    end

    it "第 6 包：handle 可改，改名同 txn 寫 301；同值＝no-op 不寫列" do
      login!
      created = create_via_api!
      old_handle = created["handle"]

      # 同值＝no-op：不產生 redirect
      post_graphql(MUTATION, variables: {
        input: base_input(id: created["id"], lockVersion: 0, handle: old_handle)
      })
      expect(response.parsed_body.dig("data", "productSet", "userErrors")).to eq([])
      ActsAsTenant.with_tenant(shop) { expect(UrlRedirect.count).to eq(0) }

      # 改名：301 同 transaction 落列
      post_graphql(MUTATION, variables: {
        input: base_input(id: created["id"], lockVersion: 1, handle: "changed-handle")
      })
      expect(response.parsed_body.dig("data", "productSet", "userErrors")).to eq([])
      ActsAsTenant.with_tenant(shop) do
        row = UrlRedirect.sole
        expect([ row.from_path, row.to_path, row.status_code, row.source ])
          .to eq([ "/products/#{old_handle}", "/products/changed-handle", 301, "handle_change" ])
      end
    end

    it "不存在／他店的 id ⇒ NOT_FOUND" do
      login!
      post_graphql(MUTATION, variables: {
        input: base_input(id: "gid://chilllove/Product/999999", lockVersion: 0)
      })
      expect(response.parsed_body.dig("data", "productSet", "userErrors", 0, "code")).to eq("NOT_FOUND")
    end
  end

  describe "組織分類＋SEO（91 §11–12，P1）" do
    ORG_MUTATION = <<~GRAPHQL
      mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
        productSet(input: $input, idempotencyKey: $idempotencyKey) {
          product {
            id lockVersion vendor productType tags
            seo { title description }
          }
          userErrors { field message code }
        }
      }
    GRAPHQL

    it "建立帶齊四欄位：strip、tags 去重保序、SEO 落覆寫欄" do
      login!
      post_graphql(ORG_MUTATION, variables: { idempotencyKey: SecureRandom.uuid, input: base_input(
        vendor: "  Frederic Malle ", productType: "香水",
        tags: [ " 花香 ", "花香", "秋冬", "" ],
        seo: { title: "玫瑰雷鳴 EDP", description: "前調玫瑰。" }
      ) })

      data = response.parsed_body.dig("data", "productSet")
      expect(data["userErrors"]).to eq([])
      expect(data.dig("product", "vendor")).to eq("Frederic Malle")
      expect(data.dig("product", "productType")).to eq("香水")
      expect(data.dig("product", "tags")).to eq([ "花香", "秋冬" ])
      expect(data.dig("product", "seo", "title")).to eq("玫瑰雷鳴 EDP")
      expect(data.dig("product", "seo", "description")).to eq("前調玫瑰。")
    end

    it "更新：缺席鍵保持現值、空字串／空陣列＝清除（宣告式語義）" do
      login!
      post_graphql(ORG_MUTATION, variables: { idempotencyKey: SecureRandom.uuid, input: base_input(
        vendor: "Frederic Malle", productType: "香水", tags: [ "花香" ],
        seo: { title: "玫瑰雷鳴" }
      ) })
      created = response.parsed_body.dig("data", "productSet", "product")

      # 只送 vendor 清除＋tags 清空：productType 與 seo.title 缺席 ⇒ 保持現值
      post_graphql(ORG_MUTATION, variables: { input: base_input(
        id: created["id"], lockVersion: created["lockVersion"],
        vendor: "", tags: []
      ) })

      data = response.parsed_body.dig("data", "productSet")
      expect(data["userErrors"]).to eq([])
      expect(data.dig("product", "vendor")).to be_nil
      expect(data.dig("product", "tags")).to eq([])
      expect(data.dig("product", "productType")).to eq("香水")
      expect(data.dig("product", "seo", "title")).to eq("玫瑰雷鳴")
    end

    it "SEO 標題超過 70 ⇒ userErrors seo.title TOO_LONG；Meta 描述 160–320 之間可存（160 是建議值不是上限）" do
      login!
      post_graphql(ORG_MUTATION, variables: { idempotencyKey: SecureRandom.uuid, input: base_input(
        seo: { title: "長" * (Limits.fetch(:content, :seo_title_max_chars) + 1) }
      ) })
      data = response.parsed_body.dig("data", "productSet")
      expect(data["userErrors"]).to contain_exactly(
        a_hash_including("field" => [ "seo", "title" ], "code" => "TOO_LONG")
      )

      over_serp = "描" * 200 # >160（SERP 建議）但 <320（上限）⇒ 必須成功
      post_graphql(ORG_MUTATION, variables: { idempotencyKey: SecureRandom.uuid, input: base_input(
        title: "第二件商品", seo: { description: over_serp }
      ) })
      data = response.parsed_body.dig("data", "productSet")
      expect(data["userErrors"]).to eq([])
      expect(data.dig("product", "seo", "description")).to eq(over_serp)
    end

    it "productVendors／productTypes：去重、字母序、tenant-scoped" do
      login!
      ActsAsTenant.with_tenant(shop) do
        create(:product, vendor: "Byredo", product_type: "香水")
        create(:product, vendor: "Aesop", product_type: "護膚")
        create(:product, vendor: "Byredo", product_type: nil)
      end
      other_shop = create(:shop, subdomain: "other-org-shop")
      ActsAsTenant.with_tenant(other_shop) { create(:product, vendor: "外店廠商") }

      post_graphql("query { productVendors productTypes }", variables: {})
      data = response.parsed_body["data"]
      expect(data["productVendors"]).to eq([ "Aesop", "Byredo" ])
      # utf8mb4_0900_ai_ci 對 CJK 按碼位序：護(U+8B77) < 香(U+9999)
      expect(data["productTypes"]).to eq([ "護膚", "香水" ])
    end
  end

  describe "product(id:) 查詢與 variants 讀取面" do
    it "編輯頁載入形：descriptionHtml 與變體金額（R4 兩位小數字串）" do
      login!
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: SecureRandom.uuid })
      gid = response.parsed_body.dig("data", "productSet", "product", "id")

      post_graphql(<<~GRAPHQL, variables: { id: gid })
        query($id: ID!) {
          product(id: $id) {
            id title descriptionHtml status lockVersion
            variants(first: 10) { nodes { id title price compareAtPrice sku taxable position } }
          }
        }
      GRAPHQL

      product = response.parsed_body.dig("data", "product")
      expect(product["title"]).to eq("奶茶色寬版帽T")
      expect(product["descriptionHtml"]).to eq("<p>秋冬款</p>")
      variant = product["variants"]["nodes"].sole
      expect(variant["title"]).to eq("Default Title")
      expect(variant["price"]).to eq("128.00")
      expect(variant["compareAtPrice"]).to be_nil
      expect(variant["taxable"]).to be(true)
    end
  end

  describe "回放的 result_ref 已刪（11 §2.1(b) 末列）" do
    it "回 NOT_FOUND userError（原請求成功、商品隨後被刪）" do
      login!
      key = SecureRandom.uuid
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      ActsAsTenant.with_tenant(shop) { Product.sole.destroy! }

      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: key })
      error = response.parsed_body.dig("data", "productSet", "userErrors", 0)
      expect(error["code"]).to eq("NOT_FOUND")
      ActsAsTenant.with_tenant(shop) { expect(Product.count).to eq(0) }
    end
  end

  describe "授權與租戶隔離" do
    it "無 products.edit 的一般 staff ⇒ top-level ACCESS_DENIED，不建資料" do
      limited = ActsAsTenant.with_tenant(shop) do
        create(:staff_member, shop:, owner: false)
      end
      login!(email: limited.email)
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: SecureRandom.uuid })

      payload = response.parsed_body
      expect(payload.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
      ActsAsTenant.with_tenant(shop) { expect(Product.count).to eq(0) }
    end

    it "建立的商品綁在目前租戶（shop_id 同源雙保險）" do
      login!
      post_graphql(MUTATION, variables: { input: base_input, idempotencyKey: SecureRandom.uuid })

      ActsAsTenant.without_tenant do
        expect(Product.sole.shop_id).to eq(shop.id)
      end
    end
  end

  private

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
