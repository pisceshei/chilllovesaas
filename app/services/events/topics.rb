# frozen_string_literal: true

module Events
  # 事件 topic 的單一常數表（第 19 包 §4.4；收斂 28 §15／63 §C.1／代碼字面三份清單）。
  #
  # ①這是什麼：全部 outbox topic 的正典。產生端與 relay 一律引這裡，不寫字面字串。
  # ②兩層語義（63 §C.1）：對外 topic「資源/動詞」可被 webhookSubscriptionCreate 訂閱
  #   （M1 尚未實作訂閱面）；內部 topic「資源.動詞」永不進可訂閱列表。
  # ③內部 topic 目前只發 INVENTORY_ADJUSTED 與 PRODUCT_PUBLICATION_CHANGED；
  #   其餘三個（product.updated／product.variant.updated／inventory.level.changed）是
  #   63 §C.1 決議表的留位——接消費者的包啟用（前置＝event_deliveries，見 63 §L-4 門檻）。
  #   `inventory.level.changed` 保留給非調整型變化（如地點停用連動），Adjust 不發它。
  # ④跨功能影響：Catalog::SaveProduct／Inventory::Adjust（產生端）、Events::Relay（消費端
  #   路由鍵）、未來的 webhookSubscriptionCreate 白名單（EXTERNAL 即該白名單的種子）。
  #
  # 🔴 einvoice/issue_requested／void_requested／refund_routed（18 §F1-6 的三個內部 topic）
  #    屬 TW jurisdiction pack，pack 未實作前留註不留值——加值時同步 28 §15。
  module Topics
    # 對外（28 §15 首發面的商品線子集）
    PRODUCTS_CREATE = "products/create"
    PRODUCTS_UPDATE = "products/update"
    PRODUCTS_DELETE = "products/delete"
    COLLECTIONS_CREATE = "collections/create"
    COLLECTIONS_UPDATE = "collections/update"
    COLLECTIONS_DELETE = "collections/delete"
    INVENTORY_LEVELS_UPDATE = "inventory_levels/update"

    EXTERNAL = [
      PRODUCTS_CREATE, PRODUCTS_UPDATE, PRODUCTS_DELETE,
      COLLECTIONS_CREATE, COLLECTIONS_UPDATE, COLLECTIONS_DELETE,
      INVENTORY_LEVELS_UPDATE
    ].freeze

    # 內部（63 §C.1 決議表；不對外開放訂閱）
    PRODUCT_UPDATED = "product.updated"
    PRODUCT_VARIANT_UPDATED = "product.variant.updated"
    PRODUCT_PUBLICATION_CHANGED = "product.publication.changed"
    INVENTORY_LEVEL_CHANGED = "inventory.level.changed"
    INVENTORY_ADJUSTED = "inventory.adjusted"

    INTERNAL = [
      PRODUCT_UPDATED, PRODUCT_VARIANT_UPDATED, PRODUCT_PUBLICATION_CHANGED,
      INVENTORY_LEVEL_CHANGED, INVENTORY_ADJUSTED
    ].freeze

    ALL = (EXTERNAL + INTERNAL).freeze
  end
end
