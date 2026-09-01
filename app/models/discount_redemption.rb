# frozen_string_literal: true

# 折扣兌換帳（G6 步 9a；17-F3.2）。
#
# once_per_customer 的唯一索引硬保證：insert 撞 uq＝已用過。
# customer_key＝customer_id（登入）或正規化 email 的 sha256（17-F3 坑：
# 先正規化再 hash——大小寫/空白繞不過）。
class DiscountRedemption < ApplicationRecord
  acts_as_tenant :shop
  belongs_to :discount

  # @param email [String]
  # @return [String] sha256 hex
  def self.email_key(email)
    Digest::SHA256.hexdigest(Customer.normalize_email(email).to_s)
  end
end
