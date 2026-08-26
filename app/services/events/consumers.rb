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
      Events::Topics::INVENTORY_ADJUSTED => [ Collections::ResyncConsumer ]
    }.freeze

    # @param topic [String]
    # @return [Array<#name, #call>]
    def self.for(topic)
      REGISTRY.fetch(topic, [])
    end
  end
end
