# frozen_string_literal: true

# 第 3 包：共用遷移批次（一次改表，避免五次遷移演練）。
#
# ①cache stamp 欄（63 §D.3 的 key-based expiry 維度；正典清單＝limits
#   `cache.cache_stamp_sources`）。🔴 stamp 欄晚補的失敗形態是**靜默的**：
#   第 33 包的頁級快取 key 少一個維度＝顯示舊圖舊價且沒人會知道。
#   欄位**刻意 nullable**：null＝「本包上線前從未變動過」，快取 key 端把 null
#   當 epoch；改 `null: false` 會要求每個 `Product.create!` 呼叫點都帶值，
#   炸掉全部既有 factory 與腳本。backfill 仍做（見 up），讓存量資料有誠實起點。
# ②`files.alt_source`（62 §F.1：AI 產生的 alt 要標來源）。**nullable、不 backfill**
#   ——存量 alt 的來源是未知的，猜成 human 就是把未取證假設寫進資料（鐵律 19）。
# ③`orders.locale_snapshot`（訂單成立當下的顧客語言快照）。寫入者在 M3；
#   現在搭車加欄，避免 orders 表二次遷移。
#
# 🔴 本包原清單的另外三項**已由先前包落地，不在本遷移**（證據見 worklog）：
#   unavailable buckets＝inventory_levels 的四個子欄＋ledger 的對應 delta 欄；
#   冪等索引改型＝`uq_inventory_adjustment_groups_idem_key`（群組級）＋
#   `uq_inv_adjustments_group_level`（行級派生）；actor＝groups.staff_member_id。
class AddCacheStampsAndAuditColumns < ActiveRecord::Migration[8.1]
  def up
    # 冪等（本檔第一次跑就實測到的形態）：MySQL 的 DDL 不進交易，backfill 一失敗
    # 就留下「欄已加、版本未記」的半套狀態，重跑會撞 Duplicate column。
    add_column :products, :variants_updated_at, :datetime, if_not_exists: true,
      comment: "變體樹最後變動時刻（cache stamp；null＝立欄前未變動過）"
    add_column :products, :media_updated_at, :datetime, if_not_exists: true,
      comment: "媒體（含衍生尺寸與檔案層 alt）最後變動時刻（cache stamp）"
    add_column :products, :publications_updated_at, :datetime, if_not_exists: true,
      comment: "發布狀態最後變動時刻（cache stamp；寫入者隨第 12 包）"
    add_column :collections, :products_updated_at, :datetime, if_not_exists: true,
      comment: "成員集合最後變動時刻（cache stamp；14 §F1）"
    add_column :shops, :catalog_version, :bigint, if_not_exists: true, default: 1, null: false,
      comment: "目錄級版本（市場／價格表變動時 bump；寫入者隨第 32 包）"
    add_column :files, :alt_source, :string, if_not_exists: true, limit: 16,
      comment: "alt 的來源稽核（ai／human／imported；62 §F.1）。null＝立欄前的存量"
    add_column :orders, :locale_snapshot, :string, if_not_exists: true, limit: 35,
      comment: "訂單成立當下的顧客語言（BCP-47；寫入者在 M3）"

    # backfill：存量商品的三個 stamp 都以「最後一次整體更新」為誠實起點——
    # 全樹鎖下任何儲存都 bump updated_at，所以它是三者的上界。
    # 純 backfill UPDATE（小表、無鎖風險）；strong_migrations 看不進 execute
    # 的內容，一律要 safety_assured 明示。
    safety_assured do
      execute <<~SQL.squish
        UPDATE products
           SET variants_updated_at = updated_at,
               media_updated_at = updated_at,
               publications_updated_at = updated_at
      SQL
      execute "UPDATE collections SET products_updated_at = updated_at"
    end
  end

  def down
    remove_column :products, :variants_updated_at
    remove_column :products, :media_updated_at
    remove_column :products, :publications_updated_at
    remove_column :collections, :products_updated_at
    remove_column :shops, :catalog_version
    remove_column :files, :alt_source
    remove_column :orders, :locale_snapshot
  end
end
