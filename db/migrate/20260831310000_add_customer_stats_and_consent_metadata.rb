# frozen_string_literal: true

# G6-7 顧客線地基（checkout 欄位資料對接）：
# ①customers.last_order_at——16 §F6.1 統計欄三件套（amount_spent/orders_count/
#   last_order_at）的缺欄；訂單成立增量維護、列表排序鍵「最新訂單日期」用它。
# ②email 同意的兩個中繼欄——08-customers §C.4 要求 consent 記錄
#   (state, optInLevel, consentUpdatedAt, source)；完整 append-only
#   customer_marketing_consents 事件表與六值狀態機屬顧客模組全量包（worklog 登記），
#   本包先落「最後一次變更的時間戳＋來源」讓 cd-consent 卡（74 §4）有資料可顯示。
# ③orders.buyer_accepts_marketing——checkout 同名欄的訂單面快照
#   （g6-4 worklog Pending 明列的傳導義務；對位 Order API buyer_accepts_marketing）。
class AddCustomerStatsAndConsentMetadata < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :last_order_at, :datetime,
               comment: "最新訂單時間（16 §F6.1 統計欄；訂單成立增量維護）"
    add_column :customers, :email_marketing_consent_updated_at, :datetime,
               comment: "email 同意最後變更時間（08 §C.4 consentUpdatedAt）"
    add_column :customers, :email_marketing_consent_source, :string, limit: 32,
               comment: "email 同意最後變更來源（08 §C.4 source；如 checkout）"
    add_column :orders, :buyer_accepts_marketing, :boolean, null: false, default: false,
               comment: "成單當下的行銷勾選快照（checkout 同名欄傳導；對位 Order API）"
  end
end
