# frozen_string_literal: true

# 平台層 filters（包 30；PoC ~70 filters 生產移植；對照 docs/research/26 §3）。
#
# 🔴 money 族：輸入＝**integer cents**（鐵律 3 儲存尺度）；顯示一律兩位小數
#   （2026-08-12 裁定二）。符號經 registers[:money_symbol]（v1 由 shop.store_currency
#   解析；完整 locale 格式鏈＝包 34，91 §3.48 登記）。
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

    def stylesheet_tag(input, opts = {})
      media = opts.is_a?(Hash) ? opts["media"] : opts
      %(<link rel="stylesheet" href="#{input}"#{media.is_a?(String) ? %( media="#{media}") : ''}>)
    end

    def script_tag(input) = %(<script src="#{input}" defer></script>)

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
      when nil then placeholder_url(w, h, "image")
      else
        s = input.to_s
        if s.start_with?("shopify://") || s.empty?
          placeholder_url(w, h, File.basename(s.sub("shopify://", "")))
        else
          s
        end
      end
    end
    alias_method :img_url, :image_url

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

    def placeholder_svg_tag(input, cls = nil)
      %(<svg class="#{cls} placeholder-svg" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="#e8ded2"/><title>#{CGI.escapeHTML(input.to_s)}</title></svg>)
    end

    # ---- money（integer cents → 字串）--------------------------------------
    def money(input) = format_money(input, "%<sym>s%<amt>s")
    def money_with_currency(input)
      cur = @context.registers[:currency] || ""
      "#{format_money(input, '%<sym>s%<amt>s')} #{cur}".rstrip
    end
    def money_without_currency(input) = format_money(input, "%<amt>s")
    def money_without_trailing_zeros(input) = format_money(input, "%<sym>s%<amt>s").sub(/\.00\z/, "")

    def format_money(input, pattern)
      sym = @context.registers[:money_symbol] || "$"
      amt = format("%.2f", input.to_f / 100.0).gsub(/\B(?=(\d{3})+(?!\d))/, ",")
      format(pattern, sym: sym, amt: amt)
    end

    # ---- string / misc -----------------------------------------------------
    def handleize(input) = input.to_s.downcase.gsub(/[^a-z0-9\p{Han}]+/, "-").gsub(/\A-|-\z/, "")
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

    def date(input, fmt = "%Y-%m-%d")
      t = input.is_a?(String) ? Time.zone.parse(input) : input
      (t || Time.zone.now).strftime(fmt.to_s)
    rescue StandardError
      input.to_s
    end

    def pluralize(input, singular, plural) = input.to_i == 1 ? singular : plural
    def default_errors(_input) = ""
    def highlight(input, _q = nil) = input
    def url_param_escape(input) = CGI.escape(input.to_s)
    def link_to(input, url, _title = nil) = %(<a href="#{url}">#{input}</a>)
    def link_to_vendor(input) = %(<a href="/collections/vendors?q=#{CGI.escape(input.to_s)}">#{input}</a>)
    def url_for_vendor(input) = "/collections/vendors?q=#{CGI.escape(input.to_s)}"
    def link_to_type(input) = %(<a href="/collections/types?q=#{CGI.escape(input.to_s)}">#{input}</a>)
    def link_to_tag(input, tag) = %(<a href="#{tag}">#{input}</a>)
    def within(input, _c) = input.to_s

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
      lines << %(  src: url("#{input.file}") format("woff2");)
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
      "rgba(#{drop.red}, #{drop.green}, #{drop.blue}, #{value.to_f})"
    rescue StandardError
      input.to_s
    end
    def color_to_rgb(input) = input
    def color_lighten(input, _p = 0) = input
    def color_darken(input, _p = 0) = input
    def color_mix(input, _o = nil, _p = 0) = input

    # ---- 平台雜項（stub 到不炸為止；miss 由 drops 層遙測）-------------------
    def structured_data(_input) = ""
    def payment_type_svg_tag(input, _o = {}) = placeholder_svg_tag(input, "payment-icon")
    def payment_type_img_url(_input) = ""
    def payment_button(_input, _o = {}) = ""
    def payment_terms(_input) = ""
    def login_button(_input, _o = {}) = ""
    def avatar(_input) = ""
    def customer_login_link(input) = link_to(input, "/account/login")
    def customer_logout_link(input) = link_to(input, "/account/logout")
    def external_video_url(input, _o = {}) = input.to_s
    def external_video_tag(_input, _o = {}) = ""
    def video_tag(_input, _o = {}) = ""
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

      price = format_money(input, "%<sym>s%<amt>s")
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
