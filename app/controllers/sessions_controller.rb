require "securerandom"

# 以可撤銷 DB session 實作 staff 登入與登出。
#
# 未知帳號也執行 dummy bcrypt，所有登入失敗使用相同繁中訊息，避免帳號
# 枚舉與 timing disclosure。見 docs/specs/11 §1、docs/specs/12 F2。
class SessionsController < ApplicationController
  AUTHENTICATION_ERROR = "帳號或密碼錯誤。"
  DUMMY_PASSWORD_DIGEST = BCrypt::Password.create(
    SecureRandom.hex(32),
    cost: Rails.env.test? ? BCrypt::Engine::MIN_COST : 12
  ).to_s.freeze

  before_action :require_shop!
  before_action :authenticate_staff!, only: :destroy

  # 顯示目前租戶的 staff 登入頁。
  #
  # @note 副作用：已登入時回應 redirect，否則 render view。
  # @return [void]
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F2
  def new
    redirect_to admin_root_path if Current.staff
  end

  # 驗證帳密並輪替 Rails cookie session 與 DB session。
  #
  # 未知使用者仍會執行一次 bcrypt 比對，降低帳號 timing disclosure。
  #
  # @note 副作用：成功時 `reset_session`、新增 sessions 資料列並 redirect；
  #   失敗時只 render 統一錯誤，不建立 session。
  # @return [void]
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F2
  def create
    staff = StaffMember.find_by(email: params[:email].to_s.strip.downcase)
    authenticated_staff = authenticate_candidate(staff, params[:password].to_s)

    if authenticated_staff && permitted_for_current_shop?(authenticated_staff)
      reset_session
      _record, raw_token = ::Session.issue!(staff_member: authenticated_staff, request: request)
      session[:admin_session_token] = raw_token
      redirect_to admin_root_path
    else
      flash.now[:alert] = AUTHENTICATION_ERROR
      render :new, status: :unprocessable_content
    end
  end

  # 撤銷目前 DB session 並清除加密 cookie。
  #
  # @note 副作用：更新 `sessions.revoked_at`、`reset_session` 並 redirect。
  # @return [void]
  # @see docs/specs/11-production-baseline.md §1
  def destroy
    Current.admin_session&.revoke!
    reset_session
    redirect_to login_path
  end

  private

  # 這個 staff 有沒有**本店**的指派。
  #
  # 🔴 `StaffMember.find_by(email:)` 是**全平台**查的（email 已改為平台級唯一，D8），
  # 所以密碼對了只證明「這個人是誰」，不證明「這個人屬於這間店」。
  # 少了這一句，A 店的人在 B 店 host 輸入自己的帳密就能拿到 B 店的 session。
  #
  # 失敗時走**與帳密錯誤完全相同**的錯誤訊息（`AUTHENTICATION_ERROR`）：
  # 若另給一句「你不屬於這間店」，就等於用登入表單洩漏「這個 email 在平台上存在」，
  # 以及「這間店存在」——兩個都是枚舉側通道。
  #
  # 這是第一道閘的登入側；session 恢復側在 `ApplicationController#resume_admin_session`。
  # 兩邊都要有：只擋登入，既有的 cookie 仍能用；只擋恢復，登入會「成功」然後畫面像沒登入。
  def permitted_for_current_shop?(staff)
    return false if Current.shop.nil?

    UserStoreAssignment.exists?(staff_member_id: staff.id, shop_id: Current.shop.id)
  end

  def authenticate_candidate(staff, password)
    # invited staff 沒有 password_digest；仍以 dummy digest 做一次同成本比對，
    # 避免把「帳號存在但尚未啟用」變成 timing side channel。見 docs/specs/12 F2。
    digest = staff&.password_digest.presence || DUMMY_PASSWORD_DIGEST
    authenticated = BCrypt::Password.new(digest).is_password?(password)

    staff if authenticated && staff.active_for_authentication?
  end
end
