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
    # GET /admin/store/preview/:theme_id/assets/*file
    def asset
      authorize Theme, :index?
      theme = Theme.find(params[:theme_id])
      source = ThemeEngine::Sources.resolve(theme)
      body = source&.read(File.join("assets", params[:file].to_s))
      return head :not_found if body.nil?

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      send_data body, type: Marcel::MimeType.for(name: params[:file].to_s), disposition: "inline"
    end

    # GET /admin/store/preview/:theme_id(/*path)
    def show
      authorize Theme, :index?
      theme = Theme.find(params[:theme_id])
      publication = Publication.online_store!
      result = ThemeEngine::PageRenderer.new(
        theme: theme, shop: Current.shop, publication: publication,
        design_mode: false, host: request.host
      ).render("/#{params[:path]}", params: request.query_parameters)

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render html: result.html.html_safe, status: result.status, layout: false
    rescue ThemeEngine::MissingSourceError => e
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render plain: e.message, status: :unprocessable_entity
    end
  end
end
