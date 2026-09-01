# frozen_string_literal: true

# 整頁渲染（包 30；路由 → template → sections → layout 的組裝層）。
#
# ①這是什麼：`Runtime` 之上的一層——解析 JSON template（DB 覆寫 → 來源檔）、
#   依 `order` 渲染 sections、把結果塞進 `layout/theme.liquid` 的
#   `content_for_layout`。可見性判準＝`Storefront::Lookup`（specs/93 §C：
#   直連 purchasable；查無 ⇒ :not_found，controller 層轉 404）。
# ②路由值域（v1）：`/`＝index；`/products/:handle`；`/collections/:handle`；
#   `/pages/:handle`；其餘 ⇒ 404 template（78 §4 的 11 型之一）。
#   搜尋／購物車／帳戶等路由隨對應功能線（W6 後續包）。
module ThemeEngine
  class PageRenderer
    # content_type：:html（整頁／單 section）或 :json（?sections= map）。
    # volatile：頁面讀到揮發欄位（inventory_quantity 等）⇒ 頁級快取 TTL 兜底（63 §D.5）。
    Result = Struct.new(:status, :html, :page_type, :content_type, :volatile, keyword_init: true) do
      def volatile? = !!volatile
    end

    def initialize(theme:, shop:, publication:, url_prefix: "", design_mode: false, host: nil, source: nil,
                   cart_json: nil, asset_base: nil, locale: nil, web_presence: nil)
      @theme, @shop, @publication = theme, shop, publication
      @url_prefix, @design_mode, @host = url_prefix, design_mode, host
      @source = source
      @cart_json = cart_json
      @asset_base = asset_base
      @locale = locale
      @web_presence = web_presence
    end

    # @param path [String] 前綴已剝除的站內路徑（如 "/products/rose-serum"）
    # @param params [Hash] query 參數（缺口分析 A2：`variant` 進選中態；
    #   其餘參數目前忽略——`section_id`／`sections` 端點面歸包 33）。
    # @return [Result]
    # @note 整段在租戶脈絡內執行（引擎的全部 DB 讀取——templates／theme_settings／
    #   menus／lookup——都要 tenant；巢狀 with_tenant 冪等，controller 已設也無妨）。
    # @param assigns [Hash] 額外全域 assigns（步 12b：suggest／recommendations 的
    #   section 形把 predictive_search／recommendations 疊進渲染語境）。
    # PR-7：draft_sections＝編輯器未儲存 entry 的覆蓋（sid → entry）——
    # SRA 單 section 渲染吃它 ⇒ 右側即時預覽（本尊改設定即時重渲染的對位）。
    def render(path, params: {}, assigns: {}, draft_sections: nil, draft_settings: nil)
      @params = params || {}
      @extra_assigns = assigns || {}
      @draft_sections = draft_sections || {}
      @draft_settings = draft_settings
      ActsAsTenant.with_tenant(@shop) do
        # Section Rendering API（包 33；契約＝83 §3.4＋§12.3 真店逐格）：
        # 兩參數並存時 `sections` 壓過 `section_id`（實測：回 JSON）。
        if @params["sections"].present?
          render_sections_json(path)
        elsif @params["section_id"].present?
          render_single_section(path)
        else
          render_inside_tenant(path)
        end
      end
    end

    private

    def render_inside_tenant(path)
      page_type, assigns, status, record = resolve(path)
      runtime = Runtime.new(theme: @theme, shop: @shop, url_prefix: @url_prefix,
                            design_mode: @design_mode, page_type: page_type,
                            path: path, host: @host, source: @source, cart_json: @cart_json,
                            asset_base: @asset_base, locale: @locale, web_presence: @web_presence,
                            publication: @publication, params: @params,
                            draft_settings: @draft_settings, draft_sections: @draft_sections)
      template_key = template_key_for(runtime, page_type)
      if template_key != page_type
        runtime.assign("template", TemplateDrop.new(page_type, suffix: template_key.delete_prefix("#{page_type}.")))
      end
      assigns.each { |k, v| runtime.assign(k, v) }
      @extra_assigns&.each { |k, v| runtime.assign(k, v) }
      if (product = assigns["product"])
        runtime.closest = ClosestDrop.new(product: product)
      end
      # 平台 head 注入（包 35；62 §A.1 第 1 層）：canonical＋hreflang＋JSON-LD。
      # 只在公開店面（有 presence）注入；預覽面（noindex 牆後）維持空字串（包 30 行為）。
      if @web_presence
        runtime.assign("content_for_header", Seo::HeadTags.build(
          shop: @shop, presence: @web_presence, locale_tag: @locale.to_s,
          canonical_path: path, params: @params, record:, status:
        ))
      end

      body = render_template_sections(runtime, template_key)
      html = render_layout(runtime, body, template_key: template_key)
      # PR-3：window.Shopify bootstrap（主題 JS 生態依賴；shopify_global.rb 檔頭）
      html = html.sub("</head>") do
        ThemeEngine::ShopifyGlobal.script(
          shop: @shop, theme: @theme, locale: @locale.to_s,
          currency: @shop.store_currency, root: root_prefix_path,
          design_mode: @design_mode) + "</head>"
      end
      # PR-19：theme 級 Custom CSS（head 尾；官方全站生效語義）
      theme_css = runtime.theme_custom_css_style
      html = html.sub("</head>") { theme_css + "</head>" } if theme_css.present?
      # PR-3：{% javascript %}/{% stylesheet %} 聚合輸出（本尊語義＝逐 section
      # 收集、全頁去重、頁尾一次輸出；先前整塊吞掉）
      aggregated = runtime.aggregated_section_assets
      html = html.sub("</body>", "#{aggregated}</body>") if aggregated.present?
      # 步 16a：design_mode 注入編輯器橋（selection 雙向——14 §F3）
      html = html.sub("</body>", "#{ThemeEngine::Runtime::EDITOR_BRIDGE_JS}</body>") if @design_mode
      Result.new(status: status, html: html, page_type: page_type,
                 volatile: runtime.render_flags.include?(:volatile))
    end

    # `?view=` 替代模板（96 §6）：suffix 合法且模板存在 ⇒ `{type}.{suffix}`；
    # 🔴 不存在 ⇒ 靜默 fallback 預設模板（真店實證：?view=不存在 suffix 回 200
    # 渲染預設，不是 404）。404 頁不吃 view。
    # buyer 面根路徑（Shopify.routes.root；帶語言前綴＋尾斜線——本尊形）
    def root_prefix_path
      prefix = @url_prefix.to_s
      prefix.empty? ? "/" : "/#{prefix.delete_prefix('/')}/"
    end

    def template_key_for(runtime, page_type)
      view = @params["view"].to_s
      return page_type if page_type == "404" || view.blank? ||
                          !view.match?(/\A[a-z0-9][a-z0-9\-_.]{0,64}\z/i)

      candidate = "#{page_type}.#{view}"
      runtime.template_json(candidate) ? candidate : page_type
    end

    # @return [Array(String, Hash, Integer, Object)] [template key, 額外 assigns, HTTP status,
    #   資源 record（head 注入用；404／index 為 nil）]
    def resolve(path)
      at = Time.current
      case path
      when "/", ""
        [ "index", {}, 200 ]
      when "/cart"
        # G2 縫補（打磨包）：cart 頁模板對映——`cart` drop 走 global assigns
        # （cart_json 由 pages controller 對本路徑**繞過頁快取**注入；14 §F1-4
        # 個人化不進快取的紀律不變——是「不快取」，不是「快取空車」）。
        [ "cart", {}, 200 ]
      when %r{\A/products/([^/]+)\z}
        product = ActsAsTenant.with_tenant(@shop) do
          found = Storefront::Lookup.product_by_handle(publication: @publication, handle: Regexp.last_match(1), at: at)
          # preload 面＝drops 的讀取契約（缺口分析 A′）：庫存鏈（available/
          # inventory_quantity）、變體選項座標（A3 分組）、變體專圖與商品媒體。
          found && Product.where(shop_id: @shop.id, id: found.id)
                          .includes(
                            product_variants: [ :product_variant_option_values,
                                                { inventory_item: :inventory_levels },
                                                { media: :stored_file } ],
                            product_options: :option_values,
                            media: :stored_file
                          ).first
        end
        product ? [ "product", { "product" => ProductDrop.new(product, url_prefix: @url_prefix,
                                                              selected_variant_id: selected_variant_id,
                                                              publication: @publication,
                                                              translations: translations_for(product)) },
                   200, product ] : not_found
      when "/collections"
        # 步 12（96 §1）：集合列表頁。內容全由 `collections` 全域供給（Runtime 已備）。
        [ "list-collections", {}, 200 ]
      when %r{\A/blogs/([^/]+)\z}
        blog = ActsAsTenant.with_tenant(@shop) { Blog.find_by(shop_id: @shop.id, handle: Regexp.last_match(1)) }
        blog ? [ "blog", { "blog" => BlogDrop.new(blog, url_prefix: @url_prefix) }, 200, blog ] : not_found
      when %r{\A/blogs/([^/]+)/tagged/([^/]+)\z}
        # 98 §2 官方：/tagged/{tag-handle}＋`+` 多 tag；current_tags 於 blog 模板可用
        blog = ActsAsTenant.with_tenant(@shop) { Blog.find_by(shop_id: @shop.id, handle: Regexp.last_match(1)) }
        tags = Regexp.last_match(2).split("+").map { |raw| CGI.unescape(raw) }
        blog ? [ "blog", { "blog" => BlogDrop.new(blog, url_prefix: @url_prefix, current_tags: tags),
                           "current_tags" => tags }, 200, blog ] : not_found
      when %r{\A/blogs/([^/]+)/([^/]+)\z}
        found = ActsAsTenant.with_tenant(@shop) do
          blog = Blog.find_by(shop_id: @shop.id, handle: Regexp.last_match(1))
          article = blog && Article.visible.includes(:blog)
                                   .find_by(shop_id: @shop.id, blog_id: blog.id, handle: Regexp.last_match(2))
          article && [ blog, article ]
        end
        if found
          blog, article = found
          [ "article", { "article" => ArticleDrop.new(article, url_prefix: @url_prefix, blog:),
                         "blog" => BlogDrop.new(blog, url_prefix: @url_prefix) }, 200, article ]
        else
          not_found
        end
      when "/search"
        # 步 12b（96 §3）：搜尋頁。search 物件自帶懶載——無 q ⇒ performed=false 空表單頁。
        [ "search", { "search" => SearchDrop.new(
          shop: @shop, publication: @publication, url_prefix: @url_prefix,
          locale: @locale, params: @params
        ) }, 200 ]
      when %r{\A/collections/([^/]+)\z}
        handle = Regexp.last_match(1)
        collection = ActsAsTenant.with_tenant(@shop) do
          Storefront::Lookup.collection_by_handle(publication: @publication, handle:, at: at)
        end
        # 96 §2：/collections/all 虛擬全商品系列（真店實證 title=Products、字母序）；
        # 商家自建 handle=all 的真系列優先（上面已查、命中即走真系列分支）。
        if collection.nil? && handle.downcase == "all"
          virtual = VirtualAllCollection.new("Products", "all", "title_asc", nil, nil)
          return [ "collection", { "collection" => CollectionDrop.new(
            virtual, url_prefix: @url_prefix, publication: @publication,
            locale: @locale, sort_param: @params["sort_by"]
          ) }, 200 ]
        end
        collection ? [ "collection", { "collection" => CollectionDrop.new(
          collection, url_prefix: @url_prefix,
          published_at: ResourcePublication.where(
            shop_id: @shop.id, publication_id: @publication.id,
            publishable_type: "Collection", publishable_id: collection.id
          ).pick(:published_at),
          translations: translations_for(collection),
          publication: @publication, locale: @locale, sort_param: @params["sort_by"]
        ) }, 200, collection ] : not_found
      when %r{\A/pages/([^/]+)\z}
        page = ActsAsTenant.with_tenant(@shop) do
          Page.visible(at: at).find_by(shop_id: @shop.id, handle: Regexp.last_match(1))
        end
        page ? [ "page", { "page" => PageDrop.new(page, url_prefix: @url_prefix) }, 200, page ] : not_found
      else
        not_found
      end
    end

    def not_found = [ "404", {}, 404 ]

    # 內容翻譯 preload（67 §F.3(c)：走 drops 不走 t；一次批載不逐欄查——63 §D.1 N+1 防線）。
    # 來源語言或未指定 locale ⇒ 空 overlay（drop 直讀 base row，零查詢）。
    # @return [Hash{String => String}] field_key => 譯文（omitted 欄位不進 overlay）
    def translations_for(record)
      locale = @locale.to_s
      return {} if locale.blank?

      resolved = Translations::Resolve.batch(shop: @shop, resources: [ record ], locale:)
      type = Translations::Resolve::RESOURCE_TYPE_BY_CLASS.fetch(record.class.name, nil)
      fields = resolved[[ type, record.id ]] || {}
      fields.each_with_object({}) do |(key, entry), acc|
        acc[key] = entry.value unless entry.omitted?
      end
    end

    # ── Section Rendering API（包 33） ─────────────────────────────────────
    # 真店契約（83 §12.3，2026-08-31 乾淨態）：
    #   單 id：200 text/html 帶 wrapper；未知 id ⇒ 404 **空 body**（不是主題 404 頁）。
    #   多 id：200 application/json map；未知鍵值＝null；>5 ⇒ 400 空 body。
    #   context 繼承請求頁（含 ?variant= 選中態——Ella 變體切換就靠這疊加）。
    # 🔴 id 語義差異（登記）：本尊＝`template--N__key`／`sections--N__key` 動態
    #   實例 id；我方 v1 無實例編號 ⇒ id＝template JSON 的 section 鍵或群組 JSON
    #   的 section 鍵（DB 實例化隨編輯器寫入面）。
    def render_single_section(path)
      page_type, assigns, = resolve(path)
      runtime = build_runtime(page_type, assigns)
      sid = @params["section_id"].to_s
      data = section_data_for(runtime, page_type, sid)
      return Result.new(status: 404, html: "", page_type: page_type) if data.nil?

      Result.new(status: 200, html: runtime.render_section(sid, data), page_type: page_type)
    end

    def render_sections_json(path)
      ids = @params["sections"].to_s.split(",").map(&:strip).reject(&:empty?)
      max = Limits.fetch(:theme_engine, :section_rendering_max_ids)
      return Result.new(status: 400, html: "", page_type: nil) if ids.size > max

      page_type, assigns, = resolve(path)
      runtime = build_runtime(page_type, assigns)
      map = ids.to_h do |sid|
        data = section_data_for(runtime, page_type, sid)
        [ sid, data && runtime.render_section(sid, data) ]
      end
      Result.new(status: 200, html: JSON.generate(map), page_type: page_type, content_type: :json)
    end

    def build_runtime(page_type, assigns)
      runtime = Runtime.new(theme: @theme, shop: @shop, url_prefix: @url_prefix,
                            design_mode: @design_mode, page_type: page_type,
                            path: nil, host: @host, source: @source, cart_json: @cart_json,
                            asset_base: @asset_base, locale: @locale, web_presence: @web_presence,
                            publication: @publication, params: @params)
      assigns.each { |k, v| runtime.assign(k, v) }
      @extra_assigns&.each { |k, v| runtime.assign(k, v) }
      if (product = assigns["product"])
        runtime.closest = ClosestDrop.new(product: product)
      end
      # PR-13：page_image（官方＝product/collection/article 用資源 featured
      # image，其餘退 social sharing image——後者我方無資料面 ⇒ nil，主題
      # `!= blank` 閘走無圖分支；shopify.dev objects/page_image 2026-09-02）
      if (img = page_image_for(assigns))
        runtime.assign("page_image", img)
      end
      runtime
    end

    def page_image_for(assigns)
      resource = assigns["product"] || assigns["collection"] || assigns["article"]
      resource.respond_to?(:featured_image) ? resource.featured_image : nil
    end

    # id 解析：①請求頁 template 的 sections ②layout 引用的各群組 JSON 的 sections。
    # 找不到 ⇒ nil（呼叫端依端點轉 404／null）。?view= 語境下先查替代模板
    # （section 請求繼承請求頁 context——83 §12.3；替代模板頁的 section 也要找得到）。
    def section_data_for(runtime, page_type, sid)
      # PR-7：編輯器 draft 覆蓋最優先（未儲存的即時預覽）
      return @draft_sections[sid] if @draft_sections&.key?(sid)

      tj = runtime.template_json(template_key_for(runtime, page_type))
      data = tj && (tj["sections"] || {})[sid]
      return data if data

      layout_group_names(runtime).each do |name|
        g = runtime.load_json("sections/#{name}.json") or next
        found = (g["sections"] || {})[sid]
        return found if found
      end
      # ③檔名直渲染（步 12b）：Ajax API 的 section_id＝**section 檔名**（官方
      # "the section file that you want render"；Dawn/Ella 實際請求 predictive-search
      # ／related-products／cart-drawer 全是檔名——25 §5＋96 §4.3 live 200 實證）。
      # 檔存在 ⇒ 合成空設定 data（schema defaults 生效）；名限 [\w-]（防路徑逃逸）。
      if sid.match?(/\A[\w-]+\z/) && runtime.read("sections/#{sid}.liquid")
        return { "type" => sid, "settings" => {} }
      end
      nil
    end

    # layout theme.liquid 裡 {% sections 'name' %} 的名單（引擎渲染群組的同一來源）。
    def layout_group_names(runtime)
      layout = runtime.compiled("layout/theme.liquid")
      return [] if layout.nil?

      src = runtime.raw_layout_source
      return [] if src.nil?

      src.scan(/\{%-?\s*sections\s+'([^']+)'/).flatten.uniq
    end

    # A2：`?variant=` → Integer；非數字／缺席 ⇒ nil（壞值忽略＝ours，
    # 本尊壞值行為未取證，缺口分析 §D 登記）。
    def selected_variant_id
      raw = @params["variant"] || @params[:variant]
      raw.to_s =~ /\A\d+\z/ ? raw.to_i : nil
    end

    def render_template_sections(runtime, key)
      tj = runtime.template_json(key)
      return runtime.comment("缺 template #{key}") if tj.nil?

      order = tj["order"] || tj.dig("sections") && tj["sections"].keys || []
      Array(order).map do |k|
        # PR-11：draft 覆蓋最優先（編輯器整頁草稿）——與 section_data_for 同序
        data = @draft_sections[k] || (tj["sections"] || {})[k] or next ""
        data["disabled"] ? "" : runtime.render_section(k, data)
      end.join
    end

    # PR-10：template JSON `layout` 鍵（官方三值語義逐字取證 2026-09-01：
    # 字串＝"The filename of the layout to use…specify \"full-width\" to render
    # layout/full-width.liquid"；false＝無 layout（且 "Templates without a
    # layout can't be customized in the theme editor"）；缺鍵＝"The default
    # layout is theme.liquid."）。`wrapper` 屬性未接（登記 V）。
    def render_layout(runtime, content, template_key: nil)
      layout_key = template_key ? runtime.template_json(template_key)&.fetch("layout", nil) : nil
      return content if layout_key == false

      name = layout_key.is_a?(String) && layout_key.present? ? layout_key : "theme"
      layout = runtime.compiled("layout/#{name}.liquid")
      # 指名 layout 缺檔 ⇒ 回落 theme.liquid（寬容）；theme 也缺 ⇒ 裸 content
      layout = runtime.compiled("layout/theme.liquid") if layout.nil? && name != "theme"
      return content if layout.nil?

      assigns = runtime.global_assigns.merge("content_for_layout" => content)
      html = layout[:tpl].render(runtime.build_context(assigns, runtime.base_registers.merge(frame: {})))
      runtime.collect_errors("layout/#{name}.liquid", layout[:tpl])
      html
    end
  end
end
