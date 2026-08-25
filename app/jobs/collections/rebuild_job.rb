# frozen_string_literal: true

module Collections
  # 智慧系列全量重建 job（第 11 包）。payload 只帶 id——執行時重讀**當前**規則
  # （研究 §5：帶規則快照的 job 會用舊規則覆蓋新結果）。冪等：重跑收斂。
  class RebuildJob < ApplicationJob
    queue_as :default

    # @param shop_id [Integer]
    # @param collection_id [Integer]
    def perform(shop_id, collection_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil?

      collection = ActsAsTenant.with_tenant(shop) { Collection.find_by(shop_id: shop.id, id: collection_id) }
      return if collection.nil?   # 系列已刪：job 比資料活得久，不是錯誤

      result = Collections::Rebuild.call(shop:, collection:)
      # 🔴 鎖等逾時＝同系列另一場 rebuild 正在跑且超出等待預算：**讓位＋延後重排**，
      #   不靜默丟——跑者可能在本 job 觸發的規則版本**之前**編譯（advisory lock 見
      #   Rebuild 檔頭⑤a）。重排以實際爭用為界（鎖隨連線死亡自動釋放，不會永久卡住）；
      #   rake catalog:rebuild:collections 為兜底。
      if result.error == Collections::Rebuild::LOCK_TIMEOUT_ERROR
        delay = Limits.fetch(:collection, :rebuild_lock_requeue_delay_seconds)
        self.class.set(wait: delay.seconds).perform_later(shop_id, collection_id)
      end
    end
  end
end
