# frozen_string_literal: true

require "rails_helper"

# 第 11 包：規則編輯 vs 增量重算的併發（研究 §5 的序列化點＝collection 列鎖）。
#
# 🔴 競態窗必須人工撐開（第 6 包教訓：MRI 的 GIL 下兩執行緒自然序列化＝假綠）。
# 危險交錯：resync 在規則編輯 commit 前讀舊規則、在編輯後才落庫 ⇒ 舊蓋新且無錯誤。
# 防線＝resync 的逐系列短 txn 內 `Collection.lock`（鎖定讀讀最新已提交規則）。
RSpec.describe "智慧系列引擎併發" do
  self.use_transactional_tests = false

  def purge!
    EventOutbox.unscoped.delete_all
    CollectionMembership.unscoped.delete_all
    CollectionSourceRule.unscoped.delete_all
    CollectionSource.unscoped.delete_all
    ProductTag.unscoped.delete_all
    IdempotencyKey.unscoped.delete_all
    InventoryLevel.unscoped.delete_all
    InventoryItem.unscoped.delete_all
    Location.unscoped.delete_all
    ProductVariantOptionValue.unscoped.delete_all
    OptionValue.unscoped.delete_all
    ProductOption.unscoped.delete_all
    ProductVariant.unscoped.delete_all
    Media.unscoped.delete_all
    CollectionProduct.unscoped.delete_all
    Collection.unscoped.delete_all
    Product.unscoped.delete_all
    Publication.unscoped.delete_all
    Translation.unscoped.delete_all
    TranslationStatus.unscoped.delete_all
    ShopLocale.unscoped.delete_all
    UserStoreAssignment.unscoped.delete_all
    StaffMember.unscoped.delete_all
    Shop.delete_all
  end

  before { purge! }
  after { purge! }

  let!(:shop) { create(:shop, subdomain: "eng-conc") }

  it "🔴 resync 與規則編輯交錯：resync 的鎖定讀必見**最新已提交**規則，不得用舊規則落庫" do
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ], product_type: "香水")
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    collection = ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "紅色", handle: "reds",
                             collection_type: "smart", sort_order: "manual", description_html: "")
      s = CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                                   target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: s.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      c
    end

    # 撐開窗：resync 執行緒先起跑、在「取得 collection 鎖之前」被閘住；
    # 主執行緒此刻把規則改成 blue 並 commit；然後放行 resync。
    # 正確行為＝resync 鎖下重讀規則 ⇒ 看到 blue ⇒ 商品不再命中 ⇒ 不加入。
    reached = Queue.new
    release = Queue.new
    gated = false
    allow(Collection).to receive(:lock).and_wrap_original do |orig, *args|
      if !gated && Thread.current[:resync_thread]
        gated = true
        reached << :ok
        release.pop
      end
      orig.call(*args)
    end

    resync = Thread.new do
      Thread.current[:resync_thread] = true
      ActiveRecord::Base.connection_pool.with_connection do
        Collections::ResyncProduct.call(shop:, product_id: product.id)
      end
    end
    reached.pop
    # 主執行緒：把規則改掉並 commit（模擬商家同時編輯規則）。
    ActsAsTenant.with_tenant(shop) do
      CollectionSourceRule.where(shop_id: shop.id).update_all(value_text: "blue")
    end
    release << :go
    result = resync.value

    expect(result.joined).to eq(0),
      "resync 用了閘住之前讀的舊規則（red）落庫——鎖定讀防線失效"
    members = ActsAsTenant.with_tenant(shop) do
      CollectionMembership.where(collection_id: collection.id).pluck(:product_id)
    end
    expect(members).to be_empty
  end

  it "🔴 F2（2026-08-26 審查）：rebuild 對 rebuild 整程序列化——advisory lock 被占＝讓位，不交錯" do
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    collection = ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "紅色", handle: "reds-lock",
                             collection_type: "smart", sort_order: "manual", description_html: "")
      s = CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                                   target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: s.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      c
    end

    # 等待預算歸零：被占＝立即讓位（不用真等 60 秒）。
    allow(Limits).to receive(:fetch).and_call_original
    allow(Limits).to receive(:fetch).with(:collection, :rebuild_lock_wait_seconds).and_return(0)

    lock_name = "chilllove:rebuild:#{shop.id}:#{collection.id}"
    holder = ActiveRecord::Base.connection_pool.checkout
    begin
      expect(holder.select_value(ActiveRecord::Base.sanitize_sql_array([ "SELECT GET_LOCK(?, 0)", lock_name ])).to_i).to eq(1)

      result = Collections::Rebuild.call(shop:, collection:)
      expect(result.status).to eq(:skipped)
      expect(result.error).to eq(Collections::Rebuild::LOCK_TIMEOUT_ERROR)
      expect(ActsAsTenant.with_tenant(shop) { CollectionMembership.count }).to eq(0),
        "鎖被占仍寫入＝整程序列化失效（F2 的交錯掃尾窗重開）"

      # 讓位不靜默丟：RebuildJob 見逾時訊號要延後重排。
      expect {
        Collections::RebuildJob.perform_now(shop.id, collection.id)
      }.to have_enqueued_job(Collections::RebuildJob).with(shop.id, collection.id)
    ensure
      holder.execute(ActiveRecord::Base.sanitize_sql_array([ "SELECT RELEASE_LOCK(?)", lock_name ]))
      ActiveRecord::Base.connection_pool.checkin(holder)
    end

    # 鎖釋放後照常重建。
    result = Collections::Rebuild.call(shop:, collection:)
    expect(result.status).to eq(:ok)
    expect(ActsAsTenant.with_tenant(shop) { CollectionMembership.pluck(:product_id) }).to eq([ product.id ])
  end

  it "🔴 F2 單調帶：舊世代 upsert 降不了現任列的 rebuilt_at（GREATEST），掃尾刪不掉它" do
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅2", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
    end
    collection = ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "紅色2", handle: "reds-belt",
                             collection_type: "smart", sort_order: "manual", description_html: "")
      s = CollectionSource.create!(shop_id: shop.id, collection_id: c.id, source_type: "conditions",
                                   target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: s.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      c
    end
    Collections::Rebuild.call(shop:, collection:)

    # 模擬「較新世代已寫入」的現任列（F2 的降戳形態＝晚開場、小世代的一方覆蓋它）。
    future = 1.hour.from_now
    ActsAsTenant.with_tenant(shop) do
      CollectionMembership.update_all(rebuilt_at: future)
    end

    Collections::Rebuild.call(shop:, collection:)
    ActsAsTenant.with_tenant(shop) do
      row = CollectionMembership.sole
      expect(row.rebuilt_at).to be_within(1.second).of(future),
        "本輪（較舊）世代把 rebuilt_at 降下來了——GREATEST 單調帶失效，交錯掃尾可清空系列"
    end
  end
end
