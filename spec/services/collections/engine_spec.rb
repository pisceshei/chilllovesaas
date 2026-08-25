# frozen_string_literal: true

require "rails_helper"

# 第 11 包：求值引擎整合測試（rebuild／resync／求值公式；13 §F4.2 的三條必測）。
RSpec.describe "智慧系列求值引擎" do
  let(:shop) { create(:shop, subdomain: "smart-engine") }

  def product!(title:, tags: [], type: "香水", vendor: "CHILL", status: "active", price_cents: 12_800, compare_at: nil)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, title:, tags:, product_type: type, vendor:, status:)
      create(:product_variant, shop:, product:, price_cents:, compare_at_price_cents: compare_at)
      tags.each do |raw|
        key = Tags::Normalize.key(raw)
        ProductTag.find_or_create_by!(shop_id: shop.id, product_id: product.id, tag_key: key) { |t| t.tag_display = raw }
      end
      product
    end
  end

  def smart!(title: "測試系列", sources:)
    ActsAsTenant.with_tenant(shop) do
      collection = Collection.create!(shop_id: shop.id, title:, handle: title.parameterize.presence || "c#{SecureRandom.hex(3)}",
                                      collection_type: "smart", sort_order: "manual", description_html: "")
      sources.each_with_index do |src, index|
        source = CollectionSource.create!(
          shop_id: shop.id, collection_id: collection.id, source_type: "conditions",
          target_type: "products", inclusion_match: src.fetch(:inclusion_match, "all"),
          exclusion_match: src[:exclusion_match], position: index
        )
        src.fetch(:rules).each_with_index do |rule, r_index|
          CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: source.id,
                                       position: r_index, **rule)
        end
      end
      collection
    end
  end

  def members(collection)
    ActsAsTenant.with_tenant(shop) do
      CollectionMembership.where(shop_id: shop.id, collection_id: collection.id).pluck(:product_id)
    end
  end

  def rebuild!(collection) = Collections::Rebuild.call(shop:, collection:)

  describe "🔴 求值公式：最終集 = ⋃ₛ ( inclusion(s) − exclusion(s) )（13 §F4.2 三條必測）" do
    it "①同一來源：條件命中＋明確排除同商品 ⇒ 不在系列內" do
      hit = product!(title: "紅玫瑰", tags: [ "red", "clearance" ])
      keep = product!(title: "白玫瑰", tags: [ "red" ])
      collection = smart!(sources: [ {
        rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" },
          { block: "exclusion", condition_type: "product_tag", relation: "includes", value_text: "clearance" }
        ]
      } ])

      rebuild!(collection)

      expect(members(collection)).to contain_exactly(keep.id)
      expect(members(collection)).not_to include(hit.id)
    end

    it "🔴 ③A 來源排除商品 X ＋ B 來源包含 X ⇒ X **仍在**系列內（per-source 相減；全域相減會判反）" do
      x = product!(title: "X", tags: [ "red", "sale" ], type: "蠟燭")
      collection = smart!(sources: [
        { rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" },
          { block: "exclusion", condition_type: "product_tag", relation: "includes", value_text: "sale" }
        ] },   # A：包含 red 但排除 sale ⇒ X 被 A 剔除
        { rules: [
          { block: "inclusion", condition_type: "product_type", relation: "eq", value_text: "蠟燭" }
        ] }    # B：包含蠟燭 ⇒ X 由 B 進來
      ])

      rebuild!(collection)

      expect(members(collection)).to include(x.id),
        "X 被判出局＝全域相減（V-57 已撤銷的靜默錯誤形態）；正解＝排除只在自己的來源內結算"
    end
  end

  describe "rebuild 的收斂性與世代掃尾" do
    it "🔴 連跑兩次：列數不變、inserted=0 swept=0、不重發快取失效" do
      product!(title: "紅", tags: [ "red" ])
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])

      first = rebuild!(collection)
      expect(first.inserted).to eq(1)

      stamp = ActsAsTenant.with_tenant(shop) { collection.reload.products_updated_at }
      outbox_before = ActsAsTenant.with_tenant(shop) { EventOutbox.where(topic: "collections/update").count }

      second = travel(2.seconds) { rebuild!(collection) }

      expect(second.inserted).to eq(0)
      expect(second.swept).to eq(0)
      expect(members(collection).length).to eq(1)
      ActsAsTenant.with_tenant(shop) do
        expect(collection.reload.products_updated_at).to eq(stamp),
          "零變更的 rebuild 不得推 cache stamp（初版用 affected_rows 判變更，每輪都白打快取）"
        expect(EventOutbox.where(topic: "collections/update").count).to eq(outbox_before)
      end
    end

    it "規則改了 ⇒ 掃尾移除不再命中的、rebuild_status=OK、stamp 推進" do
      red = product!(title: "紅", tags: [ "red" ])
      blue = product!(title: "藍", tags: [ "blue" ])
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])
      rebuild!(collection)
      expect(members(collection)).to contain_exactly(red.id)

      ActsAsTenant.with_tenant(shop) do
        CollectionSourceRule.where(shop_id: shop.id).update_all(value_text: "blue")
      end
      result = travel(2.seconds) { rebuild!(collection) }

      expect(result.inserted).to eq(1)
      expect(result.swept).to eq(1)
      expect(members(collection)).to contain_exactly(blue.id)
      expect(ActsAsTenant.with_tenant(shop) { collection.reload.rebuild_status }).to eq("OK")
    end

    it "🔴 編不了的規則 ⇒ 整系列 ERROR、零寫入（不部分物化）" do
      product!(title: "紅", tags: [ "red" ])
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" },
        { block: "inclusion", condition_type: "metafield_boolean", relation: "eq", value_text: "1" }
      ] } ])

      result = rebuild!(collection)

      expect(result.status).to eq(:error)
      expect(members(collection)).to be_empty
      expect(ActsAsTenant.with_tenant(shop) { collection.reload.rebuild_status }).to eq("ERROR")
    end

    it "🔴 智慧成員**不**寫 collection_products（兩個真相的紅線）" do
      product!(title: "紅", tags: [ "red" ])
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])

      rebuild!(collection)

      ActsAsTenant.with_tenant(shop) do
        expect(CollectionProduct.where(collection_id: collection.id)).to be_empty
        expect(CollectionMembership.where(collection_id: collection.id).count).to eq(1)
      end
    end
  end

  describe "resync（增量；與 rebuild 同一段 SQL）" do
    it "商品變得命中 ⇒ 進；變得不命中 ⇒ 出；ARCHIVED ⇒ 出" do
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_type", relation: "eq", value_text: "香水" }
      ] } ])
      rebuild!(collection)
      product = product!(title: "新品", type: "香水")

      r1 = Collections::ResyncProduct.call(shop:, product_id: product.id)
      expect(r1.joined).to eq(1)
      expect(members(collection)).to include(product.id)

      ActsAsTenant.with_tenant(shop) { product.update!(product_type: "蠟燭") }
      r2 = Collections::ResyncProduct.call(shop:, product_id: product.id)
      expect(r2.left).to eq(1)
      expect(members(collection)).not_to include(product.id)

      ActsAsTenant.with_tenant(shop) { product.update!(product_type: "香水") }
      Collections::ResyncProduct.call(shop:, product_id: product.id)
      ActsAsTenant.with_tenant(shop) { product.update!(status: "archived") }
      r3 = Collections::ResyncProduct.call(shop:, product_id: product.id)
      expect(r3.left).to eq(1)
      expect(members(collection)).not_to include(product.id)
    end

    it "🔴 UNLISTED **不**移出（只是前台不可見，成員資格照舊——13 §F1.2(f)）" do
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_type", relation: "eq", value_text: "香水" }
      ] } ])
      product = product!(title: "隱藏款", type: "香水")
      Collections::ResyncProduct.call(shop:, product_id: product.id)

      ActsAsTenant.with_tenant(shop) { product.update!(status: "unlisted") }
      result = Collections::ResyncProduct.call(shop:, product_id: product.id)

      expect(result.left).to eq(0)
      expect(members(collection)).to include(product.id)
    end

    it "商品刪除 ⇒ 從所有系列移出" do
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_type", relation: "eq", value_text: "香水" }
      ] } ])
      product = product!(title: "將刪", type: "香水")
      Collections::ResyncProduct.call(shop:, product_id: product.id)
      expect(members(collection)).to include(product.id)

      product_id = product.id
      ActsAsTenant.with_tenant(shop) do
        # 依 FK 序清掉整棵樹再刪商品（91 §3.15 已登記 Product#destroy 的 FK 順序）。
        variant_ids = ProductVariant.where(shop_id: shop.id, product_id:).select(:id)
        item_ids = InventoryItem.where(shop_id: shop.id, product_variant_id: variant_ids).select(:id)
        InventoryLevel.where(shop_id: shop.id, inventory_item_id: item_ids).delete_all
        InventoryItem.where(shop_id: shop.id, product_variant_id: variant_ids).delete_all
        ProductVariant.where(shop_id: shop.id, product_id:).delete_all
        Product.where(id: product_id).delete_all
      end
      result = Collections::ResyncProduct.call(shop:, product_id:)

      expect(result.left).to eq(1)
      expect(members(collection)).not_to include(product_id)
    end

    it "ERROR 系列跳過（不對著壞規則亂算）" do
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "metafield_boolean", relation: "eq", value_text: "1" }
      ] } ])
      rebuild!(collection)   # → ERROR
      product = product!(title: "任意", type: "香水")

      result = Collections::ResyncProduct.call(shop:, product_id: product.id)

      expect(result.skipped_error).to eq(1)
      expect(members(collection)).to be_empty
    end
  end

  describe "exclusion 的 collection 型（減去被引用系列的最終成員——V-140）" do
    it "被引用系列的物化成員被剔除" do
      excluded_product = product!(title: "冬季款", tags: [ "red" ])
      normal = product!(title: "常態款", tags: [ "red" ])
      winter = ActsAsTenant.with_tenant(shop) do
        c = Collection.create!(shop_id: shop.id, title: "冬季", handle: "winter",
                               collection_type: "manual", sort_order: "manual", description_html: "")
        CollectionProduct.create!(shop_id: shop.id, collection_id: c.id, product_id: excluded_product.id, position: 0)
        # 手動系列的「最終成員」對 exclusion 而言＝memberships？手動走 collection_products
        # ——v1 的 collection exclusion 讀 memberships（物化）⇒ 手動系列要先有物化列。
        # 🔴 這是 v1 已知邊界：exclusion 引用**手動**系列時讀不到成員（登記 dev doc）。
        c
      end
      smart_ref = ActsAsTenant.with_tenant(shop) do
        c = Collection.create!(shop_id: shop.id, title: "紅色引用", handle: "reds-ref",
                               collection_type: "smart", sort_order: "manual", description_html: "")
        s = CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                                     target_type: "products", inclusion_match: "all", position: 0)
        CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: s.id, block: "inclusion",
                                     condition_type: "product_title", relation: "eq", value_text: "冬季款", position: 0)
        c
      end
      rebuild!(smart_ref)   # 物化：冬季款

      main = smart!(title: "主系列", sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" },
        { block: "exclusion", condition_type: "collection", relation: "includes", value_int: smart_ref.id }
      ] } ])
      rebuild!(main)

      expect(members(main)).to contain_exactly(normal.id)
      expect(winter).to be_present   # 手動系列僅作上面紅字邊界的敘事錨
    end
  end
end
