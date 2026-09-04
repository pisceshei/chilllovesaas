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

    # {% style %} → `<style data-shopify>` 包裹（區塊作用域 CSS 的主要載體）。官方逐字（tags/style，2026-09-03）：
    # "Generates an HTML <style> tag with an attribute of data-shopify."；hoko.vip 全頁 `<style data-shopify>` 逐字。
    class StyleTag < Liquid::Block
      def render(context) = "<style data-shopify>#{super}</style>"
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

    # {% form 'type'[, resource][, key: value …] %}（官方 tags/form，取證 2026-09-02）。
    #
    # ①opening tag **逐型固定**（TYPES）：action／預設 id／class／enctype／型別 data-* 與
    #   型別專屬隱藏欄（`product-id`／`guest`／`_method`／`return_to`）。
    # ②主題參數：key 允許 `[\w-]+`（`data-*`／`aria-*`／`novalidate`／`style`／`is`），
    #   值可為字串字面或**變數**（Ella `id: formId`、Kalles `id: form_id`、`style: form_styles`）
    #   ——渲染期求值，nil 值的參數不輸出。原實作只吃引號字串 ⇒ 變數 id 整個被丟
    #   （hoko 稽核候選「`{% form %}` 丟變數 `id:`」）。主題給的 id／class **取代**預設：
    #   真店 hoko.vip（2026-09-02）`customer` 型預設 class `contact-form`，Ella 傳
    #   `class: 'email-signup__form'` 後輸出只剩後者。
    # ③contact／customer 的 action fragment 跟隨**生效 id**（真店逐字
    #   `action="/contact#EmailSignup-…" id="EmailSignup-…"`）；new_comment 走該文章的
    #   comment_post_url（98 §2 真店抓包形 `/blogs/{blog}/{article}/comments`，無 fragment）。
    # ④屬性序照真店：method, action, id, accept-charset, 型別 data-*, class, enctype,
    #   其餘主題參數；隱藏欄 `<input type="hidden" … />` 自閉形、每個獨立一行（真店逐字）。
    # ⑤`return_to`：官方 "Accepts `back`, relative paths, or routes attributes"；currency／
    #   localization 型未給時預設當前路徑（registers[:request_path]）。`back` 的伺服端展開
    #   形＝未取得，先原樣輸出。
    # ⑥`form` 物件依型別宣告屬性——見 FormDrop。
    class FormTag < Liquid::Block
      # 官方每型的固定形；缺鍵者不輸出該屬性。product 的 id 官方形 `product_form_[id]`，
      # customer_address 新地址 `address_form_new`（既有地址形＝`address_form_{id}`，未取得
      # 官方逐字，依 new 形類推並登記）。
      TYPES = {
        "activate_customer_password" => { action: "/account/activate" },
        "cart" => { action: "/cart", id: "cart_form", class: "shopify-cart-form", enctype: "multipart/form-data" },
        "contact" => { action: "/contact", fragment: true, id: "contact_form", class: "contact-form" },
        "create_customer" => { action: "/account", id: "create_customer",
                               data: { "login-with-shop-sign-up" => "true" } },
        "currency" => { action: "/cart/update", id: "currency_form", class: "shopify-currency-form",
                        enctype: "multipart/form-data", return_to: true },
        "customer" => { action: "/contact", fragment: true, id: "contact_form", class: "contact-form" },
        "customer_address" => { action: "/account/addresses", id: "address_form_new" },
        "customer_login" => { action: "/account/login", id: "customer_login",
                              data: { "login-with-shop-sign-in" => "true" } },
        "guest_login" => { action: "/account/login", id: "customer_login_guest", hidden: { "guest" => "true" } },
        "localization" => { action: "/localization", id: "localization_form", class: "shopify-localization-form",
                            enctype: "multipart/form-data", hidden: { "_method" => "put" }, return_to: true },
        "new_comment" => { action: "/blogs", id: "comment_form", class: "comment-form" },
        "product" => { action: "/cart/add", id: "product_form_%{id}", class: "shopify-product-form",
                       enctype: "multipart/form-data", resource_hidden: "product-id" },
        "recover_customer_password" => { action: "/account/recover" },
        "reset_customer_password" => { action: "/account/reset" },
        "storefront_password" => { action: "/password", id: "login_form", class: "storefront-password-form" }
      }.freeze

      # `key: 'str'`／`key: "str"`／`key: expr`（expr＝到下一個逗號為止的裸運算式）。
      PARAM = /([\w-]+)\s*:\s*(?:(['"])(.*?)\2|([^,]+?))\s*(?=,|\z)/

      def initialize(tag_name, markup, options)
        super
        @type = markup[/\A\s*(['"])(\w+)\1/, 2] || "contact"
        rest = markup.sub(/\A\s*(['"])\w+\1/, "")
        # 位置參數（官方 `{% form 'new_comment', article %}`／`{% form 'product', product %}`）：
        # 型別後第一個**不帶冒號**的裸識別字＝資源變數，渲染期求值。
        if (m = rest.match(/\A\s*,\s*([a-zA-Z_][\w.]*)\s*(?=,|\z)/))
          @resource_expr = Liquid::Expression.parse(m[1])
          rest = m.post_match
        end
        @params = rest.scan(PARAM).to_h { |k, _q, str, expr| [ k, str || Liquid::Expression.parse(expr) ] }
      end

      def render(context)
        spec = TYPES.fetch(@type, { action: "/" })
        resource = @resource_expr && context.evaluate(@resource_expr)
        params = @params.transform_values { |v| v.is_a?(String) ? v : context.evaluate(v) }.compact
        id = params.delete("id") || default_id(spec, resource)
        klass = params.delete("class") || spec[:class]
        return_to = params.delete("return_to")
        default_return = return_to.nil? && spec[:return_to]
        return_to = default_return_to(context) if default_return

        inner = nil
        context.stack do
          context["form"] = ThemeEngine::FormDrop.new(@type, id: id)
          inner = super
        end

        attrs = [ %(method="post"), %(action="#{form_action(context, spec, resource, id)}") ]
        attrs << %(id="#{h(id)}") if id
        attrs << %(accept-charset="UTF-8")
        (spec[:data] || {}).each { |k, v| attrs << %(data-#{k}="#{v}") }
        attrs << %(class="#{h(klass)}") if klass
        attrs << %(enctype="#{spec[:enctype]}") if spec[:enctype]
        params.each { |k, v| attrs << %(#{k}="#{h(v)}") }

        hidden = [ [ "form_type", @type ], [ "utf8", "✓" ] ]
        (spec[:hidden] || {}).each { |k, v| hidden << [ k, v ] }
        # E8b：product 型的 `product-id`／`section-id` 不在開頭——本尊放在 `</form>` 之前（尾端）；見下 tail。
        # E16：預設 return_to 的 `&` 本尊**不轉義**（hoko.vip 2026-09-04 逐字
        # `value="/collections/all?sort_by=price-ascending&section_id=…&page=2"`）⇒ 該值只轉 `"`／`<`／`>`
        # （本尊對這三個字元的處置＝未取得，91 §3.85）；主題明給的 return_to 照舊 h()。
        hidden << [ "return_to", default_return ? RawAmp.new(return_to) : return_to ] if return_to
        # 本尊逐字（hoko.vip 2026-09-03，customer／product／contact／customer_login 四形一致）：
        # `<form …>` 緊接 `<input type="hidden" name="form_type" value="…" /><input type="hidden" name="utf8" value="✓" />`
        # 再緊接內容，隱藏欄位之間與前後**無任何空白**。
        inputs = hidden.map { |k, v| %(<input type="hidden" name="#{k}" value="#{v.is_a?(RawAmp) ? v.escaped : h(v)}" />) }.join
        # E8b：本尊 product 表單尾端逐字（hoko.vip 2026-09-03 商品頁）：
        # `…</div><input type="hidden" name="product-id" value="{product.id}" /><input type="hidden" name="section-id" value="{section.id}" /></form>`
        # ——內容與隱藏欄之間無空白；section-id＝當前 section 完整 id（registers[:section_drop]）。
        tail = ""
        if spec[:resource_hidden] && resource.respond_to?(:id)
          tail = %(<input type="hidden" name="#{spec[:resource_hidden]}" value="#{h(resource.id)}" />)
          section = context.registers[:section_drop]
          tail += %(<input type="hidden" name="section-id" value="#{h(section.id)}" />) if section.respond_to?(:id) && section.id
        end
        %(<form #{attrs.join(' ')}>#{inputs}#{inner}#{tail}</form>)
      end

      private

      def h(value) = CGI.escapeHTML(value.to_s)

      # 預設 return_to 的值物件：`&` 保留、只轉 `"`／`<`／`>`（見 render 內註）。
      RawAmp = Struct.new(:value) do
        def escaped = value.to_s.gsub('"', "&quot;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      # E16 預設 `return_to`＝當前請求的路徑＋原始 query string（external-facts §G24，hoko.vip 2026-09-04 逐字）：
      #   `/?section_id=…` ⇒ `/?section_id=…`；`/en/?section_id=…`／`/en?section_id=…` ⇒ `/en?section_id=…`
      #   （前綴根**不帶尾斜線**）；`/collections/all?sort_by=price-ascending&section_id=…&page=2` 原順序原編碼照出。
      # registers[:request_path]＝帶前綴路徑（Runtime `"#{url_prefix}#{path}"`，前綴根為 `/en/`）；
      # request_query＝原始 query（nil／空 ⇒ 不加問號）。
      def default_return_to(context)
        base = context.registers[:request_path].to_s.presence || "/"
        base = base.chomp("/") if base.length > 1
        query = context.registers[:request_query].to_s
        query.empty? ? base : "#{base}?#{query}"
      end

      def default_id(spec, resource)
        template = spec[:id] or return nil
        return template unless template.include?("%{id}")

        resource.respond_to?(:id) ? format(template, id: resource.id) : nil
      end

      def form_action(context, spec, resource, id)
        if @type == "new_comment" && resource.respond_to?(:comment_post_url)
          return resource.comment_post_url
        end
        action = spec[:action]
        spec[:fragment] && id ? "#{action}##{id}" : action
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
      # 變數形（`{% render child_block %}`）另收 `, key: value` 參數（Ella `_lookbook.liquid`
      # `{% render child_block, enable_lookbook_all_items_layout: … %}`）⇒ 參數進 block 內變數（同 content_for 'block'）。
      BARE_VAR = /\A\s*([a-zA-Z_][\w-]*(?:\.[\w-]+)*)\s*(?:,(.*))?\z/m

      def initialize(tag_name, markup, options)
        if (m = markup.match(BARE_VAR))
          @block_expr = Liquid::Expression.parse(m[1])
          @block_params = m[2].to_s.scan(FormTag::PARAM).to_h { |k, _q, str, expr| [ k, str || Liquid::Expression.parse(expr) ] }
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
          extra = @block_params.transform_values { |v| v.is_a?(String) ? v : context.evaluate(v) }
          # LF 尾接由 render_block 統一處理（本尊每個 block 渲染後皆接 LF，見 Runtime#render_block）
          output << runtime.render_block(target.key, target.data, context, path: target.path, extra_assigns: extra)
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
