# frozen_string_literal: true

module Orders
  # 訂單履行狀態的**唯一推導器**（G6-8；鐵律 7——16 §F4.3 同款紀律：rollup 欄
  # 由子物件聚合推導，不可散寫）。
  #
  # 推導軸有二：①行項 fulfillable 存量（unfulfilled/partially_fulfilled/fulfilled）
  # ②FO 狀態覆蓋（on_hold > in_progress，僅在未全出貨時覆蓋——全出貨的單
  # 不再顯示 hold；ord-2 §1.3 官方 ON_HOLD 語義「fulfillment process can't be
  # initiated until the hold is released」只對未完成的工作有意義）。
  #
  # ⚠️ Solidus 同構佐證（ord-3 §1.2，BSD）：order 級 payment/shipment 軸＝
  # OrderUpdater 聚合重算的 rollup，真狀態機在子物件。
  module FulfillmentStatus
    module_function

    # @param order [Order] 呼叫端已持鎖（本方法不自行加鎖——在寫入交易內被呼叫）
    # @return [String] Order::FULFILLMENT_STATUSES 之一
    # @note 副作用：兩次 SELECT（行項聚合＋FO 狀態）；不寫入。
    def derive(order)
      totals = LineItem.where(shop_id: order.shop_id, order_id: order.id)
                       .pick(Arel.sql("COALESCE(SUM(quantity),0), COALESCE(SUM(fulfillable_quantity),0)"))
      ordered, fulfillable = Array(totals).map(&:to_i)
      return "fulfilled" if ordered.positive? && fulfillable.zero?

      fo_statuses = FulfillmentOrder.where(shop_id: order.shop_id, order_id: order.id)
                                    .distinct.pluck(:status)
      return "on_hold" if fo_statuses.include?("on_hold")
      return "in_progress" if fo_statuses.include?("in_progress")
      return "partially_fulfilled" if fulfillable < ordered

      "unfulfilled"
    end

    # 推導並落庫（呼叫端在交易內、已持 order 鎖）。
    #
    # @return [String] 寫入後的值
    # @note 副作用：可能 UPDATE orders.fulfillment_status。
    def sync!(order)
      value = derive(order)
      order.update!(fulfillment_status: value) if order.fulfillment_status != value
      value
    end
  end
end
