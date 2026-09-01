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
      opts.each { |k, v| s = s.gsub("%{#{k}}", v.to_s).gsub("{{ #{k} }}", v.to_s) } if opts.is_a?(Hash)
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
    def image_url(input, opts = {})
      w = opts.is_a?(Hash) ? opts["width"] : nil
      h = opts.is_a?(Hash) ? opts["height"] : nil
      case input
      when ThemeEngine::ImageDrop, ThemeEngine::FileImageDrop, ThemeEngine::PlaceholderImageDrop
        # PR-2 nil 防線：真圖 drop 但 url 缺（檔案列壞）⇒ 佔位，不出空 src
        input.url.presence ||
          ThemeEngine::PlaceholderImageDrop.new(label: "image", w: (w || 800).to_i, h: (h || w || 800).to_i).url
      when nil then ThemeEngine::PlaceholderImageDrop.new(label: "image", w: (w || 800).to_i, h: (h || w || 800).to_i).url
      else
        s = input.to_s
        if s.start_with?("shopify://") || s.empty?
          ThemeEngine::PlaceholderImageDrop.new(label: File.basename(s.sub("shopify://", "")),
                                                w: (w || 800).to_i, h: (h || w || 800).to_i).url
        else
          s
        end
      end
    end
    alias_method :img_url, :image_url

    def image_tag(input, opts = {})
      attrs = opts.is_a?(Hash) ? opts.map { |k, v| %(#{k.to_s.tr('_', '-')}="#{CGI.escapeHTML(v.to_s)}") }.join(" ") : ""
      src = input.respond_to?(:url) ? input.url : input.to_s
      # PR-2 nil 防線：空 src 出佔位（半殘鏈不出壞 <img src="">）
      src = ThemeEngine::PlaceholderImageDrop.new(label: "image", w: 800, h: 800).url if src.to_s.empty?
      %(<img src="#{src}" #{attrs}>)
    end
    alias_method :img_tag, :image_tag

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
    def unit_price_with_measurement(_u) = ""
    def weight_with_unit(input, _u = nil) = "#{input} g"
    def stylesheet(_input) = ""
    def distance_from(_i, _o) = nil
    def sort_natural(input, _p = nil) = input.respond_to?(:sort) ? Array(input).sort_by { |x| x.to_s.downcase } : input

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
