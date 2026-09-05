# frozen_string_literal: true

module Storefront
  # 公開店面頁面（包 33 後半；六步方案步 2）。
  #
  # ①路由紀律（67 §F.1(b)(c)；limits `i18n.locale_prefix.*`；🔴 2026-09-04 D80 方案 1 使用者裁定＝本尊形）：
  #   - 根路徑與無前綴路徑 ⇒ **直接**以店預設 (market, locale) 渲染（本尊 `/` 200、`lang="zh-CN"`；不再 302）。
  #   - 第一段長得像前綴（SEGMENT 粗篩）⇒ 查 `Markets::PrefixIndex`；命中 ⇒ 剝前綴、以該 (market, locale) 渲染；
  #     未命中 ⇒ 整條路徑當無前綴路徑（本尊 `/zh-hans/` 404＝沒有這個頁面，`/fr-hk/` 同理；不是「前綴查無」的特別碼）。
  #   - 共用主網域上的市場再由買家選國 cookie 覆寫（BaseController ③）；頁快取 key 含 market ⇒ 不同市場不互汙。
  # ②頁級快取（63 §D.3）＝`Storefront::PageCache`；🔴 渲染快取頁不帶 cart_json
  #   （14 §F1-4 個人化不進頁快取——買家 cart 態由 /cart.js 端點取）。
  # ③🔴 B13：robots 全站 Disallow ＋ 頁面 X-Robots-Tag noindex——SEO 面（hreflang／
  #   sitemap／開放索引）是步 4（包 35）的射程，開放時兩者一起摘除。
  class PagesController < BaseController
    before_action :require_published_theme!, except: %i[robots]

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

    # GET /（＝無前綴根路徑；D80 起直接渲染首頁，不重導）
    def root
      hit = default_hit
      return head :not_found if hit.nil?

      serve(hit, "/")
    end

    # GET /*path
    def show
      first, rest = split_path
      hit = first.match?(prefix_shape) ? locale_hit(first) : nil
      if hit
        path = rest
      else
        hit = default_hit
        return head :not_found if hit.nil?

        path = request.path.chomp("/").presence || "/"
      end
      serve(hit, path)
    end

    private

    # 以 (market, presence, locale) 渲染前綴已剝的站內路徑。
    def serve(hit, rest)
      # G6 打磨包：/cart 是個人化頁——**繞過頁快取**、以買家 cookie 的真車渲染
      # （14 §F1-4「個人化不進頁快取」＝不快取本頁，而不是快取一台空車）。
      # E12：Section Rendering API 在**任何頁面**（官方 ajax/section-rendering，取證 2026-09-04："Sections rendered in response to
      # the section_id query parameter are returned directly as HTML and, like sections, this parameter can be used to render a
      # section in the context of any page."；"If the requested section ID doesn't exist on the theme, then the server responds
      # with a 404 status."）。先前只有 search/suggest、recommendations、cart POST 走這條，`/search?section_id=` 回整頁 ⇒ Ella 的
      # recently-viewed JS 拿到整頁 HTML 而顯示警告區塊（hoko 該段 display:none）。繞過頁快取（cart drawer 段含個人化）。
      if section_rendering_request?
        response.headers["Cache-Control"] = "no-store"
        payload = render_page(hit, rest, cart_json: buyer_cart_json, extra: section_rendering_params,
                                         query_string: request.query_string)
        return head :not_found if payload["status"] == 404
        return head :bad_request if payload["status"] == 400
        return render(json: payload["html"], status: payload["status"]) if payload["content_type"] == :json

        return render html: Storefront::RequestValues.substitute(payload["html"], cookies:).html_safe, status: payload["status"], layout: false
      end

      if rest == "/cart"
        response.headers["Cache-Control"] = "no-store"
        payload = render_page(hit, rest, cart_json: buyer_cart_json, query_string: request.query_string)
      elsif preview_theme_active?
        # PR-12：🔴 預覽不進頁快取（不讀不寫）——快取鍵含 theme 擋得住互汙，
        # 但預覽的意義是看未儲存中的主題現狀，命中舊 entry 即假象。
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Robots-Tag"] = "noindex, nofollow"
        payload = render_page(hit, rest, cart_json: rest == "/cart" ? buyer_cart_json : nil,
                                         query_string: request.query_string)
      elsif rest == "/search"
        # 步 12b：搜尋頁**不進頁快取**——q 鍵空間無界（S6b 同型防灌爆），
        # 且結果隨庫存/發布即時變。robots 已 Disallow /search（既有）。
        payload = render_page(hit, rest, query_string: request.query_string)
      else
        # E16：進頁快取的整頁只餵**快取鍵會看的** query 對（CACHE_PARAMS ∪ filter.*，原順序原編碼）——
        # 整頁 HTML 必須是快取鍵的純函數，否則 `?utm_…` 這類不進鍵的參數會經 `return_to` 洩進別的請求的快取命中
        # （Ella 整頁不渲染 localization 表單、只在 section fetch 出現 ⇒ 真店不可觀測此形，91 §3.85）。
        payload = PageCache.fetch(
          shop: current_shop, theme: published_theme, market: hit.market,
          locale_tag: hit.locale_tag, path: rest, params: cache_params
        ) { render_page(hit, rest, query_string: cache_relevant_query_string) }
      end

      # 301 引擎（包 36）：掛在 404 之前、活頁面先贏（渲染 200 就不查表）。
      # 查表用無前綴正規路徑，命中後**保留前綴** 301（/zh-hant/products/舊 ⇒ /zh-hant/products/新；預設語言無前綴）。
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
      # 由 Storefront::ContentForHeader 以 meta robots 承接（limits `product.unlisted_meta_robots`；E19 前為 Seo::HeadTags）。
      # PR-12：預覽列——僅整頁 HTML（片段/JSON 不注）；自有樣式（鐵律 9：
      # 功能對位本尊 preview bar，視覺用我方設計語言）。
      if preview_theme_active? && payload["html"].to_s.include?("</body>")
        payload["html"] = payload["html"].sub("</body>", "#{preview_bar_html}</body>")
      end
      render html: Storefront::RequestValues.substitute(payload["html"], cookies:).html_safe, status: payload["status"], layout: false
    end

    # 前綴形＝Markets::UrlPrefix::SEGMENT（同一來源，不抄第二份）——只是省一次查表的粗篩：
    # 像前綴就查 PrefixIndex，查無或不像 ⇒ 整條路徑當無前綴路徑（D80）。
    def prefix_shape
      /\A#{Markets::UrlPrefix::SEGMENT.source}\z/
    end

    def split_path
      segments = request.path.delete_prefix("/").split("/", 2)
      [ segments[0].to_s.downcase, "/#{segments[1]}".chomp("/").presence || "/" ]
    end

    # 原始 query string 中**進快取鍵**的鍵值對（CACHE_PARAMS 與 facets 鍵），保留請求的順序與編碼；無 ⇒ nil。
    def cache_relevant_query_string
      pairs = request.query_string.to_s.split("&").reject(&:empty?).select do |pair|
        key = Rack::Utils.unescape(pair.split("=", 2)[0].to_s)
        CACHE_PARAMS.include?(key) || key.start_with?("filter.")
      end
      pairs.empty? ? nil : pairs.join("&")
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

    # @param query_string [String, nil] 餵 `{% form %}` return_to 預設值的原始 query（E16）；快取分支只給進鍵的對
    def render_page(hit, rest, cart_json: nil, extra: {}, query_string: nil)
      ThemeEngine::PageRenderer.new(
        theme: current_theme, shop: current_shop, publication: Publication.online_store!,
        url_prefix: Markets::UrlPrefix.for(hit.web_presence, hit.locale_tag),
        host: request.host, locale: hit.locale_tag, asset_base: "/theme-assets",
        origin: "#{request.protocol}#{request.host_with_port}", # E18：平台 head 注入的絕對 URL（本機 http 埠形也要能載模組）
        web_presence: hit.web_presence, # localization 真值（切換器只列開放∧已發布——67 §F.2）
        market: hit.market, country_code: hit.effective_country_code, # D80：買家選國覆寫後的市場／國家
        query_string: query_string.presence,
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
