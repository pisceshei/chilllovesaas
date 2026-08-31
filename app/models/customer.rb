# frozen_string_literal: true

# 顧客主檔（16 §F6／08-customers 章；表自 M0 就在 schema，G6-7 起有寫入者）。
#
# ①這是什麼：per-shop 顧客 profile。身分鍵＝email（08 §C.1：每店唯一；
#   `uq_customers_email` DB 兜底）；phone 表上是非 unique 索引——08 §C.1 要求
#   unique，補索引屬顧客模組全量包（worklog 登記），本包不動既有資料面。
# ②統計欄（orders_count/total_spent_cents/last_order_at）＝訂單域 rollup 餵入
#   （08 §E.2；鐵律 7：列表欄、詳情 KPI、報表同源讀這三欄）；寫入端唯一＝
#   `Customers::UpsertFromCheckout`（訂單成立交易內增量）＋nightly 對帳（待排程包）。
# ③email 正規化（16 §F6 ⚠️坑：guest 大小寫不同重複下單）＝lowercase+strip，
#   在 before_validation 收口——所有寫入路徑（含未來 customerCreate）共用。
# ④行銷同意：boolean 快取欄＋最後變更 (updated_at, source) 中繼欄；六值狀態機
#   與 append-only 事件表（08 §B.2/§C.4）隨顧客模組全量包。
class Customer < ApplicationRecord
  acts_as_tenant :shop

  has_many :customer_addresses, dependent: :delete_all
  has_many :orders

  validates :email, length: { maximum: 320 },
                    uniqueness: { scope: :shop_id, case_sensitive: false }, allow_nil: true
  validates :state, inclusion: { in: %w[enabled disabled invited declined] }

  before_validation :normalize_email

  # 顯示名（列表「顧客名稱」欄；74 §1 恆第一欄）：姓名缺項時回落 email。
  # @return [String]
  def display_name
    name = [ first_name, last_name ].compact_blank.join(" ")
    name.presence || email.to_s
  end

  # 預設地址（列表「地點」欄與詳情 cd-address 卡的來源）。
  # @return [CustomerAddress, nil]
  def default_address
    customer_addresses.detect(&:default_address) || customer_addresses.first
  end

  # email 正規化的唯一定義點（16 §F6 ⚠️坑）；查詢端用同一把。
  # @param raw [String, nil]
  # @return [String, nil]
  def self.normalize_email(raw)
    value = raw.to_s.strip.downcase
    value.presence
  end

  private

  def normalize_email
    self.email = self.class.normalize_email(email)
  end
end
