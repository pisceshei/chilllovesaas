# frozen_string_literal: true

# 買家 session（G6 步 11；74 §7：365 天上限）。token 明文只出現在 set-cookie
# 瞬間；表存 sha256 digest（admin sessions 同紀律）。
class CustomerSession < ApplicationRecord
  acts_as_tenant :shop
  belongs_to :customer

  # @return [Array(CustomerSession, String)] [列, 明文 token]
  def self.issue!(shop:, customer:)
    token = SecureRandom.hex(32)
    row = create!(shop_id: shop.id, customer_id: customer.id,
                  token_digest: digest(token),
                  expires_at: Limits.fetch(:customer, :session_days).to_i.days.from_now)
    [ row, token ]
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token)

  # @return [CustomerSession, nil] 過期＝nil（不刪列——排查留痕，purge 隨清理 job）
  def self.authenticate(shop:, token:)
    return nil if token.blank?

    row = find_by(shop_id: shop.id, token_digest: digest(token))
    row if row && row.expires_at > Time.current
  end
end
