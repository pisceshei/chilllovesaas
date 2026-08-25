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

      Collections::Rebuild.call(shop:, collection:)
    end
  end
end
