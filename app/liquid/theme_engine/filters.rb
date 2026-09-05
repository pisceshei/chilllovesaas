# frozen_string_literal: true

# 平台層 filters（包 30；PoC ~70 filters 生產移植；對照 docs/research/26 §3）。
#
# 🔴 money 族：輸入＝**integer cents**（鐵律 3 儲存尺度）；顯示形＝店級 `money_format`／
#   `money_with_currency_format`（D81；registers[:money_format]／[:money_with_currency_format] 由
#   Runtime 與 Notifications::Renderer 以 shop 兩欄注入；渲染邏輯一份＝ThemeEngine::MoneyFormat）。
module ThemeEngine
  module Filters
    # ---- localization ------------------------------------------------------
    def t(input, opts = {})
      dict = @context.registers[:locale_dict] || {}
      key = input.to_s
      val = key.split(".").reduce(dict) { |h, k| h.is_a?(Hash) ? h[k] : nil }
      val = opts["default"] if val.nil? && opts.is_a?(Hash)
      val = key.split(".").last.to_s.tr("_", " ") if val.nil?
      if val.is_a?(Hash) # 複數鍵 {one:, other:}
        count = opts.is_a?(Hash) ? (opts["count"] || 1) : 1
        val = count.to_i == 1 ? (val["one"] || val["other"]) : (val["other"] || val["one"])
      end
      s = val.to_s
      # PR-8：{{ key }} 佔位空白寬容（Ella 有 `{{ inventory}}` 無尾空格形——實錘）
      if opts.is_a?(Hash)
        opts.each do |k, v|
          s = s.gsub("%{#{k}}", v.to_s)
               .gsub(/\{\{\s*#{Regexp.escape(k.to_s)}\s*\}\}/, v.to_s)
        end
      end
      s
    end

    # ---- assets / URLs -----------------------------------------------------
    def asset_url(input)
      base = @context.registers[:asset_base] || "/theme-assets"
      "#{base}/#{input}"
    end
    def asset_img_url(input, _size = nil) = asset_url(input)
    def file_url(input) = asset_url(input)
    def file_img_url(input, _s = nil) = asset_url(input)
    def shopify_asset_url(input) = asset_url(input)
    def global_asset_url(input) = asset_url(input)

    # 官方逐字（filters/stylesheet_tag，取證 2026-09-03）：`<link href="…" rel="stylesheet" type="text/css" media="all" />`
    # ——rel／href 由 filter 管、media 預設 all、可加其他屬性；渲染 1:1 對表：舊實作 `<link rel="stylesheet" href="…">` 與
    # 本尊逐字不同（hoko.vip header section diff 實錘）。
    # `preload: true` 不是屬性——官方逐字（filters/stylesheet_tag，2026-09-03）："When preload is set to true, a resource hint
    # is sent as a Link header with a rel value of preload."（hoko.vip base.css tag 無 preload 屬性；Link header 我方未實作，登記）
    def stylesheet_tag(input, opts = {})
      extra = opts.is_a?(Hash) ? opts.reject { |k, _| %w[href rel preload].include?(k.to_s) } : {}
      media = extra.delete("media") || (opts.is_a?(String) ? opts : nil) || "all"
      attrs = extra.map { |k, v| %( #{k}="#{CGI.escapeHTML(v.to_s)}") }.join
      %(<link href="#{input}" rel="stylesheet" type="text/css" media="#{CGI.escapeHTML(media.to_s)}"#{attrs} />)
    end

    # 官方逐字（filters/script_tag）：`<script src="…" type="text/javascript"></script>`（無 defer）。
    def script_tag(input) = %(<script src="#{input}" type="text/javascript"></script>)

    # 資產檔**照檔輸出、含檔尾換行**：hoko.vip 原始位元組 `</svg>\r\n</span>`（account-drawer.liquid
    # `{{- 'icon-close.svg' | inline_asset_content -}}` 兩側都有 `-`，唯一可能的 `\r\n` 來源是資產檔尾；
    # 2026-09-03 同日曾誤判為修尾——toolbar 的 `</svg>\r</span>` 其實來自 `block.settings.icon` 字串，不是資產檔）。
    def inline_asset_content(input)
      rt = @context.registers[:runtime]
      rt ? rt.asset(input.to_s).to_s : ""
    end

    # ---- image -------------------------------------------------------------
    # PR-9（官方 image_url 文檔取證 2026-09-01）：width/height 以 query 參數逐字
    # 編進 URL（例 `...jpg?v=…&width=450`）；'800x' 類字串 to_i 係數化；format
    # 參數吞掉不編出（我方衍生恆 webp＝ours；官方值域僅 pjpg/jpg、webp 走自動
    # 協商）。回傳 ImageUrlResult（攜 drop＋請求尺寸——image_tag 推導用）。
    def image_url(input, opts = {})
      w = opts.is_a?(Hash) ? opts["width"].to_i : 0
      h = opts.is_a?(Hash) ? opts["height"].to_i : 0
      case input
      when ThemeEngine::ImageDrop, ThemeEngine::FileImageDrop
        base = input.url.presence
        return placeholder_url(w, h, "image") if base.nil? # PR-2 nil 防線不動
        ThemeEngine::ImageUrlResult.new(
          sized_media_url(base, width: w, height: h), source_drop: input,
          requested_width: w.positive? ? w : nil, requested_height: h.positive? ? h : nil)
      when ThemeEngine::PlaceholderImageDrop then input.url
      # E17：`country | image_url: width: 32` ⇒ 國旗（本尊 hoko.vip 2026-09-05 header_mobile 區段逐字
      # `url(//cdn.shopify.com/static/images/flags/tw.svg?width=32)`，SVG viewBox 640×480＝4:3）。我方路徑形照本尊、主機＝店主機、
      # 圖檔＝MIT flag-icons 4x3（鐵律 9：不用本尊 CDN 圖）；Normalizer 把 `//cdn.shopify.com/static/images/flags/` 抹成同路徑。
      when ThemeEngine::CountryDrop
        code = input["iso_code"].to_s.downcase
        "//#{@context.registers[:host]}/cdn/static/images/flags/#{code}.svg#{w.positive? ? "?width=#{w}" : ''}"
      when ThemeEngine::ExternalPreviewImageDrop then input.url # E12：供應商縮圖 URL 不加 width／height 參數
      # E12（更正 E8b #52）：nil ⇒ raise「invalid url input」——hoko.vip 商品頁 `blocks/_sticky-add-to-cart` 逐字
      # `<div class="sticky-atc__media">Liquid error (blocks/_sticky-add-to-cart line 96): invalid url input</div>`
      # （`{{ current_media | image_url | image_tag }}`，current_media nil）。E8b 看到的 `data-product-variant-media=""` 不是「nil ⇒ 空字串」，
      # 而是同一個錯誤發生在 `{% assign %}` 裡：Liquid 5.13 的 assign 吞錯、變數為空（本機 `bundle exec ruby` 探針；本尊同形）。
      # 我方先前回空字串 ⇒ `image_tag` 再退佔位 ⇒ sticky-atc 多出一張 800px 佔位圖（computed 對表 E12 抓到）。
      # `shopify://`／空字串輸入仍走佔位（既有 PR-2 行為，官方未逐字，V）。
      when nil then raise Liquid::ArgumentError, "invalid url input"
      else
        s = input.to_s
        if s.start_with?("shopify://") || s.empty?
          placeholder_url(w, h, File.basename(s.sub("shopify://", "")))
        else
          s
        end
      end
    end

    # E17：舊版 `img_url`（deprecated）對 nil 輸入**不是**錯誤而是平台「無圖」佔位 URL——hoko.vip 2026-09-05
    # `/products/acme-tee?view=ajax_edit_cart`（Ella `snippets/resource-card-edit-cart` `{{ image | img_url: '270x' }}`，image nil）逐字
    # `srcset="//hoko.vip/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12_270x.gif"`；`image_url` 對 nil 仍是
    # 「invalid url input」（E12）。尺寸段＝`_{size}`；無尺寸形本尊未取得（91 §3.86）。圖片本體＝我方自繪（鐵律 9），路徑形照本尊。
    def img_url(input, size = nil, *rest)
      return no_image_url(size) if input.nil?

      image_url(input, size, *rest)
    end

    def no_image_url(size)
      suffix = size.to_s.strip.empty? ? "" : "_#{size.to_s.strip}"
      "//#{@context.registers[:host]}/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12#{suffix}.gif"
    end

    # PR-9（官方 image_tag 文檔取證 2026-09-01）：
    # - srcset：明示 srcset ＞ widths（CSV→逐寬換 src 的 width 參數＋" Nw"，
    #   只取 ≤ src width 者——官方 "up to the maximum defined in the image URL"）
    #   ＞ 預設（src 帶 width 時出單條 `src Nw`；官方 smart set 未取得＝V）。
    # - width 屬性＝明示 ＞ src width 參數；height＝明示 ＞ width÷aspect_ratio
    #   （官方例證 200→133）；alt＝明示 ＞ drop alt。widths/preload 不落 HTML
    #   屬性（先前 widths 誤輸出成屬性——對表軸實錘）。
    def image_tag(input, opts = {})
      opts = opts.is_a?(Hash) ? opts.dup : {}
      widths = opts.delete("widths")
      explicit_srcset = opts.key?("srcset") ? opts.delete("srcset") : :auto
      opts.delete("preload") # 載入優先權面未接（V）
      src = input.respond_to?(:to_s) ? input.to_s : ""
      src = placeholder_url(800, 800, "image") if src.empty?

      meta = input.is_a?(ThemeEngine::ImageUrlResult) ? input : nil
      src_width = meta&.requested_width || url_width_param(src)
      drop = meta&.source_drop

      unless opts.key?("width")
        opts["width"] = src_width if src_width
      end
      if !opts.key?("height") && opts["width"] && drop&.aspect_ratio&.positive?
        opts["height"] = (opts["width"].to_i / drop.aspect_ratio).round
      end
      opts["alt"] = drop.alt if !opts.key?("alt") && drop.respond_to?(:alt) && drop.alt

      srcset = build_srcset(src, src_width, widths, explicit_srcset)
      opts["srcset"] = srcset if srcset

      attrs = opts.filter_map { |k, v| v.nil? ? nil : %(#{k.to_s.tr('_', '-')}="#{CGI.escapeHTML(v.to_s)}") }.join(" ")
      %(<img src="#{src}" #{attrs}>)
    end
    alias_method :img_tag, :image_tag

    # 逐寬換 src query 的 width 鍵（只動 width、其餘參數與順序保留——與官方
    # `?v=…&width=N` 換值形同構）。
    def build_srcset(src, src_width, widths, explicit_srcset)
      return explicit_srcset if explicit_srcset != :auto # 明示（nil ⇒ 省略）
      if widths.present?
        candidates = widths.to_s.split(",").map { |x| x.to_i }.select(&:positive?)
        candidates = candidates.select { |x| x <= src_width } if src_width
        return nil if candidates.empty?
        return candidates.map { |x| "#{swap_width(src, x)} #{x}w" }.join(", ")
      end
      src_width ? "#{src} #{src_width}w" : nil
    end

    def swap_width(src, width)
      src.include?("width=") ? src.sub(/width=\d+/, "width=#{width}") :
        (src.include?("?") ? "#{src}&width=#{width}" : "#{src}?width=#{width}")
    end

    def url_width_param(src)
      m = src.to_s.match(/[?&]width=(\d+)/)
      m && m[1].to_i
    end

    def sized_media_url(base, width: 0, height: 0)
      query = []
      query << "width=#{width}" if width.positive?
      query << "height=#{height}" if height.positive?
      query.empty? ? base : "#{base}#{base.include?('?') ? '&' : '?'}#{query.join('&')}"
    end

    def placeholder_url(w, h, label)
      ThemeEngine::PlaceholderImageDrop.new(label: label.to_s.presence || "image",
                                            w: (w.positive? ? w : 800),
                                            h: (h.positive? ? h : (w.positive? ? w : 800))).url
    end

    # 官方名稱表的整張插圖（我方自繪；形態與 class 規則見 PlaceholderSvg 檔頭）。
    def placeholder_svg_tag(input, cls = nil) = PlaceholderSvg.tag(input, cls)

    # ---- money（integer cents → 店級格式字串；D81）-----------------------------
    # 官方逐字（filters/money 族，取證 2026-09-03，external-facts §G15）：money＝"Formats a given price based on
    # the store's HTML without currency setting."（例 1000 ⇒ `$10.00`）；money_with_currency＝"…based on the
    # store's HTML with currency setting."（例 `$10.00 CAD`）；money_without_currency＝"…without the currency
    # symbol."（例 `10.00`）；money_without_trailing_zeros＝"…excluding the decimal separator and trailing
    # zeros."（例 `$10`）。空值（nil／空字串）⇒ 空輸出（hoko.vip 佔位商品卡
    # `{{ card_product.compare_at_price | money }}` ⇒ `<s …> </s>`；官方對空值未逐字，V）。
    # registers 缺席（獨立 harness）⇒ 官方例的 `${{amount}}`。
    def money(input) = with_cents(input) { |c| MoneyFormat.render(c, money_pattern) }
    def money_with_currency(input) = with_cents(input) { |c| MoneyFormat.render(c, money_with_currency_pattern) }
    def money_without_currency(input) = with_cents(input) { |c| MoneyFormat.amount_only(c, money_pattern) }
    def money_without_trailing_zeros(input)
      with_cents(input) { |c| MoneyFormat.strip_trailing_zeros(MoneyFormat.render(c, money_pattern)) }
    end

    def money_pattern = @context.registers[:money_format] || "${{amount}}"
    def money_with_currency_pattern = @context.registers[:money_with_currency_format] || money_pattern

    def with_cents(input)
      cents = MoneyFormat.coerce(input)
      cents.nil? ? "" : yield(cents)
    end

    # ---- string / misc -----------------------------------------------------
    # Unicode 字母／數字保留（本尊 `HeaderMenu-首頁`：link.handle 保留 CJK；官方例 "100% M & M's!!!" ⇒ "100-m-m-s"）
    def handleize(input) = input.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, "-").gsub(/\A-|-\z/, "")
    alias_method :handle, :handleize

    # drop 感知（資料出口包）：形狀契約與黑名單見 JsonSerializer 檔頭。
    def json(input) = JsonSerializer.dump(input)

    # PR-3：接 format 參數（先前忽略 ⇒ 文章日期出原始 timestamp）。
    def time_tag(input, fmt = nil, *_rest)
      t = input.respond_to?(:strftime) ? input : Time.zone.parse(input.to_s)
      return input.to_s if t.nil?

      display = fmt.to_s.include?("%") ? t.strftime(fmt.to_s) : t.strftime("%B %d, %Y")
      %(<time datetime="#{t.iso8601}">#{display}</time>)
    rescue StandardError
      input.to_s
    end

    # E8b：整數／純數字字串＝Unix 時間戳（Ella schema.liquid `'now' | date: '%s' | plus: 31536000 | date: '%Y-%m-%d'`
    # ⇒ hoko.vip `"priceValidUntil": "2027-09-03"`；先前 `Time.zone.parse("1819990583")` 失敗 ⇒ 原字串）。官方 date 文件未逐字
    # 提時間戳輸入（V）。
    # E17：時區＝**店時區**（registers[:time_zone]）——hoko.vip 2026-09-05 23:40 UTC 取樣 `"priceValidUntil": "2027-09-05"`
    # （`'now' | date` 落在 +08:00 的 9 月 5 日；`/products/acme-tee.js` 時戳 `+08:00` 同證）；我方先前 `Time.zone`（UTC）⇒ 差一天。
    def date(input, fmt = "%Y-%m-%d")
      zone = liquid_time_zone
      t =
        if input.is_a?(Integer) || (input.is_a?(String) && input.match?(/\A\d{9,}\z/))
          zone.at(input.to_i)
        else
          input.is_a?(String) ? zone.parse(input) : input
        end
      t = t.in_time_zone(zone) if t.respond_to?(:in_time_zone)
      (t || zone.now).strftime(fmt.to_s)
    rescue StandardError
      input.to_s
    end

    def liquid_time_zone
      ActiveSupport::TimeZone[@context.registers[:time_zone].to_s] || Time.zone
    end

    def pluralize(input, singular, plural) = input.to_i == 1 ? singular : plural
    def default_errors(_input) = ""
    def highlight(input, _q = nil) = input
    # 官方逐字（filters/url_param_escape，取證 2026-09-04）："Escapes any characters in a string that are unsafe for URL parameters."；
    # 例 `{{ '<p>Health & Love potions</p>' | url_param_escape }}` ⇒ `%3Cp%3EHealth%20%26%20Love%20potions%3C/p%3E`（空白 %20、& %26、/ 保留）。
    # hoko.vip 商品頁分享連結 `text=Acme%20Tee`（Ella `share_title | url_param_escape`）；先前 CGI.escape ⇒ `Acme+Tee`、`/` ⇒ `%2F`。
    def url_param_escape(input) = ERB::Util.url_encode(input.to_s).gsub("%2F", "/")
    # 官方逐字（filters/url_escape）："Escapes any URL-unsafe characters in a string."；同例 ⇒ `%3Cp%3EHealth%20&%20Love%20potions%3C/p%3E`
    # （& 保留）。例外保留字元只證 `&` 與 `/`（V）。
    def url_escape(input) = url_param_escape(input).gsub("%26", "&")
    def link_to(input, url, _title = nil) = %(<a href="#{url}">#{input}</a>)
    # vendor／type 連結四支（引擎缺口 PR-4）：官方 url_for_vendor 例逐字
    # `/collections/vendors?q=Polina%27s%20Potent%20Potions`（filters/url_for_vendor，取證 2026-09-02）
    # ⇒ 空白編成 `%20`（percent-encoding），不是 CGI.escape 的 `+`。
    # url_for_type："Generates a URL for a collection page that lists all products of the given product
    # type."，例 `/collections/types?q=health`。
    # 官方逐字（filters/link_to_vendor，取證 2026-09-04）：`{{ "Polina's Potent Potions" | link_to_vendor }}` ⇒
    # `<a href="/collections/vendors?q=Polina%27s%20Potent%20Potions" title="Polina&#39;s Potent Potions">Polina's Potent Potions</a>`
    # ⇒ title 屬性 HTML-escape、內文不 escape（hoko.vip 商品頁 `title="Acme"` 同形）。link_to_type 官方頁未給例 ⇒ 同形（V）。
    def link_to_vendor(input) = %(<a href="#{url_for_vendor(input)}" title="#{ERB::Util.html_escape(input.to_s)}">#{input}</a>)
    def url_for_vendor(input) = "/collections/vendors?q=#{ERB::Util.url_encode(input.to_s)}"
    def url_for_type(input) = "/collections/types?q=#{ERB::Util.url_encode(input.to_s)}"
    def link_to_type(input) = %(<a href="#{url_for_type(input)}" title="#{ERB::Util.html_escape(input.to_s)}">#{input}</a>)
    # ---- tag／sort／within 連結（引擎缺口 PR-6；官方 filters/* 逐字，取證 2026-09-02）------
    # link_to_tag："Generates an HTML `<a>` tag with an `href` attribute linking to the current blog or
    #   collection, filtered to show only articles or products that have a given tag."；官方例
    #   `<a href="/services/liquid_rendering/extra-potent" title="Show products matching tag extra-potent">extra-potent</a>`
    #   ⇒ href＝當前系列 URL＋"/"＋tag；部落格 title "Show articles tagged X"、路徑形 `/tagged/X`（98 §2）。
    # link_to_add_tag：title "Narrow selection to products matching tag X"、href＝current_tags＋X（`+` 連接）；
    #   官方："Tags already in `current_tags` display as plain text, while unused tags become clickable links"。
    # link_to_remove_tag："…filtered to show only articles or products that have any currently active
    #   tags, except the provided tag."⇒ href＝current_tags 去掉 X（最後一個 ⇒ 系列根）；title 官方例
    #   未示 ⇒ "Remove tag X"（登記）。
    # sort_by："Generates a collection URL with the provided `sort_by` parameter appended."
    #   例 `/collections/sale-potions?sort_by=best-selling`（既有 query ⇒ `&`）。
    # within："Generates a product URL within the context of the provided collection."
    #   例 `/collections/sale-potions/products/draught-of-immortality`；非系列物件 ⇒ 原樣。
    def link_to_tag(input, tag) = tag_link(input, [ tag.to_s ], :show)

    def link_to_add_tag(input, tag)
      active = current_tags
      return input.to_s if active.include?(tag.to_s)

      tag_link(input, active + [ tag.to_s ], :add, tag)
    end

    def link_to_remove_tag(input, tag) = tag_link(input, current_tags - [ tag.to_s ], :remove, tag)

    def sort_by(input, value)
      url = input.to_s
      "#{url}#{url.include?('?') ? '&' : '?'}sort_by=#{ERB::Util.url_encode(value.to_s)}"
    end

    def within(input, collection)
      url = input.to_s
      return url unless collection.respond_to?(:url) && (m = url.match(%r{/products/([^/?#]+)(.*)\z}))

      "#{collection.url}/products/#{m[1]}#{m[2]}"
    end

    private def tag_link(input, tags, mode, tag = nil)
      path = @context.registers[:request_path].to_s.presence || "/collections/all"
      blog = path.start_with?("/blogs/") || path.match?(%r{\A/[a-z]{2}(?:-[a-z]{2})?/blogs/})
      base = tag_base_path(path, blog)
      href = if tags.empty? then base
      elsif blog then "#{base}/tagged/#{tags.join('+')}"
      else "#{base}/#{tags.join('+')}"
      end
      title = case mode
      when :show then blog ? "Show articles tagged #{tags.first}" : "Show products matching tag #{tags.first}"
      when :add then "Narrow selection to products matching tag #{tag}"
      else "Remove tag #{tag}"
      end
      %(<a href="#{href}" title="#{CGI.escapeHTML(title)}">#{input}</a>)
    end

    private def current_tags
      Array(@context["current_tags"]).map(&:to_s).reject(&:blank?)
    end

    # 去掉當前路徑尾端的 tag 段：部落格 `/tagged/…`；系列＝（locale 前綴＋）`/collections/{handle}` 以後全部。
    private def tag_base_path(path, blog)
      p = path.split("?").first.to_s
      return p.sub(%r{/tagged/[^/]*\z}, "") if blog

      m = p.match(%r{\A((?:/[a-z]{2}(?:-[a-z]{2})?)?/collections/[^/]+)})
      m ? m[1] : p
    end

    # default_pagination："Generates HTML for a set of links for paginated results. Must be applied to
    #   the `paginate` object."；參數 previous／next＝連結文字。官方例逐字：
    #   `<span class="page current">1</span> <span class="page"><a href="…?page=2" title="">2</a></span> <span class="next"><a href="…?page=2" title="">Next &raquo;</a></span>`
    #   previous 側官方例未示 ⇒ 對稱形 `<span class="prev">…&laquo; Previous</span>`（登記）；
    #   窗式省略號 `<span class="deco">&hellip;</span>`（登記）。
    def default_pagination(input, opts = {})
      return "" unless input.is_a?(ThemeEngine::PaginateDrop)

      opts = {} unless opts.is_a?(Hash)
      next_text = opts["next"] || opts[:next] || "Next &raquo;"
      prev_text = opts["previous"] || opts[:previous] || "&laquo; Previous"
      pieces = []
      if (prev = input["previous"])
        pieces << %(<span class="prev"><a href="#{prev['url']}" title="">#{prev_text}</a></span>)
      end
      Array(input["parts"]).each do |part|
        pieces << if part["is_link"]
          %(<span class="page"><a href="#{part['url']}" title="">#{part['title']}</a></span>)
        elsif part["title"].to_s == "&hellip;"
          %(<span class="deco">&hellip;</span>)
        else
          %(<span class="page current">#{part['title']}</span>)
        end
      end
      if (nxt = input["next"])
        pieces << %(<span class="next"><a href="#{nxt['url']}" title="">#{next_text}</a></span>)
      end
      pieces.join(" ")
    end

    # md5："Converts a string into an MD5 hash."（例 `'' | md5` ⇒ d41d8cd98f00b204e9800998ecf8427e）
    def md5(input) = Digest::MD5.hexdigest(input.to_s)

    # ---- fonts（步 13a 真實作；97 §1）--------------------------------------
    # 輸出形對齊真店實測（97 §1.2）：family 無引號＋weight＋style＋（有傳才出）
    # font-display＋src。我方單 woff2 src（live 雙 src 的 woff 退路 ⚪ 97 §1.3）；
    # system font／nil（font_modify 的合法缺席值）⇒ 空輸出。
    def font_face(input, opts = {})
      return "" unless input.is_a?(ThemeEngine::FontDrop) && input.file

      display = opts.is_a?(Hash) ? (opts["font_display"] || opts[:font_display]) : nil
      lines = [ "  font-family: #{input.family};",
                "  font-weight: #{input.weight};",
                "  font-style: #{input.style};" ]
      lines << "  font-display: #{display};" if display
      # 本尊 src 兩行（hoko.vip 2026-09-03 原始位元組）：woff2 之後接 `,\n       url("….woff") format("woff")`；
      # 我方 woff 檔未提供（現代瀏覽器優先 woff2 不會請求 woff；登記）。
      woff = input.file.to_s.sub(/\.woff2\z/, ".woff")
      lines << %(  src: url("#{input.file}") format("woff2"),\n       url("#{woff}") format("woff");)
      "@font-face {\n#{lines.join("\n")}\n}"
    end

    # 官方預設 woff2；我方只 host woff2 ⇒ 'woff' 請求同回 woff2 URL（⚪ 97 §1.3）。
    def font_url(input, _format = "woff2")
      input.is_a?(ThemeEngine::FontDrop) ? input.file.to_s : ""
    end

    # 官方值域（97 §1.1）：style＝normal/italic/oblique；weight＝100..900/normal/
    # bold/±100..±900/lighter/bolder（CSS font-weight 相對規則）。
    # 🔴 變體不存在 ⇒ **nil**（官方逐字；Ella italic 缺席鏈靠這個 nil 靜默——
    # font_face(nil) 空輸出）。
    def font_modify(input, prop = nil, value = nil)
      return nil unless input.is_a?(ThemeEngine::FontDrop)

      case prop.to_s
      when "style"
        target = value.to_s
        return nil unless %w[normal italic oblique].include?(target)

        ThemeEngine::FontLibrary.variant(input, style: target, weight: input.weight)
      when "weight"
        target = modify_weight(input.weight, value.to_s)
        target && ThemeEngine::FontLibrary.variant(input, style: input.style, weight: target)
      end
    end

    # ---- color -------------------------------------------------------------
    def color_brightness(input)
      m = input.to_s.match(/#?(..)(..)(..)/) or return 128
      r, g, b = m.captures.map { |x| x.to_i(16) }
      ((r * 299 + g * 587 + b * 114) / 1000.0).round(2)
    end

    # PR-3：alpha 分支實作（overlay 漸層關鍵——coverage 軸最高視覺缺口）；
    # 其餘鍵維持原樣（登記）。
    def color_modify(input, key = nil, value = nil)
      return input.to_s unless key.to_s == "alpha"

      drop = input.is_a?(ThemeEngine::ColorDrop) ? input : ThemeEngine::ColorDrop.new(input.to_s)
      "rgba(#{drop.red}, #{drop.green}, #{drop.blue}, #{css_alpha(value)})"
    rescue StandardError
      input.to_s
    end

    # alpha 的 CSS 數字形：整數值不帶 `.0`（hoko.vip：`color_modify: 'alpha', 0` ⇒ `rgba(0, 0, 0, 0)`；官方例 0.85 ⇒ `0.85`）
    def css_alpha(value)
      f = value.to_f
      f == f.floor ? f.to_i.to_s : f.to_s
    end
    # 引擎缺口 PR-6（官方 filters/color_to_hsl／color_to_rgb，取證 2026-09-02）：
    #   color_to_hsl "Converts a CSS color string to `HSL` format."，例 '#EA5AB9' ⇒ 'hsl(320, 77%, 64%)'，
    #   "If a color with an alpha component is provided, the color is converted to `HSLA` format."；
    #   color_to_rgb 例 ⇒ 'rgb(234, 90, 185)'（alpha ⇒ RGBA）。輸入收 #RGB／#RRGGBB／#RRGGBBAA／rgb(a)()；
    #   解析不出 ⇒ 原樣（不炸頁）。
    def color_to_hsl(input)
      parsed = parse_css_color(input) or return input.to_s
      r, g, b, a = parsed
      h, s, l = rgb_to_hsl(r, g, b)
      a < 1 ? "hsla(#{h}, #{s}%, #{l}%, #{a})" : "hsl(#{h}, #{s}%, #{l}%)"
    end

    def color_to_rgb(input)
      parsed = parse_css_color(input) or return input.to_s
      r, g, b, a = parsed
      a < 1 ? "rgba(#{r}, #{g}, #{b}, #{css_alpha(a)})" : "rgb(#{r}, #{g}, #{b})"
    end

    private def parse_css_color(input)
      s = input.to_s.strip
      if (m = s.match(/\A#(\h{3}|\h{4}|\h{6}|\h{8})\z/))
        hex = m[1]
        hex = hex.chars.map { |c| c * 2 }.join if hex.size <= 4
        alpha = hex.size == 8 ? (hex[6, 2].to_i(16) / 255.0).round(2) : 1
        [ hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16), alpha ]
      elsif (m = s.match(/\Argba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)\z/i))
        [ m[1].to_i, m[2].to_i, m[3].to_i, m[4] ? m[4].to_f : 1 ]
      end
    end

    private def rgb_to_hsl(r, g, b)
      rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
      max, min = [ rf, gf, bf ].max, [ rf, gf, bf ].min
      l = (max + min) / 2
      if max == min
        h = s = 0
      else
        d = max - min
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        sector = case max
        when rf then (gf - bf) / d + (gf < bf ? 6 : 0)
        when gf then (bf - rf) / d + 2
        else (rf - gf) / d + 4
        end
        h = sector * 60
      end
      [ h.round, (s * 100).round, (l * 100).round ]
    end

    def color_lighten(input, _p = 0) = input
    def color_darken(input, _p = 0) = input
    def color_mix(input, _o = nil, _p = 0) = input

    # ---- 平台雜項（stub 到不炸為止；miss 由 drops 層遙測）-------------------
    def structured_data(_input) = ""
    def payment_type_svg_tag(input, _o = {})
      %(<svg class="payment-icon placeholder-svg" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="#e8ded2"/><title>#{CGI.escapeHTML(input.to_s)}</title></svg>)
    end
    def payment_type_img_url(_input) = ""
    # E18（T4）：`{{ form | payment_button }}`（動態結帳按鈕）本尊逐字（hoko.vip 2026-09-05 商品頁 main，external-facts §G26）：
    #   <div data-shopify="payment-button" class="shopify-payment-button"> <shopify-accelerated-checkout recommended="null"
    #   fallback="{&quot;supports_subs&quot;:true,&quot;supports_def_opts&quot;:true,&quot;name&quot;:&quot;buy_it_now&quot;,&quot;wallet_params&quot;:{}}"
    #   access-token="{32 hex}" buyer-country="TW" buyer-locale="zh-CN" buyer-currency="HKD" variant-params="[{&quot;id&quot;:…,&quot;requiresShipping&quot;:true}]"
    #   shop-id="68893507687" enabled-flags="[&quot;a1d1f9a1&quot;]" disabled > <div class="shopify-payment-button__button" role="button" disabled
    #   aria-hidden="true" style="background-color: transparent; border: none"> <div class="shopify-payment-button__skeleton">&nbsp;</div> </div>
    #   </shopify-accelerated-checkout> </div>
    # 我方無錢包服務 ⇒ 出同形 disabled 骨架（本尊在無可用錢包時同樣停在骨架；E12 computed 對表 main 段無差）。access-token（本尊 storefront token）
    # 與 shop-id 是身分值：我方以店 id 導出穩定 32 hex／店 id，Normalizer 抹之；`enabled-flags` 本尊值照抄（語義未取得，91 §3.87 V）。
    # 無 product 脈絡（非商品表單）⇒ 空字串（既有）。
    def payment_button(_input, _o = {})
      product = @context["product"]
      variant = product.respond_to?(:selected_or_first_available_variant) ? product.selected_or_first_available_variant : nil
      return "" if variant.nil?

      r = @context.registers
      r[:runtime]&.payment_button_rendered! # E19：content_for_header 依此出模組形
      token = Storefront::AccessToken.for(r[:shop_id])
      fallback = CGI.escapeHTML(%({"supports_subs":true,"supports_def_opts":true,"name":"buy_it_now","wallet_params":{}}))
      vparams = CGI.escapeHTML(%([{"id":#{variant.id},"requiresShipping":#{variant.requires_shipping ? 'true' : 'false'}}]))
      flags = CGI.escapeHTML(%(["a1d1f9a1"]))
      %(<div data-shopify="payment-button" class="shopify-payment-button"> <shopify-accelerated-checkout recommended="null" fallback="#{fallback}" ) +
        %(access-token="#{token}" buyer-country="#{r[:buyer_country]}" buyer-locale="#{r[:buyer_locale]}" buyer-currency="#{r[:currency]}" ) +
        %(variant-params="#{vparams}" shop-id="#{r[:shop_id]}" enabled-flags="#{flags}" disabled > ) +
        %(<div class="shopify-payment-button__button" role="button" disabled aria-hidden="true" style="background-color: transparent; border: none"> ) +
        %(<div class="shopify-payment-button__skeleton">&nbsp;</div> </div> </shopify-accelerated-checkout> </div>)
    end
    def payment_terms(_input) = ""
    def login_button(_input, _o = {}) = ""
    def avatar(_input) = ""
    def customer_login_link(input) = link_to(input, "/account/login")
    def customer_logout_link(input) = link_to(input, "/account/logout")
    # PR-16（官方 "Returns the URL for a given external video…specify
    # parameters for the external video player"；YouTube embed 官方例
    # `youtube.com/embed/{id}?…`，取證 2026-09-02。Vimeo embed host＝
    # player.vimeo.com/video/{id}——Vimeo 官方嵌入形，Shopify 頁未逐字給出，
    # 標 V）。輸入收 external_video media drop（host/external_id）或
    # video_url setting drop（type/id）；參數原樣編 query。
    def external_video_url(input, params = {})
      type, vid, title = video_identity(input)
      return input.to_s if vid.nil?

      base = type == "vimeo" ? "https://player.vimeo.com/video/#{vid}"
                             : "https://www.youtube.com/embed/#{vid}"
      query = (params || {}).map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
      ExternalVideoUrlResult.new(query.empty? ? base : "#{base}?#{query}",
                                 video_type: type, title: title)
    end

    # 官方 iframe 形（例輸出逐字：frameborder="0"、allow="accelerometer;
    # autoplay; encrypted-media; gyroscope; picture-in-picture"、
    # allowfullscreen、src、title）；額外參數 ⇒ HTML 屬性。
    def external_video_tag(input, attrs = {})
      url = input.is_a?(ExternalVideoUrlResult) ? input : external_video_url(input)
      return "" unless url.is_a?(ExternalVideoUrlResult)

      extra = (attrs || {}).map { |k, v| %( #{k}="#{ERB::Util.html_escape(v.to_s)}") }.join
      title = ERB::Util.html_escape(url.title.to_s)
      %(<iframe frameborder="0" allow="accelerometer; autoplay; encrypted-media; ) +
        %(gyroscope; picture-in-picture" allowfullscreen="allowfullscreen" ) +
        %(src="#{ERB::Util.html_escape(url)}" title="#{title}"#{extra}></iframe>)
    end

    # video 媒體物件（sources）或 URL 字串（ours 救援形——Ella video snippet
    # 支援 URL 形）⇒ <video>。布林參數出布林屬性；nil 值略過。
    def video_tag(input, opts = {})
      src = if input.respond_to?(:sources) && input.sources.respond_to?(:first)
              entry = input.sources.first
              entry.respond_to?(:url) ? entry.url : entry && entry["url"]
      else
              s = input.to_s
              s if s.match?(%r{\Ahttps?://|\A/})
      end
      return "" if src.to_s.empty?

      attrs = +""
      (opts || {}).each do |k, v|
        next if v.nil?
        key = k.to_s
        next if key == "image_size" # 媒體管線參數，不落 HTML
        if v == true then attrs << %( #{key})
        elsif v == false then next
        else attrs << %( #{key}="#{ERB::Util.html_escape(v.to_s)}")
        end
      end
      %(<video src="#{ERB::Util.html_escape(src)}"#{attrs}></video>)
    end
    def media_tag(_input, _o = {}) = ""
    def model_viewer_tag(_input, _o = {}) = ""
    def article_img_url(_i, _s = nil) = ""
    # PR-3：從 cart items 加總（先前恆 0——「已在購物車 N 件」全失真）。
    def item_count_for_variant(cart, variant_id)
      items = if cart.respond_to?(:items) then cart.items
      elsif cart.is_a?(Hash) then cart["items"]
      end
      Array(items).sum do |item|
        vid = item.respond_to?(:variant_id) ? item.variant_id : item["variant_id"]
        qty = item.respond_to?(:quantity) ? item.quantity : item["quantity"]
        vid.to_i == variant_id.to_i ? qty.to_i : 0
      end
    rescue StandardError
      0
    end
    def line_items_for(_cart, _obj) = []
    def format_address(_a) = ""
    # PR-13（官方 "Formats a given unit price and measurement"，輸出形
    # `$50.00/kg`；reference_value>1 ⇒ `/100ml`。shopify.dev filters/
    # unit_price_with_measurement 2026-09-02）。輸入＝integer cents（鐵律 3）；
    # measurement 收 Hash/Drop（reference_value/reference_unit），nil 寬容回空。
    def unit_price_with_measurement(input, measurement = nil)
      return "" if input.nil?

      price = money(input) # 店級格式（D81）
      ref_value = dig_measurement(measurement, "reference_value")
      ref_unit = dig_measurement(measurement, "reference_unit")
      return price if ref_unit.to_s.empty?

      ref = ref_value.to_i > 1 ? "#{ref_value.to_i}#{ref_unit}" : ref_unit.to_s
      "#{price}/#{ref}"
    end
    def weight_with_unit(input, _u = nil) = "#{input} g"
    def stylesheet(_input) = ""
    def distance_from(_i, _o) = nil
    def sort_natural(input, _p = nil) = input.respond_to?(:sort) ? Array(input).sort_by { |x| x.to_s.downcase } : input

    # (type, id, title)；認得 external_video media drop 與 video_url drop
    def video_identity(input)
      if input.respond_to?(:external_id) && input.external_id
        [ input.respond_to?(:host) ? input.host.to_s : "youtube", input.external_id,
          input.respond_to?(:alt) ? input.alt : nil ]
      elsif input.respond_to?(:type) && input.respond_to?(:id) &&
            %w[youtube vimeo].include?(input.type.to_s)
        [ input.type.to_s, input.id, nil ]
      else
        [ nil, nil, nil ]
      end
    end

    def dig_measurement(measurement, key)
      return nil if measurement.nil?
      return measurement[key] if measurement.respond_to?(:[])

      measurement.respond_to?(key) ? measurement.public_send(key) : nil
    end

    private

    # font_modify weight 值 → 目標 weight（97 §1.1 官方值域；lighter/bolder＝CSS
    # font-weight 相對規則表）。非法值 ⇒ nil（fail-closed，font_modify 回 nil）。
    def modify_weight(current, value)
      case value
      when /\A[+-]\d00\z/ then current + value.to_i
      when /\A\d00\z/ then value.to_i
      when "normal" then 400
      when "bold" then 700
      when "lighter"
        case current
        when 100..500 then 100
        when 600..700 then 400
        else 700
        end
      when "bolder"
        case current
        when 100..300 then 400
        when 400..500 then 700
        else 900
        end
      end
    end
  end
end
