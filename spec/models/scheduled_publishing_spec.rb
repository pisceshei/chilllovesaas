# frozen_string_literal: true

require "rails_helper"

# S2：**排程發布態**的強制測試矩陣。
#
# 🔴 **本檔存在的理由**（與鐵律 3 的 zero-decimal 陷阱同型）：
#   本尊的兩種讀出投影（`ResourcePublication` vs `ResourcePublicationV2`）
#   對同一個布林 `isPublished` 給出**相反**的答案，而那個分歧
#   **只在「已排程但尚未到點」這一個狀態顯現**：
#     - 已發布時：兩邊都 true
#     - 完全未發布時：V1 是 false，而 V2 **根本沒有這一列**
#   ⇒ **一份沒有排程 fixture 的測試矩陣會 100% 全綠**，而實作可以完全做錯。
#
#   S2 研究階段實查（HEAD `b399d79`）：`Collection.with_member_counts` 組與
#   `ProductVariant.purchasable_on` 組**各自零個**未來 `published_at` 的格子；
#   `spec/requests/publication_lifecycle_spec.rb` 的 `from_now` 命中數為 **0**。
#   本檔補上那個維度。
#
# 🔴 **判準集合（每一格都必須在排程態下驗）**：
#   ①`Product.purchasable` ②`Product.discoverable` ③`Product.published_on`
#   ④`ProductVariant.purchasable_on` ⑤`Collection.with_member_counts` 的前台可見件數
#   ⑥`ResourcePublication#published?` ⑦GraphQL 的 V2 投影
#   複驗集合：`grep -n "^  describe " spec/models/scheduled_publishing_spec.rb`
#
# @see docs/dev/m2-resource-publication-semantics.md
# @see docs/research/82-admin-channels.md §12.3
RSpec.describe "排程發布（future publishing）" do
  let(:shop) { create(:shop, subdomain: "sched-pub") }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }
  let(:future) { 3.days.from_now }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # 把某個 publishable 在線上商店的發布時刻改成未來＝把它變成「已排程未到點」。
  #
  # 🔴 用 `update_all` 是刻意的：本輪**還沒有**任何合法的寫入路徑能把既有列改成未來時間
  #   （`Publications::Write` 的 add 走 create-only 區塊、remove 是硬刪列）。
  #   那條路徑屬 S5。⇒ 這裡直接改資料庫，測的是**讀取面**在排程態下的行為。
  def schedule!(record, at: future)
    ActsAsTenant.without_tenant do
      ResourcePublication
        .where(shop_id: shop.id, publication_id: online_store.id,
               publishable_type: record.class.name, publishable_id: record.id)
        .update_all(published_at: at)
    end
  end

  def new_product(status: "active")
    product = create(:product, shop:, status:)
    create(:product_variant, product:)
    product
  end

  # ── ① 商品的可購買性 ──────────────────────────────────────────────────────

  describe "Product.purchasable" do
    it "排程中的商品**不可購買**（到點前不算上架）" do
      product = new_product
      schedule!(product)
      schedule!(product.product_variants.first)

      expect(Product.purchasable(publication: online_store)).not_to include(product)
    end

    it "到點之後可購買（同一筆資料，只是 `at` 走到未來）" do
      product = new_product
      schedule!(product)
      schedule!(product.product_variants.first)

      expect(Product.purchasable(publication: online_store, at: future + 1.hour)).to include(product)
    end

    # 🔴 邊界：`PUBLISHED_SQL` 用的是 `<=`，所以**剛好到點**那一刻算已發布。
    #   改成 `<` 這一格會紅。
    it "🔴 邊界：published_at 恰等於 at ⇒ 算已發布（`<=` 不是 `<`）" do
      product = new_product
      schedule!(product)
      schedule!(product.product_variants.first)

      expect(Product.purchasable(publication: online_store, at: future)).to include(product)
    end
  end

  # ── ② 商品的可發現性 ──────────────────────────────────────────────────────

  describe "Product.discoverable" do
    it "排程中的商品不可發現" do
      product = new_product
      schedule!(product)
      schedule!(product.product_variants.first)

      expect(Product.discoverable(publication: online_store)).not_to include(product)
    end
  end

  # ── ③ published_on ───────────────────────────────────────────────────────

  describe "Product.published_on" do
    it "排程中的商品不在已發布集合內" do
      product = new_product
      schedule!(product)

      expect(Product.published_on(online_store)).not_to include(product)
      expect(Product.published_on(online_store, at: future + 1.hour)).to include(product)
    end
  end

  # ── ④ 變體 ───────────────────────────────────────────────────────────────

  describe "ProductVariant.purchasable_on" do
    # 🔴 S2 研究階段實查：這一組原本**零個**未來 `published_at` 的格子。
    #   而「父商品排程中 ⇒ 變體不可購買」是靠 `merge(Product.purchasable)` 才成立的，
    #   拿掉那個 merge 上面的格子照樣全綠。
    it "🔴 父商品排程中 ⇒ 變體不可購買（靠 merge(Product.purchasable) 才成立）" do
      product = new_product
      variant = product.product_variants.first
      schedule!(product)

      expect(ProductVariant.purchasable_on(publication: online_store)).not_to include(variant)
    end

    it "變體自己排程中 ⇒ 變體不可購買" do
      product = new_product
      variant = product.product_variants.first
      schedule!(variant)

      expect(ProductVariant.purchasable_on(publication: online_store)).not_to include(variant)
    end

    it "父商品與變體都到點 ⇒ 可購買" do
      product = new_product
      variant = product.product_variants.first
      schedule!(product)
      schedule!(variant)

      expect(ProductVariant.purchasable_on(publication: online_store, at: future + 1.hour))
        .to include(variant)
    end
  end

  # ── ⑤ 系列的前台可見件數 ──────────────────────────────────────────────────

  describe "Collection.with_member_counts" do
    let(:collection) do
      Collection.create!(shop_id: shop.id, title: "排程測試", handle: "sched-counted",
                         description_html: "", collection_type: "manual", sort_order: "manual")
    end

    def add_member(product)
      CollectionProduct.create!(shop_id: shop.id, collection_id: collection.id, product_id: product.id)
    end

    def visible_count(at: Time.current)
      row = Collection.with_member_counts(publication: online_store, at:).find(collection.id)
      [ row.read_attribute("member_count").to_i, row.read_attribute("visible_member_count").to_i ]
    end

    # 🔴 S2 研究階段實查：這一組原本**零個**未來 `published_at` 的格子。
    it "🔴 排程中的成員計入後台件數，但**不計入前台可見件數**" do
      live = new_product
      scheduled = new_product
      add_member(live)
      add_member(scheduled)
      schedule!(scheduled)
      schedule!(scheduled.product_variants.first)

      expect(visible_count).to eq([ 2, 1 ])
    end

    it "到點之後兩個數字相等" do
      live = new_product
      scheduled = new_product
      add_member(live)
      add_member(scheduled)
      schedule!(scheduled)
      schedule!(scheduled.product_variants.first)

      expect(visible_count(at: future + 1.hour)).to eq([ 2, 2 ])
    end
  end

  # ── ⑥ model 層謂詞 ───────────────────────────────────────────────────────

  describe "ResourcePublication 的三種狀態 scope" do
    let!(:product) { new_product }

    def row_for(record)
      ActsAsTenant.without_tenant do
        ResourcePublication.find_by(shop_id: shop.id, publication_id: online_store.id,
                                    publishable_type: record.class.name, publishable_id: record.id)
      end
    end

    it "已發布 ⇒ currently_published 收、staged 不收" do
      row = row_for(product)
      expect(row.published?).to be(true)

      ActsAsTenant.without_tenant do
        expect(ResourcePublication.currently_published.where(id: row.id)).to exist
        expect(ResourcePublication.staged.where(id: row.id)).not_to exist
        expect(ResourcePublication.published_or_staged.where(id: row.id)).to exist
      end
    end

    it "🔴 已排程未到點 ⇒ currently_published **不收**、staged 收、published_or_staged 收" do
      schedule!(product)
      row = row_for(product)
      expect(row.published?).to be(false)

      ActsAsTenant.without_tenant do
        expect(ResourcePublication.currently_published.where(id: row.id)).not_to exist
        expect(ResourcePublication.staged.where(id: row.id)).to exist
        expect(ResourcePublication.published_or_staged.where(id: row.id)).to exist
      end
    end

    # 🔴 V2 投影的定義性質：`published_at IS NULL` 的列**不屬於 V2**。
    #   官方逐字：`an instance of ResourcePublicationV2 can't be unpublished.
    #   It must either be published or scheduled to be published.`
    it "🔴 published_at 為 NULL ⇒ 三個 scope 都不收（V2 的成員集合不含它）" do
      row = row_for(product)
      ActsAsTenant.without_tenant { ResourcePublication.where(id: row.id).update_all(published_at: nil) }

      ActsAsTenant.without_tenant do
        expect(ResourcePublication.currently_published.where(id: row.id)).not_to exist
        expect(ResourcePublication.staged.where(id: row.id)).not_to exist
        expect(ResourcePublication.published_or_staged.where(id: row.id)).not_to exist
      end
    end
  end

  # ── ⑦ 排程的既有 validation ──────────────────────────────────────────────

  describe "排程的 validation" do
    # 🔴 判準改成引 `config/limits.yml` 的 `future_publishing_unsupported`（S2 改，鐵律 6）。
    #   原本硬編 `"ProductVariant"` 字面值，與正典是兩份清單。
    it "🔴 變體不得排程發布，且判準來自 limits 不是硬編字面值" do
      product = new_product
      variant = product.product_variants.first
      row = ActsAsTenant.without_tenant do
        ResourcePublication.find_by(shop_id: shop.id, publishable_type: "ProductVariant",
                                    publishable_id: variant.id)
      end

      row.published_at = future
      expect(row).not_to be_valid
      expect(row.errors[:published_at].join).to include("排程")

      # 正典鍵確實含 variant——這一格同時證明「limits 有這個值」與「validation 讀了它」。
      expect(Limits.fetch(:sales_channels, :future_publishing_unsupported)).to include("variant")
    end

    it "商品可以排程（不在不支援清單內）" do
      product = new_product
      row = ActsAsTenant.without_tenant do
        ResourcePublication.find_by(shop_id: shop.id, publishable_type: "Product",
                                    publishable_id: product.id)
      end

      row.published_at = future
      expect(row).to be_valid
    end

    # ⚠️ 這條 validation 在**生產路徑上永遠不可能觸發**——所有生產路徑建的 publication
    #   都是 `supports_future_publishing: true`（`Shop#after_create` 與 `Publications::Write`
    #   兩處都明文寫 true）。本格用 fixture 直接造出 false 的管道來證明它還活著。
    #   🔴 這是 fail-open 的登記，不是宣稱它守住了什麼（鐵律 20.2 第 5 類）。
    it "🔴 不支援排程的管道拒絕未來時間（fail-open 登記：生產路徑觸發不到）" do
      product = new_product
      manual = Publication.create!(shop_id: shop.id, name: "不支援排程", channel_handle: "nosched",
                                   auto_publish: false, supports_future_publishing: false)

      row = ResourcePublication.new(shop_id: shop.id, publication_id: manual.id,
                                    publishable_type: "Product", publishable_id: product.id,
                                    published_at: future)

      expect(row).not_to be_valid
      expect(row.errors[:published_at].join).to include("不支援排程發布")
    end
  end
end
