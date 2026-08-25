# frozen_string_literal: true

module Collections
  # 商品變動 → 智慧系列增量重算的消費者（第 11 包；P11-U17 的 ours 裁定）。
  #
  # ①契約（Events::Consumers 檔頭）：`name`（進 event_deliveries.consumer，改名＝重放）
  #   ＋`call(event)` 冪等——`ResyncProduct` 算的是「現值該不該在」，重叫收斂。
  # ②訂閱三個 topic（註冊表）：PRODUCTS_CREATE／PRODUCTS_UPDATE（標題/類型/廠商/標籤/
  #   狀態/變體樹都經 productSet ⇒ 這兩個事件涵蓋）＋INVENTORY_ADJUSTED
  #   （variant_inventory 條件的變因，不經 productSet）。
  # ③payload 形狀差異（🔴 2026-08-26 收斂輪 H3 更正）：Product 事件帶 `product_id`；
  #   **庫存事件帶的是 `inventory_item_id`**——`Inventory::Adjust#enqueue_adjust_event!`
  #   的 payload 只有 `{adjustment, location_id, inventory_item_id, availability_flipped}`，
  #   **從來沒有** `product_id`／`product_variant_id`。初版照後者讀 ⇒ 兩個鍵都是 nil ⇒
  #   `return`，Relay 把 delivery 記成 done、事件標 published，**無錯誤、無重試**：
  #   整條 INVENTORY_ADJUSTED 觸發鏈是死的，`variant_inventory` 條件的智慧系列
  #   永遠不因庫存變動更新。單元測試看不見，因為它自己捏了一個帶 `product_variant_id`
  #   的 payload——**fixture 與真實生產者不符＝假綠**。
  #   ⇒ 本消費者自己反查（`inventory_item_id` → `product_variant_id` → `product_id`），
  #   不改生產端（那是庫存包的契約，且 D43 規定庫存寫入只走 `Inventory::Adjust`）。
  #   三個鍵都支援：`product_id` 直用；`product_variant_id` 反查；`inventory_item_id` 反查。
  #   查無主＝事件比資料活得久，不是錯誤——但商品刪除本身**必須**重算
  #   （從所有系列移出），所以 product_id 查無仍照跑（ResyncProduct 對 nil product
  #   的語義就是移出）。
  module ResyncConsumer
    module_function

    def name = "collections.resync"

    # @param event [EventOutbox]
    def call(event)
      shop = Shop.find_by(id: event.shop_id)
      return if shop.nil?

      product_id = event.payload["product_id"]
      product_id ||= resolve_via_variant(shop, event.payload["product_variant_id"])
      product_id ||= resolve_via_inventory_item(shop, event.payload["inventory_item_id"])
      return if product_id.nil?

      ResyncProduct.call(shop:, product_id:)
    end

    # 變體已刪 ⇒ nil（商品層事件會另行到達）。
    def resolve_via_variant(shop, variant_id)
      return nil if variant_id.nil?

      ProductVariant.unscoped.where(shop_id: shop.id, id: variant_id).pick(:product_id)
    end

    # 庫存事件的唯一識別（H3）：inventory_items 是 variant 的 1:1 側車。
    def resolve_via_inventory_item(shop, inventory_item_id)
      return nil if inventory_item_id.nil?

      variant_id = InventoryItem.unscoped.where(shop_id: shop.id, id: inventory_item_id)
                                .pick(:product_variant_id)
      resolve_via_variant(shop, variant_id)
    end
  end
end
