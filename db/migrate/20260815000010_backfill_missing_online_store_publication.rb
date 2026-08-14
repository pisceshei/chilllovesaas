# 補上「在 `20260814200000` 之後、`Shop#after_create` 之前」建立的商店所缺的
# `online_store` publication（88 §5 #1 的歷史那一半）。
#
# 🔴 **這個缺陷有兩半，缺一半就等於沒修**：
#   - **未來**：`Shop#after_create`（本批同一個 commit）讓之後每一間新店都有管道；
#   - **歷史**：本 migration 補上那個時間窗裡建出來的店。
# 只做 callback，既有的店永遠是壞的；只做 migration，明天建的店又是壞的。
#
# 時間窗有多真實：`20260814200000` 只回填了**它執行當下既有**的店。之後每一次
# `bin/rails db:seed`（新 subdomain）、每一次 spec 建店、每一次開發者手動建店，
# 都會產生一間沒有管道的店——而且**不會拋任何錯**，只是那間店的所有商品都上不了架。
#
# ## 🔴 為什麼不順便回填 `resource_publications`
#
# `20260814200000` 當時把 `products.published_at` 原樣搬進 `resource_publications`——
# 但**那個欄位已經被同一支 migration 移除了**。時間窗裡建出來的商品從來沒有過
# `published_at`，所以「原樣搬」無值可搬，只剩兩個都要靠猜的選項：
#   - 填 `NOW()` ⇒ 這是在實作 `auto_publish` 的行為（88 §2.1：「新增管道時既有商品
#     自動可用」），而那是 **§5 #2，明確延後到商品 CRUD**；
#   - 填 `NULL` ⇒ 與我們正要建的這個 publication 的 `auto_publish: true` **自相矛盾**。
# ⇒ 兩條都是發明語義。本 migration 只補**確定該有**的那一列 publication，
#   `auto_publish` 的實際行為（既有商品自動納入 ＋ 新商品自動納入）整包留給 §5 #2，
#   一次做對比拆兩半各做一點好。
#
# @see docs/specs/88-publication-model.md §4、§5 #1、§5 #2
# @see app/models/shop.rb#create_default_publication
class BackfillMissingOnlineStorePublication < ActiveRecord::Migration[8.1]
  def up
    # strong_migrations 的 `check_execute` 是**無條件** raise（不像索引檢查只在
    # PostgreSQL 上 raise），所以 `execute` 一定要明示安全。
    # 安全理由：單一 INSERT ... SELECT，只寫入 `publications`；
    # `NOT EXISTS` 讓它天生冪等（重跑不會產生第二列，也不會撞
    # `uq_publications_channel` 這個 `(shop_id, channel_handle)` 唯一索引）。
    safety_assured do
      execute <<~SQL.squish
        INSERT INTO publications (shop_id, name, channel_handle, auto_publish,
                                  supports_future_publishing, created_at, updated_at)
        SELECT s.id, '線上商店', 'online_store', TRUE, TRUE, NOW(), NOW()
        FROM shops s
        WHERE NOT EXISTS (
          SELECT 1 FROM publications p
          WHERE p.shop_id = s.id AND p.channel_handle = 'online_store'
        )
      SQL
    end
  end

  # 🔴 **不可逆**，而且刻意不做成可逆。
  # 「刪掉所有 online_store publication」會連 `20260814200000` 建的那一批一起刪，
  # 而它們是**上一支 migration 的產物**——回滾本檔不該動到上一支的成果。
  # 而「只刪本檔建的那些」需要一個標記欄位來區分，為了 rollback 加一個永久欄位
  # 是本末倒置。⇒ 宣告不可逆，讓誤操作當場失敗而不是靜默刪掉別人的資料。
  def down
    raise ActiveRecord::IrreversibleMigration,
      "回滾會連 20260814200000 建立的 publication 一起刪除；" \
      "若真的要移除，請針對特定 shop_id 手動處理。"
  end
end
