# frozen_string_literal: true

require "rails_helper"

# S5 的服務層判準：**GraphQL 層看不見的三件事**。
#
# 🔴 上面那個 request spec 測的是「回什麼」；本檔測的是「順帶做了什麼」——
#   cache stamp 寫進去的值、outbox 那一筆的 `available_at`、
#   以及兩條寫入路徑是否真的收斂到同一份規則。
#   這三件事全部**不出現在 payload 裡**，只用 request spec 會 100% 全綠。
#
# @see docs/dev/m2-publishable-write.md §4
RSpec.describe Publications::Write, "S5 的寫入副作用" do
  let(:shop) { create(:shop, subdomain: "pubw-svc") }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }
  let(:future) { 5.days.from_now.change(usec: 0) }

  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      record = create(:product, shop:)
      create(:product_variant, product: record)
      record
    end
  end

  def product_gid = "gid://chilllove/Product/#{product.id}"
  def publication_gid(publication) = "gid://chilllove/Publication/#{publication.id}"

  def entry(publication, date: :omitted)
    base = { publication_id: publication_gid(publication) }
    return base if date == :omitted

    base.merge(publish_date: date, publish_date_given: true)
  end

  def scheduled_events
    ActsAsTenant.without_tenant do
      EventOutbox.where(shop_id: shop.id, topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED).to_a
    end
  end

  def row_for(publication, record: product)
    ActsAsTenant.without_tenant do
      ResourcePublication.find_by(shop_id: shop.id, publication_id: publication.id,
                                  publishable_type: record.class.name, publishable_id: record.id)
    end
  end

  def stamp = ActsAsTenant.without_tenant { Product.where(id: product.id).pick(:publications_updated_at) }

  # ── ① cache stamp：`at` 與 `publishDate` 必須解耦 ─────────────────────────

  describe "cache stamp" do
    # 🔴 **這是一個具體的事故形態，不是風格問題**：
    #   `Product.bump_publications_stamp!` 是**直接賦值** `publications_updated_at = ?`，
    #   不是取 `Time.current`。把未來的 `publishDate` 傳進去，stamp 就變成未來時間，
    #   之後每一次真實變動要嘛不讓它前進、要嘛讓它倒退——兩種都污染 stamp 語義。
    it "🔴 排程發布時 stamp 寫的是**現在**，不是那個未來的 publishDate" do
      described_class.publish(shop:, publishable_gid: product_gid,
                              entries: [ entry(online_store, date: future) ])

      expect(row_for(online_store).published_at).to eq(future)
      expect(stamp).to be_within(30.seconds).of(Time.current)
      expect(stamp).to be < future
    end

    it "取消發布也會 bump（否則前台快取不失效且不拋錯）" do
      before_stamp = stamp
      travel 2.seconds do
        described_class.unpublish(shop:, publishable_gid: product_gid,
                                  entries: [ entry(online_store) ])
      end

      expect(stamp).to be > before_stamp
    end

    # ⚠️ **讀取側目前零消費者**（W6 前台包尚未存在）——正典
    #   `catalog_flow.cache_stamp_sources` 已宣告這個欄位，S5 履行的是寫入側義務。
    #   本格只證明「寫了」，**不宣稱**「所以快取會失效」（鐵律 19）。
    it "變體的發布變動 bump 的是**父商品**（collections 沒有這個欄位，不 bump）" do
      variant = ActsAsTenant.without_tenant { product.product_variants.first }
      before_stamp = stamp

      travel 2.seconds do
        described_class.publish(shop:, publishable_gid: "gid://chilllove/ProductVariant/#{variant.id}",
                                entries: [ entry(online_store) ])
      end

      expect(stamp).to be > before_stamp
    end
  end

  # ── ② outbox：全倉第一個 available_at 未來值的使用者 ──────────────────────

  describe "排程事件（outbox）" do
    # 🔴 既有六個 producer **一律**寫 `Time.current`，既有 spec 從未覆蓋這個分支。
    it "🔴 排程列 ⇒ 投一筆事件，available_at **精確等於** published_at（未來值）" do
      described_class.publish(shop:, publishable_gid: product_gid,
                              entries: [ entry(online_store, date: future) ])

      event = scheduled_events.sole
      expect(event.available_at).to eq(future)
      expect(event.available_at).to be > Time.current
      expect(event.payload["scheduled"]).to be(true)
      expect(event.payload["publication_id"]).to eq(online_store.id)
      expect(event.aggregate_type).to eq("Product")
    end

    # 🔴 立即發布**不投事件**：cache stamp 已經在同一個請求裡同步 bump 完了，
    #   沒有任何延後的事要做。投了就是製造一條沒有載荷的事件流。
    #
    # 🔴 **必須打在「真的建了一列」那一格**（用第二個管道），不能用線上商店：
    #   線上商店那一列 `Materialize` 已經建好且是過去時間 ⇒ 省略 publishDate 走的是
    #   R5 no-op，`published_at` 沒變就**根本不會呼叫** `enqueue_scheduled_event!`。
    #   ⚠️ 突變測試實跑抓到的：把判準改成「非 NULL 就投」時這一格仍然全綠
    #     ——因為它測的是 no-op 路徑，不是立即發布路徑。
    it "🔴 立即發布（真的建了一列）⇒ **不**投事件" do
      target = ActsAsTenant.with_tenant(shop) do
        Publication.create!(shop_id: shop.id, name: "即時管道", channel_handle: "instant",
                            auto_publish: false, supports_future_publishing: true)
      end

      described_class.publish(shop:, publishable_gid: product_gid, entries: [ entry(target) ])

      expect(row_for(target).published?).to be(true), "這一格必須真的建出一列，否則什麼都沒測到"
      expect(scheduled_events).to be_empty
    end

    it "🔴 R7 no-op（排程中＋省略 publishDate）⇒ **不**重複投事件" do
      described_class.publish(shop:, publishable_gid: product_gid,
                              entries: [ entry(online_store, date: future) ])
      expect(scheduled_events.size).to eq(1)

      described_class.publish(shop:, publishable_gid: product_gid,
                              entries: [ entry(online_store) ])

      expect(scheduled_events.size).to eq(1), "沒有任何變動卻投了第二筆事件"
    end

    it "改期 ⇒ 投第二筆，available_at 跟著新日期" do
      described_class.publish(shop:, publishable_gid: product_gid,
                              entries: [ entry(online_store, date: future) ])
      later = 12.days.from_now.change(usec: 0)
      described_class.publish(shop:, publishable_gid: product_gid,
                              entries: [ entry(online_store, date: later) ])

      expect(scheduled_events.map(&:available_at)).to contain_exactly(future, later)
    end

    it "取消發布 ⇒ 不投事件（S5 只投排程，取消發布是立即生效的）" do
      described_class.publish(shop:, publishable_gid: product_gid,
                              entries: [ entry(online_store, date: future) ])
      described_class.unpublish(shop:, publishable_gid: product_gid, entries: [ entry(online_store) ])

      expect(scheduled_events.size).to eq(1)
    end

    # 🔴 反向釘子：本事件**不得**掛在 `Publications::Materialize` 的 `after_create` 上。
    #   掛上去會讓 `spec/services/events/producers_spec.rb` 的
    #   「status 未變更 ⇒ 不產 publication.changed」直接轉紅，而那格斷言是對的
    #   ——建立商品不是「發布狀態變更」。
    it "🔴 建立商品（Materialize 自動物化發布列）⇒ **不**投事件" do
      ActsAsTenant.with_tenant(shop) { create(:product, shop:) }

      expect(scheduled_events).to be_empty
    end

    it "事件與業務寫入同交易（rollback 時一併消失，鐵律 5）" do
      expect {
        ApplicationRecord.transaction do
          described_class.publish(shop:, publishable_gid: product_gid,
                                  entries: [ entry(online_store, date: future) ])
          raise ActiveRecord::Rollback
        end
      }.not_to change { scheduled_events.size }

      expect(row_for(online_store).published?).to be(true)
    end
  end

  # ── ③ 兩條寫入路徑的收斂 ─────────────────────────────────────────────────

  describe "🔴 publicationUpdate 與 publishablePublish 走同一份寫入規則" do
    let(:other) do
      ActsAsTenant.with_tenant(shop) do
        Publication.create!(shop_id: shop.id, name: "第二管道", channel_handle: "second",
                            auto_publish: false, supports_future_publishing: true)
      end
    end

    # S2 §4-E4 登記的分岔：舊的 `find_or_create_by!` create-only 區塊在
    # 「既有列 `published_at IS NULL`」那一格**什麼都不做**（回報成功但資源不可見），
    # 而 `publishablePublish` 會把它改成現在 ⇒ 同一件事兩種結果。
    it "🔴 既有列為 NULL 時，兩條路都把它改成已發布（收斂前 publicationUpdate 會靜默不動）" do
      ActsAsTenant.without_tenant do
        ResourcePublication.where(id: row_for(online_store).id).update_all(published_at: nil)
      end

      described_class.update(shop:, publication: online_store,
                             publishables_to_add: [ product_gid ])

      expect(row_for(online_store).published?).to be(true),
        "publicationUpdate 命中既有 NULL 列時什麼都沒寫＝回報成功但資源仍不可見"
    end

    it "🔴 既有列排程中時，兩條路都**不動**排程日期（不得靜默取消排程）" do
      ActsAsTenant.without_tenant do
        ResourcePublication.where(id: row_for(online_store).id).update_all(published_at: future)
      end

      described_class.update(shop:, publication: online_store,
                             publishables_to_add: [ product_gid ])

      expect(row_for(online_store).published_at).to eq(future)
    end

    it "兩條路對「不存在的列」建出等價的結果" do
      described_class.update(shop:, publication: other, publishables_to_add: [ product_gid ])
      via_update = row_for(other).published_at

      second = ActsAsTenant.with_tenant(shop) do
        Publication.create!(shop_id: shop.id, name: "第三管道", channel_handle: "third",
                            auto_publish: false, supports_future_publishing: true)
      end
      described_class.publish(shop:, publishable_gid: product_gid, entries: [ entry(second) ])

      expect(row_for(second).published_at).to be_within(5.seconds).of(via_update)
    end
  end

  # ── ④ 鎖順序（死鎖防線）─────────────────────────────────────────────────

  # 🔴 **誠實登記本格證明什麼**：它釘的是「寫入目標一律依 `publication_id` 遞增排序」
  #   這個**契約**，不是「死鎖不會發生」。真正的死鎖需要兩個交易以相反順序取鎖，
  #   而那在 MRI ＋ 這幾條查詢的速度下無法穩定重現（重現得了也是 flaky spec）。
  #   ⚠️ 突變測試實跑證實：拿掉排序時，全部行為性的格子**都不會紅**
  #     ——所以必須有這一格直接量它，否則這條防線等於沒有測試。
  #
  # 為什麼需要這條防線：`publishablePublish` 是「一個資源 × N 個管道」、
  # `publicationUpdate` 是「一個管道 × N 個資源」，兩者交錯執行時若各自照輸入順序
  # 取列鎖，就會互相咬住。全域一致的排序把環打斷。
  it "🔴 寫入目標一律依 publication_id 遞增排序（跨兩支 mutation 的一致鎖順序）" do
    ActsAsTenant.with_tenant(shop) do
      created = 3.times.map do |index|
        Publication.create!(shop_id: shop.id, name: "管道#{index}", channel_handle: "lock-order-#{index}",
                            auto_publish: false, supports_future_publishing: true)
      end

      # 刻意用**遞減**的輸入順序送進去
      entries = created.reverse.map { |publication| entry(publication) }
      targets, errors = described_class.resolve_publication_entries(
        shop:, entries:, record: product, mode: :publish, at: Time.current
      )

      expect(errors).to eq([])
      ids = targets.map { |target| target[:publication].id }
      expect(ids).to eq(ids.sort), "輸入是遞減的，輸出必須是遞增的——沒排序就會原樣穿過"
      expect(ids).to eq(created.map(&:id).sort)
    end
  end

  # ── ⑤ 不得繞過租戶守衛 ───────────────────────────────────────────────────

  # 🔴 `resource_publications` 的 publishable 側**沒有 DB 外鍵**（多型欄位建不了），
  #   唯一那道租戶守衛是 model validation `publishable_belongs_to_same_shop`
  #   ⇒ 任何 `insert_all`／`upsert_all` 都會直接繞過它。本格是那條規則的行為守衛。
  it "🔴 逐列走 model（不是 insert_all）：跨租戶的 publishable 被 validation 擋下" do
    other_shop = create(:shop, subdomain: "pubw-svc-other")
    alien = ActsAsTenant.with_tenant(other_shop) { create(:product, shop: other_shop) }

    # ⚠️ `ResourcePublication` 的 `acts_as_tenant` 是 `require_tenant = true`
    #   ⇒ `.new` 與 `valid?` **都**要在租戶內，否則拋的是 `NoTenantSet` 而不是驗證失敗，
    #   那樣這一格就變成在測 gem 的租戶檢查，而不是在測跨租戶守衛。
    ActsAsTenant.with_tenant(shop) do
      row = ResourcePublication.new(shop_id: shop.id, publication_id: online_store.id,
                                    publishable_type: "Product", publishable_id: alien.id,
                                    published_at: Time.current)

      expect(row).not_to be_valid
      expect(row.errors[:publishable].join).to include("必須屬於同一間商店")
    end
  end
end
