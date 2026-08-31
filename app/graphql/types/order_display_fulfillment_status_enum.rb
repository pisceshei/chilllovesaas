# frozen_string_literal: true

module Types
  # 訂單履行顯示狀態（G6-6a）。對外 enum 名對位 Admin API
  # OrderDisplayFulfillmentStatus；值域＝我方 v1 儲存三值
  # （Order::FULFILLMENT_STATUSES：unfulfilled/partially_fulfilled/fulfilled）。
  #
  # 🔴 官方全集 10 值（88 §7：另含 IN_PROGRESS/ON_HOLD/SCHEDULED/REQUEST_DECLINED
  # 與三個被取代舊值）——SCHEDULED/ON_HOLD 等隨步 5 履約線把 hold/schedule 落庫時
  # 同批擴值（ours 刻意子集，先出現行狀態機能表達的值，不出永遠不會出現的值）。
  class OrderDisplayFulfillmentStatusEnum < GraphQL::Schema::Enum
    graphql_name "OrderDisplayFulfillmentStatus"
    description "訂單的履行顯示狀態（v1 三值；擴值隨履約線）"

    Order::FULFILLMENT_STATUSES.each do |status|
      value status.upcase, value: status
    end
  end
end
