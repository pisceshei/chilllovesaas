# frozen_string_literal: true

module Admin
  # 登入後主題預覽（包 30／D77；工作卡「登入後預覽（noindex，不觸發 67 §I L7）」）。
  #
  # ①這是什麼：staff session 內以 `ThemeEngine::PageRenderer` 渲染任一主題的前台頁。
  #   **不是**公開店面（那是包 33 的射程：帶前綴路由＋頁級快取＋robots 紀律）——
  #   本端點只給商家看主題長什麼樣，等價本尊 admin 的 theme preview。
  # ②🔴 noindex：`X-Robots-Tag: noindex, nofollow` 回應頭（頁面在登入牆後，
  #   雙保險；本尊預覽站全域 noindex 的對位——82 §20.4 控制組實測）。
  # ③可見性：渲染內的商品／系列直連走 `Storefront::Lookup`（specs/93 §C），
  #   draft／archived／未發布 ⇒ 404 template。🔴 預覽**不**繞可見性閘——
  #   與 shopifypreview.com 的「商家視角」語義（82 §20.4，publication 閘未執行）
  #   刻意不同：我方預覽所見＝買家將見（ours，登記 91 §3.48）。
  # ④資產：主題 assets 由 `asset` action 供給（同 staff 閘；路徑逃逸由
  #   FileSource 防線擋——spec E7）。
  class StorefrontPreviewController < BaseController
    include ThemeCsp # 編輯器 iframe 的主題預覽同樣要主題面 CSP
    # 🔴 E13（2026-09-04 編輯器預覽 computed 對表實錘）：`asset` 必須跳過 CSRF——Rails 的 cross-origin JavaScript 防護
    #   （`verify_same_origin_request`：GET、回應 media type 為 text/javascript、非 XHR ⇒ raise ⇒ 422；actionpack 8.1.3.1
    #   request_forgery_protection.rb `verify_same_origin_request`／`non_xhr_javascript_response?`）把編輯器預覽 iframe 的
    #   每個 `<script src>` 打成 422 ⇒ Ella 的 21 支主題 JS 一支都不載（dev log 逐字 "Security warning: an embedded <script>
    #   tag on another site requested protected JavaScript."），預覽只剩無 JS 的形（marquee／header-mobile／cart-drawer 全走樣）。
    #   與 Storefront::AssetsController 同紀律：純讀端點無狀態變更，CSRF 語義不適用；staff 閘（authorize）照舊。
    #   test 環境 forgery 預設關 ⇒ 規格 PV1 顯式開再打（同 storefront S10）。
    skip_forgery_protection only: :asset

    # GET /admin/store/preview/:theme_id/assets/*file
    def asset
      authorize Theme, :index?
      rel = params[:file].to_s
      # 同 Storefront::AssetsController：主題根**內**的 `assets/../…` 逃逸也要擋
      # （FileSource 只擋根外——包 33 後半 S7 抓到後兩個 asset 端點同輪封閉）。
      return head :not_found if rel.blank? || rel.include?("..") || rel.include?("\\")

      theme = Theme.find(params[:theme_id])
      source = ThemeEngine::Sources.resolve(theme)
      body = source&.read(File.join("assets", rel))
      return head :not_found if body.nil?

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      send_data body, type: Marcel::MimeType.for(name: params[:file].to_s), disposition: "inline"
    end

    # POST /admin/store/preview/:theme_id/draft_section（PR-7 即時預覽）
    # body: { path, section_id, entry }——以未儲存 entry 渲染單 section 片段。
    def draft_section
      authorize Theme, :index?
      theme = Theme.find(params[:theme_id])
      sid = params[:section_id].to_s
      entry = params[:entry].respond_to?(:to_unsafe_h) ? params[:entry].to_unsafe_h : params[:entry]
      return head :unprocessable_entity if sid.blank? || !entry.is_a?(Hash)

      hit = default_locale_hit
      result = ThemeEngine::PageRenderer.new(
        theme: theme, shop: Current.shop, publication: Publication.online_store!,
        design_mode: true, host: request.host,
        locale: hit&.locale_tag, web_presence: hit&.web_presence # E13：與 show 同一語言真相
      ).render(params[:path].presence || "/", params: { "section_id" => sid },
               draft_sections: { sid => entry })

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render html: result.html.html_safe, status: result.status, layout: false
    end

    # POST /admin/store/preview/:theme_id/draft_page（PR-11 改即見全面化；E9 改形）
    # body: { path, sections: {sid=>entry}, settings: {} }——把全部未儲存 draft（全帶 sections＋佈景設定）
    # **存成短效草稿並回 `{token}`**，前端以 `show?editor=1&draft=token` 重載 iframe。
    # 🔴 E9 根因（2026-09-03 使用者實測截圖）：原本回整頁 HTML、前端 `iframe.srcdoc` 換入——srcdoc 文件繼承
    #   admin 頁的嚴格 CSP（style-src 'self'／script-src nonce），主題 inline style／script 全被擋 ⇒ 改任何設定
    #   600ms 後預覽退化成無樣式。改成真實 URL 重載後，回應帶 ThemeCsp（主題面 CSP）與正確 base URL。
    # 草稿 cache key 以 shop＋theme 定界、TTL 短（DRAFT_TTL）；token 只在 staff 閘後可用。
    DRAFT_TTL = 20.minutes

    def draft_page
      authorize Theme, :index?
      theme = Theme.find(params[:theme_id])
      sections = params[:sections].respond_to?(:to_unsafe_h) ? params[:sections].to_unsafe_h : params[:sections]
      settings = params[:settings].respond_to?(:to_unsafe_h) ? params[:settings].to_unsafe_h : params[:settings]

      token = SecureRandom.urlsafe_base64(18)
      Rails.cache.write(draft_cache_key(theme, token),
                        { "sections" => sections.is_a?(Hash) ? sections : {},
                          "settings" => settings.is_a?(Hash) ? settings : nil },
                        expires_in: DRAFT_TTL)
      render json: { token: token }
    end

    # GET /admin/store/preview/:theme_id(/*path)
    def show
      authorize Theme, :index?
      theme = Theme.find(params[:theme_id])
      publication = Publication.online_store!
      cart = cookies.signed["_cl_buyer"].presence&.then do |token|
        Cart.includes(cart_line_items: { product_variant: :product })
            .find_by(shop_id: Current.shop.id, token: token)
      end
      design_mode = params[:editor] == "1"
      draft = design_mode ? draft_payload(theme, params[:draft]) : nil # E9：只在編輯器 iframe 套草稿
      hit = default_locale_hit
      result = ThemeEngine::PageRenderer.new(
        theme: theme, shop: Current.shop, publication: publication,
        design_mode: design_mode, host: request.host, # 步 16a：編輯器 iframe 開 design_mode
        locale: hit&.locale_tag, web_presence: hit&.web_presence, # E13：預覽以店的預設市場語言渲染（default_locale_hit）
        cart_json: cart && Storefront::CartSerializer.cart_json(cart)
      ).render("/#{params[:path]}", params: request.query_parameters.except("draft"),
               draft_sections: draft&.fetch("sections", nil), draft_settings: draft&.fetch("settings", nil))

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      # 包 33：?sections= 回 JSON（83 §12.3 真店＝application/json；單 section
      # 與整頁維持 text/html）。
      if result.content_type == :json
        render json: result.html, status: result.status
      else
        render html: result.html.html_safe, status: result.status, layout: false
      end
    rescue ThemeEngine::MissingSourceError => e
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render plain: e.message, status: :unprocessable_entity
    end

    private

    # E13（2026-09-04）：預覽頁以店的預設 (market, locale) 渲染——本尊編輯器的市場選擇器預設 "Store default"
    # （docs/research/100 §中 2）。原本 renderer 不帶 locale／web_presence ⇒ `<html lang="">`、`Shopify.locale = ""`、
    # `Shopify.country = ""`、平台字串走英文回退（computed 對表：skip link `body>a` 寬 134 vs 219），與公開店面
    # （Storefront::PagesController#render_page 帶 locale_hit）不一致，違反鐵律 22.1「兩者皆是」。單一真相＝
    # `Markets::PrefixIndex.default_hit`（根路徑 302 目標與無前綴 SRA 端點同一落點）。url_prefix 仍為空：預覽路徑在
    # /admin/store/preview/ 之下，前綴由橋的 cl:navigate 導航語義承接（D80 前綴裁定未定，不在本包）。
    def default_locale_hit
      Markets::PrefixIndex.default_hit(shop: Current.shop)
    end

    # 草稿鍵：租戶＋主題＋token——另一主題／另一店的 token 找不到就是找不到（fail-closed 為「不套草稿」）。
    def draft_cache_key(theme, token)
      "editor-draft/v1/#{Current.shop.id}/#{theme.id}/#{token}"
    end

    def draft_payload(theme, token)
      t = token.to_s
      return nil unless t.match?(/\A[\w-]{16,64}\z/)

      payload = Rails.cache.read(draft_cache_key(theme, t))
      payload.is_a?(Hash) ? payload : nil
    end
  end
end
