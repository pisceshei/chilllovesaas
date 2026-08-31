# frozen_string_literal: true

# G6 步 6（通知基座；89 號 teardown）：shops.sender_email——寄件人（89 §6：
# 官方語義＝顧客收到自動通知信的 From 位址；NULL＝未設定 ⇒ mailer 落預設 no-reply）。
#
# 🔴 notification_templates **不在本檔建**：M0 core schema（20260811000000）已建
#   （key／name／channel／subject／body／enabled；uq [shop_id, channel, key]）。
#   步 6 是它的第一個消費者——採用 M0 形，不建平行表（本檔首版曾帶一個
#   table_exists? 守衛的 create_table，被 M0 表靜默跳過＝守衛救了一次撞名；
#   dead code 已移除，worklog 記）。
class CreateNotificationTemplates < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:shops, :sender_email)
      add_column :shops, :sender_email, :string, limit: 320,
                 comment: "通知信 From 位址（89 §6；NULL＝未設定走平台預設）"
    end
  end
end
