# frozen_string_literal: true

# G6 步 7（棄單挽回）：Email status 欄的資料基礎（本尊列表 Sent/Not sent 徽章；
# 89 §8 實測）。寫入者唯一＝Notifications::DeliverJob 寄出後回填。
class AddRecoveryEmailSentAtToCheckouts < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:checkouts, :recovery_email_sent_at)
      add_column :checkouts, :recovery_email_sent_at, :datetime,
                 comment: "挽回信寄出時間（NULL＝未寄；列表 Email status 徽章）"
    end
  end
end
