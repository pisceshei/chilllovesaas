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
    # 🔴 發布列必須排在 Publication 之前刪（第 12 包）：Product／ProductVariant／
    #    Collection 的 after_create 會建 resource_publications，而本幫手用的是
    #    `delete_all`（繞過 dependent: :destroy）⇒ 殘列讓 fk_res_pub_publication_id 擋住刪除。
    ResourcePublication.unscoped.delete_all
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
      }.to have_enqueued_job(Collections::RebuildJob).with(shop.id, collection.id, [])
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

  it "🔴 M2（2026-08-26 第八輪）：環的複查在序列化點內——並行建環的後到者必須被擋" do
    # `normalize` 的 pre-flight 是純讀、在 txn 與列鎖之外，且列鎖只鎖被編輯的那一列
    # ⇒ 兩個請求各加環的一端時構造上不互斥。複查因此必須在店級序列化點內再做一次。
    a, b = %w[m2-a m2-b].map do |handle|
      ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: handle, handle:,
                           collection_type: "smart", sort_order: "manual", description_html: "")
      end
    end

    save_edge = lambda do |owner, referenced|
      Catalog::SaveCollection.call(shop:, input: {
        id: "gid://chilllove/Collection/#{owner.id}",
        lock_version: owner.reload.lock_version,
        title: owner.title,
        sources: [ { rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" },
          { block: "exclusion", condition_type: "collection", relation: "includes",
            referenced_collection_id: "gid://chilllove/Collection/#{referenced.id}" }
        ] } ]
      })
    end

    first = ActsAsTenant.with_tenant(shop) { save_edge.call(a, b) }
    expect(first.user_errors).to eq([])

    # 🔴 模擬 TOCTOU：把 **pre-flight**（非鎖定讀那一次）打瞎，只留序列化點內的複查。
    #   少了複查，環就會落庫——那正是並行下真實會發生的事。
    #   （序列化測試裡兩個請求本來就不會交錯，必須把第一道拿掉才測得到第二道。）
    allow(Collections::ReferenceGraph).to receive(:ancestors).and_wrap_original do |orig, *args, **kwargs|
      kwargs[:lock] ? orig.call(*args, **kwargs) : Set.new
    end

    second = ActsAsTenant.with_tenant(shop) { save_edge.call(b, a) }
    expect(second.user_errors.map { |e| e[:code] }).to eq([ "INVALID" ]),
      "pre-flight 被繞過後沒有第二道 ⇒ 並行請求可以把環寫進資料庫（M2）"

    edges = ActsAsTenant.with_tenant(shop) do
      CollectionSourceRule.where(shop_id: shop.id, condition_type: "collection").count
    end
    expect(edges).to eq(1), "環落庫了（M2）"
  end

  it "🔴 N1（2026-08-26 第九輪）：序列化點內的複查必須是**鎖定讀**——真交錯下環不得落庫" do
    # 🔴 這一格用**真的兩條連線交錯**，不 stub 任何東西：
    #   主執行緒開 txn 持 `Shop.lock`；T1 送 A→B，會卡在 `HandleChange.serialize!`；
    #   主執行緒此時提交 B→A 並釋放店鎖；T1 才拿到鎖繼續。
    #   T1 的 read view 早在它自己的 `collection.save!` 時就建立（**在等鎖之前**），
    #   所以**普通讀看不到**主執行緒剛提交的 B→A ⇒ 少了 `lock: true` 這道複查會整個
    #   失效、環照樣落庫。鎖定讀一律讀最新已提交版本。
    a, b = %w[n1-a n1-b].map do |handle|
      ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: handle, handle:,
                           collection_type: "smart", sort_order: "manual", description_html: "")
      end
    end

    save_edge = lambda do |owner, referenced|
      Catalog::SaveCollection.call(shop:, input: {
        id: "gid://chilllove/Collection/#{owner.id}",
        lock_version: owner.reload.lock_version,
        title: owner.title,
        sources: [ { rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" },
          { block: "exclusion", condition_type: "collection", relation: "includes",
            referenced_collection_id: "gid://chilllove/Collection/#{referenced.id}" }
        ] } ]
      })
    end

    # 把 T1 的 pre-flight 打瞎（等同「檢查時對方還沒提交」），只留序列化點內那一道。
    allow(Collections::ReferenceGraph).to receive(:ancestors).and_wrap_original do |orig, *args, **kwargs|
      kwargs[:lock] ? orig.call(*args, **kwargs) : Set.new
    end

    t1_result = nil
    gate = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Shop.transaction do
          Shop.lock.find(shop.id)          # 先占住店級序列化點
          gate << :locked
          ActsAsTenant.with_tenant(shop) { save_edge.call(b, a) }   # B→A，同 txn 內提交
        end
      end
    end
    gate.pop

    t1 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        # A→B：會卡在 serialize! 直到 holder 提交並釋放店鎖。
        t1_result = ActsAsTenant.with_tenant(shop) { save_edge.call(a, b) }
      end
    end

    holder.join
    t1.join

    edges = ActsAsTenant.with_tenant(shop) do
      CollectionSourceRule.where(shop_id: shop.id, condition_type: "collection")
                          .joins(:source).pluck("collection_sources.collection_id", :value_int)
    end
    expect(edges.length).to eq(1),
      "普通讀吃的是等鎖之前的快照 ⇒ 複查看不到對方剛提交的邊，環落庫了（N1）：#{edges.inspect}"
    expect(t1_result.user_errors.map { |e| e[:code] }).to eq([ "INVALID" ])
  end

  it "🔴 P1（2026-08-26 第十一輪）：併發**建立**帶 sources 的智慧系列不得死鎖" do
    # 第十輪把店鎖改成「只要動 rules 就無條件取」，於是 create 變成同一列的 S→X 升級：
    #   `Collection.create!` 因 `fk_collections_shop` 先取 shops 的 **S**，
    #   `serialize!` 再要 **X** ⇒ 兩個併發建立各持相容的 S、各等對方放掉才能升級 ⇒ 必死鎖。
    #   實測（審查方）24 次建立丟失 13 次。修法＝create 一律不取店鎖
    #   （新系列的 id 在 commit 前無人能引用它 ⇒ 構造上不可能成環）。
    threads = 4
    results = Array.new(threads)
    barrier = Queue.new
    workers = Array.new(threads) do |i|
      Thread.new do
        barrier.pop
        ActiveRecord::Base.connection_pool.with_connection do
          results[i] = ActsAsTenant.with_tenant(shop) do
            Catalog::SaveCollection.call(shop:, input: {
              title: "併發建立 #{i}", collection_type: "smart",
              sources: [ { rules: [
                { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
              ] } ]
            })
          end
        end
      rescue StandardError => e
        results[i] = e
      end
    end
    threads.times { barrier << :go }
    workers.each(&:join)

    failures = results.reject { |r| r.respond_to?(:user_errors) && r.user_errors.empty? }
    expect(failures).to be_empty,
      "併發建立死鎖／失敗：#{failures.map { |f| f.is_a?(Exception) ? f.class : f.user_errors }.inspect}"
    created = ActsAsTenant.with_tenant(shop) { Collection.where(shop_id: shop.id, collection_type: "smart").count }
    expect(created).to eq(threads), "有建立請求整份丟失（P1）"
  end

  it "🔴 P2（同上）：死鎖被 rescue 後回的 code 必須是 enum 合法值，不得穿出成 500" do
    # 第十輪回的是 `RACED`，而 `CollectionSetUserErrorCode` 沒有這個值、`code` 又是
    # `null: false` ⇒ graphql-ruby 丟 UnresolvedValueError，controller 的去敏 rescue
    # 接不到 ⇒ HTTP 500 連 body 都沒有，比它要取代的「200＋INTERNAL」更糟。
    collection = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "P2", handle: "p2-code",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    allow(Catalog::HandleChange).to receive(:serialize!).and_raise(ActiveRecord::Deadlocked, "boom")

    result = ActsAsTenant.with_tenant(shop) do
      Catalog::SaveCollection.call(shop:, input: {
        id: "gid://chilllove/Collection/#{collection.id}",
        lock_version: collection.reload.lock_version,
        title: "P2",
        sources: [ { rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
        ] } ]
      })
    end

    codes = result.user_errors.map { |e| e[:code] }
    expect(codes).to eq([ "STALE_OBJECT" ])
    valid = Types::Errors::CollectionSetUserErrorCode.values.keys
    expect(valid).to include(*codes),
      "回了不在 enum 裡的 code ⇒ graphql-ruby 會丟 UnresolvedValueError、穿出成 500（P2）"
  end

  it "🔴 P2 對偶：**create** 路徑的死鎖 rescue 也必須回合法 code（兩個 site 都要看著）" do
    # 🔴 兩個 rescue site（create／update）必須各有一格盯著——第一次跑突變時只改了
    #   create 那一個就整套全綠，因為當時只有 update 有測試。
    allow(Collection).to receive(:create!).and_raise(ActiveRecord::Deadlocked, "boom")

    result = ActsAsTenant.with_tenant(shop) do
      Catalog::SaveCollection.call(shop:, input: {
        title: "建立時死鎖", collection_type: "smart",
        sources: [ { rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
        ] } ]
      })
    end

    codes = result.user_errors.map { |e| e[:code] }
    expect(codes).to eq([ "STALE_OBJECT" ])
    expect(Types::Errors::CollectionSetUserErrorCode.values.keys).to include(*codes)
  end


  it "🔴 P3（同上）：update 路徑的店鎖必須有回歸保護——拿掉它這一格要紅" do
    # 第十輪宣稱 MO5 的反向複驗是「併發 spec 紅」，實測拿掉店鎖全套 1008 例全綠
    # ⇒ 那個 🔴 修法零回歸保護。本格直接盯著「update 走 serialize!」這件事。
    collection = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "P3", handle: "p3-lock",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end

    expect(Catalog::HandleChange).to receive(:serialize!).with(shop).at_least(:once).and_call_original
    ActsAsTenant.with_tenant(shop) do
      Catalog::SaveCollection.call(shop:, input: {
        id: "gid://chilllove/Collection/#{collection.id}",
        lock_version: collection.reload.lock_version,
        title: "P3",
        sources: [ { rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
        ] } ]
      })
    end
  end

  it "create 路徑**不得**取店鎖（P1 的對偶：取了就是 S→X 升級死鎖）" do
    expect(Catalog::HandleChange).not_to receive(:serialize!)
    result = ActsAsTenant.with_tenant(shop) do
      Catalog::SaveCollection.call(shop:, input: {
        title: "建立不取店鎖", collection_type: "smart",
        sources: [ { rules: [
          { block: "inclusion", condition_type: "product_tag", relation: "includes", value_text: "red" }
        ] } ]
      })
    end
    expect(result.user_errors).to eq([])
  end
end
