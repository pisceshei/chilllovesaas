# frozen_string_literal: true

module Events
  # 消費者註冊表（第 25 包；63 §L-4 門檻結清後的路由層）。
  #
  # ①這是什麼：topic → 具名消費者清單。消費者契約＝回應 `name`（String，
  #   進 event_deliveries.consumer，改名＝重放）與 `call(event)`（冪等——
  #   at-least-once 語義下同一事件可能重叫）。
  # ②🔴 接消費者只動本表，不動 Relay（掛載縫契約，P19 relay.rb ⑦沿革）。
  #   第 26 包接上首個真實消費者（`MediaPipeline::ProcessConsumer`）；
  #   第 30 包 CacheStampBumper 訂閱 product.updated／product.variant.updated。
  # ③逐消費者語義（Relay#deliver）：每消費者一列 event_deliveries；done 列重試時
  #   跳過——一個消費者失敗不連累另一個重放（本包判準，spec 釘住）。
  module Consumers
    REGISTRY = {
      Events::Topics::MEDIA_UPLOADED => [ MediaPipeline::ProcessConsumer ],
      # 第 11 包（D50）：商品/庫存變動 → 智慧系列增量重算（P11-U17 的 ours 裁定——
      # 走 outbox 消費者而非寫路徑同步，鐵律 5＋不掛在商品儲存的鎖持有時間上）。
      Events::Topics::PRODUCTS_CREATE => [ Collections::ResyncConsumer ],
      Events::Topics::PRODUCTS_UPDATE => [ Collections::ResyncConsumer ],
      Events::Topics::INVENTORY_ADJUSTED => [ Collections::ResyncConsumer ],
      # PR-C（D53）：排程發布到點 → cache stamp bump。同 topic 兩種 payload 形狀
      # （scheduled／status_transition），分流在消費者內（見其檔頭 ①）。
      # S8（D74）：同 topic 第二個消費者——到點時把排程轉成對外 ADD 事件
      # （官方逐字 "At the scheduled datetime, Shopify sends a product_listing/add
      # event"）。逐消費者 delivery 隔離（本表檔頭③）⇒ 兩者互不連累。
      Events::Topics::PRODUCT_PUBLICATION_CHANGED => [
        Publications::ScheduledPublicationConsumer,
        Publications::ListingEventTranslator
      ]
    }.freeze

    # @param topic [String]
    # @return [Array<#name, #call>]
    def self.for(topic)
      REGISTRY.fetch(topic, [])
    end
  end
end
