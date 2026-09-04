# frozen_string_literal: true

module Storefront
  # 公開店面 controller 基底（包 33 後半）。
  #
  # ①刻意**不**繼承 ApplicationController：那條鏈帶 staff session 恢復、Pundit、
  #   `allow_browser :modern`（買家瀏覽器不設門檻）——店面是匿名面，身分只有
  #   `_cl_buyer` 簽名 cookie（cart 家族）。
  # ②租戶恆由 host 解析（TenantResolver middleware 寫 `Current.shop`）：
  #   平台 host（無租戶）一律 404——店面在租戶 host 之外不存在。
  # ③市場兩層來源（limits `i18n.locale_prefix.market_determined_by: url_then_buyer_selection`；D80 2026-09-04）：
  #   URL 前綴命中的 presence 決定 (market, locale)；共用主網域上沒有自己 presence 的市場由買家選國寫下的
  #   `localization` cookie（國碼）覆寫——本尊 POST /localization country_code=US ⇒ `Set-Cookie: localization=US`，
  #   之後同 URL `Shopify.country = "US"`（external-facts §G23）。語言仍只由 URL 決定；本層不讀 GeoIP。
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

    # PR-12：渲染用主題＝預覽釘選優先，否則已發布（83 §12.3 sticky 對位）。
    def current_theme
      return @current_theme if defined?(@current_theme)

      @current_theme = resolve_preview_theme || published_theme
    end

    def preview_theme_active?
      current_theme.present? && current_theme != published_theme
    end

    def require_published_theme!
      # PR-12：釘住預覽主題時放行（本尊可在未發布店預覽主題）
      return if current_theme

      render plain: "商店尚未發布主題。", status: :service_unavailable
    end

    # 佈景主題預覽釘選（Ella 修復 PR-12）：`?preview_theme_id=` 帶一次 ⇒ 簽名
    # cookie 釘住，之後**不帶參數的請求也繼續渲染預覽主題**（本尊 sticky cookie
    # 行為，83 §12.3 live 實測 2026-08-31）；帶正式主題 id 或無效 id ⇒ 解除
    # （同節「復位法＝帶一次正式主題 id」）。跨租戶 id 經 with_tenant 查詢天然
    # 落空 ⇒ 視同無效解除。robots 已 Disallow `/*?*preview_theme_id=`（62 §366）。
    PREVIEW_COOKIE = "_cl_preview_theme"

    def resolve_preview_theme
      raw = params[:preview_theme_id].presence
      if raw
        theme = ActsAsTenant.with_tenant(current_shop) { Theme.find_by(id: raw.to_i) }
        if theme.nil? || theme.role == "published"
          cookies.delete(PREVIEW_COOKIE)
          return nil
        end
        cookies.signed[PREVIEW_COOKIE] = { value: theme.id, httponly: true }
        return theme
      end

      pinned = cookies.signed[PREVIEW_COOKIE].presence
      return nil if pinned.nil?

      theme = ActsAsTenant.with_tenant(current_shop) { Theme.find_by(id: pinned) }
      if theme.nil? || theme.role == "published"
        cookies.delete(PREVIEW_COOKIE) # 釘的主題已被刪／已轉正 ⇒ 解除
        return nil
      end
      theme
    end
    # E12：SRA 端點（recommendations／search suggest／cart sections）與整頁一樣**語言只由 URL 前綴決定**——先前三支
    # renderer 一律 `locale: nil` ⇒ 段以英文渲染（hoko.vip 商品頁「Related products」卡片按鈕「售罄」／「加入购物车」，我方
    # 「Sold out」／「Add to cart」，computed 對表按鈕寬 32／80 vs 74／99）。
    # D80：命中後套買家選國（cookie）覆寫共用市場；同一段同一請求只解析一次。
    def locale_hit(first_segment = params[:locale_prefix])
      seg = first_segment.to_s
      return nil if seg.blank?

      @locale_hits ||= {}
      return @locale_hits[seg] if @locale_hits.key?(seg)

      hit = Markets::PrefixIndex.resolve(shop: current_shop, domain: current_domain, first_segment: seg)
      @locale_hits[seg] = apply_buyer_country(hit)
    end

    # E13（2026-09-04）：無前綴請求退回店的預設 (market, locale)（Markets::PrefixIndex.default_hit）——根路徑、無前綴頁面、
    # 編輯器預覽內主題 JS 打的無前綴 SRA URL 三者同一落點；D80 起再套買家選國 cookie。帶前綴者仍只由前綴決定語言。
    def default_hit
      return @default_hit if defined?(@default_hit)

      @default_hit = apply_buyer_country(Markets::PrefixIndex.default_hit(shop: current_shop))
    end

    # 前綴命中優先；無前綴 ⇒ 店預設（E13）。
    def effective_hit
      locale_hit || default_hit
    end

    # 買家選國 cookie（本尊 cookie 名 `localization`，值＝ISO 3166-1 alpha-2；§G23）。髒值一律當沒有。
    LOCALIZATION_COOKIE = "localization"

    def buyer_country_code
      return @buyer_country_code if defined?(@buyer_country_code)

      raw = cookies[LOCALIZATION_COOKIE].to_s.strip.upcase
      @buyer_country_code = raw.match?(MarketRegion::COUNTRY_CODE_FORMAT) ? raw : nil
    end

    def apply_buyer_country(hit)
      return hit if hit.nil? || buyer_country_code.nil?

      Markets::PrefixIndex.with_buyer_country(hit, shop: current_shop, domain: current_domain,
                                                   country_code: buyer_country_code)
    end

    def current_domain
      @current_domain ||= ActsAsTenant.with_tenant(current_shop) do
        Domain.find_by(host: request.host.to_s.downcase) || Domain.primary.first
      end
    end
  end
end
