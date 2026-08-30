# frozen_string_literal: true

# 平台層 tags（包 30；PoC 9 tags 生產移植——核心＝content_for 的 blocks 機制，24 §2.4／27 §6）。
module ThemeEngine
  module Tags
    # {% content_for 'blocks' %} / {% content_for 'block', type: 'x', id: 'y' %}
    class ContentFor < Liquid::Tag
      SYNTAX = /\A\s*(['"])(\w+)\1\s*(?:,(.*))?\z/m

      def initialize(tag_name, markup, options)
        super
        m = markup.match(SYNTAX) or raise Liquid::SyntaxError, "content_for 語法錯誤: #{markup}"
        @kind = m[2]
        @attrs = {}
        (m[3] || "").scan(/(\w+)\s*:\s*(?:(['"])(.*?)\2|([\w.\-]+))/) do |k, _q, str, var|
          @attrs[k] = str || Liquid::Expression.parse(var)
        end
      end

      def render(context)
        runtime = context.registers[:runtime]
        frame   = context.registers[:frame]
        return "" unless runtime && frame

        case @kind
        when "blocks"
          order = frame["block_order"] || []
          order.map do |bid|
            bdata = (frame["blocks"] || {})[bid] or next ""
            runtime.render_block(bid, bdata, context)
          end.join
        when "block"
          id   = evaluate_attr(@attrs["id"], context).to_s
          type = evaluate_attr(@attrs["type"], context).to_s
          bdata = (frame["blocks"] || {})[id] || { "type" => type, "settings" => {} }
          runtime.render_block(id, bdata, context, static: true)
        else ""
        end
      end

      def evaluate_attr(v, context) = v.is_a?(String) ? v : context.evaluate(v)
    end

    # {% style %} → <style> 包裹（區塊作用域 CSS 的主要載體）。
    class StyleTag < Liquid::Block
      def render(context) = "<style>#{super}</style>"
    end

    # {% stylesheet %}／{% javascript %}：section 級資產（由 asset_url 載入 ⇒ 渲染期吞掉）。
    class Swallow < Liquid::Block
      def render(_context) = ""
    end

    # {% doc %}…{% enddoc %}（LiquidDoc）。內容非合法 Liquid ⇒ 逐 token 吞掉。
    class DocTag < Liquid::Block
      def parse(tokens)
        while (t = tokens.shift)
          return if t =~ /\{%-?\s*enddoc\s*-?%\}/
        end
      end

      def render(_context) = ""
    end

    # {% form 'type', obj, attr: val %} → 最小 <form> 包裹（action 表隨結帳線擴充）。
    class FormTag < Liquid::Block
      ACTIONS = { "product" => "/cart/add", "contact" => "/contact", "customer_login" => "/account/login",
                  "create_customer" => "/account", "recover_customer_password" => "/account/recover",
                  "currency" => "/cart/update", "localization" => "/localization",
                  "customer" => "/contact", "new_comment" => "/blogs" }.freeze

      def initialize(tag_name, markup, options)
        super
        @type = markup[/\A\s*(['"])(\w+)\1/, 2] || "contact"
        @attrs = markup.scan(/(?:,|\s)(\w+)\s*:\s*(['"])(.*?)\2/).map { |k, _q, v| [ k, v ] }.to_h
      end

      def render(context)
        inner = nil
        context.stack do
          context["form"] = ThemeEngine::FormDrop.new
          inner = super
        end
        extra = @attrs.map { |k, v| %(#{k.tr('_', '-')}="#{v}") }.join(" ")
        %(<form method="post" action="#{ACTIONS.fetch(@type, '/')}" accept-charset="UTF-8" #{extra}><input type="hidden" name="form_type" value="#{@type}"><input type="hidden" name="utf8" value="✓">#{inner}</form>)
      end
    end

    # {% paginate expr by N %}（v1 單頁 drop；真分頁隨前台包 33 keyset 接線）。
    class PaginateTag < Liquid::Block
      def initialize(tag_name, markup, options)
        super
        @size = markup[/by\s+(\d+)/, 1]&.to_i || 24
      end

      def render(context)
        inner = nil
        context.stack do
          context["paginate"] = ThemeEngine::PaginateDrop.new(page_size: @size)
          inner = super
        end
        inner
      end
    end

    # {% section 'name' %} → 靜態 section（設定在 settings_data.current.sections，27 §4）。
    class SectionTag < Liquid::Tag
      def initialize(tag_name, markup, options)
        super
        @name = markup[/(['"])([\w\-]+)\1/, 2]
      end

      def render(context)
        rt = context.registers[:runtime] or return ""
        rt.render_static_section(@name)
      end
    end

    # {% sections 'group' %} → section group；缺檔寬容（25 坑 #12）。
    class SectionsTag < Liquid::Tag
      def initialize(tag_name, markup, options)
        super
        @name = markup[/(['"])([\w\-]+)\1/, 2]
      end

      def render(context)
        rt = context.registers[:runtime] or return ""
        rt.render_section_group(@name)
      end
    end

    # {% layout none %} → 路由層職責，渲染期 no-op。
    class LayoutTag < Liquid::Tag
      def render(_context) = ""
    end

    # @param target [Liquid::Environment]
    def self.register!(target)
      target.register_tag("content_for", ContentFor)
      target.register_tag("style", StyleTag)
      target.register_tag("stylesheet", Swallow)
      target.register_tag("javascript", Swallow)
      target.register_tag("doc", DocTag)
      target.register_tag("form", FormTag)
      target.register_tag("paginate", PaginateTag)
      target.register_tag("section", SectionTag)
      target.register_tag("sections", SectionsTag)
      target.register_tag("layout", LayoutTag)
      target.register_tag("schema", Swallow) # 保險網——正常已於載入期剝離
    end
  end
end
