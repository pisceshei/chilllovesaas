# frozen_string_literal: true

# 登入驗證碼（G6 步 11；74 §7 六位數字形）。
#
# ①code 只存 digest；expires＝limits customer.otp_expiry_minutes；
#   attempts ≥ limits customer.otp_max_attempts ⇒ 作廢（防爆破——6 位碼空間小，
#   不限次數＝可枚舉）。
# ②重發節流：同 email 最新一筆 created_at 距今 < otp_resend_cooldown_s ⇒ 拒發。
class CustomerOtp < ApplicationRecord
  acts_as_tenant :shop

  # @return [Array(CustomerOtp, String)] [列, 明文六位碼]
  def self.issue!(shop:, email:)
    code = format("%06d", SecureRandom.random_number(1_000_000))
    row = create!(shop_id: shop.id, email:,
                  code_digest: Digest::SHA256.hexdigest(code),
                  expires_at: Limits.fetch(:customer, :otp_expiry_minutes).to_i.minutes.from_now)
    [ row, code ]
  end

  # @return [Symbol] :ok / :invalid / :expired / :too_many_attempts
  def self.verify!(shop:, email:, code:)
    row = where(shop_id: shop.id, email:, consumed_at: nil).order(created_at: :desc).first
    return :invalid if row.nil?
    return :expired if row.expires_at <= Time.current
    return :too_many_attempts if row.attempts >= Limits.fetch(:customer, :otp_max_attempts).to_i

    if ActiveSupport::SecurityUtils.secure_compare(row.code_digest, Digest::SHA256.hexdigest(code.to_s))
      row.update!(consumed_at: Time.current)
      :ok
    else
      row.increment!(:attempts)
      :invalid
    end
  end

  def self.cooldown_active?(shop:, email:)
    latest = where(shop_id: shop.id, email:).order(created_at: :desc).first
    latest && latest.created_at > Limits.fetch(:customer, :otp_resend_cooldown_s).to_i.seconds.ago
  end
end
