# frozen_string_literal: true

require "rails_helper"

# S9：前台直連讀取入口（docs/specs/93 §C 的可執行矩陣）。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤）——scope 內部分岔點已由
#   `spec/models/product_spec.rb` 的 .purchasable/.discoverable 區塊封閉，
#   本檔只封 **lookup 層自己的**分岔點：
#   U1 unlisted 直連可得（把直連判準換成 `discoverable` ⇒ 轉紅的是它）
#   B1 draft 直連 nil（把 lookup 寫成裸 `find_by(handle:)` ⇒ 轉紅）
#   C1 真實取消發布後 nil（判準只看 status ⇒ 轉紅；用真實生產者 Publications::Write）
#   S1 排程未到點 nil、帶 at 過點可得（無視 at ⇒ 轉紅）
#   N1 查無 handle 回 nil 不 raise（照抄 find_by! ⇒ 轉紅）
#
# 實測對照（82 §20，2026-08-30）：draft/archived 直連 404、unlisted 直連 200
# 且兩種搜尋面皆排除；官方錨＝specs/93 §A。
RSpec.describe Storefront::Lookup do
  let(:shop) { create(:shop) }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }

  def sellable(status: "active", handle: nil)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status:, **(handle ? { handle: } : {}))
      create(:product_variant, product:)
      product
    end
  end

  # W6 請求層以 ActsAsTenant 設定租戶後才呼叫 lookup（controller 射程）；
  # 本 helper 鏡射該脈絡。
  def lookup(method, **kwargs)
    ActsAsTenant.with_tenant(shop) { described_class.public_send(method, **kwargs) }
  end

  def unpublish!(record)
    ActsAsTenant.with_tenant(shop) do
      Publications::Write.unpublish(
        shop: shop,
        publishable_gid: "gid://chilllove/#{record.class.name}/#{record.id}",
        entries: [ { publication_id: "gid://chilllove/Publication/#{online_store.id}" } ]
      )
    end
  end

  describe ".product_by_handle" do
    it "A1 active＋已發布 ⇒ 回商品" do
      product = sellable(handle: "s9-a1")
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-a1")).to eq(product)
    end

    it "U1 🔴 unlisted 直連可得（官方逐字 you need a direct link to view it；判準是 purchasable 不是 discoverable）" do
      product = sellable(status: "unlisted", handle: "s9-u1")
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-u1")).to eq(product)
      # 同一筆在發現面必須不可見——這一格與 U1 合起來才是 UNLISTED 的完整語義
      discoverable = ActsAsTenant.with_tenant(shop) { Product.discoverable(publication: online_store).to_a }
      expect(discoverable).not_to include(product)
    end

    it "B1 🔴 draft ⇒ nil（實測：直連 404）；archived 同" do
      sellable(status: "draft", handle: "s9-b1")
      sellable(status: "archived", handle: "s9-b2")
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-b1")).to be_nil
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-b2")).to be_nil
    end

    it "C1 🔴 真實取消發布（Publications::Write）⇒ nil（官方逐字 not found when queried by handle or ID）" do
      product = sellable(handle: "s9-c1")
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-c1")).to eq(product)
      unpublish!(product)
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-c1")).to be_nil
    end

    it "S1 🔴 排程未到點 ⇒ nil；帶 at 過點 ⇒ 可得" do
      product = sellable(handle: "s9-s1")
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "Product", publishable_id: product.id)
                           .update_all(published_at: 1.day.from_now)
      end
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-s1")).to be_nil
      expect(lookup(:product_by_handle, publication: online_store, handle: "s9-s1", at: 2.days.from_now))
        .to eq(product)
    end

    it "N1 查無 handle ⇒ nil，不 raise" do
      expect(lookup(:product_by_handle, publication: online_store, handle: "no-such-handle")).to be_nil
    end
  end

  describe ".product_by_id" do
    it "id 形態與 handle 同判準：unlisted 可得、取消發布後 nil" do
      product = sellable(status: "unlisted")
      expect(lookup(:product_by_id, publication: online_store, id: product.id)).to eq(product)
      unpublish!(product)
      expect(lookup(:product_by_id, publication: online_store, id: product.id)).to be_nil
    end
  end

  describe ".collection_by_handle" do
    def collection!(handle)
      ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: "S9 系列 #{handle}", handle:,
                           description_html: "", collection_type: "manual", sort_order: "manual")
      end
    end

    it "已發布（Materialize 自動）⇒ 回系列；真實取消發布 ⇒ nil" do
      collection = collection!("s9-col-1")
      expect(lookup(:collection_by_handle, publication: online_store, handle: "s9-col-1")).to eq(collection)
      unpublish!(collection)
      expect(lookup(:collection_by_handle, publication: online_store, handle: "s9-col-1")).to be_nil
    end

    it "排程未到點 ⇒ nil（系列只有發布層一個閘）" do
      collection = collection!("s9-col-2")
      ActsAsTenant.without_tenant do
        ResourcePublication.where(publishable_type: "Collection", publishable_id: collection.id)
                           .update_all(published_at: 1.day.from_now)
      end
      expect(lookup(:collection_by_handle, publication: online_store, handle: "s9-col-2")).to be_nil
    end
  end
end
