# frozen_string_literal: true

module Types
  # 某個 (item, location) 的五個數量（實測 94 §2.1 的列表欄序）。
  #
  # 🔴 `unavailable` 與 `onHand` 是 DB 的 STORED GENERATED 欄（第 16 包），
  # 讀取即恆等式成立——**前端不得自行相加**（兩處算式遲早漂移，鐵律 7）。
  # `incoming` 不在 on_hand 恆等式內（本尊明文，docs/research/95 §2）。
  class InventoryQuantitiesType < BaseObject
    graphql_name "InventoryQuantities"
    description "單一地點的庫存數量；unavailable 與 onHand 由資料庫導出。"

    field :unavailable, Integer, null: false,
      description: "不可售合計（reserved＋damaged＋safety_stock＋quality_control，DB generated）。"
    field :committed, Integer, null: false, description: "已被訂單佔用（訂單線獨佔，不可手調）。"
    field :available, Integer, null: false, description: "可售。"
    field :on_hand, Integer, null: false,
      description: "在庫總量＝unavailable＋committed＋available（DB generated；不含 incoming）。"
    field :incoming, Integer, null: false, description: "在途（採購／轉移線獨佔，不可手調）。"
  end
end
