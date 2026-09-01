# frozen_string_literal: true

module Storefront
  # 公開店面 controller 基底（包 33 後半）。
  #
  # ①刻意**不**繼承 ApplicationController：那條鏈帶 staff session 恢復、Pundit、
  #   `allow_browser :modern`（買家瀏覽器不設門檻）——店面是匿名面，身分只有
  #   `_cl_buyer` 簽名 cookie（cart 家族）。
  # ②租戶恆由 host 解析（TenantResolver middleware 寫 `Current.shop`）：
  #   平台 host（無租戶）一律 404——店面在租戶 host 之外不存在。
  # ③🔴 市場只由 URL 決定（limits `i18n.locale_prefix.market_determined_by`）：
  #   本層不讀 GeoIP／cookie 推市場。
  class BaseController < ActionController::Base
    include ThemeCsp # 主題渲染面 CSP（Ella 修復 PR-1；concern 檔頭有完整理由）

    before_action :require_shop!
    before_action :require_storefront_password

    # PR-10：密碼閘（本尊 private mode——啟用時全站 302 → /password；
    # digest 綁密碼雜湊 ⇒ 改密碼即失效全部既有通行 cookie）。
    def require_storefront_password
      digest = current_shop&.storefront_password_digest
      return if digest.blank?
      return if cookies.signed[:cl_storefront_digest] == Digest::SHA256.hexdigest(digest)

      redirect_to "/password"
    end

    private

    def current_shop = Current.shop

    def require_shop!
      return if current_shop

      render plain: "找不到這間商店。", status: :not_found
    end

    # 已發布主題（單一 published role；缺 ⇒ 店面尚未開張）。
    def published_theme
      @published_theme ||= ActsAsTenant.with_tenant(current_shop) { Theme.published.first }
    end

    def require_published_theme!
      return if published_theme

      render plain: "商店尚未發布主題。", status: :service_unavailable
    end
  end
end
