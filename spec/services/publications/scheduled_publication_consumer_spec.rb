# frozen_string_literal: true

require "rails_helper"

# PR-C 到點副作用機制的測試矩陣（D53；裁定書 §4.1 的 T01–T26）。
#
# 🔴 **T26 是本檔的地基紀律：全部事件一律由真實生產者產生**
#   （`Publications::Write.publish` ／ `Catalog::SaveProduct.call`），
#   禁止自捏 payload。理由是 `Collections::ResyncConsumer` 的 H3 事故逐字根因——
#   自捏 fixture 與真實生產者不符 ⇒ 消費者對真實事件全部 return、整條觸發鏈死掉，
#   而測試全綠（`app/services/collections/resync_consumer.rb` 檔頭 ③）。
#
# 🔴 **投遞一律走 `Events::Relay.drain!`**，不直呼消費者：
#   到點語義（`available_at <= now` 才取件）與 delivery 帳都在 relay 裡，
#   直呼消費者會把這兩層一起跳過。
RSpec.describe Publications::ScheduledPublicationConsumer do
  let!(:shop) { create(:shop, subdomain: "pr-c-shop") }
  let!(:product) { ActsAsTenant.with_tenant(shop) { create(:product, shop:, status: "active") } }
  # `:product` factory 不連帶建變體，而 `Catalog::SaveProduct` 的 variants 是必填
  # ⇒ 明確建一個預設變體（無選項＝本尊的 Default Title，合法狀態）。
  let!(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, product:) } }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }
  let(:future) { 5.days.from_now.change(usec: 0) }
  let(:product_gid) { "gid://chilllove/Product/#{product.id}" }

  def publication_gid(publication) = "gid://chilllove/Publication/#{publication.id}"

  def entry(publication, date: :omitted)
    base = { publication_id: publication_gid(publication) }
    return base if date == :omitted

    base.merge(publish_date: date, publish_date_given: true)
  end

  # 真實生產者①：S5 的排程發布寫入（產生 available_at=未來 的 outbox 列）。
  def schedule!(date: future, publication: online_store, gid: product_gid)
    ActsAsTenant.with_tenant(shop) do
      Publications::Write.publish(shop:, publishable_gid: gid, entries: [ entry(publication, date:) ])
    end
  end

  # 真實生產者②：狀態轉移（產生 status_transition payload、available_at=now）。
  def save_status!(status)
    ActsAsTenant.with_tenant(shop) do
      Catalog::SaveProduct.call(shop:, input: {
        id: product_gid, title: product.reload.title, status: status,
        lock_version: product.reload.lock_version,
        variants: [ { id: "gid://chilllove/ProductVariant/#{variant.id}", price: "128.00" } ]
      })
    end
  end

  def set_status!(status)
    ActsAsTenant.without_tenant { Product.where(id: product.id).update_all(status: status) }
  end

  def stamp = ActsAsTenant.without_tenant { Product.where(id: product.id).pick(:publications_updated_at) }

  def scheduled_event
    ActsAsTenant.without_tenant do
      EventOutbox.where(topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED)
                 .where("payload LIKE ?", "%scheduled%").order(:id).last
    end
  end

  def row = ActsAsTenant.without_tenant do
    ResourcePublication.find_by(shop_id: shop.id, publication_id: online_store.id,
                                publishable_type: "Product", publishable_id: product.id)
  end

  # 到點：把時鐘撥到 published_at 之後再 drain（不改任何 DB 值）。
  def drain_at_due!(at: future + 1.minute)
    ActsAsTenant.without_tenant { Events::Relay.drain!(now: at) }
  end

  before { online_store }

  # ── T01–T04：status 閘門（可見性軸，不是 == ACTIVE）───────────────────────
  describe "status 閘門" do
    it "T01 active ⇒ stamp 前進" do
      schedule!
      before_stamp = stamp
      drain_at_due!
      expect(stamp).to be > before_stamp
    end

    it "🔴 T02 unlisted ⇒ stamp **前進**（判準是可見性軸，不是 == ACTIVE）" do
      schedule!
      set_status!("unlisted")
      before_stamp = stamp
      drain_at_due!
      expect(stamp).to be > before_stamp
    end

    it "T03 draft ⇒ stamp 不動、未 raise、事件 published、published_at 未改寫、列仍在" do
      schedule!
      set_status!("draft")
      before_stamp = stamp
      event = scheduled_event

      expect { drain_at_due! }.not_to raise_error
      expect(stamp).to eq(before_stamp)
      expect(event.reload.status).to eq("published")
      expect(row).to be_present
      expect(row.published_at).to eq(future)
    end

    it "T04 archived ⇒ 同 T03" do
      schedule!
      set_status!("archived")
      before_stamp = stamp
      event = scheduled_event

      expect { drain_at_due! }.not_to raise_error
      expect(stamp).to eq(before_stamp)
      expect(event.reload.status).to eq("published")
      expect(row.published_at).to eq(future)
    end
  end

  # ── T05–T06：列生命週期（payload 只作定位，DB 現值為權威）──────────────────
  describe "列生命週期" do
    it "🔴 T05 排程後 unpublish（列硬刪）⇒ no-op success，事件不進重試" do
      schedule!
      event = scheduled_event
      ActsAsTenant.with_tenant(shop) do
        Publications::Write.unpublish(shop:, publishable_gid: product_gid, entries: [ entry(online_store) ])
      end
      expect(row).to be_nil

      expect { drain_at_due! }.not_to raise_error
      expect(event.reload.attempts).to eq(0)
      expect(event.status).to eq("published")
    end

    it "🔴 T06 排程後改期 ⇒ 舊時點那筆 no-op（payload.published_at ≠ DB），stamp 不動" do
      schedule!
      old_event = scheduled_event
      later = future + 3.days
      schedule!(date: later)
      expect(row.published_at).to eq(later)

      before_stamp = stamp
      ActsAsTenant.without_tenant { Events::Relay.drain!(now: future + 1.minute) }
      expect(old_event.reload.status).to eq("published")
      expect(stamp).to eq(before_stamp)
      expect(row.published_at).to eq(later)
    end
  end

  # ── T07–T08：型別分流 ───────────────────────────────────────────────────
  describe "型別分流" do
    it "T07 Collection 到點 ⇒ no-op success，未 raise" do
      collection = ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop:, title: "排程系列", handle: "sched-collection", description_html: "")
      end
      schedule!(gid: "gid://chilllove/Collection/#{collection.id}")
      before_stamp = stamp

      expect { drain_at_due! }.not_to raise_error
      expect(stamp).to eq(before_stamp)
    end

    # 🔴 T08 的形態與裁定書寫的「（若能構造）」一致——**在我方架構下構造不出來**：
    #   `Publications::Write#validate_publish_date` 的 R12 在**寫入層**就 reject 變體排程
    #   （官方 help 逐字 `You can't set a future publishing date for individual product variants.`）
    #   ⇒ 變體排程事件沒有真實生產者。故拆成兩格：
    #   (a) 用真實生產者證明這條路確實封死（含「不產生任何事件」）；
    #   (b) 消費者的變體分支仍必須存在且不得炸（D53 §3.1 第 4 項明文），
    #       但它**不是真實路徑** ⇒ 只能直呼消費者。這裡明確標註，不冒充端到端。
    it "T08a 變體帶 publishDate ⇒ 寫入層 reject（INVALID_STATE），且不產生任何排程事件" do
      result = ActsAsTenant.with_tenant(shop) do
        Publications::Write.publish(shop:, publishable_gid: "gid://chilllove/ProductVariant/#{variant.id}",
                                    entries: [ entry(online_store, date: future) ])
      end

      expect(result.user_errors.map { |e| e[:code] }).to include("INVALID_STATE")
      scheduled = ActsAsTenant.without_tenant do
        EventOutbox.where(topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED)
                   .where("payload LIKE ?", "%scheduled%").count
      end
      expect(scheduled).to eq(0)
    end

    it "T08b 防禦性分支：變體型的列走到消費者 ⇒ 讀**父商品** status，不在 variant.status 上炸" do
      # ⚠️ 直呼消費者（非端到端）——理由見上方註釋：真實生產者被 R12 封死。
      #   立即發布的變體列是真實存在的（Materialize 建的），這裡餵它的實際欄位值。
      variant_row = ActsAsTenant.without_tenant do
        ResourcePublication.find_by(shop_id: shop.id, publication_id: online_store.id,
                                    publishable_type: "ProductVariant", publishable_id: variant.id)
      end
      expect(variant_row).to be_present

      event = ActsAsTenant.without_tenant do
        EventOutbox.create!(shop_id: shop.id, event_id: SecureRandom.uuid,
                            topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED,
                            aggregate_type: "ProductVariant", aggregate_id: variant.id,
                            payload: { publication_id: online_store.id, publishable_type: "ProductVariant",
                                       publishable_id: variant.id,
                                       published_at: variant_row.published_at.utc.iso8601, scheduled: true },
                            available_at: Time.current, status: "pending")
      end
      before_stamp = stamp

      expect { ActsAsTenant.without_tenant { Events::Relay.drain! } }.not_to raise_error
      expect(event.reload.status).to eq("published")
      expect(stamp).to be > before_stamp
    end
  end

  # ── T09–T10：payload 分流（同一 topic 兩種形狀）──────────────────────────
  describe "payload 分流" do
    it "🔴 T09 status_transition 型（無 publication_id）⇒ 不 KeyError，走商品級 bump" do
      # 🔴 商品 factory 建出來就是 active ⇒ 存成 ACTIVE **不構成狀態轉移**，
      #   `Catalog::StatusTransition` 不會被呼叫、不產事件。先降 draft 才有轉移可測。
      set_status!("draft")
      before_stamp = stamp
      result = save_status!("ACTIVE")
      expect(result.user_errors).to eq([])

      expect { ActsAsTenant.without_tenant { Events::Relay.drain! } }.not_to raise_error
      expect(stamp).to be > before_stamp
      transition = ActsAsTenant.without_tenant do
        EventOutbox.where(topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED)
                   .where("payload LIKE ?", "%status_transition%").sole
      end
      expect(transition.status).to eq("published")
      expect(transition.attempts).to eq(0)
    end

    it "T10 未知形狀 ⇒ fail-closed（no-op），不 raise" do
      event = ActsAsTenant.without_tenant do
        EventOutbox.create!(shop_id: shop.id, event_id: SecureRandom.uuid,
                            topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED,
                            aggregate_type: "Product", aggregate_id: product.id,
                            payload: { unexpected: true }, available_at: Time.current, status: "pending")
      end
      before_stamp = stamp

      expect { ActsAsTenant.without_tenant { Events::Relay.drain! } }.not_to raise_error
      expect(event.reload.status).to eq("published")
      expect(stamp).to eq(before_stamp)
    end
  end

  # ── T11–T13：catch-up 三聯（D53 F2）────────────────────────────────────
  describe "catch-up" do
    it "🔴 T11 draft 錯過時點 → 走真實 SaveProduct 改 active ⇒ stamp bump 一次" do
      schedule!
      set_status!("draft")
      drain_at_due!
      after_missed = stamp

      expect(save_status!("ACTIVE").user_errors).to eq([])
      ActsAsTenant.without_tenant { Events::Relay.drain! }
      expect(stamp).to be > after_missed
    end

    it "🔴 T12 全程 resource_publications.published_at 未被改寫" do
      schedule!
      set_status!("draft")
      drain_at_due!
      save_status!("ACTIVE")
      ActsAsTenant.without_tenant { Events::Relay.drain! }

      expect(row.published_at).to eq(future)
    end

    it "🔴 T13 DRAFT 期間不可購買；改 ACTIVE 後同一查詢立即可購買，且未執行補發布" do
      baseline_rows = ActsAsTenant.without_tenant { ResourcePublication.where(shop_id: shop.id).count }
      schedule!
      set_status!("draft")
      drain_at_due!

      at = future + 1.minute
      purchasable = -> { ActsAsTenant.without_tenant { Product.purchasable(publication: online_store, at:).pluck(:id) } }
      expect(purchasable.call).not_to include(product.id)

      save_status!("ACTIVE")
      ActsAsTenant.without_tenant { Events::Relay.drain! }
      expect(purchasable.call).to include(product.id)
      # 「不補發布」＝沒有任何新的發布列被建立、published_at 保持商家設定的時刻
      expect(row.published_at).to eq(future)
      # 「不補發布」＝沒有**新增**任何發布列（基線是 Materialize 為 product＋variant 各建的那些，
      #   不是絕對值 1——絕對值會隨 fixture 變動而假紅/假綠）。
      expect(ActsAsTenant.without_tenant { ResourcePublication.where(shop_id: shop.id).count }).to eq(baseline_rows)
    end
  end

  # ── T14–T17：重試與隔離（沿用 Relay 既有機制，F3）───────────────────────
  describe "重試" do
    it "T14 消費者拋 StandardError ⇒ attempts=1、available_at=now+2s、pending、last_error 有值" do
      allow(described_class).to receive(:call).and_raise(StandardError, "boom")
      schedule!
      event = scheduled_event
      at = future + 1.minute
      ActsAsTenant.without_tenant { Events::Relay.drain!(now: at) }

      event.reload
      expect(event.attempts).to eq(1)
      expect(event.status).to eq("pending")
      expect(event.available_at).to be_within(1.second).of(at + 2.seconds)
      expect(event.last_error).to be_present
    end

    it "🔴 T15 連續失敗至上限 ⇒ dead、last_error 保留、dedupe_key 清空" do
      allow(described_class).to receive(:call).and_raise(StandardError, "boom")
      schedule!
      event = scheduled_event
      limit = Limits.fetch(:events, :outbox_dead_letter_attempts)
      at = future + 1.minute
      limit.times do |i|
        ActsAsTenant.without_tenant { Events::Relay.drain!(now: at + (2**(i + 1)).seconds + 1.second) }
      end

      event.reload
      expect(event.status).to eq("dead")
      expect(event.attempts).to eq(limit)
      expect(event.last_error).to be_present
      expect(event.dedupe_key).to be_nil
    end

    it "🔴 T16 重試三輪後 payload 與 DB 的 published_at 皆未被改寫" do
      allow(described_class).to receive(:call).and_raise(StandardError, "boom")
      schedule!
      event = scheduled_event
      original = event.payload["published_at"]
      at = future + 1.minute
      3.times { |i| ActsAsTenant.without_tenant { Events::Relay.drain!(now: at + (2**(i + 1)).seconds + 1.second) } }

      expect(event.reload.payload["published_at"]).to eq(original)
      expect(row.published_at).to eq(future)
    end

    it "🔴 T17 兩消費者同 topic 一失敗 ⇒ 成功者 done 且重試時不重複 bump" do
      failing = Module.new do
        def self.name = "spec.failing"
        def self.call(_event) = raise(StandardError, "boom")
      end
      stub_const("Events::Consumers::REGISTRY",
                 Events::Consumers::REGISTRY.merge(
                   Events::Topics::PRODUCT_PUBLICATION_CHANGED => [ described_class, failing ]
                 ))
      schedule!
      event = scheduled_event
      at = future + 1.minute
      ActsAsTenant.without_tenant { Events::Relay.drain!(now: at) }

      done = ActsAsTenant.without_tenant do
        EventDelivery.find_by(event_id: event.event_id, consumer: described_class.name)
      end
      expect(done.state).to eq("done")

      after_first = stamp
      ActsAsTenant.without_tenant { Events::Relay.drain!(now: at + 3.seconds) }
      expect(stamp).to eq(after_first)
    end
  end

  # ── T18–T20：relay 取件語義（S5 是 available_at 未來值的第一個使用者）──────
  describe "relay 取件" do
    it "T18 available_at 未來值 ⇒ 不被取件" do
      schedule!
      before_stamp = stamp
      expect(ActsAsTenant.without_tenant { Events::Relay.drain!(now: future - 1.day) }).to eq(0)
      expect(stamp).to eq(before_stamp)
    end

    it "🔴 T19 available_at 已過去 ⇒ 下一次 drain! 取出" do
      schedule!
      expect(ActsAsTenant.without_tenant { Events::Relay.drain!(now: future + 1.second) }).to eq(1)
    end

    it "🔴 T20 available_at 遠在過去（7 天前到點）⇒ 仍取出並執行，不因過齡丟棄" do
      schedule!
      before_stamp = stamp
      expect(ActsAsTenant.without_tenant { Events::Relay.drain!(now: future + 7.days) }).to eq(1)
      expect(stamp).to be > before_stamp
    end
  end

  # ── T21：可觀測（沒有它，no-op 與「消費者沒被觸發」不可分辨）────────────────
  describe "可觀測" do
    it "🔴 T21 draft 到點 ⇒ 有一筆 decision=not_purchasable 的結構化 log" do
      schedule!
      set_status!("draft")
      messages = []
      allow(Rails.logger).to receive(:info) { |m| messages << m.to_s }
      drain_at_due!

      expect(messages).to include(a_string_matching(/decision=not_purchasable/))
      expect(messages).to include(a_string_matching(/publishable_type=Product/))
    end
  end

  # ── T22：backfill（冪等）──────────────────────────────────────────────
  describe "backfill" do
    it "🔴 T22 stamp 落後的到點列 ⇒ 前進；**重跑 ⇒ 冪等不再前進**" do
      schedule!
      # 模擬 PR-C 之前：事件被零消費者消化掉 ⇒ stamp 停在排程當刻、落後於 published_at
      ActsAsTenant.without_tenant do
        EventOutbox.where(topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED).update_all(status: "published")
      end
      expect(stamp).to be < future

      first = Publications::BackfillScheduledStamps.call(now: future + 1.minute)
      expect(first[:bumped]).to eq(1)
      after_first = stamp
      expect(after_first).to eq(future)

      second = Publications::BackfillScheduledStamps.call(now: future + 1.minute)
      expect(second[:bumped]).to eq(0)
      expect(stamp).to eq(after_first)
    end

    it "backfill 的資格閘與消費者同一條：draft 不補" do
      schedule!
      set_status!("draft")
      before_stamp = stamp
      expect(Publications::BackfillScheduledStamps.call(now: future + 1.minute)[:bumped]).to eq(0)
      expect(stamp).to eq(before_stamp)
    end
  end
end
