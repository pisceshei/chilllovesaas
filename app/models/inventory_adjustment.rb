# frozen_string_literal: true

# append-only 庫存 ledger 子行（排程第 16 包；總裁定 §一：一列＝一個 (group, level) 的全部 delta）。
#
# ①這是什麼：group 的子行。六個 leaf delta 實體欄；`unavailable_delta`／`on_hand_delta` 是
#   STORED GENERATED（狀態間移動一列自含：damaged→available ＝ 同列兩個相反符號 delta，
#   on_hand_delta 自動為 0）。
# ②值域：delta 可正可負；`ledger_document_uri` 除 available 外必填、禁 `gid://shopify/*`
#   （驗證在第 17 包服務層——本尊三個對應錯誤碼見 docs/research/95 §4）。
# ③怎麼做：**append-only**——無 update 路徑；建立走 `Inventory::Adjust` 唯一入口（第 17 包）。
#   `readonly?` 對持久列恆 true ＝ DB 層之外的第二道防改機制。
# ④跨功能影響：歷程頁一列＝一個 group（顯示時按 group 聚合，本表提供 per-level delta）；
#   API `changes[]`＝讀取期展開非零 delta（含 generated 兩欄）；對帳（第 17 包 rake）
#   對本表做 SUM(delta) 與 levels 現值逐式比對。
class InventoryAdjustment < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :inventory_adjustment_group
  belongs_to :inventory_level

  attr_readonly :on_hand_delta, :unavailable_delta

  # append-only：持久化後任何 update/destroy 一律拒絕（ActiveRecord::ReadOnlyRecord）。
  def readonly? = persisted?
end
