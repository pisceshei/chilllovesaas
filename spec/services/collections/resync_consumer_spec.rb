# frozen_string_literal: true

require "rails_helper"

# 第 11 包：outbox 消費者接線（P11-U17 的 ours 裁定）。
RSpec.describe Collections::ResyncConsumer do
  let(:shop) { create(:shop, subdomain: "resync-consumer") }

  def event!(topic:, payload:)
    ActsAsTenant.with_tenant(shop) do
      EventOutbox.create!(event_id: SecureRandom.uuid, topic:, aggregate_type: "Product",
                          aggregate_id: 1, shop_id: shop.id, available_at: Time.current,
                          payload:)
    end
  end

  it "tripwire：三個 topic 都掛了本消費者（註冊表）" do
    [ Events::Topics::PRODUCTS_CREATE, Events::Topics::PRODUCTS_UPDATE,
      Events::Topics::INVENTORY_ADJUSTED ].each do |topic|
      expect(Events::Consumers.for(topic)).to include(described_class), topic
    end
  end

  it "product 事件：payload 的 product_id 直達 ResyncProduct" do
    expect(Collections::ResyncProduct).to receive(:call).with(shop: shop, product_id: 42)

    described_class.call(event!(topic: Events::Topics::PRODUCTS_UPDATE, payload: { product_id: 42 }))
  end

  it "inventory 事件：product_variant_id 經變體反查商品" do
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    variant = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:, product:) }
    expect(Collections::ResyncProduct).to receive(:call).with(shop: shop, product_id: product.id)

    described_class.call(event!(topic: Events::Topics::INVENTORY_ADJUSTED,
                                payload: { product_variant_id: variant.id }))
  end

  it "變體已刪 ⇒ 靜默返回（商品層事件會另行到達，不是錯誤）" do
    expect(Collections::ResyncProduct).not_to receive(:call)

    described_class.call(event!(topic: Events::Topics::INVENTORY_ADJUSTED,
                                payload: { product_variant_id: 999_999 }))
  end

  it "🔴 商品已刪的 product 事件**仍要跑**（刪除＝從所有系列移出的觸發源）" do
    expect(Collections::ResyncProduct).to receive(:call).with(shop: shop, product_id: 999_999)

    described_class.call(event!(topic: Events::Topics::PRODUCTS_UPDATE, payload: { product_id: 999_999 }))
  end

  it "🔴 G4（2026-08-26 收斂輪）：A 排除 B 且 A.id < B.id 時，單次 resync 也要收斂" do
    shop = create(:shop, subdomain: "resync-order")
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end

    # 先建 A（id 較小），再建 B；A 的規則＝tag red 排除 B 的成員，B＝tag red。
    a = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "A", handle: "col-a",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    b = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "B", handle: "col-b",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    expect(a.id).to be < b.id

    ActsAsTenant.with_tenant(shop) do
      sa = CollectionSource.create!(shop_id: shop.id, collection_id: a.id, source_type: "conditions",
                                    target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sa.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sa.id, block: "exclusion",
                                   condition_type: "collection", relation: "includes",
                                   value_int: b.id, position: 1)
      sb = CollectionSource.create!(shop_id: shop.id, collection_id: b.id, source_type: "conditions",
                                    target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sb.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
    end

    Collections::ResyncProduct.call(shop:, product_id: product.id)

    members = ->(c) { ActsAsTenant.with_tenant(shop) { CollectionMembership.where(collection_id: c.id).pluck(:product_id) } }
    expect(members.call(b)).to eq([ product.id ])
    expect(members.call(a)).to be_empty,
      "第一趟算 A 時商品還沒進 B ⇒ A 誤留；引用其他系列的必須再算一次"
  end

  it "🔴 G1 自癒面：resync 的工作清單＝全部智慧系列，零 source 的殘留成員也要被移出" do
    shop = create(:shop, subdomain: "resync-orphan")
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    collection = ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "孤兒", handle: "orphan",
                             collection_type: "smart", sort_order: "manual", description_html: "")
      # 物化列還在，但條件已被清空（G1 的殘留形態）。
      CollectionMembership.create!(shop_id: shop.id, collection_id: c.id, product_id: product.id,
                                   origin: "conditions", rebuilt_at: Time.current)
      c
    end

    Collections::ResyncProduct.call(shop:, product_id: product.id)

    remaining = ActsAsTenant.with_tenant(shop) do
      CollectionMembership.where(collection_id: collection.id).pluck(:product_id)
    end
    expect(remaining).to be_empty,
      "工作清單從 collection_sources 導出 ⇒ 條件被清空的系列從所有清理路徑消失，殘留成員無自癒"
  end

  it "🔴 H3（2026-08-26 收斂輪）：庫存事件的**真實** payload 形狀（只有 inventory_item_id）也要能觸發" do
    # 🔴 這一格的 payload 必須與 `Inventory::Adjust#enqueue_adjust_event!` 實際產生的
    #   形狀一致：`{adjustment, location_id, inventory_item_id, availability_flipped}`
    #   ——**沒有** product_id／product_variant_id。初版消費者照後兩者讀 ⇒ 永遠早退，
    #   整條 INVENTORY_ADJUSTED 觸發鏈是死的，而舊 spec 自己捏了帶 product_variant_id
    #   的 payload 所以綠。fixture 與真實生產者不符＝假綠。
    shop = create(:shop, subdomain: "resync-inv")
    variant = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "庫存商品")
      create(:product_variant, shop:, product: p, price_cents: 100)
    end
    # 變體工廠已建 inventory_item（1:1 側車）——取現成的，不另建（唯一索引擋）。
    item = ActsAsTenant.with_tenant(shop) do
      InventoryItem.find_by!(shop_id: shop.id, product_variant_id: variant.id)
    end

    event = ActsAsTenant.with_tenant(shop) do
      EventOutbox.create!(event_id: SecureRandom.uuid, topic: Events::Topics::INVENTORY_ADJUSTED,
                          aggregate_type: "InventoryLevel", aggregate_id: 1, shop_id: shop.id,
                          available_at: Time.current,
                          payload: { inventory_item_id: item.id, location_id: 1,
                                     adjustment: { reason: "correction", quantity_name: "available",
                                                   delta: 5, ledger_id: 1, group_id: 1 },
                                     availability_flipped: false })
    end

    expect(Collections::ResyncProduct).to receive(:call).with(shop: anything, product_id: variant.product_id)
    described_class.call(event)
  end

  it "🔴 H5（2026-08-26 收斂輪）：引用其他系列的排最後算——不得先提交錯誤成員再刪" do
    shop = create(:shop, subdomain: "resync-noflap")
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    a = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "A", handle: "noflap-a",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    b = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "B", handle: "noflap-b",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    ActsAsTenant.with_tenant(shop) do
      sa = CollectionSource.create!(shop_id: shop.id, collection_id: a.id, source_type: "conditions",
                                    target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sa.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sa.id, block: "exclusion",
                                   condition_type: "collection", relation: "includes",
                                   value_int: b.id, position: 1)
      sb = CollectionSource.create!(shop_id: shop.id, collection_id: b.id, source_type: "conditions",
                                    target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sb.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      EventOutbox.where(shop_id: shop.id).delete_all
    end

    result = Collections::ResyncProduct.call(shop:, product_id: product.id)

    # A 從頭到尾不該有這個商品 ⇒ 不該有「加入又移除」的中間提交。
    expect(result.joined).to eq(1), "A 被先加入再移除 ⇒ joined 把同一個商品算了兩次"
    expect(result.left).to eq(0)
    events = ActsAsTenant.with_tenant(shop) do
      EventOutbox.where(shop_id: shop.id, topic: Events::Topics::COLLECTIONS_UPDATE)
                 .pluck(:aggregate_id)
    end
    expect(events).to eq([ b.id ]),
      "A 沒有實際成員變動卻發了 collections/update（先加後刪各一則＝兩倍快取失效）"
  end

  it "🔴 J3（2026-08-26 收斂輪）：鏈式單向引用 A→B→C 單次事件也要收斂（拓樸序）" do
    # H5 的「改序」修掉了翻轉，卻把第二次求值機會也拿掉 ⇒ A 與 B 同落尾段、
    # 順序由 pluck 決定，A 讀到完全沒被重算過的 B。正解＝依引用關係拓樸排序。
    shop = create(:shop, subdomain: "resync-chain")
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end

    a, b, c = %w[chain-a chain-b chain-c].map do |handle|
      ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: handle, handle:,
                           collection_type: "smart", sort_order: "manual", description_html: "")
      end
    end
    # A 排除 B；B 排除 C；C＝tag red。id 序 a < b < c（最壞情況：與需要的序相反）。
    ActsAsTenant.with_tenant(shop) do
      [ [ a, b ], [ b, c ] ].each do |(owner, referenced)|
        src = CollectionSource.create!(shop_id: shop.id, collection_id: owner.id, source_type: "conditions",
                                       target_type: "products", inclusion_match: "all", position: 0)
        CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: src.id, block: "inclusion",
                                     condition_type: "product_tag", relation: "includes",
                                     value_text: "red", position: 0)
        CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: src.id, block: "exclusion",
                                     condition_type: "collection", relation: "includes",
                                     value_int: referenced.id, position: 1)
      end
      src_c = CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                                       target_type: "products", inclusion_match: "all", position: 0)
      # 🔴 C 用商品**沒有**的標籤：這樣 C 空 ⇒ B 含商品 ⇒ A 應為空。
      #   若 C 也含商品，B 就是空的，A 無論什麼順序都「碰巧」對——
      #   拓樸序的守衛必須在「依賴方非空」的拓樸下才測得出來（MJ3 第一次是綠的原因）。
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: src_c.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "blue", position: 0)
    end

    Collections::ResyncProduct.call(shop:, product_id: product.id)

    members = ->(col) { ActsAsTenant.with_tenant(shop) { CollectionMembership.where(collection_id: col.id).pluck(:product_id) } }
    expect(members.call(c)).to be_empty                    # C：tag blue ⇒ 商品不在
    expect(members.call(b)).to eq([ product.id ])          # B：tag red 減去 C（空）⇒ 在
    expect(members.call(a)).to be_empty,                   # A：tag red 減去 B（含商品）⇒ 空
      "A 讀到的是本次事件沒被重算過的 B ⇒ 鏈式引用未收斂（拓樸序失效）"
  end

  it "🔴 J7（同上）：與本商品無關的系列不進工作清單（每則事件不掃全店）" do
    shop = create(:shop, subdomain: "resync-scope")
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    with_source = ActsAsTenant.with_tenant(shop) do
      col = Collection.create!(shop_id: shop.id, title: "有條件", handle: "scoped-a",
                               collection_type: "smart", sort_order: "manual", description_html: "")
      src = CollectionSource.create!(shop_id: shop.id, collection_id: col.id, source_type: "conditions",
                                     target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: src.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      col
    end
    # 零 source、且本商品沒有物化列 ⇒ 構造上不可能有變化，不該被造訪。
    untouched = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "無關", handle: "scoped-b",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    # 零 source 但**有**本商品的殘留列 ⇒ 必須被造訪（G1 的自癒面）。
    orphan = ActsAsTenant.with_tenant(shop) do
      col = Collection.create!(shop_id: shop.id, title: "殘留", handle: "scoped-c",
                               collection_type: "smart", sort_order: "manual", description_html: "")
      CollectionMembership.create!(shop_id: shop.id, collection_id: col.id, product_id: product.id,
                                   origin: "conditions", rebuilt_at: Time.current)
      col
    end

    locked = []
    allow(Collection).to receive(:lock).and_wrap_original do |orig, *args|
      relation = orig.call(*args)
      allow(relation).to receive(:find_by).and_wrap_original do |find, *find_args|
        row = find.call(*find_args)
        locked << row.id if row
        row
      end
      relation
    end

    Collections::ResyncProduct.call(shop:, product_id: product.id)

    expect(locked).to include(with_source.id)
    expect(locked).to include(orphan.id), "G1 的自癒面被 J7 的過濾誤殺"
    expect(locked).not_to include(untouched.id),
      "與本商品構造上無關的系列仍被逐一鎖住求值（J7 的放大鏈）"
  end
end
