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

  it "🔴 F1（2026-08-26 審查）：not_eq 納入 NULL 欄商品——與 tag does_not_include 的空值語義一致" do
    typed = product!(title: "有型", type: "香水")
    untyped = product!(title: "無型", type: nil, vendor: nil)
    collection = smart!(sources: [ { rules: [
      { block: "inclusion", condition_type: "product_type", relation: "not_eq", value_text: "香水" }
    ] } ])

    rebuild!(collection)
    expect(members(collection)).to contain_exactly(untyped.id)
    expect(members(collection)).not_to include(typed.id)
  end

  describe "🔴 G1（2026-08-26 收斂輪）：條件清空後物化成員必須被回收" do
    it "sources 清成空陣列 ⇒ 掃尾清空成員、rebuild_status 回 OK" do
      product = product!(title: "紅玫瑰", tags: [ "red" ])
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])
      rebuild!(collection)
      expect(members(collection)).to eq([ product.id ])

      # 契約明文的「空陣列＝清除」（request spec 自己在測的合法輸入）。
      ActsAsTenant.with_tenant(shop) do
        CollectionSource.where(shop_id: shop.id, collection_id: collection.id).destroy_all
        collection.update_columns(rebuild_status: "PENDING")
      end

      result = rebuild!(collection.reload)
      expect(result.status).to eq(:ok),
        "零 source 的智慧系列被當成『與本服務無關』早退 ⇒ 掃尾不執行、成員永久殘留"
      expect(result.swept).to eq(1)
      expect(members(collection)).to be_empty
      expect(collection.reload.rebuild_status).to eq("OK")
    end

    it "🔴 殘留成員會污染**別的**系列：X 清空後，「排除 X」的 Y 必須算得出正確成員" do
      product = product!(title: "紅玫瑰2", tags: [ "red" ])
      x = smart!(title: "X", sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])
      rebuild!(x)
      expect(members(x)).to eq([ product.id ])

      ActsAsTenant.with_tenant(shop) do
        CollectionSource.where(shop_id: shop.id, collection_id: x.id).destroy_all
      end
      rebuild!(x.reload)

      # Y＝tag red 減去 X 的成員。X 已無條件 ⇒ X 無成員 ⇒ Y 應含該商品。
      y = smart!(title: "Y", sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" },
        { block: "exclusion", condition_type: "collection", relation: "includes", value_int: x.id }
      ] } ])
      rebuild!(y)
      expect(members(y)).to eq([ product.id ]),
        "Y 被 X 的幽靈成員錯誤排除——殘留列不是死資料，compile_collection_exclusion 讀它"
    end

    it "非智慧系列照舊跳過（手動成員不歸本服務管）" do
      manual = ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: "手動", handle: "manual-one",
                           collection_type: "manual", sort_order: "manual", description_html: "")
      end
      expect(rebuild!(manual).status).to eq(:skipped)
    end
  end

  it "🔴 F7（2026-08-26 自查）：NULL 世代戳的列既要能被蓋上戳，也要能被掃掉" do
    product = product!(title: "紅3", tags: [ "red" ])
    collection = smart!(sources: [ { rules: [
      { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
    ] } ])
    rebuild!(collection)

    # 模擬未帶世代戳的物化列（日後 manual／nested／app origin 的形態；欄位可空）。
    ActsAsTenant.with_tenant(shop) { CollectionMembership.update_all(rebuilt_at: nil) }

    result = rebuild!(collection)
    expect(members(collection)).to eq([ product.id ]),
      "仍命中規則的列被掃掉了"
    stamp = ActsAsTenant.with_tenant(shop) { CollectionMembership.sole.rebuilt_at }
    expect(stamp).not_to be_nil,
      "GREATEST(NULL, 世代) 回 NULL ⇒ 這一列再也蓋不上戳、也掃不掉（不死列）"
    expect(result.status).to eq(:ok)
  end

  it "🔴 F7 對偶：NULL 戳且**不再命中**規則的列必須被掃掉" do
    product = product!(title: "紅4", tags: [ "red" ])
    collection = smart!(sources: [ { rules: [
      { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
    ] } ])
    rebuild!(collection)
    ActsAsTenant.with_tenant(shop) do
      CollectionMembership.update_all(rebuilt_at: nil)
      # 規則改成藍：這個商品不再命中。
      CollectionSourceRule.where(shop_id: shop.id).update_all(value_text: "blue")
    end

    rebuild!(collection)
    expect(members(collection)).to be_empty,
      "掃尾的 `< 世代` 在三值邏輯下漏掉 NULL ⇒ 陳舊列永遠留在系列裡"
    expect(product).to be_present
  end

  it "🔴 G2 行為面：沒設過比價的商品必須被『比價不等於 X』納入" do
    without_compare = product!(title: "沒比價", compare_at: nil)
    with_compare = product!(title: "有比價", compare_at: 19_800)
    collection = smart!(sources: [ { rules: [
      { block: "inclusion", condition_type: "variant_compare_at_price", relation: "not_eq", value_cents: 19_800 }
    ] } ])

    rebuild!(collection)
    expect(members(collection)).to contain_exactly(without_compare.id)
    expect(members(collection)).not_to include(with_compare.id)
  end

  describe "🔴 H1／H2（2026-08-26 收斂輪）：已 quote 的片段不得再被當成 SQL 模板" do
    it "條件值含 `?` 的系列必須能重建（不是 PreparedStatementInvalid）" do
      # `sanitize_sql_array` 用 count("?") 對位、不分引號內外 ⇒ 商家值裡的一個問號
      # 就讓 arity 不符。寫入層不濾 `?`（自由文字），所以這是可達輸入。
      hit = product!(title: "Why not?")
      miss = product!(title: "Why not")
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_title", relation: "eq", value_text: "Why not?" }
      ] } ])

      result = rebuild!(collection)
      expect(result.status).to eq(:ok)
      expect(members(collection)).to eq([ hit.id ])
      expect(members(collection)).not_to include(miss.id)
    end

    it "tag 值含 `?`（Tags::Normalize 原樣保留）同樣要能重建" do
      hit = product!(title: "問號標籤", tags: [ "Sale? Item" ])
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "Sale? Item" }
      ] } ])

      expect(rebuild!(collection).status).to eq(:ok)
      expect(members(collection)).to eq([ hit.id ])
    end

    it "🔴 resync 端同樣（一個問號規則不得讓整店的增量重算停擺）" do
      other = product!(title: "無關商品", tags: [ "red" ])
      product!(title: "Why not?")
      smart!(title: "問號系列", sources: [ { rules: [
        { block: "inclusion", condition_type: "product_title", relation: "eq", value_text: "Why not?" }
      ] } ])
      red = smart!(title: "紅", sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])

      expect { Collections::ResyncProduct.call(shop:, product_id: other.id) }.not_to raise_error
      expect(members(red)).to eq([ other.id ]),
        "問號系列拋例外 ⇒ 迴圈中排在它後面的無辜系列拿不到增量更新"
    end

    it "🔴 條件值內部的連續空白必須原樣比對（squish 不得改寫商家值）" do
      # `<<~SQL.squish` 在內插之後才跑 ⇒ 會把 '紅玫瑰  禮盒'（兩空白）壓成一個，
      # 而 resync 端沒有 squish ⇒ 兩支引擎對同一條規則給出不同答案。
      double_space = product!(title: "紅玫瑰  禮盒")
      single_space = product!(title: "紅玫瑰 禮盒")
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_title", relation: "eq", value_text: "紅玫瑰  禮盒" }
      ] } ])

      rebuild!(collection)
      expect(members(collection)).to eq([ double_space.id ])
      expect(members(collection)).not_to include(single_space.id)

      # 兩支引擎必須同答案（13 §F4.9「求值只有 SQL 一套」）。
      Collections::ResyncProduct.call(shop:, product_id: single_space.id)
      Collections::ResyncProduct.call(shop:, product_id: double_space.id)
      expect(members(collection)).to eq([ double_space.id ])

      # 連跑兩次列數不變（13:716 的驗收錨）。
      second = rebuild!(collection)
      expect([ second.inserted, second.swept ]).to eq([ 0, 0 ])
    end
  end

  it "🔴 條件值含反斜線＋數字必須原樣比對（`sub` 的反向參照不得解讀商家值）" do
    # `where_sql` 是用 `sub` 代入模板的。`sub(pattern, replacement)` 的**字串形式**
    # 把替換字串裡的 `\0`／`\1`／`\&` 當反向參照 ⇒ mysql2 為了跳脫而產生的
    # `\\`（SQL 裡的兩個字元）被折回一個 ⇒ SQL 變成 `'折扣\1號'`，
    # 而 MySQL 讀 `\1` 就是 `1` ⇒ 比對到完全不同的字串。**block 形式**不做這個解讀。
    # （值用 `92.chr` 組，避免 Ruby 字面值把 `\1` 讀成八進位跳脫。）
    backslash_title = "折扣" + 92.chr + "1號"
    hit = product!(title: backslash_title)
    miss = product!(title: "折扣1號")
    collection = smart!(sources: [ { rules: [
      { block: "inclusion", condition_type: "product_title", relation: "eq", value_text: backslash_title }
    ] } ])

    result = rebuild!(collection)
    expect(result.status).to eq(:ok)
    expect(members(collection)).to eq([ hit.id ])
    expect(members(collection)).not_to include(miss.id)
  end

  describe "🔴 H4（2026-08-26 收斂輪）：ARCHIVED 的判定兩支引擎必須一致" do
    it "全量 rebuild 不得把封存商品塞回物化表" do
      active = product!(title: "在架", tags: [ "red" ])
      archived = product!(title: "已封存", tags: [ "red" ], status: "archived")
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])

      rebuild!(collection)
      expect(members(collection)).to eq([ active.id ]),
        "rebuild 的 INSERT…SELECT 沒有 archived 守衛 ⇒ 封存品被塞回、掃尾也刪不掉"
      expect(members(collection)).not_to include(archived.id)
    end

    it "resync 移出封存品之後，rake 兜底的 rebuild 不得又把它加回來" do
      product = product!(title: "先在架", tags: [ "red" ])
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])
      rebuild!(collection)
      expect(members(collection)).to eq([ product.id ])

      ActsAsTenant.with_tenant(shop) { product.update_columns(status: "archived") }
      Collections::ResyncProduct.call(shop:, product_id: product.id)
      expect(members(collection)).to be_empty

      rebuild!(collection)
      expect(members(collection)).to be_empty,
        "成員集合不得取決於『最後跑的是哪一支引擎』"
    end

    it "UNLISTED 照舊是成員（前台不可見≠非成員）" do
      unlisted = product!(title: "未列出", tags: [ "red" ], status: "unlisted")
      collection = smart!(sources: [ { rules: [
        { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
      ] } ])

      rebuild!(collection)
      expect(members(collection)).to eq([ unlisted.id ])
    end
  end

  it "🔴 J2 商品側（2026-08-26 收斂輪）：正規化後超長的標籤 ⇒ userError，不得漏成 500" do
    # `product_tags.tag_key` 是 varchar(255)，而 `Tags::Normalize.key` 會展開
    # （ß→ss）⇒ 原字串 255 但 key 510。少了 key 側的檢查，`sync_product_tags!` 的
    # `create!` 會拋 ValueTooLong，而它不在 SaveProduct 的 rescue 清單裡 ⇒
    # **整筆商品**回 top-level INTERNAL、商家看不到任何 userError（鐵律 4①）。
    result = ActsAsTenant.with_tenant(shop) do
      Catalog::SaveProduct.call(shop:, input: { title: "膨脹標籤", tags: [ "ß" * 255 ],
                                                variants: [ { price: "10.00" } ] })
    end

    expect(result.user_errors.map { |e| e[:code] }).to eq([ "TOO_LONG" ])
    expect(result.user_errors.first[:field]).to include("tags")
    expect(ActsAsTenant.with_tenant(shop) { Product.where(title: "膨脹標籤").count }).to eq(0)
  end

  it "J2 對照組：正規化後仍在欄寬內的標籤照常存檔" do
    result = ActsAsTenant.with_tenant(shop) do
      Catalog::SaveProduct.call(shop:, input: { title: "正常標籤", tags: [ "ß" * 100 ],
                                                variants: [ { price: "10.00" } ] })
    end

    expect(result.user_errors).to eq([])
    key = ActsAsTenant.with_tenant(shop) { ProductTag.where(tag_display: "ß" * 100).pick(:tag_key) }
    expect(key.length).to eq(200)
  end
end
