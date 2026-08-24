# frozen_string_literal: true

module Catalog
  # 商品狀態轉移的一處實作（13 §F1.2(e) 明文「一處實作」；第 19 包 §4.5(a) 落地事件面）。
  #
  # ①這是什麼：SaveProduct 偵測到 status 變更時的唯一出口。回傳 payload 用的
  #   status_transition 摘要，並在同 transaction 內補一筆 product.publication.changed
  #   內部事件（63 §C.1 決議表）。
  # ②為什麼集中：狀態轉移扇出到發布讀取層／管道同步／前台快取（塊 A 與未來包）——
  #   散在各寫入點就會像 IndexNow 一樣「按領域切包時被切碎後消失」（排程表 §2.1④）。
  #   本包只做事件面；發布讀取層語義不在本包（第 19 包 §5-7）。
  # ③冪等：事件與業務寫入同 transaction（鐵律 5），rollback 時一併消失。
  # ④跨功能影響：Catalog::SaveProduct（唯一呼叫端）、Events::Topics、
  #   未來的 Publishing::SyncJob（63 §C.5——訂 product.publication.changed）。
  class StatusTransition
    class << self
      # @param shop [Shop]
      # @param product [Product] 已 save、`saved_changes` 含 "status" 的商品
      # @return [Hash] {from:, to:} —— SaveProduct 塞進對外事件 payload 的摘要
      def call(shop:, product:)
        from, to = product.saved_changes.fetch("status")
        EventOutbox.create!(
          shop_id: shop.id,
          event_id: SecureRandom.uuid,
          topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED,
          aggregate_type: "Product",
          aggregate_id: product.id,
          payload: {
            product_id: product.id,
            resource_version: product.lock_version,
            status_transition: { from: from, to: to }
          },
          available_at: Time.current,
          status: "pending"
        )
        { from: from, to: to }
      end
    end
  end
end
