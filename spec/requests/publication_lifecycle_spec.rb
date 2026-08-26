# frozen_string_literal: true

require "rails_helper"

# S1：publication 生命週期的三支 mutation ＋ 讀取面。
#
# 本尊契約＝`docs/plans/2026-08-26-S1-規格草案.md` §1；
# admin 實測＝`docs/research/82-admin-channels.md` §11。
RSpec.describe "Admin GraphQL publication lifecycle", type: :request do
  let(:shop) { create(:shop, subdomain: "pub-life-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  let(:list_query) { <<~GRAPHQL }
    query publications {
      publications {
        id legacyResourceId title handle autoPublish catalogId catalogType
        supportsFuturePublishing supportsBundles supportsPublicationForUnlistedProducts
        operationStatus publishedResourceCount
      }
    }
  GRAPHQL

  let(:create_mutation) { <<~GRAPHQL }
    mutation publicationCreate($input: PublicationCreateInput!) {
      publicationCreate(input: $input) {
        publication { id title handle autoPublish catalogType publishedResourceCount }
        userErrors { field message code }
      }
    }
  GRAPHQL

  let(:update_mutation) { <<~GRAPHQL }
    mutation publicationUpdate($id: ID!, $input: PublicationUpdateInput!) {
      publicationUpdate(id: $id, input: $input) {
        publication { id autoPublish publishedResourceCount }
        userErrors { field message code }
      }
    }
  GRAPHQL

  let(:delete_mutation) { <<~GRAPHQL }
    mutation publicationDelete($id: ID!) {
      publicationDelete(id: $id) {
        deletedId
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "pub-life-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  # 🔴 每支 request spec 各自定義這三個 helper（本倉庫既有形態，見
  #   `spec/requests/shop_locale_settings_spec.rb` 等）。不抽共用 support——
  #   那是跨檔重構，不在本包射程內（鐵律 20.5）。
  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
  end

  def json = response.parsed_body

  def online_store
    ActsAsTenant.with_tenant(shop) { Publication.online_store! }
  end

  def gid(record) = "gid://chilllove/Publication/#{record.id}"

  # ── 讀取面 ────────────────────────────────────────────────────────────────

  describe "publications query" do
    it "回建店時建立的線上商店管道，title 取自 catalog、handle 取自 channel" do
      login!
      post_graphql(list_query)

      rows = json.dig("data", "publications")
      expect(rows.size).to eq(1)
      row = rows.first

      expect(row["id"]).to eq(gid(online_store))
      expect(row["legacyResourceId"]).to eq(online_store.id.to_s)
      # 🔴 title 的權威是 catalog.title，不是 publications.name（本尊 name 已 deprecated）
      expect(row["title"]).to eq("線上商店")
      # 🔴 handle 的權威是 channels.handle（S0 PR B 的權威遷移）
      expect(row["handle"]).to eq(Shop::DEFAULT_CHANNEL_HANDLE)
      expect(row["autoPublish"]).to be(true)
      expect(row["catalogType"]).to eq("app")
      expect(row["supportsFuturePublishing"]).to be(true)
      expect(row["supportsBundles"]).to be(true)
      expect(row["operationStatus"]).to be_nil
    end

    # 🔴 對外契約用本尊的 GID Type 名 `AppCatalog`，不是我方 model 名 `SalesCatalog`。
    #   model 名加 `Sales` 前綴是實作層為了避開既有命名空間，不該漏到契約上。
    it "catalogId 的 GID Type 是 AppCatalog（不是我方的 SalesCatalog）" do
      login!
      post_graphql(list_query)

      catalog_id = json.dig("data", "publications", 0, "catalogId")
      expect(catalog_id).to match(%r{\Agid://chilllove/AppCatalog/\d+\z})
    end

    it "看不到別間店的 publication（鐵律 2）" do
      create(:shop, subdomain: "pub-life-other")
      login!
      post_graphql(list_query)

      ids = json.dig("data", "publications").map { |row| row["legacyResourceId"].to_i }
      expect(ids).to eq([ online_store.id ])
    end
  end

  # ── publicationCreate ────────────────────────────────────────────────────

  describe "publicationCreate" do
    it "建立一個 catalog publication：自建 catalog、沒有 channel ⇒ handle 為 null" do
      login!
      post_graphql(create_mutation, variables: { input: { title: "批發目錄" } })

      payload = json.dig("data", "publicationCreate")
      expect(payload["userErrors"]).to eq([])
      expect(payload.dig("publication", "title")).to eq("批發目錄")
      # 🔴 API 建立的 publication **沒有 channel**（channel 是 app 的身分，來自安裝流程）
      expect(payload.dig("publication", "handle")).to be_nil
      expect(payload.dig("publication", "catalogType")).to eq("app")
      expect(payload.dig("publication", "publishedResourceCount")).to eq(0)
    end

    # 官方 `PublicationCreateInput.autoPublish` 明文 `Default:false`。
    it "autoPublish 缺席時預設 false（本尊 Default:false）" do
      login!
      post_graphql(create_mutation, variables: { input: { title: "預設值檢查" } })

      expect(json.dig("data", "publicationCreate", "publication", "autoPublish")).to be(false)
    end

    # 🔴 這一格盯的是「新建 publication 不得靜默改變既有商品的可見性」。
    #   autoPublish 只管**之後**建立的資源（本尊 `newly created products`），
    #   不回填存量——存量是 add-all 那條非同步路徑的事。
    it "🔴 autoPublish=true 的新 publication 不回填既有商品" do
      product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
      login!

      post_graphql(create_mutation, variables: { input: { title: "自動發布", autoPublish: true } })
      expect(json.dig("data", "publicationCreate", "userErrors")).to eq([])

      created = ActsAsTenant.without_tenant do
        Publication.where(shop_id: shop.id).order(:id).last
      end
      rows = ActsAsTenant.without_tenant do
        ResourcePublication.where(shop_id: shop.id, publication_id: created.id).count
      end
      expect(rows).to eq(0), "既有商品 #{product.id} 被靜默回填了——那是 add-all 的語義，不是 autoPublish"
    end

    it "🔴 defaultState=ALL_PRODUCTS 誠實拒絕（本步未支援），不是靜默當成 EMPTY" do
      login!
      post_graphql(create_mutation,
                   variables: { input: { title: "全部商品", defaultState: "ALL_PRODUCTS" } })

      errors = json.dig("data", "publicationCreate", "userErrors")
      expect(errors.size).to eq(1)
      expect(errors.first["code"]).to eq("FEATURE_NOT_ENABLED")
      expect(errors.first["field"]).to eq([ "input", "defaultState" ])
      expect(json.dig("data", "publicationCreate", "publication")).to be_nil
    end

    it "catalogId 指向不存在的 catalog ⇒ CATALOG_NOT_FOUND（HTTP 仍 200）" do
      login!
      post_graphql(create_mutation,
                   variables: { input: { title: "壞的 catalog", catalogId: "gid://chilllove/AppCatalog/999999" } })

      expect(response).to have_http_status(:ok)
      errors = json.dig("data", "publicationCreate", "userErrors")
      expect(errors.first["code"]).to eq("CATALOG_NOT_FOUND")
      expect(errors.first["field"]).to eq([ "input", "catalogId" ])
    end

    it "🔴 catalogId 指向**別間店**的 catalog ⇒ 一樣是 CATALOG_NOT_FOUND，不得成功" do
      other = create(:shop, subdomain: "pub-life-cross")
      other_catalog = ActsAsTenant.without_tenant { SalesCatalog.find_by(shop_id: other.id) }
      login!

      post_graphql(create_mutation, variables: {
        input: { title: "跨租戶", catalogId: "gid://chilllove/AppCatalog/#{other_catalog.id}" }
      })

      expect(json.dig("data", "publicationCreate", "userErrors").first["code"]).to eq("CATALOG_NOT_FOUND")
    end
  end

  # ── publicationUpdate ────────────────────────────────────────────────────

  describe "publicationUpdate" do
    let!(:product) { ActsAsTenant.with_tenant(shop) { create(:product, shop:) } }

    def target
      ActsAsTenant.without_tenant { Publication.where(shop_id: shop.id).order(:id).last }
    end

    before do
      login!
      post_graphql(create_mutation, variables: { input: { title: "目標管道" } })
    end

    it "把商品加入 publication（累加語義）" do
      post_graphql(update_mutation, variables: {
        id: gid(target),
        input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
      })

      payload = json.dig("data", "publicationUpdate")
      expect(payload["userErrors"]).to eq([])
      expect(payload.dig("publication", "publishedResourceCount")).to eq(1)
    end

    # 🔴 本尊官方逐字：`If the variant is already published to that publication,
    #   the mutation succeeds with no change.`
    it "🔴 重複加入是 no-op success，不是 ALREADY_EXISTS" do
      2.times do
        post_graphql(update_mutation, variables: {
          id: gid(target),
          input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
        })
      end

      expect(json.dig("data", "publicationUpdate", "userErrors")).to eq([])
      expect(json.dig("data", "publicationUpdate", "publication", "publishedResourceCount")).to eq(1)
    end

    it "移除 publishable" do
      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
      })
      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToRemove: [ "gid://chilllove/Product/#{product.id}" ] }
      })

      expect(json.dig("data", "publicationUpdate", "userErrors")).to eq([])
      expect(json.dig("data", "publicationUpdate", "publication", "publishedResourceCount")).to eq(0)
    end

    # 🔴 這是 S1 最容易做錯的一格。本倉庫的 `productSet`／`collectionSet` 是**宣告式全量**
    #   （未列出＝移除），而本尊的發布是**累加**（`docs/research/82` §11.5 實測：
    #   發布 modal 一律全部未勾開場）。照宣告式習慣實作，商家一次勾選會清空整個管道。
    it "🔴 只送 publishablesToAdd 時，既有成員**不得**被移除（累加不是宣告式全量）" do
      second = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }

      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
      })
      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{second.id}" ] }
      })

      expect(json.dig("data", "publicationUpdate", "publication", "publishedResourceCount")).to eq(2)
    end

    it "autoPublish 缺席＝保持現值（官方未標 default，我方明文選保持）" do
      post_graphql(update_mutation, variables: { id: gid(target), input: { autoPublish: true } })
      expect(json.dig("data", "publicationUpdate", "publication", "autoPublish")).to be(true)

      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
      })
      expect(json.dig("data", "publicationUpdate", "publication", "autoPublish")).to be(true)
    end

    # 🔴 合計超過上限 ⇒ TOO_BIG。fail-closed 取「合計」是 ours 加嚴：
    #   官方兩句措辭不同（`simultaneously` vs `per operation`）且都沒指明切分。
    it "🔴 加與減**合計**超過 limits 上限 ⇒ TOO_BIG" do
      cap = Limits.fetch(:sales_channels, :publication_bulk_products_max)
      add = Array.new(cap) { |i| "gid://chilllove/Product/#{i + 1}" }

      post_graphql(update_mutation, variables: {
        id: gid(target),
        input: { publishablesToAdd: add, publishablesToRemove: [ "gid://chilllove/Product/#{product.id}" ] }
      })

      errors = json.dig("data", "publicationUpdate", "userErrors")
      expect(errors.size).to eq(1)
      expect(errors.first["code"]).to eq("TOO_BIG")
      expect(errors.first["message"]).to include(cap.to_s)
    end

    it "恰好等於上限 ⇒ 通過（邊界不是差一）" do
      cap = Limits.fetch(:sales_channels, :publication_bulk_products_max)
      products = ActsAsTenant.with_tenant(shop) { Array.new(cap - 1) { create(:product, shop:) } }
      gids = ([ product ] + products).map { |record| "gid://chilllove/Product/#{record.id}" }
      expect(gids.size).to eq(cap)

      post_graphql(update_mutation, variables: { id: gid(target), input: { publishablesToAdd: gids } })

      expect(json.dig("data", "publicationUpdate", "userErrors")).to eq([])
      expect(json.dig("data", "publicationUpdate", "publication", "publishedResourceCount")).to eq(cap)
    end

    # 🔴 帶索引的 field path（28 §0.3.1：陣列索引用十進位裸字串）——
    #   50 筆一起送時，帶索引是前端定位「第幾筆出錯」的唯一方式。
    it "🔴 不合法的 GID 逐筆回報且帶陣列索引" do
      post_graphql(update_mutation, variables: {
        id: gid(target),
        input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}", "not-a-gid" ] }
      })

      errors = json.dig("data", "publicationUpdate", "userErrors")
      expect(errors.size).to eq(1)
      expect(errors.first["code"]).to eq("INVALID_PUBLISHABLE_ID")
      expect(errors.first["field"]).to eq([ "input", "publishablesToAdd", "1" ])
    end

    it "🔴 任何一筆不合法 ⇒ 整批不寫入（不是寫一半）" do
      post_graphql(update_mutation, variables: {
        id: gid(target),
        input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}", "not-a-gid" ] }
      })

      rows = ActsAsTenant.without_tenant do
        ResourcePublication.where(shop_id: shop.id, publication_id: target.id).count
      end
      expect(rows).to eq(0)
    end

    it "🔴 別間店的商品 ⇒ INVALID_PUBLISHABLE_ID（不得跨租戶發布）" do
      other = create(:shop, subdomain: "pub-life-victim")
      victim = ActsAsTenant.with_tenant(other) { create(:product, shop: other) }

      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{victim.id}" ] }
      })

      expect(json.dig("data", "publicationUpdate", "userErrors").first["code"]).to eq("INVALID_PUBLISHABLE_ID")
    end

    # `PUBLISHABLE_TYPES` 之外的型別（例如 File）不得被當成 publishable。
    it "🔴 非 publishable 型別的 GID 被擋（值域是封閉集合）" do
      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/File/1" ] }
      })

      expect(json.dig("data", "publicationUpdate", "userErrors").first["code"]).to eq("INVALID_PUBLISHABLE_ID")
    end

    it "publication GID 查不到 ⇒ NOT_FOUND，HTTP 仍 200" do
      post_graphql(update_mutation, variables: {
        id: "gid://chilllove/Publication/999999", input: { autoPublish: true }
      })

      expect(response).to have_http_status(:ok)
      errors = json.dig("data", "publicationUpdate", "userErrors")
      expect(errors.first["code"]).to eq("NOT_FOUND")
      expect(errors.first["field"]).to eq([ "id" ])
    end

    # 🔴 cache stamp：發布狀態變了、前台可見性就變了，快取必須失效。
    #   ⚠️ 但**不得**動 `lock_version`——那會把商家開著的編輯表單直接作廢
    #   （`app/models/product.rb` 的 `bump_publications_stamp!` 記過這個事故）。
    it "🔴 加入商品會 bump publications_updated_at，且**不動** lock_version" do
      before_stamp, before_lock = ActsAsTenant.without_tenant do
        Product.where(id: product.id).pick(:publications_updated_at, :lock_version)
      end

      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
      })

      after_stamp, after_lock = ActsAsTenant.without_tenant do
        Product.where(id: product.id).pick(:publications_updated_at, :lock_version)
      end

      expect(after_stamp).to be > before_stamp
      expect(after_lock).to eq(before_lock),
        "lock_version 被推進了——商家開著的商品編輯表單會直接 StaleObjectError"
    end

    # 變體的發布狀態會改變父商品的有效可購買性（`Product.published_on` 的第二個 EXISTS）
    # ⇒ 規則與 `Publications::Materialize.bump_publications_stamp!` 同一份。
    it "🔴 加入**變體**時 bump 的是父商品的 stamp" do
      variant = ActsAsTenant.with_tenant(shop) { create(:product_variant, product:) }
      before_stamp = ActsAsTenant.without_tenant { Product.where(id: product.id).pick(:publications_updated_at) }

      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/ProductVariant/#{variant.id}" ] }
      })

      after_stamp = ActsAsTenant.without_tenant { Product.where(id: product.id).pick(:publications_updated_at) }
      expect(after_stamp).to be > before_stamp
    end
  end

  # ── publicationDelete ────────────────────────────────────────────────────

  describe "publicationDelete" do
    let!(:product) { ActsAsTenant.with_tenant(shop) { create(:product, shop:) } }

    def target
      ActsAsTenant.without_tenant { Publication.where(shop_id: shop.id).order(:id).last }
    end

    before do
      login!
      post_graphql(create_mutation, variables: { input: { title: "要刪的目錄" } })
    end

    it "刪掉 API 建立的 publication" do
      id = gid(target)
      post_graphql(delete_mutation, variables: { id: })

      payload = json.dig("data", "publicationDelete")
      expect(payload["userErrors"]).to eq([])
      expect(payload["deletedId"]).to eq(id)
      expect(ActsAsTenant.without_tenant { Publication.where(shop_id: shop.id).count }).to eq(1)
    end

    # 🔴 這一格是本 PR 最重要的守衛。沒有它，刪掉線上商店 publication 會讓
    #   `Publication.online_store` 回 nil，而那個 nil 的後果是
    #   **整店商品前台不可見且不拋任何錯**（與 S0 修掉的 C-9 是同一個症狀）。
    it "🔴 綁著 channel 的 publication 不可刪（CANNOT_MODIFY_APP_CATALOG_PUBLICATION）" do
      post_graphql(delete_mutation, variables: { id: gid(online_store) })

      errors = json.dig("data", "publicationDelete", "userErrors")
      expect(errors.size).to eq(1)
      expect(errors.first["code"]).to eq("CANNOT_MODIFY_APP_CATALOG_PUBLICATION")
      expect(errors.first["field"]).to eq([ "id" ])
      expect(json.dig("data", "publicationDelete", "deletedId")).to be_nil
      expect(ActsAsTenant.with_tenant(shop) { Publication.online_store }).to be_present
    end

    # 🔴 Medusa 明文區分 `dismiss`（解除關聯）與 `delete`（連帶刪被連記錄）；我方只做前者。
    #   沒有這條測試，未來有人在 publishable 側加 `dependent: :destroy` 就是靜默資料遺失。
    it "🔴 級聯刪發布列，但**絕不**連帶刪商品本體" do
      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
      })
      expect(ActsAsTenant.without_tenant { ResourcePublication.where(shop_id: shop.id, publication_id: target.id).count }).to eq(1)

      publication_id = target.id
      post_graphql(delete_mutation, variables: { id: gid(target) })

      expect(json.dig("data", "publicationDelete", "userErrors")).to eq([])
      ActsAsTenant.without_tenant do
        expect(ResourcePublication.where(shop_id: shop.id, publication_id: publication_id).count).to eq(0)
        expect(Product.where(id: product.id).count).to eq(1), "商品本體被連帶刪了"
      end
    end

    # 🔴 `dependent: :destroy` **不會** bump cache stamp。刪 publication 會讓大量商品的
    #   前台可見性改變，而快取不失效**且不拋錯**——必須在刪除路徑顯式 bump，
    #   且順序不可倒（刪完就查不到受影響的是哪些商品了）。
    it "🔴 刪除會 bump 受影響商品的 publications_updated_at" do
      post_graphql(update_mutation, variables: {
        id: gid(target), input: { publishablesToAdd: [ "gid://chilllove/Product/#{product.id}" ] }
      })
      before_stamp = ActsAsTenant.without_tenant { Product.where(id: product.id).pick(:publications_updated_at) }

      post_graphql(delete_mutation, variables: { id: gid(target) })

      after_stamp = ActsAsTenant.without_tenant { Product.where(id: product.id).pick(:publications_updated_at) }
      expect(after_stamp).to be > before_stamp
    end

    # 🔴 **這一格是線上驗證抓到的缺陷**（2026-08-26 正式庫實跑，逐字輸出
    #   `cleanup: publication_left=0 catalog_left=1`）：刪 publication 之後
    #   `sales_catalogs` 那一列留在庫裡，每建一次刪一次就漏一列、而且不拋任何錯。
    #   ⚠️ 上面那些格子抓不到它——它們數的是 publication 與發布列，**沒有人數 catalog**。
    it "🔴 刪掉自建的 publication 會一併清掉它的 catalog（不留孤兒列）" do
      catalog_id = ActsAsTenant.without_tenant { target.sales_catalog_id }
      expect(catalog_id).to be_present

      post_graphql(delete_mutation, variables: { id: gid(target) })

      expect(json.dig("data", "publicationDelete", "userErrors")).to eq([])
      expect(ActsAsTenant.without_tenant { SalesCatalog.where(id: catalog_id).count }).to eq(0)
    end

    # 🔴 **這一格是上一格帶出來的第二個缺陷**：本來想測「共用 catalog 時不得誤刪」，
    #   寫出來才發現**共用 catalog 這件事本身就不該被接受**——我方
    #   `SalesCatalog has_one :publication` 是 1:1，但在此之前沒有任何東西擋它，
    #   第二個 publication 會撞到 `channel_handle` 的唯一性（佔位值由 catalog id 導出），
    #   錯誤訊息指向一個呼叫端**根本沒有傳的欄位**（`input.channelHandle`）。
    #   ⇒ 改成在源頭擋，錯誤指向真正的輸入欄位。
    it "🔴 catalogId 指向已經有 publication 的 catalog ⇒ TAKEN（一個 catalog 最多一個 publication）" do
      taken_catalog_id = ActsAsTenant.without_tenant { target.sales_catalog_id }

      post_graphql(create_mutation, variables: {
        input: { title: "想共用 catalog", catalogId: "gid://chilllove/AppCatalog/#{taken_catalog_id}" }
      })

      errors = json.dig("data", "publicationCreate", "userErrors")
      expect(errors.size).to eq(1)
      expect(errors.first["code"]).to eq("TAKEN")
      expect(errors.first["field"]).to eq([ "input", "catalogId" ]),
        "錯誤必須指向呼叫端真的傳了的欄位，不是 channelHandle 那個內部佔位欄"
    end

    # 🔴 **孤兒清理的判準是「沒有 publication 指著」，不是「這是不是我們建的」。**
    #   有了上面那道 TAKEN 守衛之後，共用 catalog 在**服務層**已經不可達
    #   ⇒ 這一格刻意繞過服務層、直接在 model 層構造該狀態，證明那道判準真的在做事。
    #   ⚠️ 沒有這一格，`destroy_orphan_catalog!` 的 `exists?` 判準是**沒人看著的死碼**：
    #   把它整行拿掉，上面所有格子照樣全綠（本輪突變實測 M9 得到 `0 failures`）。
    #   ⚠️ 它不是多餘的：`Publication : Catalog` 是 1:1 還是 1:N ＝**官方未取得**
    #   （S1 規格草案 U-19）。哪天放寬成 1:N，這道判準就從防禦變成承重。
    it "🔴 catalog 仍被別的 publication 指著時，刪除**不得**把它一併清掉" do
      shared_catalog_id = ActsAsTenant.without_tenant { target.sales_catalog_id }

      # 繞過服務層與 validation，直接造出「兩個 publication 共用一個 catalog」。
      squatter = ActsAsTenant.without_tenant do
        Publication.create!(shop_id: shop.id, name: "借用者", channel_handle: "squatter",
                            auto_publish: false, supports_future_publishing: true)
      end
      ActsAsTenant.without_tenant { squatter.update_columns(sales_catalog_id: shared_catalog_id) }

      post_graphql(delete_mutation, variables: { id: gid(target) })

      expect(json.dig("data", "publicationDelete", "userErrors")).to eq([])
      expect(ActsAsTenant.without_tenant { SalesCatalog.where(id: shared_catalog_id).count }).to eq(1),
        "catalog 還被 publication ##{squatter.id} 指著卻被刪了——那會留下一個指向不存在 catalog 的外鍵"
    end

    # 建店那個 catalog 同樣受保護（它的 publication 綁著 channel）。
    it "🔴 catalogId 指向建店的 catalog 也是 TAKEN" do
      online_catalog_id = ActsAsTenant.without_tenant { online_store.sales_catalog_id }

      post_graphql(create_mutation, variables: {
        input: { title: "想借線上商店的 catalog", catalogId: "gid://chilllove/AppCatalog/#{online_catalog_id}" }
      })

      expect(json.dig("data", "publicationCreate", "userErrors").first["code"]).to eq("TAKEN")
    end

    # 線上驗證同時證實：建店那個 catalog 不會被誤刪（它的 publication 綁著 channel、刪不掉）。
    it "🔴 建店的 catalog 不受影響" do
      before_count = ActsAsTenant.without_tenant { SalesCatalog.where(shop_id: shop.id).count }
      post_graphql(delete_mutation, variables: { id: gid(target) })

      after_count = ActsAsTenant.without_tenant { SalesCatalog.where(shop_id: shop.id).count }
      expect(after_count).to eq(before_count - 1)
      expect(ActsAsTenant.with_tenant(shop) { Publication.online_store!.sales_catalog }).to be_present
    end

    it "GID 查不到 ⇒ NOT_FOUND，deletedId 為 null" do
      post_graphql(delete_mutation, variables: { id: "gid://chilllove/Publication/999999" })

      expect(json.dig("data", "publicationDelete", "deletedId")).to be_nil
      expect(json.dig("data", "publicationDelete", "userErrors").first["code"]).to eq("NOT_FOUND")
    end

    it "🔴 別間店的 publication ⇒ NOT_FOUND（不得跨租戶刪除）" do
      other = create(:shop, subdomain: "pub-life-target")
      victim = ActsAsTenant.without_tenant { Publication.find_by(shop_id: other.id) }

      post_graphql(delete_mutation, variables: { id: gid(victim) })

      expect(json.dig("data", "publicationDelete", "userErrors").first["code"]).to eq("NOT_FOUND")
      expect(ActsAsTenant.without_tenant { Publication.where(id: victim.id).count }).to eq(1)
    end
  end
end
