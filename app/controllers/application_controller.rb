# 所有 browser controller 共用的安全、session resume 與 Pundit 邊界。
#
# 每個 request 會嘗試從加密 cookie 恢復可撤銷的 DB session；不直接信任
# client 傳來的 staff/shop 身分。見 docs/specs/11 §1、docs/specs/12 F2/F4。
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  protect_from_forgery with: :exception

  before_action :resume_admin_session

  # admin shell 只支援具備現代 Web/CSS 能力的 browser。
  allow_browser versions: :modern

  rescue_from Pundit::NotAuthorizedError, with: :handle_not_authorized

  # 取得 TenantResolver 為目前 request 選定的商店。
  #
  # @return [Shop, nil] 目前 request 的商店；平台 host 為 nil
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F1
  def current_shop
    Current.shop
  end
  helper_method :current_shop

  # 取得目前通過 DB session 驗證的管理員。
  #
  # @return [StaffMember, nil] 目前 request 的 staff；未登入為 nil
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F2
  def current_staff
    Current.staff
  end
  helper_method :current_staff

  # 取得集中設定的平台品牌名稱。
  #
  # @return [String] 平台顯示名稱
  # @note 副作用：無；只讀取 `config/brand.yml`。
  # @see HANDOFF.md D3
  def brand_name
    Rails.configuration.x.brand.name
  end
  helper_method :brand_name

  private

  # Pundit 的授權主體就是經 DB session 恢復的目前 staff；不提供
  # `current_user` fallback，避免另一套身分來源。見 docs/specs/12 F2/F3。
  def pundit_user
    Current.staff
  end

  # 從加密 cookie 恢復可撤銷的 DB session，並施加**第一道租戶閘**。
  #
  # 🔴 兩層是 AND，不是 OR（`docs/dev/m1-identity-tenancy.md`）：
  #   第一層（這裡）＝**這個人能不能進這間店**——`Current#can_access_shop?`，fail-closed。
  #   第二層（Pundit policy／resolver 的 `authorize_*`）＝**進來之後能做什麼**。
  #
  # 在本方法接上這道閘之前，第一層**方法存在但零呼叫點**（D8 明文要求的安全網從未接線）。
  # 後果：`sessions` 與 `staff_members` 都已升為組織層、不帶 `shop_id`，
  # 而 `Session.authenticate` 只比對 token digest、`StaffMember#can?` 第一行就
  # `return true if owner?` ⇒ **A 店的 owner 在 B 店的 host 登入即可讀寫 B 店資料**。
  # 對抗式複查（2026-08-24）在庫存讀取面抓到它，但曝險面是整個 admin：
  # `Admin::BaseController` 與 GraphQL controller 都繼承本類別，所以閘放這裡是**一處覆蓋全部**。
  #
  # 🔴 為什麼不改 `can?` 的 owner 短路：那是**第二層**，而 owner 在自己有指派的店裡
  # 本來就該無所不能。把租戶歸屬塞進第二層會讓兩層語義混在一起；
  # 缺的是第一層，就補第一層。
  def resume_admin_session
    return unless Current.shop

    record = ::Session.authenticate(session[:admin_session_token])
    unless record
      session.delete(:admin_session_token)
      return
    end

    Current.admin_session = record
    Current.staff = record.staff_member

    # fail-closed：無法明確證明這個 staff 屬於本店，就當作沒登入。
    # 不是 403 而是「未登入」——回 403 等於告訴對方「這間店存在、你只是沒權限」，
    # 那是一個租戶枚舉側通道。
    unless Current.can_access_shop?(Current.shop.id)
      Current.admin_session = nil
      Current.staff = nil
      session.delete(:admin_session_token)
      return
    end

    record.record_activity!
  end

  def authenticate_staff!
    handle_unauthenticated unless Current.staff
  end

  def require_shop!
    return if Current.shop

    render plain: "找不到這間商店。", status: :not_found
  end

  def handle_unauthenticated
    redirect_to login_path, alert: SessionsController::AUTHENTICATION_ERROR
  end

  def handle_not_authorized
    render plain: "沒有權限執行此操作。", status: :forbidden
  end
end
