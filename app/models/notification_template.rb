# frozen_string_literal: true

# 通知模板覆寫列（G6 步 6；89 §7.3；表＝M0 core schema 既有 notification_templates）。
#
# ①這是什麼：Settings › Notifications › Customer notifications 的模板編輯結果。
#   一列＝一店對一個（channel, key）的覆寫；**無列＝用平台預設**（Notifications::Catalog）。
# ②欄位語義（M0 形）：key＝模板識別（Catalog::KINDS）；channel v1 恆 "email"
#   （SMS 隨後續步驟）；name＝顯示名快照（Catalog title）；enabled 預留
#   （89 §2 V-236：本尊 2026 清單多數模板無停用 toggle，v1 不做開關）。
# ③revert to default（89 §4 官方兩目標之 Default）＝刪列；Previous 版本目標 ⚪ 後置。
# ④跨功能影響：Notifications::Renderer 的模板來源；notificationTemplate* GraphQL；
#   步 7 棄單挽回／步 8 顧客邀請都經同一 overlay 機制取模板。
class NotificationTemplate < ApplicationRecord
  CHANNELS = %w[email].freeze

  acts_as_tenant :shop

  validates :key, inclusion: { in: -> { Notifications::Catalog::KINDS } },
                  uniqueness: { scope: %i[shop_id channel] }
  validates :channel, inclusion: { in: CHANNELS }
  validates :name, presence: true
  validates :subject, presence: true, length: { maximum: 255 }
  validates :body, presence: true
end
