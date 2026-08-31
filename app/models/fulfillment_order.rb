# frozen_string_literal: true

# 履約工作單（G6-8 步 5；對位本尊 FulfillmentOrder——ord-2 §1.1 官方句
# "The FulfillmentOrder object represents either an item or a group of items in an
# Order that are expected to be fulfilled from the same location."）。
#
# ①這是什麼：按地點拆分的「待辦出貨工作」。本尊訂單一成立就有 FO（"Fulfillment
#   orders represent the work which is intended to be done in relation to an order."）
#   ⇒ 我方 CreateFromCheckout 同步物化＋migration 20260901010000 回填既有單。
# ②v1 形＝**每單一張 FO**（單地點；location＝priority 最高，同建單扣庫存的
#   level 選擇規則）。多地點拆單／MOVE／SPLIT／MERGE 隨多地點線。
# ③status 值域＝官方 FulfillmentOrderStatus 7 值全落（小寫儲存）；v1 生產路徑
#   只會產生 open/in_progress/on_hold/closed/cancelled——scheduled 需 fulfill_at
#   寫入入口（未做，enum 不出值）、incomplete 需 3PL 拒單形（未做）。
# ④request_status v1 恆 unsubmitted（無 3PL 履約服務；16 §F3.1 的 8 值隨 3PL 線）。
# ⑤跨功能影響：fulfillmentCreate 收 FO id（本尊形）；Order.displayFulfillmentStatus
#   從 FO/fulfillment 推導（Orders::FulfillmentStatus 唯一推導器）；出貨扣 committed
#  （訂單線獨佔——inventory/adjust.rb 檔頭明文）。
class FulfillmentOrder < ApplicationRecord
  STATUSES = %w[open in_progress on_hold scheduled closed cancelled incomplete].freeze
  REQUEST_STATUSES = %w[unsubmitted].freeze # 3PL 線擴（submitted/accepted/…）

  acts_as_tenant :shop

  belongs_to :order
  belongs_to :location
  has_many :fulfillments, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :request_status, inclusion: { in: REQUEST_STATUSES }
end
