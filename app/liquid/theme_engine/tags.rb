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
        # 🔴 鍵允許帶點（`closest.product: product`——Ella 商品卡的傳遞形；官方
        #   content_for 可傳任意參數給 static block）。原 `\w+` 會把
        #   `closest.product` 錯切成 `product`，商品卡整卡拿不到商品（步 12a 生產實錘）。
        (m[3] || "").scan(/([\w.]+)\s*:\s*(?:(['"])(.*?)\2|([\w.\-]+))/) do |k, _q, str, var|
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
          # `closest.*` 參數 ⇒ block 子樹的 closest 覆寫層；其餘任意參數 ⇒ block 內
          # 變數（官方："You can pass additional arbitrary parameters (such as
          # `color`) that will be accessible within the static block."）。
          closest_overrides = {}
          extra_assigns = {}
          @attrs.each do |key, value|
            next if %w[id type].include?(key)

            if key.start_with?("closest.")
              closest_overrides[key.delete_prefix("closest.")] = evaluate_attr(value, context)
            else
              extra_assigns[key] = evaluate_attr(value, context)
            end
          end
          runtime.render_block(id, bdata, context, static: true,
                               closest_overrides:, extra_assigns:)
        else ""
        end
      end

      def evaluate_attr(v, context) = v.is_a?(String) ? v : context.evaluate(v)
    end

    # {% style %} → <style> 包裹（區塊作用域 CSS 的主要載體）。
    class StyleTag < Liquid::Block
      def render(context) = "<style>#{super}</style>"
    end

    # {% stylesheet %}／{% javascript %}：section 級資產（PR-3——本尊語義＝
    # 逐 section 收集、全頁去重、聚合輸出；先前整塊吞掉 ⇒ 商品頁 tabs 等
    # 互動 JS 與裝飾 CSS 遺失，coverage 軸點名）。收進 runtime 聚合桶，
    # PageRenderer 頁尾一次輸出。
    # {% schema %} 的載入期剝離保險網仍用吞掉語義。
    class Swallow < Liquid::Block
      def render(_context) = ""
    end

    class SectionAssetTag < Liquid::Block
      def initialize(tag_name, markup, options)
        super
        @kind = tag_name == "javascript" ? :js : :css
      end

      def render(context)
        content = super.to_s
        context.registers[:runtime]&.collect_section_asset(@kind, content)
        ""
      end
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
        # 位置參數（官方 `{% form 'new_comment', article %}`——步 14c）：
        # 逗號後第一個裸識別字＝資源變數，渲染期求值。
        @resource_expr = markup[/\A\s*(?:['"])\w+(?:['"])\s*,\s*([a-zA-Z_][\w.]*)/, 1]
          &.then { |raw| Liquid::Expression.parse(raw) }
        @attrs = markup.scan(/(?:,|\s)(\w+)\s*:\s*(['"])(.*?)\2/).map { |k, _q, v| [ k, v ] }.to_h
      end

      def render(context)
        inner = nil
        context.stack do
          context["form"] = ThemeEngine::FormDrop.new
          inner = super
        end
        extra = @attrs.map { |k, v| %(#{k.tr('_', '-')}="#{v}") }.join(" ")
        action = form_action(context)
        %(<form method="post" action="#{action}" accept-charset="UTF-8" #{extra}><input type="hidden" name="form_type" value="#{@type}"><input type="hidden" name="utf8" value="✓">#{inner}</form>)
      end

      # new_comment 的 action＝該文章的 comment_post_url（98 §2 真店抓包形：
      # /blogs/{blog}/{article}/comments）；其餘型維持靜態表。
      def form_action(context)
        if @type == "new_comment" && @resource_expr
          target = context.evaluate(@resource_expr)
          return target.comment_post_url if target.respond_to?(:comment_post_url)
        end
        ACTIONS.fetch(@type, "/")
      end
    end

    # {% paginate expr by size %}（步 12 真分頁；96 §1）。
    #
    # ①`by` 的右值可為變數（Ella：`by limit`、`by section.settings.products_per_page`）
    #   ⇒ 渲染期求值；clamp 1..250（官方 "between 1 and 250"）。
    # ②expr 求值出的物件若支援 `paginate!(page:, per:)`（CollectionProductsDrop／
    #   CollectionsDrop 等懶載 drop），同一物件改回該頁窗——block 內
    #   `{% for x in expr %}` 重新求值拿到的是同一 memoized drop ⇒ 迭代頁窗。
    # ③頁碼＝`page` URL 參數（registers[:request_params]）；深度上限 25,000
    #   （官方）由 drop 端 offset clamp 承擔。
    # ④`window_size:` 參數吞掉不實作（Dawn 有用；窗形由 PaginateDrop 固定——登記）。
    class PaginateTag < Liquid::Block
      MAX_PAGE_SIZE = 250

      def initialize(tag_name, markup, options)
        super
        body = markup.sub(/window_size:\s*\S+/, "")
        if body =~ /\A\s*(.+?)\s+by\s+(\S+)\s*\z/m
          @expr = Liquid::Expression.parse(Regexp.last_match(1).strip)
          @by = Liquid::Expression.parse(Regexp.last_match(2))
        else
          @expr = Liquid::Expression.parse(body.strip)
          @by = 24
        end
      end

      def render(context)
        target = context.evaluate(@expr)
        per = context.evaluate(@by).to_i
        per = 24 unless per.positive?
        per = MAX_PAGE_SIZE if per > MAX_PAGE_SIZE

        request_params = context.registers[:request_params] || {}
        page = request_params["page"].to_s[/\A\d+\z/]&.to_i || 1
        page = 1 unless page.positive?

        items = if target.respond_to?(:paginate!)
          target.paginate!(page: page, per: per)
        elsif target.respond_to?(:size)
          target.size
        else
          0
        end

        path = context.registers[:request_path].to_s
        builder = lambda do |n|
          # sections/section_id＝Section Rendering 內部參數，不進買家可點 URL；
          # view/sort_by/q 等要跨頁保留（替代模板與排序在翻頁後不得掉）。
          query = request_params.except("sections", "section_id").merge("page" => n.to_s)
          query.delete("page") if n == 1
          query.empty? ? path : "#{path}?#{Rack::Utils.build_query(query)}"
        end

        inner = nil
        context.stack do
          context["paginate"] = ThemeEngine::PaginateDrop.new(
            items: items, page_size: per, current_page: page, url_builder: builder
          )
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
    # {% layout 'name' %}／{% layout none %}（官方 tags/layout；預設 theme.liquid）。
    # render 時把選擇寫進 registers[:layout_override]——PageRenderer 的
    # .liquid 模板路徑於 body 渲染後讀取：false＝不包 layout、字串＝指名
    # layout/{name}.liquid。JSON 模板走 "layout" 鍵（PR-10），互不相涉。
    class LayoutTag < Liquid::Tag
      def initialize(tag_name, markup, options)
        super
        m = markup.strip
        @value = if m == "none" then false
        elsif (q = m[/\A['"]([^'"]+)['"]\z/, 1]) then q
        end
      end

      def render(context)
        # 🔴 Liquid 5 Registers#[]= 寫 overlay、外層 hash 讀不回 ⇒ 經可變載體
        carrier = context.registers[:layout_capture]
        carrier[:value] = @value if carrier && !@value.nil?
        ""
      end
    end

    # {% render <var> %} 變數形（步 13b；97 §2）。
    #
    # ①Liquid 原生 Render 只收 quoted string ⇒ Ella `{% render child_block %}`
    #   **parse fatal**（97 §2 實測），整檔編譯失敗。live 真引擎接受變數形且值
    #   可為 block（app blocks 官方頁的 `{% render block %}` 同形）。
    # ②語義：值＝BlockDrop ⇒ 以該 block 自身 data 走 runtime.render_block
    #   （隔離語義同 content_for "block"）；其他值 ⇒ 空輸出＋遙測（不炸頁）。
    # ③quoted string 形完全走原生 super（snippet 隔離語義不動）。
    class RenderTag < Liquid::Render
      BARE_VAR = /\A\s*([a-zA-Z_][\w-]*(?:\.[\w-]+)*)\s*\z/

      def initialize(tag_name, markup, options)
        if (m = markup.match(BARE_VAR))
          @block_expr = Liquid::Expression.parse(m[1])
          # 跳過 Render 的 quoted-string 解析（會 raise）——直接 Tag 層初始化。
          Liquid::Tag.instance_method(:initialize).bind_call(self, tag_name, markup, options)
        else
          super
        end
      end

      def render_to_output_buffer(context, output)
        return super if @block_expr.nil?

        target = context.evaluate(@block_expr)
        runtime = context.registers[:runtime]
        if target.is_a?(ThemeEngine::BlockDrop) && runtime
          output << runtime.render_block(target.id, target.data, context)
        else
          ThemeEngine.count_miss("render.non_block_variable")
        end
        output
      end
    end

    # @param target [Liquid::Environment]
    def self.register!(target)
      target.register_tag("content_for", ContentFor)
      target.register_tag("style", StyleTag)
      target.register_tag("stylesheet", SectionAssetTag)
      target.register_tag("javascript", SectionAssetTag)
      target.register_tag("doc", DocTag)
      target.register_tag("form", FormTag)
      target.register_tag("paginate", PaginateTag)
      target.register_tag("section", SectionTag)
      target.register_tag("sections", SectionsTag)
      target.register_tag("layout", LayoutTag)
      target.register_tag("render", RenderTag) # 步 13b：覆蓋原生——加變數形（block）
      target.register_tag("schema", Swallow) # 保險網——正常已於載入期剝離
    end
  end
end
