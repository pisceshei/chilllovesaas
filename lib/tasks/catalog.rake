# frozen_string_literal: true

# 商品線的投影重建（`limits.catalog_flow.projection_rebuild_tasks`：沒有 saga，
# 只有可重跑的投影——CI 斷言該清單與 task 一一對應）。
namespace :catalog do
  namespace :rebuild do
    desc "重建全部智慧系列的物化成員（逐店逐系列；ERROR 系列列出並以非零碼結束）"
    task collections: :environment do
      errors = 0
      # 🔴 `:skipped` 自 2026-08-26（F2 advisory lock）起有**兩個**意思：
      #   ①該系列沒有 conditions source（不是錯誤）②鎖等逾時、這一輪沒重建。
      #   只數 `:error` 會讓②靜默——而本任務正是 dev doc §4／P11-B9 明文倚賴的「兜底」，
      #   兜底回報綠色卻沒做事＝鐵律 20.2 第 5 類 fail-open。逐項分開數、分開報。
      contended = 0
      Shop.find_each do |shop|
        ActsAsTenant.with_tenant(shop) do
          # 🔴 兜底的工作清單＝**全部智慧系列**（2026-08-26 收斂輪 G1）：從
          #   `collection_sources` 導出會讓「條件被清空」的系列從兜底視野裡消失，
          #   而那正是最需要兜底的一格（物化成員殘留且無自癒路徑）。
          ids = Collection.where(shop_id: shop.id, collection_type: "smart").pluck(:id)
          next if ids.empty?

          # 🔴 **與 resync 同一份拓樸排序**（2026-08-26 第六輪 K2）：exclusion 的
          #   `collection` 型讀被引用系列的物化列 ⇒ 先算誰會改變答案。第五輪只把
          #   resync 改成拓樸序、這支兜底仍照 id 序，於是同一份規則兩支引擎給出
          #   不同的成員集（H4「取決於最後跑的是哪一支引擎」那個根因被重新打開）。
          ids = Collections::ReferenceGraph.topological(shop, ids)

          ids.each do |collection_id|
            collection = Collection.find_by(shop_id: shop.id, id: collection_id)
            next if collection.nil?

            result = Collections::Rebuild.call(shop:, collection:)
            status_word = result.status == :ok ? "OK" : result.status.to_s.upcase
            puts "shop=#{shop.subdomain} collection=#{collection_id} #{status_word} " \
                 "+#{result.inserted} -#{result.swept}#{" error=#{result.error}" if result.error}"
            errors += 1 if result.status == :error
            contended += 1 if result.error == Collections::Rebuild::LOCK_TIMEOUT_ERROR
          end
        end
      end
      abort "rebuild FAILED：#{errors} 個系列 ERROR、#{contended} 個系列鎖等逾時未重建" if errors.positive? || contended.positive?
      puts "rebuild OK"
    end
  end
end
