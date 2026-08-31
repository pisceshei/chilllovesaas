# frozen_string_literal: true

module Fulfillments
  # 更新追蹤資訊（G6-8 步 5；對位本尊 fulfillmentTrackingInfoUpdate——官方句
  # 「Updates tracking information for a fulfillment, including the carrier name,
  # tracking numbers, and tracking URLs.」，取證 2026-09-01）。
  #
  # 🔴 「整組取代 vs 合併」＝**官方未取得**（mutation 頁與 FulfillmentTrackingInput
  # 頁對 replace／merge／existing 全部零命中——ord-4 §2 兩頁複核）。我方裁定＝
  # **整組取代**（ours）：input 是完整的 tracking 描述（company＋numbers 平行陣列），
  # 部分合併會讓「刪掉一個追蹤號」無法表達。登記 dev doc，取得官方語義後複驗。
  module UpdateTracking
    Result = Data.define(:fulfillment, :error)

    module_function

    # @param shop [Shop]
    # @param fulfillment_id [Integer]
    # @param tracking [Hash] { company:, numbers: [{number:, url:}] }
    # @param notify_customer [Boolean, nil] nil＝不改（官方逐字「If this field is
    #   left blank, then notifications won't be sent…」——缺席不通知，不改既有旗標）
    # @return [Result]
    # @note 副作用：UPDATE fulfillments；INSERT events。
    def call(shop:, fulfillment_id:, tracking:, notify_customer: nil)
      ActiveRecord::Base.transaction do
        fulfillment = Fulfillment.lock.find_by(shop_id: shop.id, id: fulfillment_id)
        if fulfillment.nil?
          next Result.new(fulfillment: nil, error: [ "fulfillmentId", "找不到這筆出貨。", "NOT_FOUND" ])
        end
        if fulfillment.status == "cancelled"
          next Result.new(fulfillment:, error: [ "fulfillmentId", "已取消的出貨不能更新追蹤資訊。", "INVALID_STATE" ])
        end

        attrs = {
          tracking_company: tracking[:company].presence,
          tracking_numbers: Array(tracking[:numbers]).map { |n| { "number" => n[:number], "url" => n[:url] }.compact }
        }
        attrs[:customer_notified] = notify_customer unless notify_customer.nil?
        fulfillment.update!(attrs)

        order = fulfillment.order
        Event.create!(shop_id: shop.id, order_id: order.id, kind: "order.tracking_updated",
                      happened_at: Time.current, subject_type: "Fulfillment", subject_id: fulfillment.id,
                      metadata: { "tracking_company" => tracking[:company].to_s.presence,
                                  "numbers" => Array(tracking[:numbers]).map { |n| n[:number] } }.compact)
        Result.new(fulfillment:, error: nil)
      end
    end
  end
end
