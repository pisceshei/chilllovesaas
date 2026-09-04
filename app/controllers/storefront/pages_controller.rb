# frozen_string_literal: true

module Storefront
  # 公開店面頁面（包 33 後半；六步方案步 2）。
  #
  # ①路由紀律（67 §F.1(b)(c)；limits `i18n.locale_prefix.*`）：
  #   - 根路徑與無前綴路徑 ⇒ **302** 到預設 (market, locale) 前綴、保留路徑與 query
  #     （root_redirect_status: 302——不是 301，預設市場會變）。
  #   - 第一段長得像前綴（FORMAT）⇒ 查 `Markets::PrefixIndex`；未命中 ⇒ 🔴 404
  #     （unknown_prefix_status／unopened_prefix_status——§A.5(c) 情形 1/3/4 全走這裡）。
  # ②頁級快取（63 §D.3）＝`Storefront::PageCache`；🔴 渲染快取頁不帶 cart_json
  #   （14 §F1-4 個人化不進頁快取——買家 cart 態由 /cart.js 端點取）。
  # ③🔴 B13：robots 全站 Disallow ＋ 頁面 X-Robots-Tag noindex——SEO 面（hreflang／
  #   sitemap／開放索引）是步 4（包 35）的射程，開放時兩者一起摘除。
  class PagesController < BaseController
    before_action :require_published_theme!, except: %i[robots root] # root 只重導，不需主題

    # query 白名單（進快取 key 的維度；未列參數不參與 key＝同一快取頁）。
    # view＝?view= 替代模板（步 12）——不進 key 會讓替代模板頁污染預設頁快取。
    # type＝搜尋頁型別過濾（步 12b）——不進 key 會讓 type=page 污染全型搜尋頁。
    CACHE_PARAMS = %w[variant page q sort_by view type].freeze

    # GET /robots.txt（包 35 起開放；62 §D.2 預設 disallow 集合＋平台保底 Sitemap 行）。
    # 主題 robots.txt.liquid 覆寫層（§D.1 本尊形態）與 AI 爬蟲三組開關（§D.3）待
    # 後續包（登記）；B13 的全站 Disallow 已隨本包撤除。
    def robots
      lines = [ "User-agent: *" ]
      %w[/cart /checkout /account /search].each { |path| lines << "Disallow: #{path}" }
      lines << "Disallow: /*?*filter."
      lines << "Disallow: /*?*sort_by="
      lines << "Disallow: /*?*preview_theme_id="
      lines << "Sitemap: https://#{request.host}/sitemap.xml"
      render plain: lines.join("\n") + "\n", content_type: "text/plain"
    end

    # GET /（＝無前綴根路徑）
    def root
      redirect_to_default_prefix("/")
    end

    # GET /*path
    def show
      first, rest = split_path
      unless first.match?(prefix_shape)
        return redirect_to_default_prefix(request.path)
      end

      hit = Markets::PrefixIndex.resolve(shop: current_shop, domain: current_domain,
                                         first_segment: first)
      return head :not_found if hit.nil?

      # G6 打磨包：/cart 是個人化頁——**繞過頁快取**、以買家 cookie 的真車渲染
      # （14 §F1-4「個人化不進頁快取」＝不快取本頁，而不是快取一台空車）。
      # E12：Section Rendering API 在**任何頁面**（官方 ajax/section-rendering，取證 2026-09-04："Sections rendered in response to
      # the section_id query parameter are returned directly as HTML and, like sections, this parameter can be used to render a
      # section in the context of any page."；"If the requested section ID doesn't exist on the theme, then the server responds
      # with a 404 status."）。先前只有 search/suggest、recommendations、cart POST 走這條，`/search?section_id=` 回整頁 ⇒ Ella 的
      # recently-viewed JS 拿到整頁 HTML 而顯示警告區塊（hoko 該段 display:none）。繞過頁快取（cart drawer 段含個人化）。
      if section_rendering_request?
        response.headers["Cache-Control"] = "no-store"
        payload = render_page(hit, rest, cart_json: buyer_cart_json, extra: section_rendering_params)
        return head :not_found if payload["status"] == 404
        return head :bad_request if payload["status"] == 400
        return render(json: payload["html"], status: payload["status"]) if payload["content_type"] == :json

        return render html: payload["html"].html_safe, status: payload["status"], layout: false
      end

      if rest == "/cart"
        response.headers["Cache-Control"] = "no-store"
        payload = render_page(hit, rest, cart_json: buyer_cart_json)
      elsif preview_theme_active?
        # PR-12：🔴 預覽不進頁快取（不讀不寫）——快取鍵含 theme 擋得住互汙，
        # 但預覽的意義是看未儲存中的主題現狀，命中舊 entry 即假象。
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Robots-Tag"] = "noindex, nofollow"
        payload = render_page(hit, rest, cart_json: rest == "/cart" ? buyer_cart_json : nil)
      elsif rest == "/search"
        # 步 12b：搜尋頁**不進頁快取**——q 鍵空間無界（S6b 同型防灌爆），
        # 且結果隨庫存/發布即時變。robots 已 Disallow /search（既有）。
        payload = render_page(hit, rest)
      else
        payload = PageCache.fetch(
          shop: current_shop, theme: published_theme, market: hit.market,
          locale_tag: hit.locale_tag, path: rest, params: cache_params
        ) { render_page(hit, rest) }
      end

      # 301 引擎（包 36）：掛在 404 之前、活頁面先贏（渲染 200 就不查表）。
      # 查表用無前綴正規路徑，命中後**保留前綴** 301（/en-hk/products/舊 ⇒ /en-hk/products/新）。
      if payload["status"] == 404
        redirect = ActsAsTenant.with_tenant(current_shop) do
          RedirectResolver.resolve(shop: current_shop, path: rest)
        end
        if redirect
          return head :gone if redirect.status_code == 410

          prefix = Markets::UrlPrefix.for(hit.web_presence, hit.locale_tag)
          target = "#{prefix}#{redirect.to_path}"
          target += "?#{request.query_string}" if request.query_string.present?
          return redirect_to target, status: redirect.status_code, allow_other_host: false
        end
      end

      # B13 的 X-Robots-Tag noindex 已隨包 35（SEO 開放）摘除；UNLISTED 的 noindex
      # 由 Seo::HeadTags 以 meta robots 承接（limits `product.unlisted_meta_robots`）。
      # PR-12：預覽列——僅整頁 HTML（片段/JSON 不注）；自有樣式（鐵律 9：
      # 功能對位本尊 preview bar，視覺用我方設計語言）。
      if preview_theme_active? && payload["html"].to_s.include?("</body>")
        payload["html"] = payload["html"].sub("</body>", "#{preview_bar_html}</body>")
      end
      render html: payload["html"].html_safe, status: payload["status"], layout: false
    end

    private

    # 前綴形＝Markets::UrlPrefix::SEGMENT（同一來源，不抄第二份）。
    # 長得像前綴但查無 ⇒ 404（上面 show）；不像前綴（products 等一般路徑）⇒ 302 補預設前綴。
    def prefix_shape
      /\A#{Markets::UrlPrefix::SEGMENT.source}\z/
    end

    def split_path
      segments = request.path.delete_prefix("/").split("/", 2)
      [ segments[0].to_s.downcase, "/#{segments[1]}".chomp("/").presence || "/" ]
    end

    def redirect_to_default_prefix(path)
      prefix = default_prefix
      return head :not_found if prefix.nil?

      target = path == "/" ? "#{prefix}/" : "#{prefix}#{path}"
      target += "?#{request.query_string}" if request.query_string.present?
      redirect_to target, status: Limits.fetch(:i18n, :locale_prefix, :root_redirect_status),
                          allow_other_host: false
    end

    # 預設落點＝primary market 的 presence × 其預設 locale（67 §F.1(b) 根路徑處置）；E13 起單一真相在
    # `Markets::PrefixIndex.default_hit`（編輯器預覽與無前綴 SRA 端點同一落點）。
    def default_prefix
      hit = Markets::PrefixIndex.default_hit(shop: current_shop) or return nil
      Markets::UrlPrefix.for(hit.web_presence, hit.locale_tag)
    rescue Markets::UrlPrefix::Error
      nil
    end

    def cache_params
      base = params.permit(*CACHE_PARAMS).to_h
      qs = facets_query_string
      base = base.merge("_facets_qs" => qs) if qs.present?
      base
    end

    # PR-20：filter.* 參數正規化子串——🔴 從 query string 解析（Rack parse_query
    # 保留重複鍵＝多值 OR；Rails params 對重複裸鍵 last-wins 丟值）＋排序重建
    # （頁快取鍵穩定：同組過濾不同順序＝同 key）。sort_by 併入（URL 重建保留）。
    def facets_query_string
      pairs = Rack::Utils.parse_query(request.query_string.to_s)
                         .flat_map { |k, v| Array(v).map { |one| [ k, one.to_s ] } }
                         .select { |k, _| %w[sort_by q type].include?(k) || k.start_with?("filter.") }
                         .sort
      pairs.empty? ? nil : Rack::Utils.build_query(pairs)
    end

    # Section Rendering API 參數：`section_id`（單段 HTML）／`sections`（逗號或陣列，回 JSON）——兩者並存時 renderer 讓 sections 壓過。
    def section_rendering_request?
      params[:section_id].present? || params[:sections].present?
    end

    def section_rendering_params
      sections = params[:sections]
      sections = sections.to_unsafe_h.values if sections.respond_to?(:to_unsafe_h)
      sections = Array(sections).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:empty?).join(",")
      { "section_id" => params[:section_id].to_s, "sections" => sections }.reject { |_, v| v.blank? }
    end

    def render_page(hit, rest, cart_json: nil, extra: {})
      ThemeEngine::PageRenderer.new(
        theme: current_theme, shop: current_shop, publication: Publication.online_store!,
        url_prefix: Markets::UrlPrefix.for(hit.web_presence, hit.locale_tag),
        host: request.host, locale: hit.locale_tag, asset_base: "/theme-assets",
        web_presence: hit.web_presence, # localization 真值（切換器只列開放∧已發布——67 §F.2）
        cart_json: # 🔴 個人化不進頁快取（14 §F1-4）——只有繞過快取的 /cart 會傳非 nil
      ).render(rest, params: cache_params.merge(extra))
    end

    # PR-12 預覽列：主題名＋結束預覽（href 帶正式主題 id＝83 §12.3 復位法；
    # 無正式主題時帶 0——查無 ⇒ 一樣解除釘選）。inline style 由 ThemeCsp 放行。
    def preview_bar_html
      name = ERB::Util.html_escape(current_theme.name)
      exit_href = "/?preview_theme_id=#{published_theme&.id || 0}"
      %(<div id="cl-preview-bar" style="position:fixed;bottom:0;left:0;right:0;) +
        %(z-index:2147483647;display:flex;align-items:center;justify-content:space-between;) +
        %(gap:12px;padding:10px 16px;background:#14151a;color:#fff;) +
        %(font:13px/1.4 system-ui,sans-serif;">) +
        %(<span>正在預覽佈景主題：<strong>#{name}</strong>（尚未發布）</span>) +
        %(<a href="#{exit_href}" style="color:#9db8ff;text-decoration:underline;">結束預覽</a></div>)
    end

    # 買家真車（/cart 頁專用）：只讀 cookie **不建車**（純瀏覽不得生車列）；
    # 無車 ⇒ nil（CartDrop 以空車渲染）。
    def buyer_cart_json
      token = cookies.signed[Storefront::CartController::COOKIE]
      return nil if token.blank?

      cart = ActsAsTenant.with_tenant(current_shop) do
        Cart.includes(cart_line_items: { product_variant: :product })
            .find_by(shop_id: current_shop.id, token: token)
      end
      cart && Storefront::CartSerializer.cart_json(cart)
    end
  end
end
