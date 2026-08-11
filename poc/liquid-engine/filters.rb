# frozen_string_literal: true
# CHILL LOVE PoC — 平台層 filters（對照 docs/research/26 §3；Ella 相容集 27 §5）

require "cgi"
require "json"

module ChillLove
  module Filters
    # ---- localization ------------------------------------------------------
    def t(input, opts = {})
      dict = @context.registers[:locale] || {}
      key = input.to_s
      val = key.split(".").reduce(dict) { |h, k| h.is_a?(Hash) ? h[k] : nil }
      val = opts["default"] if val.nil? && opts.is_a?(Hash)
      val = key.split(".").last.to_s.tr("_", " ") if val.nil?
      # 插值 %{var} 與簡易複數（PoC 級）
      if val.is_a?(Hash) # 複數鍵 {one:, other:}
        count = opts.is_a?(Hash) ? (opts["count"] || 1) : 1
        val = count.to_i == 1 ? (val["one"] || val["other"]) : (val["other"] || val["one"])
      end
      s = val.to_s
      opts.each { |k, v| s = s.gsub("%{#{k}}", v.to_s).gsub("{{ #{k} }}", v.to_s) } if opts.is_a?(Hash)
      s
    end

    # ---- assets / URLs -----------------------------------------------------
    def asset_url(input) = "assets/#{input}"
    def asset_img_url(input, _size = nil) = "assets/#{input}"
    def file_url(input) = "assets/#{input}"
    def file_img_url(input, _s = nil) = "assets/#{input}"
    def shopify_asset_url(input) = "assets/#{input}"
    def global_asset_url(input) = "assets/#{input}"

    def stylesheet_tag(input, opts = {})
      media = opts.is_a?(Hash) ? opts["media"] : opts
      %(<link rel="stylesheet" href="#{input}"#{media.is_a?(String) ? %( media="#{media}") : ''}>)
    end
    def script_tag(input) = %(<script src="#{input}" defer></script>)

    def inline_asset_content(input)
      fs = @context.registers[:runtime]
      fs ? fs.asset(input.to_s).to_s : ""
    end

    # ---- image -------------------------------------------------------------
    def image_url(input, opts = {})
      w = opts.is_a?(Hash) ? opts["width"] : nil
      h = opts.is_a?(Hash) ? opts["height"] : nil
      case input
      when ChillLove::ImageDrop then input.url
      when nil then ChillLove::ImageDrop.new(label: "image", w: (w || 800).to_i, h: (h || w || 800).to_i).url
      else
        s = input.to_s
        s.start_with?("shopify://") || s.empty? ?
          ChillLove::ImageDrop.new(label: File.basename(s.sub("shopify://", "")), w: (w || 800).to_i, h: (h || w || 800).to_i).url : s
      end
    end
    alias_method :img_url, :image_url

    def image_tag(input, opts = {})
      attrs = opts.is_a?(Hash) ? opts.map { |k, v| %(#{k.to_s.tr('_', '-')}="#{CGI.escapeHTML(v.to_s)}") }.join(" ") : ""
      src = input.is_a?(ChillLove::ImageDrop) ? input.url : input.to_s
      %(<img src="#{src}" #{attrs}>)
    end
    alias_method :img_tag, :image_tag

    def placeholder_svg_tag(input, cls = nil)
      %(<svg class="#{cls} placeholder-svg" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="#e8ded2"/><path d="M20 70 L45 40 L60 58 L72 47 L85 70 Z" fill="#a9502c" opacity=".4"/><circle cx="70" cy="30" r="8" fill="#a9502c" opacity=".4"/><title>#{CGI.escapeHTML(input.to_s)}</title></svg>)
    end

    # ---- money（integer cents → 字串；26 §3 money 族）----------------------
    def money(input) = format_money(input, "$%s")
    def money_with_currency(input) = format_money(input, "$%s USD")
    def money_without_currency(input) = format_money(input, "%s")
    def money_without_trailing_zeros(input)
      s = format_money(input, "$%s").sub(/\.00\z/, "")
      s
    end
    def format_money(input, pattern)
      cents = input.to_f
      format(pattern, format("%.2f", cents / 100.0).gsub(/\B(?=(\d{3})+(?!\d))/, ","))
    end

    # ---- string / misc -----------------------------------------------------
    def handleize(input) = input.to_s.downcase.gsub(/[^a-z0-9\p{Han}]+/, "-").gsub(/\A-|-\z/, "")
    alias_method :handle, :handleize
    def json(input)
      JSON.generate(input)
    rescue StandardError
      begin; JSON.generate(input.to_s); rescue StandardError; '""'; end
    end
    def time_tag(input, fmt = nil, _o = {}) = %(<time datetime="#{input}">#{input}</time>)
    def date(input, fmt = "%Y-%m-%d")
      t = input.is_a?(String) ? (Time.parse(input) rescue Time.now) : (input || Time.now)
      t.strftime(fmt.to_s)
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

    # ---- fonts -------------------------------------------------------------
    def font_face(input, _o = {}) = "/* @font-face #{input} (PoC stub) */"
    def font_url(_input, _f = nil) = ""
    def font_modify(input, _p = nil, _v = nil) = input

    # ---- color（Ella 用 color_brightness/color_modify）---------------------
    def color_brightness(input)
      m = input.to_s.match(/#?(..)(..)(..)/) or return 128
      r, g, b = m.captures.map { |x| x.to_i(16) }
      ((r * 299 + g * 587 + b * 114) / 1000.0).round(2)
    end
    def color_modify(input, _k = nil, _v = nil) = input
    def color_to_rgb(input) = input
    def color_lighten(input, _p = 0) = input
    def color_darken(input, _p = 0) = input
    def color_mix(input, _o = nil, _p = 0) = input

    # ---- 平台雜項（stub 到不炸為止）----------------------------------------
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
    def item_count_for_variant(_cart, _vid) = 0
    def line_items_for(_cart, _obj) = []
    def format_address(_a) = ""
    def unit_price_with_measurement(_u) = ""
    def weight_with_unit(input, _u = nil) = "#{input} g"
    def stylesheet(_input) = ""
    def distance_from(_i, _o) = nil
    def sort_natural(input, _p = nil) = input.respond_to?(:sort) ? Array(input).sort_by { |x| x.to_s.downcase } : input
  end
end
