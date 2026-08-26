# frozen_string_literal: true

require "rails_helper"

# S5：`publishablePublish` ／ `publishableUnpublish` 的完整寫入狀態矩陣。
#
# 🔴 **本檔的存在理由**：在 S5 之前，全倉**沒有任何路徑能修改既有列的 `published_at`**
#   ——S1 的 add 分支走 `find_or_create_by!` 的 create-only 區塊，`find_by` 命中時
#   區塊根本不執行 ⇒ 設排程／改期／取消排程結構上無路可達。本檔是那條路徑的守衛。
#
# 🔴 **判準集合**（§3.3 狀態矩陣的每一格都必須有正反 fixture）：
#   R1 不存在＋省略／R2 不存在＋未來／R3 NULL＋省略／R4 NULL＋未來／
#   R5 已發布＋省略（no-op）／R6 已發布＋未來（改成排程）／
#   R7 排程中＋省略（🔴 **不得**靜默取消排程）／R8 排程中＋另一未來（改期）／
#   R9 排程中＋過去（取消排程並立即發布）／R10 明確 null（reject）／
#   R11 管道不支援排程／R12 變體不得排程／U1 刪列／U2 no-op／U3 publishDate 無效果
#   複驗集合：`grep -n "  describe \|    it \"R" spec/requests/publishable_write_spec.rb`
#
# @see docs/dev/m2-publishable-write.md
# @see docs/plans/2026-08-27-S5-規格草案.md §3.3
# @see docs/research/82-admin-channels.md §13
RSpec.describe "Admin GraphQL publishable write", type: :request do
  let(:shop) { create(:shop, subdomain: "pub-write") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let(:future) { 3.days.from_now.change(usec: 0) }
  let(:later) { 9.days.from_now.change(usec: 0) }
  let(:past) { 2.days.ago.change(usec: 0) }

  let(:publish_mutation) { <<~GRAPHQL }
    mutation publishablePublish($id: ID!, $input: [PublicationInput!]!) {
      publishablePublish(id: $id, input: $input) {
        publishable {
          ... on Product { id }
          resourcePublicationsV2(onlyPublished: false) {
            isPublished publishDate publication { id }
          }
        }
        userErrors { field message code }
      }
    }
  GRAPHQL

  let(:unpublish_mutation) { <<~GRAPHQL }
    mutation publishableUnpublish($id: ID!, $input: [PublicationInput!]!) {
      publishableUnpublish(id: $id, input: $input) {
        publishable {
          ... on Product { id }
          resourcePublicationsV2(onlyPublished: false) { isPublished publication { id } }
        }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "pub-write.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
  end

  def json = response.parsed_body

  def online_store = ActsAsTenant.with_tenant(shop) { Publication.online_store! }

  # 第二個管道：預設**支援**排程；R11 另外建一個不支援的。
  def extra_publication(name: "第二管道", supports_future: true)
    ActsAsTenant.with_tenant(shop) do
      Publication.create!(shop_id: shop.id, name:, channel_handle: name.parameterize.presence || "extra",
                          auto_publish: false, supports_future_publishing: supports_future)
    end
  end

  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      record = create(:product, shop:)
      create(:product_variant, product: record)
      record
    end
  end

  def product_gid = "gid://chilllove/Product/#{product.id}"
  def publication_gid(publication) = "gid://chilllove/Publication/#{publication.id}"

  def row_for(publication, record: product)
    ActsAsTenant.without_tenant do
      ResourcePublication.find_by(shop_id: shop.id, publication_id: publication.id,
                                  publishable_type: record.class.name, publishable_id: record.id)
    end
  end

  # `Publications::Materialize` 只把商品物化到**線上商店**，所以第二個管道天然沒有列
  # ⇒ 「不存在」那兩格用它，不必先刪東西（刪了再測會把 R1 與 U1 綁在一起）。
  def publish!(entries, id: product_gid)
    post_graphql(publish_mutation, variables: { id:, input: entries })
  end

  def unpublish!(entries, id: product_gid)
    post_graphql(unpublish_mutation, variables: { id:, input: entries })
  end

  def user_errors(field = "publishablePublish")
    json.dig("data", field, "userErrors")
  end

  # ── 狀態矩陣：既有列「不存在」 ────────────────────────────────────────────

  describe "既有列不存在" do
    let!(:target) { extra_publication }

    it "R1：省略 publishDate ⇒ 建列並立即發布" do
      login!
      publish!([ { publicationId: publication_gid(target) } ])

      expect(user_errors).to eq([])
      row = row_for(target)
      expect(row).to be_present
      expect(row.published?).to be(true)
      expect(row.published_at).to be_within(30.seconds).of(Time.current)
    end

    it "R2：未來 publishDate ⇒ 建列並排程（V2 回 isPublished=false）" do
      login!
      publish!([ { publicationId: publication_gid(target), publishDate: future.iso8601 } ])

      expect(user_errors).to eq([])
      expect(row_for(target).published_at).to eq(future)

      staged = json.dig("data", "publishablePublish", "publishable", "resourcePublicationsV2")
        .find { |entry| entry.dig("publication", "id") == publication_gid(target) }
      expect(staged["isPublished"]).to be(false)
    end
  end

  # ── 狀態矩陣：既有列 published_at IS NULL ─────────────────────────────────
  #
  # 🔴 這兩格是**硬需求**，不是完整性練習：NULL 列佔住 `uq_res_pub_target`，
  #   舊的 create-only 寫法在這裡什麼都不做 ⇒ **回報成功但資源仍不可見**（靜默資料損壞）。

  describe "既有列 published_at 為 NULL" do
    before do
      ActsAsTenant.without_tenant do
        ResourcePublication.where(id: row_for(online_store).id).update_all(published_at: nil)
      end
    end

    it "🔴 R3：省略 publishDate ⇒ 把 NULL 改成現在（不是 no-op）" do
      login!
      publish!([ { publicationId: publication_gid(online_store) } ])

      expect(user_errors).to eq([])
      expect(row_for(online_store).published?).to be(true)
    end

    it "🔴 R4：未來 publishDate ⇒ 把 NULL 改成該時間" do
      login!
      publish!([ { publicationId: publication_gid(online_store), publishDate: future.iso8601 } ])

      expect(user_errors).to eq([])
      expect(row_for(online_store).published_at).to eq(future)
    end
  end

  # ── 狀態矩陣：既有列已發布 ────────────────────────────────────────────────

  describe "既有列已發布（過去時間）" do
    it "R5：省略 publishDate ⇒ no-op success，published_at **不變**" do
      before_at = row_for(online_store).published_at
      login!
      publish!([ { publicationId: publication_gid(online_store) } ])

      expect(user_errors).to eq([])
      expect(row_for(online_store).published_at).to eq(before_at)
    end

    # 🔴 官方沉默 ⇒ ours 裁定。反面選項是回 INVALID_STATE；取「照做」的依據是
    #   `id` 參數描述逐字含 `create or **update**`，且商家意圖明確。
    it "🔴 R6（ours）：未來 publishDate ⇒ 把已發布改成排程" do
      login!
      publish!([ { publicationId: publication_gid(online_store), publishDate: future.iso8601 } ])

      expect(user_errors).to eq([])
      row = row_for(online_store)
      expect(row.published_at).to eq(future)
      expect(row.published?).to be(false), "已改成排程態就不該再算已發布"
    end
  end

  # ── 狀態矩陣：既有列排程中 ────────────────────────────────────────────────

  describe "既有列排程中（未來時間）" do
    before do
      ActsAsTenant.without_tenant do
        ResourcePublication.where(id: row_for(online_store).id).update_all(published_at: future)
      end
    end

    # 🔴 **這一格是本檔最重要的反向釘子**：官方那句 no-change 的主詞是「已發布」，
    #   射程未涵蓋排程態（未取得）⇒ fail-closed 取 no-op。
    #   反面（把它改寫成現在）＝**靜默取消排程**，正是 S2 §4-E4 登記的事故形態。
    it "🔴 R7（ours，fail-closed）：省略 publishDate ⇒ **不得**動排程日期" do
      login!
      publish!([ { publicationId: publication_gid(online_store) } ])

      expect(user_errors).to eq([])
      expect(row_for(online_store).published_at).to eq(future),
        "省略 publishDate 把排程改寫成現在＝靜默取消商家設好的排程"
    end

    it "R8：另一個未來時間 ⇒ 改期" do
      login!
      publish!([ { publicationId: publication_gid(online_store), publishDate: later.iso8601 } ])

      expect(user_errors).to eq([])
      expect(row_for(online_store).published_at).to eq(later)
    end

    # 🔴 證明是 UPDATE 不是「刪了重建」——後者會讓 `created_at` 前進，
    #   也會讓任何掛在列身上的東西（日後的稽核、feedback）憑空消失。
    it "🔴 改期走的是 UPDATE：created_at 不變、id 不變" do
      row = row_for(online_store)
      login!
      publish!([ { publicationId: publication_gid(online_store), publishDate: later.iso8601 } ])

      after = row_for(online_store)
      expect(after.id).to eq(row.id)
      expect(after.created_at).to eq(row.created_at)
    end

    it "R9：過去時間 ⇒ 取消排程並立即發布" do
      login!
      publish!([ { publicationId: publication_gid(online_store), publishDate: past.iso8601 } ])

      expect(user_errors).to eq([])
      row = row_for(online_store)
      expect(row.published_at).to eq(past)
      expect(row.published?).to be(true)
    end
  end

  # ── R10：明確傳 null ──────────────────────────────────────────────────────

  describe "publishDate 明確傳 null" do
    # 🔴 官方對 `null` 完全沉默（三個版本的 PublicationInput 頁、兩支 mutation 頁、
    #   兩份 sales-channel 指南全文皆無相關陳述，取證 2026-08-27）
    #   ⇒ **不得**自行定義成「取消排程」（會與 unpublish 語義重疊且無官方背書）。
    it "🔴 R10（ours，fail-closed）：明確 null ⇒ reject INVALID，且什麼都不寫" do
      before_at = row_for(online_store).published_at
      login!
      publish!([ { publicationId: publication_gid(online_store), publishDate: nil } ])

      error = user_errors.sole
      expect(error["code"]).to eq("INVALID")
      expect(error["field"]).to eq([ "input", "0", "publishDate" ])
      expect(row_for(online_store).published_at).to eq(before_at)
    end

    # 🔴 這一格與上一格的差別**只有「有沒有寫這個 key」**——GraphQL 把兩者都
    #   餵成 `nil`，只有 `input.key?(:publish_date)` 分得開。少了這一格，
    #   把 `key?` 改成單純讀值的實作會 100% 全綠而 R5／R7 全部退化成 reject。
    it "🔴 省略該 key 與明確傳 null 是**兩種語義**（R5 no-op vs R10 reject）" do
      login!
      publish!([ { publicationId: publication_gid(online_store) } ])

      expect(user_errors).to eq([]), "省略 publishDate 不是錯誤，它是 no-op success"
    end
  end

  # ── R11／R12：兩道排程守衛 ────────────────────────────────────────────────

  describe "排程守衛" do
    # 🔴 **必須用 fixture 明確建出不支援排程的管道**：兩處生產路徑
    #   （`Shop#create_default_publication` 與 `Publications::Write.create`）
    #   **都寫死 `supports_future_publishing: true`** ⇒ 照生產資料寫測試會 100% 全綠
    #   而這道守衛從未被執行（fail-open 登記，鐵律 20.2 第 5 類）。
    it "🔴 R11：管道不支援排程 ⇒ FEATURE_NOT_ENABLED（fail-open 登記：生產路徑觸發不到）" do
      target = extra_publication(name: "不支援排程", supports_future: false)
      login!
      publish!([ { publicationId: publication_gid(target), publishDate: future.iso8601 } ])

      error = user_errors.sole
      expect(error["code"]).to eq("FEATURE_NOT_ENABLED")
      expect(error["field"]).to eq([ "input", "0", "publishDate" ])
      expect(row_for(target)).to be_nil
    end

    it "R11 反面：同一個管道收**過去**時間 ⇒ 通過（守衛只擋未來，不擋非空）" do
      target = extra_publication(name: "不支援排程", supports_future: false)
      login!
      publish!([ { publicationId: publication_gid(target), publishDate: past.iso8601 } ])

      expect(user_errors).to eq([])
      expect(row_for(target).published_at).to eq(past)
    end

    it "🔴 R12：變體不得排程 ⇒ INVALID_STATE" do
      variant = ActsAsTenant.without_tenant { product.product_variants.first }
      login!
      publish!([ { publicationId: publication_gid(online_store), publishDate: future.iso8601 } ],
               id: "gid://chilllove/ProductVariant/#{variant.id}")

      error = user_errors.sole
      expect(error["code"]).to eq("INVALID_STATE")
      # 判準來自正典而不是硬編字面值（鐵律 6）
      expect(Limits.fetch(:sales_channels, :future_publishing_unsupported)).to include("variant")
    end
  end

  # ── 取消發布 ─────────────────────────────────────────────────────────────

  describe "publishableUnpublish" do
    it "U1：既有列 ⇒ 硬刪整列（不是設回 NULL）" do
      login!
      unpublish!([ { publicationId: publication_gid(online_store) } ])

      expect(user_errors("publishableUnpublish")).to eq([])
      expect(row_for(online_store)).to be_nil,
        "留一列 published_at IS NULL 會佔住唯一鍵，重新發布時踩靜默失效"
    end

    it "🔴 U2（ours）：本來就沒發布 ⇒ no-op success，不報錯" do
      target = extra_publication
      login!
      unpublish!([ { publicationId: publication_gid(target) } ])

      expect(user_errors("publishableUnpublish")).to eq([])
      expect(row_for(target)).to be_nil
    end

    # 🔴 官方唯一的規範句：`This field has no effect if you include it in the
    #   publishableUnpublish mutation.` ——注意它說的是「無效果」不是「報錯」。
    it "🔴 U3：unpublish 帶 publishDate ⇒ **完全無效果**（不報錯、不生效、照樣刪）" do
      login!
      unpublish!([ { publicationId: publication_gid(online_store), publishDate: future.iso8601 } ])

      expect(user_errors("publishableUnpublish")).to eq([])
      expect(row_for(online_store)).to be_nil
    end

    it "🔴 U3 反面：unpublish 帶**明確 null** 的 publishDate 也不報錯（publish 側會 reject）" do
      login!
      unpublish!([ { publicationId: publication_gid(online_store), publishDate: nil } ])

      expect(user_errors("publishableUnpublish")).to eq([])
    end

    # 🔴 **這兩格才真的釘住「無效果」**：上面那些 U3 格子送的日期在 publish 側
    #   本來就會通過，所以「有沒有跳過驗證」根本分不出來——突變測試實跑證實：
    #   把 `if mode == :publish` 改成 `if true`（unpublish 也驗）時它們**全綠**。
    #   要分辨得出來，送的日期就必須是 publish 側**一定會擋**的那種。
    it "🔴 U3：unpublish 一個變體＋未來日期 ⇒ 不報錯（publish 側會回 INVALID_STATE）" do
      variant = ActsAsTenant.without_tenant { product.product_variants.first }
      variant_gid = "gid://chilllove/ProductVariant/#{variant.id}"
      login!
      unpublish!([ { publicationId: publication_gid(online_store), publishDate: future.iso8601 } ],
                 id: variant_gid)

      expect(user_errors("publishableUnpublish")).to eq([])
      expect(row_for(online_store, record: variant)).to be_nil

      # 對照組：同一組輸入送 publish 側**必須**被擋——證明上一句不是因為守衛整個壞了。
      publish!([ { publicationId: publication_gid(online_store), publishDate: future.iso8601 } ],
               id: variant_gid)
      expect(user_errors.sole["code"]).to eq("INVALID_STATE")
    end

    it "🔴 U3：unpublish 到不支援排程的管道＋未來日期 ⇒ 不報錯（publish 側會回 FEATURE_NOT_ENABLED）" do
      target = extra_publication(name: "不支援排程", supports_future: false)
      login!
      unpublish!([ { publicationId: publication_gid(target), publishDate: future.iso8601 } ])

      expect(user_errors("publishableUnpublish")).to eq([])

      publish!([ { publicationId: publication_gid(target), publishDate: future.iso8601 } ])
      expect(user_errors.sole["code"]).to eq("FEATURE_NOT_ENABLED")
    end

    it "絕不連帶刪 publishable 本體" do
      login!
      unpublish!([ { publicationId: publication_gid(online_store) } ])

      expect(ActsAsTenant.without_tenant { Product.find_by(id: product.id) }).to be_present
    end
  end

  # ── 形態 A：全有全無 ─────────────────────────────────────────────────────

  describe "批次語義（形態 A：全有全無）" do
    # 🔴 沿用 `publication_lifecycle_spec.rb` 逐字釘死的同一條規則：
    #   「任何一筆不合法 ⇒ 整批不寫入（不是寫一半）」。
    it "🔴 任一筆不合法 ⇒ 整批不寫入" do
      good = extra_publication
      login!
      publish!([
        { publicationId: publication_gid(good) },
        { publicationId: "gid://chilllove/Publication/99999999" }
      ])

      expect(user_errors.sole["code"]).to eq("NOT_FOUND")
      expect(row_for(good)).to be_nil, "第一筆被寫進去了＝寫了一半"
    end

    it "錯誤帶陣列索引，且 field path **不剝殼**（官方 fixture 逐字 [input,0,publicationId]）" do
      login!
      publish!([
        { publicationId: publication_gid(online_store) },
        { publicationId: "gid://chilllove/Publication/99999999" }
      ])

      expect(user_errors.sole["field"]).to eq([ "input", "1", "publicationId" ])
    end

    it "publicationId 缺席 ⇒ INVALID（我方必填；本尊 nullable 是為了相容 deprecated 的 channelId）" do
      login!
      publish!([ { publishDate: past.iso8601 } ])

      expect(user_errors.sole["code"]).to eq("INVALID")
      expect(user_errors.sole["field"]).to eq([ "input", "0", "publicationId" ])
    end

    it "🔴 超過 api.array_input_max_items ⇒ TOO_BIG（不是自創 LIMIT_EXCEEDED）" do
      cap = Limits.fetch(:api, :array_input_max_items)
      login!
      publish!(Array.new(cap + 1) { { publicationId: publication_gid(online_store) } })

      expect(user_errors.sole["code"]).to eq("TOO_BIG")
      expect(user_errors.sole["field"]).to eq([ "input" ])
    end

    it "同一個 publicationId 出現多次 ⇒ 後者覆蓋前者（ours：與輸入順序無關的確定行為）" do
      login!
      publish!([
        { publicationId: publication_gid(online_store), publishDate: future.iso8601 },
        { publicationId: publication_gid(online_store), publishDate: later.iso8601 }
      ])

      expect(user_errors).to eq([])
      expect(row_for(online_store).published_at).to eq(later)
    end
  end

  # ── 三種 publishable 都要能被回傳 ────────────────────────────────────────

  # 🔴 **這一格是本輪實跑抓到的 500 的守衛**：`publishable` 欄位的型別是
  #   `Publishable` **interface**，GraphQL 要靠 `ChillloveSchema.resolve_type`
  #   把 model 物件解析成具體型別。而在 S5 之前，全倉**沒有任何欄位以 interface
  #   型別回傳過變體** ⇒ `resolve_type` 少了 `ProductVariant` 那一行，
  #   兩包都沒人發現。缺它的症狀是 `RequiredImplementationMissingError`（**500**），
  #   而且**只有「變體真的成功走完」才踩得到**——回 userErrors 的那些格子全綠。
  #
  # 正典集合＝`ResourcePublication::PUBLISHABLE_TYPES`（恰三個）。
  it "🔴 三種 publishable 成功時都回得出具體型別（resolve_type 的守衛）" do
    variant = ActsAsTenant.without_tenant { product.product_variants.first }
    collection = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "回傳測試", handle: "resolve-type",
                         description_html: "", collection_type: "manual", sort_order: "manual")
    end
    target = extra_publication(name: "回傳管道")
    login!

    {
      "Product" => product_gid,
      "ProductVariant" => "gid://chilllove/ProductVariant/#{variant.id}",
      "Collection" => "gid://chilllove/Collection/#{collection.id}"
    }.each do |type, gid|
      publish!([ { publicationId: publication_gid(target) } ], id: gid)

      expect(json["errors"]).to be_nil, "#{type} 走 Publishable interface 回傳時炸了：#{json["errors"].inspect}"
      expect(user_errors).to eq([]), type
      expect(json.dig("data", "publishablePublish", "publishable")).to be_present, type
    end

    expect(ResourcePublication::PUBLISHABLE_TYPES).to contain_exactly("Product", "Collection", "ProductVariant"),
      "正典多了第四種 publishable ⇒ 上面的迴圈與 ChillloveSchema.resolve_type 都要跟著補"
  end

  # ── 主體解析與租戶隔離 ───────────────────────────────────────────────────

  describe "id 參數" do
    it "查無資源 ⇒ NOT_FOUND，field 是扁平的 [id]（本尊 id 不在 input object 裡）" do
      login!
      publish!([ { publicationId: publication_gid(online_store) } ],
               id: "gid://chilllove/Product/99999999")

      expect(user_errors.sole["code"]).to eq("NOT_FOUND")
      expect(user_errors.sole["field"]).to eq([ "id" ])
    end

    it "GID 型別不在白名單 ⇒ NOT_FOUND（不是 500）" do
      login!
      publish!([ { publicationId: publication_gid(online_store) } ],
               id: "gid://chilllove/Order/#{product.id}")

      expect(user_errors.sole["code"]).to eq("NOT_FOUND")
    end

    # 鐵律 2：GID 裡的數字是使用者輸入，查詢不帶租戶條件就等於跨店寫入。
    it "🔴 別店的 publishable ⇒ NOT_FOUND（不得寫進本店的管道）" do
      other = create(:shop, subdomain: "pub-write-other")
      alien = ActsAsTenant.with_tenant(other) { create(:product, shop: other) }
      login!
      publish!([ { publicationId: publication_gid(online_store) } ],
               id: "gid://chilllove/Product/#{alien.id}")

      expect(user_errors.sole["code"]).to eq("NOT_FOUND")
      # ⚠️ 這裡**必須**帶 `shop_id: shop.id`：別店的商品在**它自己店裡**本來就有一列
      #   發布列（`Publications::Materialize` 的 `after_create` 建的）。
      #   不帶租戶條件的計數會把那一列算進來，於是這一格永遠紅——而它紅的原因
      #   與本格要測的跨租戶寫入完全無關。判準是「**本店**有沒有多出一列」。
      expect(ActsAsTenant.without_tenant {
        ResourcePublication.where(shop_id: shop.id, publishable_type: "Product",
                                  publishable_id: alien.id).count
      }).to eq(0)
    end

    it "🔴 別店的 publication ⇒ NOT_FOUND" do
      other = create(:shop, subdomain: "pub-write-other2")
      alien = ActsAsTenant.with_tenant(other) { Publication.online_store! }
      login!
      publish!([ { publicationId: publication_gid(alien) } ])

      expect(user_errors.sole["code"]).to eq("NOT_FOUND")
    end
  end
end
