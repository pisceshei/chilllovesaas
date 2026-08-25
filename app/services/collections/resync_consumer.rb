# frozen_string_literal: true

module Collections
  # 商品變動 → 智慧系列增量重算的消費者（第 11 包；P11-U17 的 ours 裁定）。
  #
  # ①契約（Events::Consumers 檔頭）：`name`（進 event_deliveries.consumer，改名＝重放）
  #   ＋`call(event)` 冪等——`ResyncProduct` 算的是「現值該不該在」，重叫收斂。
  # ②訂閱三個 topic（註冊表）：PRODUCTS_CREATE／PRODUCTS_UPDATE（標題/類型/廠商/標籤/
  #   狀態/變體樹都經 productSet ⇒ 這兩個事件涵蓋）＋INVENTORY_ADJUSTED
  #   （variant_inventory 條件的變因，不經 productSet）。
  # ③payload 形狀差異：Product 事件帶 `product_id`；inventory 事件帶
  #   `product_variant_id`（經變體反查商品）。查無主＝事件比資料活得久，不是錯誤
  #   ——但商品刪除本身**必須**重算（從所有系列移出），所以 product_id 查無仍照跑
  #   （ResyncProduct 對 nil product 的語義就是移出）。
  module ResyncConsumer
    module_function

    def name = "collections.resync"

    # @param event [EventOutbox]
    def call(event)
      shop = Shop.find_by(id: event.shop_id)
      return if shop.nil?

      product_id = event.payload["product_id"]
      if product_id.nil? && (variant_id = event.payload["product_variant_id"])
        product_id = ProductVariant.unscoped.where(shop_id: shop.id, id: variant_id)
                                   .pick(:product_id)
        return if product_id.nil?   # 變體已刪：商品層事件會另行到達
      end
      return if product_id.nil?

      ResyncProduct.call(shop:, product_id:)
    end
  end
end
