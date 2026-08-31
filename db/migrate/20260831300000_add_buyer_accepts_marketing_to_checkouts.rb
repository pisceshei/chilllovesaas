# frozen_string_literal: true

# G6-4（87 號 §3 #2）：結帳頁「Email me with news and offers」勾選的落庫欄。
# 欄名對齊 Shopify Order API 的 buyer_accepts_marketing（G6-6 契約對位）；
# 隨訂單成立傳導到 Order 的接線登記於 worklog Pending（本包只落 checkout 面）。
class AddBuyerAcceptsMarketingToCheckouts < ActiveRecord::Migration[8.1]
  def change
    add_column :checkouts, :buyer_accepts_marketing, :boolean, null: false, default: false,
               comment: "買家勾選行銷訂閱（87 §3；對位 Order API buyer_accepts_marketing）"
  end
end
