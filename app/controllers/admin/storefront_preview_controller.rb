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

      result = ThemeEngine::PageRenderer.new(
        theme: theme, shop: Current.shop, publication: Publication.online_store!,
        design_mode: true, host: request.host
      ).render(params[:path].presence || "/", params: { "section_id" => sid },
               draft_sections: { sid => entry })

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render html: result.html.html_safe, status: result.status, layout: false
    end

    # POST /admin/store/preview/:theme_id/draft_page（PR-11 改即見全面化）
    # body: { path, sections: {sid=>entry}, settings: {} }——以全部未儲存
    # draft（全帶 sections＋佈景設定）渲染整頁 ⇒ 編輯器 iframe srcdoc 換入。
    # 佈景設定/結構操作/undo 三類變更共用此通道（fleet editor-live 軸①②③）。
    def draft_page
      authorize Theme, :index?
      theme = Theme.find(params[:theme_id])
      sections = params[:sections].respond_to?(:to_unsafe_h) ? params[:sections].to_unsafe_h : params[:sections]
      settings = params[:settings].respond_to?(:to_unsafe_h) ? params[:settings].to_unsafe_h : params[:settings]

      result = ThemeEngine::PageRenderer.new(
        theme: theme, shop: Current.shop, publication: Publication.online_store!,
        design_mode: true, host: request.host
      ).render(params[:path].presence || "/",
               draft_sections: sections.is_a?(Hash) ? sections : {},
               draft_settings: settings.is_a?(Hash) ? settings : nil)

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render html: result.html.html_safe, status: result.status, layout: false
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
      result = ThemeEngine::PageRenderer.new(
        theme: theme, shop: Current.shop, publication: publication,
        design_mode: params[:editor] == "1", host: request.host, # 步 16a：編輯器 iframe 開 design_mode
        cart_json: cart && Storefront::CartSerializer.cart_json(cart)
      ).render("/#{params[:path]}", params: request.query_parameters)

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
  end
end
