# frozen_string_literal: true

require "rails_helper"

# S8（D74）：上架事件（product_listings/* 與 ours 的 variant_listings/*）。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤；缺任一格，反向實作照樣全綠）：
#   L02 draft 的 ADD 閘（判準改 `== active` 或刪閘 ⇒ 轉紅的是 L02b/L02）
#   L04 刪排程列不發 REMOVE（把 REMOVE 無條件化 ⇒ 轉紅）
#   L06 排程當下不發 ADD（把 ADD 提前到寫入時 ⇒ 轉紅）
#   L08 translator 的 draft 閘 ＋ L09 重放冪等（dedupe 擋第二筆）
#
# fixture 紀律（PR-C 裁定書 T26 同款）：一律用真實生產者
# `Publications::Write.publish/unpublish` 產生狀態與事件，不手捏 outbox。
RSpec.describe "Publications listing events" do
  let(:shop) { create(:shop) }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }

  def product!(status: "active")
    ActsAsTenant.with_tenant(shop) do
      create(:product, shop: shop, status: status)
    end
  end

  def gid(record) = "gid://chilllove/#{record.class.name}/#{record.id}"

  def listing_events(topic)
    ActsAsTenant.without_tenant { EventOutbox.where(shop_id: shop.id, topic: topic).order(:id) }
  end

  def publish!(record, publish_date: nil)
    entry = { publication_id: "gid://chilllove/Publication/#{online_store.id}" }
    entry[:publish_date] = publish_date if publish_date
    ActsAsTenant.with_tenant(shop) do
      Publications::Write.publish(shop: shop, publishable_gid: gid(record), entries: [ entry ])
    end
  end

  def unpublish!(record)
    ActsAsTenant.with_tenant(shop) do
      Publications::Write.unpublish(
        shop: shop, publishable_gid: gid(record),
        entries: [ { publication_id: "gid://chilllove/Publication/#{online_store.id}" } ]
      )
    end
  end

  describe "即時轉場（Write 內）" do
    it "L01 立即發布 active 商品 ⇒ 恰一筆 product_listings/add，payload 帶 publication 與資源" do
      product = product!
      # Materialize 的 after_create 已自動發布 ⇒ 先清場成未發布再走顯式 publish
      unpublish!(product)
      listing_events(Events::Topics::PRODUCT_LISTINGS_REMOVE).delete_all
      result = publish!(product)
      expect(result.user_errors).to be_empty
      events = listing_events(Events::Topics::PRODUCT_LISTINGS_ADD)
      expect(events.count).to eq(1)
      payload = events.first.payload
      expect(payload["publication_id"]).to eq(online_store.id)
      expect(payload["publishable_type"]).to eq("Product")
      expect(payload["publishable_id"]).to eq(product.id)
    end

    it "L02 立即發布 draft 商品 ⇒ 不發 ADD（官方逐字 an active product）" do
      product = product!(status: "draft")
      unpublish!(product)
      publish!(product)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(0)
    end

    it "L02b unlisted 商品 ⇒ 發 ADD（判準是 PURCHASABLE 不是 == active；D53 同集合）" do
      product = product!(status: "unlisted")
      unpublish!(product)
      listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).delete_all
      publish!(product)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(1)
    end

    it "L03 取消發布已發布列 ⇒ 恰一筆 REMOVE；draft 商品也發（官方 REMOVE 無 active 限定）" do
      product = product!(status: "draft")
      # Materialize 建的列就是已發布態
      unpublish!(product)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_REMOVE).count).to eq(1)
    end

    it "L04 🔴 刪「排程中未到點」的列 ⇒ 不發 REMOVE（從未 listed 過；ours fail-closed）" do
      product = product!
      unpublish!(product)
      listing_events(Events::Topics::PRODUCT_LISTINGS_REMOVE).delete_all
      publish!(product, publish_date: 3.days.from_now.utc.iso8601)
      unpublish!(product)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_REMOVE).count).to eq(0)
    end

    it "L05 取消發布不存在的列（U2 no-op）⇒ 零事件" do
      product = product!
      unpublish!(product)
      listing_events(Events::Topics::PRODUCT_LISTINGS_REMOVE).delete_all
      unpublish!(product)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_REMOVE).count).to eq(0)
    end

    it "L06 🔴 排程未來 ⇒ 寫入當下不發 ADD（到點才由 translator 發；官方逐字 At the scheduled datetime）" do
      product = product!
      unpublish!(product)
      listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).delete_all
      publish!(product, publish_date: 3.days.from_now.utc.iso8601)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(0)
    end

    it "L07 已發布列改 published_at（過去→另一個過去）⇒ UPDATE（官方 a product publication is updated）" do
      product = product!
      # Materialize 列已發布；把日期改成另一個過去值
      publish!(product, publish_date: 2.days.ago.utc.iso8601)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_UPDATE).count).to eq(1)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(0)
    end

    it "L10 Collection 發布／取消 ⇒ 零 listing 事件（本尊無 collection listing topic）" do
      collection = ActsAsTenant.with_tenant(shop) do
        Collection.create!(shop_id: shop.id, title: "S8 測試系列", handle: "s8-listing-test",
                           description_html: "", collection_type: "manual", sort_order: "manual")
      end
      ActsAsTenant.with_tenant(shop) do
        Publications::Write.publish(
          shop: shop, publishable_gid: "gid://chilllove/Collection/#{collection.id}",
          entries: [ { publication_id: "gid://chilllove/Publication/#{online_store.id}" } ]
        )
        Publications::Write.unpublish(
          shop: shop, publishable_gid: "gid://chilllove/Collection/#{collection.id}",
          entries: [ { publication_id: "gid://chilllove/Publication/#{online_store.id}" } ]
        )
      end
      [ Events::Topics::PRODUCT_LISTINGS_ADD, Events::Topics::PRODUCT_LISTINGS_REMOVE,
        Events::Topics::PRODUCT_LISTINGS_UPDATE ].each do |topic|
        expect(listing_events(topic).count).to eq(0), "expected zero #{topic}"
      end
    end
  end

  describe "到點轉譯（ListingEventTranslator）" do
    def due_event_for(product)
      # 真實生產者：排程 ⇒ enqueue_scheduled_event!；再把 available_at 撥到過去模擬到點
      publish!(product, publish_date: 1.minute.from_now.utc.iso8601)
      event = ActsAsTenant.without_tenant do
        EventOutbox.where(shop_id: shop.id, topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED)
                   .where("payload LIKE ?", "%scheduled%").order(:id).last
      end
      expect(event).to be_present
      # 到點：DB 現值也要已生效（translator 判準是 DB，不是 payload）
      ActsAsTenant.without_tenant do
        ResourcePublication.where(shop_id: shop.id, publishable_type: "Product", publishable_id: product.id)
                           .update_all(published_at: 1.second.ago)
        event.update!(available_at: 1.second.ago)
      end
      event
    end

    it "L08a 到點 ∧ active ⇒ 發 product_listings/add" do
      product = product!
      unpublish!(product)
      event = due_event_for(product)
      ActsAsTenant.without_tenant { Events::Relay.drain! }
      expect(event.reload.status).to eq("published")
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(1)
    end

    it "L08b 🔴 到點 ∧ draft ⇒ 不發 ADD（閘與 PR-C 同集合），事件仍正常完結不重試" do
      product = product!(status: "draft")
      unpublish!(product)
      event = due_event_for(product)
      ActsAsTenant.without_tenant { Events::Relay.drain! }
      expect(event.reload.status).to eq("published")
      expect(event.attempts).to eq(0)
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(0)
    end

    it "L09 🔴 重放冪等：同一筆到點事件把 translator 叫兩次 ⇒ 仍只有一筆 ADD（dedupe_key）" do
      product = product!
      unpublish!(product)
      event = due_event_for(product)
      2.times { Publications::ListingEventTranslator.call(event) }
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(1)
    end

    it "L11 列已消失（到點前 unpublish）⇒ no-op，不 raise、零 ADD" do
      product = product!
      unpublish!(product)
      event = due_event_for(product)
      unpublish!(product)
      listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).delete_all
      expect { Publications::ListingEventTranslator.call(event) }.not_to raise_error
      expect(listing_events(Events::Topics::PRODUCT_LISTINGS_ADD).count).to eq(0)
    end
  end
end
