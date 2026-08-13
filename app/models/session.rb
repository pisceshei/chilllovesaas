require "digest"
require "securerandom"

# 支撐一個加密 admin browser session 的可撤銷 DB record。
#
# browser cookie 只保存 raw opaque token；資料庫只保存其 SHA-256 digest，
# 並在每次 request 驗證 expiry、revocation 與 staff status。見
# docs/specs/11 §1、docs/specs/12 F2。
class Session < ApplicationRecord
  TOKEN_BYTES = 32
  LIFETIME = 30.days
  ACTIVITY_WRITE_INTERVAL = 5.minutes

  acts_as_tenant :shop

  belongs_to :staff_member

  validates :token_digest, :last_active_at, :expires_at, presence: true
  validate :staff_member_belongs_to_shop

  class << self
    # 建立可撤銷 session，並回傳只交付一次的 raw token。
    #
    # raw token 不會指派給任何 Active Record attribute，只持久化 SHA-256
    # digest。
    #
    # @param staff_member [StaffMember] 已驗證的 staff account
    # @param request [ActionDispatch::Request] 來源 request metadata
    # @param expires_in [ActiveSupport::Duration] session 有效期
    # @return [Array(Session, String)] session record 與 raw cookie token
    # @note 副作用：新增一筆 tenant-scoped sessions 資料列；不持久化 raw token。
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F2
    def issue!(staff_member:, request:, expires_in: LIFETIME)
      raw_token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
      now = Time.current
      record = create!(
        shop: staff_member.shop,
        staff_member: staff_member,
        token_digest: digest(raw_token),
        ip_address: request.remote_ip,
        user_agent: request.user_agent.to_s.first(1024),
        last_active_at: now,
        expires_at: now + expires_in
      )

      [ record, raw_token ]
    end

    # 將 cookie token 解析成目前可用的 tenant-scoped session。
    #
    # @param raw_token [String, nil] 加密 cookie 內的 opaque token
    # @return [Session, nil] 可用 session；缺少、撤銷、過期或跨店時為 nil
    # @note 副作用：執行 tenant-scoped Session/StaffMember SELECT，不寫入資料。
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F2, F4
    def authenticate(raw_token)
      return if raw_token.blank?

      record = includes(:staff_member).find_by(token_digest: digest(raw_token))
      record if record&.usable?
    end

    # 計算 raw token 對應、不可逆的 database lookup value。
    #
    # @param raw_token [String] opaque random token
    # @return [String] 小寫 SHA-256 hex digest
    # @note 副作用：無。
    # @see docs/specs/11-production-baseline.md §1
    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end

  # 判斷 revocation、expiry 與 staff status 是否允許使用此 session。
  #
  # @return [Boolean] session 目前有效時回傳 true
  # @note 副作用：無；若 staff association 尚未載入，Active Record 可能執行 SELECT。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F2
  def usable?
    revoked_at.nil? && expires_at.future? && staff_member.active_for_authentication?
  end

  # 立即撤銷此 browser session。
  #
  # @return [Boolean] record 是否成功持久化
  # @note 副作用：更新 `sessions.revoked_at`；後續 request 立刻失效。
  # @see docs/specs/11-production-baseline.md §1
  def revoke!
    update!(revoked_at: Time.current)
  end

  # 記錄近期活動，但不在每個 request 都寫入資料庫。
  #
  # 五分鐘 coalescing 避免 admin navigation 讓 sessions 表形成 write hotspot，
  # 同時保留足夠的安全 metadata。
  #
  # @return [Boolean, nil] update 結果；尚未到寫入時間時為 nil
  # @note 副作用：距上次活動逾五分鐘時直接更新 `last_active_at`。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F2
  def record_activity!
    return if last_active_at && last_active_at > ACTIVITY_WRITE_INTERVAL.ago

    update_column(:last_active_at, Time.current)
  end

  private

  def staff_member_belongs_to_shop
    return if staff_member.nil? || staff_member.shop_id == shop_id

    errors.add(:staff_member, "必須屬於同一間商店")
  end
end
