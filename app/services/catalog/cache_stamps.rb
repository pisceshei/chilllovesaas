# frozen_string_literal: true

module Catalog
  # cache stamp 欄的**唯一寫入面**（第 3 包；63 §D.3 的 key-based expiry 維度）。
  #
  # ①這是什麼：第 33 包的頁級快取 key 會吃這些欄
  #   （正典清單＝limits **`catalog_flow.cache_stamp_sources`**——第一版檔頭寫成
  #   `cache.`，那個路徑不存在，審查 M3-4 抓到；handoff 自己都把它列為被推翻的
  #   假設，檔頭卻沒跟上）。欄位存在但沒人 bump＝凍結的 stamp
  #   ＝**永久舊快取**——顯示舊圖舊價且沒有任何錯誤，這正是排程把它列為
  #   「靜默失敗」的原因。所以每一個會改變前台呈現的寫入路徑都必須經過這裡。
  #
  # ②🔴 **用 `update_all` 不用 `save`**：stamp 不是業務欄位——不需要 validation、
  #   不需要 callback、**不得** bump `lock_version`（否則改一張圖的 alt 會讓
  #   正在編輯該商品的人存檔時撞 STALE_OBJECT）。一律在呼叫端的 transaction 內執行。
  #   🔴 而 **Rails 8.1 的 `update_all` 對有樂觀鎖的 model 會自動 +1 `lock_version`**
  #   （實測：`update_all(media_updated_at:)` 讓 0 → 1，正是上面要防的事故；
  #   本包首輪就被既有 C6 spec 的 destroy 撞 StaleObjectError 抓到）。
  #   官方的 opt-out＝把 locking column 顯式列進更新——`lock_version = lock_version`。
  #   下面的 `TOUCH` 字串就是為此存在，**不得**改回 hash 形式。
  #
  # ③🔴 **檔案層寫入要 bump 的是「所有用到這個檔的商品」**：D48 之後一張圖只有
  #   一份 alt，從檔案庫改一次＝所有掛著它的商品頁都變了。只 bump 一個商品
  #   是本模組最容易犯的錯——留了一個「其他商品顯示舊 alt」的靜默窗。
  #
  # ④跨功能影響：消費者＝第 33 包的頁級快取 key 與 limits
  #   `cache_stamp_selfcheck_envs` 的 render 期自檢。寫入者清單見各 bump 方法的呼叫端
  #   （複驗＝`git grep -n "CacheStamps\." app/`）。
  module CacheStamps
    class << self
      # 變體樹變了（SaveProduct 的宣告式全量寫入／DeleteVariant）。
      # 一律收 `shop_id` 整數不收 Shop 物件——ProcessFile 這類呼叫端手上只有
      # `file.shop_id`，收物件會逼它多發一次 `Shop.find`。
      # 🔴 **`UTC_TIMESTAMP(6)` 不是 `CURRENT_TIMESTAMP(6)`**（審查 cs-3，實測）：
      #   後者用 MySQL session 時區（本機＝SYSTEM＝台北 +8），寫進去的是牆鐘時刻，
      #   而 Rails 全部以 UTC 讀寫 datetime ⇒ stamp 被讀成**未來 8 小時**。
      #   同一根欄兩個時鐘域＝快取 key 的比較毫無意義。UTC_TIMESTAMP 不受 session
      #   時區影響（實測與 `Time.current.utc` 同值）；(6)＝Rails datetime 的微秒精度。
      TOUCH = "%s = UTC_TIMESTAMP(6), lock_version = lock_version"

      def bump_variants!(shop_id, product_id)
        Product.where(shop_id:, id: product_id)
               .update_all(format(TOUCH, "variants_updated_at"))
      end

      # 這個商品的媒體集合變了（掛列／卸列／排序／變體圖指派）。
      def bump_media_for_product!(shop_id, product_id)
        Product.where(shop_id:, id: product_id)
               .update_all(format(TOUCH, "media_updated_at"))
      end

      # 這個**檔案**變了（alt／衍生尺寸完成／處理失敗）⇒ 所有用到它的商品（見③）。
      def bump_media_for_file!(shop_id, file_id)
        Product.where(shop_id:,
                      id: Media.where(shop_id:, file_id:).select(:product_id))
               .update_all(format(TOUCH, "media_updated_at"))
      end

      # 系列成員集合變了（14 §F1 的 collections.products_updated_at）。
      def bump_collection_members!(shop_id, collection_id)
        Collection.where(shop_id:, id: collection_id)
                  .update_all(format(TOUCH, "products_updated_at"))
      end
    end
  end
end
