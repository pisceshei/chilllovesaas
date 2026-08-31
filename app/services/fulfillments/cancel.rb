# frozen_string_literal: true

module Fulfillments
  # 取消出貨（G6-8 步 5；對位本尊 fulfillmentCancel——官方句逐字（取證 2026-09-01）：
  # 「Cancels an existing Fulfillment and reverses its effects on associated
  # FulfillmentOrder objects. When you cancel a fulfillment, the system creates new
  # fulfillment orders for the cancelled items so they can be fulfilled again.」）。
  #
  # ## v1 對映（單 FO 形）
  # 本尊「為取消品項建**新** FO」是多 FO 模型的行為；我方 v1 每單一張 FO ⇒
  # 等價操作＝把品項的 fulfillable_quantity 回加到**同一張** FO 的射程內、
  # FO closed 則翻回 open（官方第二段「If a fulfillment order was entirely
  # fulfilled, then it automatically closes.」的逆向）。dev doc 登記此 ours 對映。
  #
  # ## 庫存
  # 出貨時 committed− ⇒ 取消出貨 committed+ 回加（訂單線獨佔欄；對稱還原，
  # 16 驗收「cancel 後庫存恆等式」）。tracked 變體才動，同 Create 的選擇規則。
  module Cancel
    Result = Data.define(:fulfillment, :error)

    module_function

    # @param shop [Shop]
    # @param fulfillment_id [Integer]
    # @return [Result]
    # @note 副作用：UPDATE fulfillments.status／line_items.fulfillable_quantity／
    #   inventory_levels.committed／fulfillment_orders.status／orders.fulfillment_status；
    #   INSERT events。
    def call(shop:, fulfillment_id:)
      ActiveRecord::Base.transaction do
        fulfillment = Fulfillment.lock.find_by(shop_id: shop.id, id: fulfillment_id)
        if fulfillment.nil?
          next Result.new(fulfillment: nil, error: [ "id", "找不到這筆出貨。", "NOT_FOUND" ])
        end
        if fulfillment.status == "cancelled"
          next Result.new(fulfillment:, error: [ "id", "這筆出貨已經取消過了。", "INVALID_STATE" ])
        end

        fo = FulfillmentOrder.lock.find_by(shop_id: shop.id, id: fulfillment.fulfillment_order_id)
        order = Order.lock.find_by(shop_id: shop.id, id: fo.order_id)

        fulfillment.update!(status: "cancelled")

        snapshot = Array(fulfillment.line_items_snapshot)
        restore_fulfillable!(shop, snapshot)
        restore_committed!(shop, snapshot)

        fo.update!(status: "open", closed_at: nil) if fo.status == "closed"
        Orders::FulfillmentStatus.sync!(order)

        Event.create!(shop_id: shop.id, order_id: order.id, kind: "order.fulfillment_cancelled",
                      happened_at: Time.current, subject_type: "Fulfillment", subject_id: fulfillment.id,
                      metadata: { "items" => snapshot.sum { |s| s["quantity"].to_i } })
        Result.new(fulfillment:, error: nil)
      end
    end

    # 回加 fulfillable（無條件加法——回加不會超過 quantity 的前提由「扣減時
    # 條件式 UPDATE 擋超量」保證；防禦性上界仍進 WHERE，破例即資料不一致誠實爆）。
    #
    # @note 副作用：UPDATE line_items。
    def restore_fulfillable!(shop, snapshot)
      snapshot.sort_by { |s| s["line_item_id"].to_i }.each do |s|
        affected = LineItem.where(shop_id: shop.id, id: s["line_item_id"])
                           .where("fulfillable_quantity + ? <= quantity", s["quantity"])
                           .update_all([ "fulfillable_quantity = fulfillable_quantity + ?", s["quantity"] ])
        if affected.zero?
          raise ActiveRecord::RecordInvalid.new(
            LineItem.new.tap { |r| r.errors.add(:base, "回加數量會超過訂購量——出貨資料不一致。") }
          )
        end
      end
    end

    # 回加 committed（出貨釋放的逆向；tracked 變體才動，level 選擇同 Create）。
    #
    # @note 副作用：UPDATE inventory_levels.committed（訂單線獨佔欄）。
    def restore_committed!(shop, snapshot)
      priorities = Location.where(shop_id: shop.id).pluck(:id, :priority).to_h
      moves = snapshot.filter_map do |s|
        row = LineItem.find_by(shop_id: shop.id, id: s["line_item_id"])
        variant = row&.product_variant_id && ProductVariant.find_by(shop_id: shop.id, id: row.product_variant_id)
        next unless variant && variant.inventory_item&.tracked

        level = variant.inventory_item.inventory_levels
                       .min_by { |l| [ priorities[l.location_id] || 0, l.id ] }
        next if level.nil?

        { level_id: level.id, quantity: s["quantity"].to_i }
      end

      moves.sort_by { |m| m[:level_id] }.each do |m|
        InventoryLevel.where(shop_id: shop.id, id: m[:level_id])
                      .update_all([ "committed = committed + ?", m[:quantity] ])
      end
    end
  end
end
