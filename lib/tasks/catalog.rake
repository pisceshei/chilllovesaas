# frozen_string_literal: true

# 商品線的投影重建（`limits.catalog_flow.projection_rebuild_tasks`：沒有 saga，
# 只有可重跑的投影——CI 斷言該清單與 task 一一對應）。
namespace :catalog do
  namespace :rebuild do
    desc "重建全部智慧系列的物化成員（逐店逐系列；ERROR 系列列出並以非零碼結束）"
    task collections: :environment do
      errors = 0
      Shop.find_each do |shop|
        ActsAsTenant.with_tenant(shop) do
          ids = CollectionSource.where(shop_id: shop.id).conditions_type.distinct.pluck(:collection_id)
          next if ids.empty?

          ids.each do |collection_id|
            collection = Collection.find_by(shop_id: shop.id, id: collection_id)
            next if collection.nil?

            result = Collections::Rebuild.call(shop:, collection:)
            status_word = result.status == :ok ? "OK" : result.status.to_s.upcase
            puts "shop=#{shop.subdomain} collection=#{collection_id} #{status_word} " \
                 "+#{result.inserted} -#{result.swept}#{" error=#{result.error}" if result.error}"
            errors += 1 if result.status == :error
          end
        end
      end
      abort "rebuild FAILED：#{errors} 個系列 ERROR" if errors.positive?
      puts "rebuild OK"
    end
  end
end
