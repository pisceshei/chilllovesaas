# frozen_string_literal: true

# 實際包裹（G6-8 步 5；對位本尊 Fulfillment——ord-2 §1.1 官方句 "a Fulfillment is
# created by a merchant or third party to represent the ongoing or completed work
# of fulfillment."）。
#
# ①status 值域＝官方 FulfillmentStatus **現行 4 值去掉 3PL 專屬**：官方全集
#   CANCELLED/ERROR/FAILURE/SUCCESS（OPEN/PENDING 已 deprecated——ord-4 取證
#   2026-09-01；棄用理由文字官方頁未刊）。我方 v1 無 3PL ⇒ 只落 success/cancelled
#   （建立即 success；error/failure 是履約服務請求的失敗形，無路徑不落值）。
#   ⚠️ schema default "pending" 是 M0 遺產，生產路徑永遠顯式寫 success，
#   inclusion 不收 pending（防止有人靠 default 建列）。
# ②tracking：tracking_company（單值）＋tracking_numbers（json array——本尊
#   FulfillmentTrackingInput.numbers 為 [String!]，url 隨 numbers 同位對應；
#   v1 儲存 numbers 陣列＋單一 tracking_url 欄位不存在 ⇒ url 存 numbers 同 json？
#   否——v1 追蹤 URL 放 tracking_numbers 同層級太髒，見 ③）。
# ③🔴 v1 tracking url 的儲存裁定：tracking_numbers json 存
#   [{"number":"…","url":"…"}] 物件陣列（一次遷移就緒的形；官方 numbers/urls
#   兩平行陣列按位對應——ord-2 §2.4 逐字——物件陣列是等價且不會錯位的儲存形）。
# ④delivered：官方以 FulfillmentEvent（FulfillmentEventStatus.DELIVERED）表達，
#   不在 FulfillmentStatus（ord-4 取證）。v1 無 events 表 ⇒ delivered_at 欄承載
#  （寫入入口隨物流 webhook 線；v1 恆 NULL，誠實登記）。
class Fulfillment < ApplicationRecord
  STATUSES = %w[success cancelled].freeze

  acts_as_tenant :shop

  belongs_to :fulfillment_order
  has_one :order, through: :fulfillment_order

  validates :status, inclusion: { in: STATUSES }
end
