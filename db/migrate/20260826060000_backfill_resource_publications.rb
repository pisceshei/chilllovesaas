# frozen_string_literal: true

# 第 12 包：補齊既有 Product／ProductVariant／Collection 的發布列。
#
# 🔴 **為什麼需要這支**：`resource_publications` 自 `20260814200000` 建立以來，
# 倉庫裡沒有任何程式碼會建立它的列（`docs/specs/88` §5 待辦 #2 明文延後）。
# 本包補上了三個 `after_create` 生產者，但它們只管**未來**建立的資源；
# **歷史資料**要靠這支回填。兩半缺一等於沒修——這與 88 §5 #1 的
# 「callback 修未來、migration 修歷史」是同一條教訓，那次也是兩半。
#
# 規則與 `Publications::Materialize` 完全相同（同一支實作，不另寫一份）：
# 對每個資源，補齊所有 `auto_publish = true` 的 publication。
#
# @see docs/plans/2026-08-26-第12包執行規格.md §2.2
# @see docs/research/82-admin-channels.md §8.4
class BackfillResourcePublications < ActiveRecord::Migration[8.1]
  def up
    # 🔴 **整段包 `ActsAsTenant.without_tenant`**——不是防禦性寫法，是必要條件。
    #   `config/initializers/acts_as_tenant.rb` 設 `require_tenant = true`，而
    #   `ResourcePublication` 與 `Publication` 都宣告 `acts_as_tenant :shop`
    #   ⇒ 在沒有 current_tenant 時，**讀**會被 default scope 過濾、**寫**直接
    #   raise `NoTenantSet`。`.unscoped` 只拿掉 default scope，擋不住寫入那一半。
    #
    # 🔴 **本檔為什麼一定要有這一行、而且一定要有配對的 spec**（2026-08-26，
    #   第 11 包 `20260826058000` 的部署事故換來的）：回填迴圈的**本體**只有在
    #   資料庫裡已經有既有資料時才會被執行到。CI 的 `db:migrate` 跑在**空資料庫**上，
    #   開發庫也常剛好沒有 ⇒ **兩處都不執行迴圈本體，`db:migrate` 一路綠**，
    #   只有正式環境會炸。「migration 在 CI 綠」不證明「migration 對既有資料安全」。
    #   ⇒ 配對 spec＝`spec/migrations/p12_backfill_publications_spec.rb`（含盯住本行的
    #   source-guard，因為 spec 用的是自己的邏輯副本，拿掉本行 spec 仍會綠）。
    say_with_time "backfill resource_publications for existing publishables" do
      created = 0

      ActsAsTenant.without_tenant do
        # 逐店處理：`auto_publish` 的管道集合是**每店各自**的。
        Publication.unscoped.where(auto_publish: true).group_by(&:shop_id).each do |shop_id, publications|
          publication_ids = publications.map(&:id)

          {
            "Product" => Product,
            "ProductVariant" => ProductVariant,
            "Collection" => Collection
          }.each do |type, klass|
            klass.unscoped.where(shop_id:).select(:id).find_in_batches(batch_size: 1_000) do |batch|
              ids = batch.map(&:id)

              # 已存在的 (publishable_id, publication_id) 配對——冪等的依據。
              existing = ResourcePublication.unscoped.where(
                shop_id:, publishable_type: type, publishable_id: ids, publication_id: publication_ids
              ).pluck(:publishable_id, :publication_id).to_set

              rows = ids.flat_map do |publishable_id|
                publication_ids.filter_map do |publication_id|
                  next if existing.include?([ publishable_id, publication_id ])

                  {
                    shop_id:, publication_id:,
                    publishable_type: type, publishable_id:,
                    published_at: Time.current,
                    created_at: Time.current, updated_at: Time.current
                  }
                end
              end
              next if rows.empty?

              # 🔴 這裡用 `insert_all` 而生產者服務用 `create!`，是**刻意的不對稱**：
              #   `insert_all` 繞過 validation（含 `publishable_belongs_to_same_shop`），
              #   在一般寫入路徑上那是漏洞——但這裡的 `publishable_id` 是**從
              #   同一個 shop_id 的表裡查出來的**，租戶歸屬由查詢本身保證，
              #   不依賴 validation。換來的是既有資料量下可接受的回填時間。
              #   ⚠️ 任何人把這段複製到**非回填**的路徑，那個保證就不存在了。
              ResourcePublication.unscoped.insert_all(rows)
              created += rows.size
            end
          end
        end
      end

      created
    end
  end

  def down
    # 不可逆：無法區分「本次回填建的列」與「使用者後來手動發布的列」。
    raise ActiveRecord::IrreversibleMigration
  end
end
