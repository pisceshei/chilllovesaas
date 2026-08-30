# frozen_string_literal: true

module Catalog
  # 商品資料變動 → 所在系列頁快取失效（包 30／D77；§1.6 接口矩陣的最後一格）。
  #
  # ①這是什麼：內部 topic `product.updated`／`product.variant.updated` 的消費者。
  #   商品的**資料**（標題／價格／媒體）變了，系列頁上顯示的是舊值——但成員集合
  #   沒變 ⇒ `Collections::Rebuild` 的 bump（成員變動時才發生）蓋不到這條路。
  #   本消費者補上：bump 所有**含該商品**的系列的 `products_updated_at`。
  # ②為什麼走事件不走寫路徑同步：與 ResyncConsumer 同理（D50 的 ours 裁定——
  #   鐵律 5 ＋ 不掛在商品儲存的鎖持有時間上）。
  # ③冪等：bump 是「推到現在時刻」的單調操作，at-least-once 重叫收斂（多推一次
  #   只是快取多失效一次，不是資料錯誤）。
  # ④成員來源＝`collection_memberships`（物化成員表，前台唯一查詢對象——
  #   13 §F4.6-1；手動＋智慧系列都在裡面）。
  module CacheStampBumper
    module_function

    # 進 event_deliveries.consumer 的具名身分（改名＝全部事件重放）。
    def name = "catalog.cache_stamp_bumper"

    # @param event [EventOutbox]
    # @return [void]
    def call(event)
      product_id = event.payload["product_id"]
      product_id ||= resolve_via_variant(event.shop_id, event.payload["product_variant_id"])
      return if product_id.nil?

      ActsAsTenant.without_tenant do
        collection_ids = CollectionMembership
                         .where(shop_id: event.shop_id, product_id: product_id)
                         .distinct.pluck(:collection_id)
        collection_ids.each { |cid| CacheStamps.bump_collection_members!(event.shop_id, cid) }
      end
    end

    # 變體事件 ⇒ 解析父商品（變體已刪 ⇒ nil，商品層事件會另行到達——ResyncConsumer 同款）。
    def resolve_via_variant(shop_id, variant_id)
      return nil if variant_id.nil?

      ProductVariant.unscoped.where(shop_id: shop_id, id: variant_id).pick(:product_id)
    end
  end
end
