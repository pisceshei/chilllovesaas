# frozen_string_literal: true

# 主題渲染 runtime（包 30；PoC ThemeRuntime 生產化——25 §6 的落地）。
#
# ①這是什麼：一次請求一個實例。載入來源檔（`FileSource`）＋ DB 覆寫
#   （`templates`／`theme_settings`），渲染 section／block／group，輸出整頁交給
#   `PageRenderer`。
# ②快取分層（25 §6 規則 2 的修訂）：
#   - **AST cache＝process 級**（`AST_CACHE`＋mutex，鍵=[source key, rel]）。
#     🔴 與 25 §6 寫的 Solid Cache 不同：`Liquid::Template` AST 非可靠序列化物
#     （Marshal 對 tag 內部狀態脆弱）⇒ 跨程序快取換成程序內記憶——來源目錄按
#     版本不可變，鍵不含 mtime。偏差登記 91 §3.48。
#   - 頁級快取＝包 33（快取 key 含 locale/currency，§1.5）。
# ③安全：drops 白名單（drops.rb 檔頭）＋ resource limits（limits.yml
#   `liquid_render_length_limit` 等三鍵）防 DoS。
# ④錯誤策略：production＝lax＋錯誤變 HTML 註解（compat 遙測）；缺檔寬容。
module ThemeEngine
  class MissingSourceError < StandardError; end

  class Runtime
    ENVIRONMENT = Liquid::Environment.build do |e|
      e.error_mode = :lax
      Tags.register!(e)
      e.register_filter(Filters)
      e.default_resource_limits = {
        render_length_limit: Limits.fetch(:theme_engine, :liquid_render_length_limit),
        render_score_limit: Limits.fetch(:theme_engine, :liquid_render_score_limit),
        assign_score_limit: Limits.fetch(:theme_engine, :liquid_assign_score_limit)
      }
    end

    AST_CACHE = {}
    AST_MUTEX = Mutex.new
    AST_CACHE_MAX = 1000 # 界限備忘：超過即整批清空（簡單防漏；正常主題檔數遠低於此）

    SCHEMA_RE = /\{%-?\s*schema\s*-?%\}(.*?)\{%-?\s*endschema\s*-?%\}/m

    attr_reader :theme, :shop, :errors, :warnings, :design_mode, :render_flags
    attr_accessor :closest

    # 寬容 JSON（25 坑 #11：第三方原始碼包帶註解/尾逗號；67 §F.3(b)1：locale 檔另見 BOM）。
    def self.tolerant_json(str)
      s = str.dup.force_encoding("UTF-8").scrub
      s.delete_prefix!("\uFEFF") # BOM（Ella locale 檔實證形態之一）
      s.gsub!(%r{/\*.*?\*/}m, "")
      s.gsub!(/,(\s*[}\]])/, '\1')
      JSON.parse(s)
    end

    # locale ⇒ t filter 走三層字典（build_locale_dict）；web_presence ⇒ localization 真值。
    # publication ⇒ collections/all_products 全域（步 12；nil＝維持 nil stub）；
    # params ⇒ paginate 頁碼與 sort_by（registers 過境，不進 assigns）；
    # template_suffix ⇒ `?view=` 替代模板的 template.suffix（96 §6）。
    def initialize(theme:, shop:, source: nil, url_prefix: "", locale: nil,
                   design_mode: false, page_type: "index", path: "/", host: nil,
                   cart_json: nil, asset_base: nil, web_presence: nil,
                   publication: nil, params: {}, template_suffix: nil,
                   draft_settings: nil, draft_sections: nil)
      @theme, @shop = theme, shop
      @cart_json = cart_json
      @publication = publication
      @params = params || {}
      @template_suffix = template_suffix
      @path = path
      # 公開店面傳 "/theme-assets"（包 33 後半）；預設維持登入預覽路徑（包 30 行為不變）。
      @asset_base = asset_base
      # 揮發旗標集（63 §D.5）：drop 讀到 volatile 欄位（inventory_quantity 等）時註冊，
      # 頁級快取據此把該頁 TTL 壓到 volatile_section_ttl_seconds——價格類走 key、數量類走 TTL 兜底。
      @render_flags = Set.new
      @source = source || Sources.resolve(theme)
      raise MissingSourceError, "主題 #{theme.name} 無檔案來源（Sources.resolve 回 nil）" if @source.nil?

      @url_prefix = url_prefix
      @design_mode = design_mode
      @errors, @warnings = [], []
      @assets = {}
      @closest = ClosestDrop.new

      # 🔴 PR-8（對表軸實錘）：全域 settings 與 section/block 同款三層解析——
      # schema defaults ← 檔案 current ← DB 覆寫。缺 defaults 時 Ella 的 inline
      # theme.config 塊會產出 `show: ,`（值缺失）⇒ SyntaxError ⇒ 整塊全滅、
      # 頁面停在 no-js（header 高 0 的真兇——本地 Chrome console 實錘）。
      schema = load_json("config/settings_schema.json") || []
      all_defs = schema.flat_map { |c| c.is_a?(Hash) ? (c["settings"] || []) : [] }
      @settings_data = schema_defaults(all_defs).merge(db_settings || file_settings_current)
      # PR-11：編輯器未儲存佈景設定的即時覆蓋（draft_page 全頁草稿渲染）
      @settings_data = @settings_data.merge(draft_settings) if draft_settings.is_a?(Hash)
      # PR-19：platform_customizations 不是 setting id——官方存於 settings_data
      # 的兄弟物件（dev json-templates 逐字）；我方收納在同一 settings hash 內
      # 但抽離出值面，SettingsDrop 不得曝露它。
      @platform_customizations = @settings_data.delete("platform_customizations") || {}
      # PR-11：未儲存 section entry 覆蓋（群組帶 {% sections %} 渲染也要吃到）
      @draft_sections = draft_sections.is_a?(Hash) ? draft_sections : {}
      @theme_types = extract_types(all_defs)
      # 三層字串（67 §F.3(a)；包 34）：③平台字串集 ← ②主題檔（default ← 截尾鏈 ← 精確）。
      # ①商家覆寫層＝租戶 translations 的 THEME_LOCALE_CONTENT 型，Resolve 尚不支援 ⇒
      # 待 ML 線擴 RESOURCE_TYPES 後接上（登記，包 34 worklog）。深併＝逐 key 解析
      # （F.3(b)3 兩套語言清單不對稱 ⇒ fallback 必須逐檔獨立，不得單一布林）。
      @locale_dict = build_locale_dict(locale)

      language = { "iso_code" => locale || "en", "endonym_name" => locale || "en", "root_url" => url_prefix.presence || "/" }
      @global_assigns = {
        "settings" => SettingsDrop.new(@settings_data, @theme_types, label: "settings", schemes: schemes_drop),
        "shop" => ShopDrop.new(shop),
        "cart" => CartDrop.new(currency: shop.store_currency, cart_json: @cart_json),
        "routes" => RoutesDrop.new(prefix: url_prefix),
        "request" => RequestDrop.new(page_type:, design_mode:, locale:, host:, path:),
        # localization 真值（67 §F.2 切換器規則）：有 presence（公開店面）＝開放∧已發布集；
        # 無 presence（預覽面／fragment）＝維持合成單語（包 30 行為不變）。
        "localization" => web_presence ? Storefront::LocalizationContext.drop(web_presence:, locale_tag: locale || "en")
                                       : LocalizationDrop.new(language:, available_languages: [ language ]),
        "linklists" => LinkListsDrop.new(shop, url_prefix: url_prefix),
        "template" => TemplateDrop.new(page_type, suffix: @template_suffix),
        # PR-10（對表軸實錘）：官方逐字「非分頁資源恆 1」——缺此全域時
        # nil != 1 令每頁 title 長出「– Page 」尾巴（密碼頁 diff 抓到的全頁性 bug）。
        "current_page" => (@params["page"].presence || 1).to_i,
        # PR-10（對表軸實錘）：官方逐字「非分頁資源恆 1」——缺此全域時
        # nil != 1 令每頁 title 長出「– Page 」尾巴（密碼頁 diff 抓到的全頁性 bug）。
        "content_for_header" => "",
        "canonical_url" => host ? "https://#{host}#{path}" : path,
        "page_title" => shop.name,
        "page_description" => nil,
        "current_tags" => nil,
        # 步 12（96 §1/§7）：有管道語境＝真 drop；無（舊呼叫面）＝維持 nil stub。
        "collections" => publication ? CollectionsDrop.new(shop:, publication:, url_prefix:, locale:) : nil,
        # 步 14c（98 §1）：blogs by-handle 全域。
        "blogs" => BlogsDrop.new(shop:, url_prefix:),
        # PR-13：pages/images by-key 全域（官方形，取證 2026-09-02）
        "pages" => PagesDrop.new(shop:, url_prefix:),
        "images" => ImagesDrop.new(shop:),
        # PR-13：powered_by_link——官方＝連 shopify.com 的署名連結；🔴 ours：
        # 品牌與連結換我方（鐵律 9），HTML 形對位（target/rel/文案結構）。
        "powered_by_link" => %(<a target="_blank" rel="nofollow" href="https://chilling.com.hk">Powered by CHILL LOVE</a>),
        "all_products" => publication ? AllProductsDrop.new(publication:, url_prefix:, locale:) : nil,
        "predictive_search" => nil,
        "recommendations" => nil,
        # 步 11：customer 顯式 nil stub——主題頁走頁快取（14 §F1-4 個人化不進
        # 快取），登入態注入需快取鍵分票，91 §3.57 登記；nil＝Ella 的
        # {% if customer %} 全走未登入分支（快取頁的正確形）。
        "customer" => nil,
        # 第三包（86 §7 差距 #3/#4）：快捷結帳鈕全域**顯式** stub（26 行 48/647 契約
        # ——v1 無 offsite provider ⇒ false/空；先前靠 miss-nil 碰巧 falsy，現落實）。
        "additional_checkout_buttons" => false,
        "content_for_additional_checkout_buttons" => "",
        # 運費試算表單的國家 select（Ella cart-shipping-calculator:28）：值域＝
        # active market ∩ 有費率 zone（85 §6 官方交集句，與結帳頁國家下拉同源——鐵律 7）。
        # ⚠ 顯示名暫用國碼（國家名字典隨 markets 幣別/在地化包，登記 86）。
        "all_country_option_tags" => country_option_tags(shop)
      }
    end

    def global_assigns = @global_assigns

    # 色階群組（步 13b）：settings_schema 的 color_scheme_group setting（Ella id＝
    # color_schemes）× settings_data 值 ⇒ 群組 drop。查無 ⇒ nil（scheme id 原樣字串）。
    def schemes_drop
      return @schemes_drop if defined?(@schemes_drop)

      @schemes_drop = begin
        key, entry = @theme_types.find { |_k, t| t.is_a?(Hash) && t["type"] == "color_scheme_group" }
        key && ColorSchemeGroupDrop.new(@settings_data[key] || {}, definition: entry["definition"] || [])
      end
    end

    def assign(key, value)
      @global_assigns[key.to_s] = value
    end

    # `<option>` 串（86 §6 官方 all_country_option_tags 對位）。HTML escape 不需要
    # ——值域是 RateResolver 驗過形的大寫 ISO 國碼。
    def country_option_tags(shop)
      ActsAsTenant.with_tenant(shop) { Checkouts::RateResolver.sellable_countries(shop:) }
                  .map { |code| %(<option value="#{code}">#{code}</option>) }
                  .join
    end

    # ---- 來源讀取與快取 -----------------------------------------------------
    def read(rel) = @source.read(rel)

    def asset(name)
      @assets[name] ||= read(File.join("assets", File.basename(name.to_s))).to_s
    end

    def load_json(rel)
      raw = read(rel)
      return nil if raw.nil?

      self.class.tolerant_json(raw)
    rescue JSON::ParserError => e
      @warnings << "JSON 解析失敗 #{rel}: #{e.message[0, 80]}"
      nil
    end

    # 三層字串字典（67 §F.3(a)；深併序＝越後越優先）：
    #   平台字串集(en←鏈←精確) → 主題 *.default.json → 主題截尾鏈檔 → 主題精確 locale 檔。
    # locale 檔一律走 tolerant_json（F.3(b)1：Ella 實證 JSONC——區塊註解／CRLF／BOM／尾逗號）。
    def build_locale_dict(locale)
      dict = Storefront::PlatformStrings.dict(locale || "en")
      dict = deep_merge_dict(dict, load_json("locales/en.default.json") || {})
      tag = locale.to_s
      unless tag.blank? || tag == "en"
        Storefront::PlatformStrings.chain(tag).reverse.each do |name|
          next if name == "en" # default 檔已併

          layer = load_json("locales/#{name}.json")
          dict = deep_merge_dict(dict, layer) if layer
        end
      end
      dict
    end

    def deep_merge_dict(base, over)
      base.merge(over) do |_k, a, b|
        a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge_dict(a, b) : b
      end
    end

    # DB 覆寫層：templates row → 來源檔 fallback（D77 讀取順序）。
    def template_json(key)
      row = Template.find_by(shop_id: @shop.id, theme_id: @theme.id, key: key.to_s)
      return row.content if row

      load_json("templates/#{key}.json")
    end

    # {% javascript %}/{% stylesheet %} 聚合桶（PR-3；tags.rb SectionAssetTag
    # 餵入、PageRenderer 頁尾輸出）。Set 去重＝同型 section 多實例只出一份
    # （本尊語義：per section type 一份）。
    def collect_section_asset(kind, content)
      return if content.to_s.strip.empty?

      (@section_assets ||= { js: Set.new, css: Set.new })[kind] << content
    end

    def aggregated_section_assets
      return "" if @section_assets.nil?

      css = @section_assets[:css].map { |c| "<style>#{c}</style>" }.join
      js = @section_assets[:js].map { |c| "<script>#{c}</script>" }.join
      css + js
    end

    # settings image_picker 值 → StoredFile（PR-2）。接受兩形：
    # `shopify://shopify/files/{filename}`（本尊 settings_data 慣用形）與裸檔名。
    # 其他 shopify:// 資源形（如 shopify://collections/…）不在此解析 ⇒ nil。
    def resolve_settings_file(value)
      s = value.to_s
      filename = s.delete_prefix("shopify://shopify/files/")
      return nil if filename.empty? || filename.start_with?("shopify://")

      ActsAsTenant.without_tenant do
        StoredFile.find_by(shop_id: @shop.id, filename: CGI.unescape(filename))
      end
    end

    def db_settings
      row = ThemeSetting.find_by(shop_id: @shop.id, theme_id: @theme.id)
      row&.settings
    end

    def file_settings_current
      (load_json("config/settings_data.json") || {})["current"] || {}
    end

    def compiled(rel)
      # 🔴 overlay 檔改 per-row 版本鍵（含 shop/theme/stamp）——共用鍵會讓 A 店
      # 編輯汙染 B 店編譯結果（15a 跨租戶汙染同軸；OverlaySource 檔頭）。
      stamp = @source.respond_to?(:overlay_stamp) ? @source.overlay_stamp(rel) : nil
      cache_key = if stamp
        [ "ovl", @shop.id, @theme.id, stamp, rel ]
      else
        [ Sources.key_for(@theme), rel ]
      end
      AST_MUTEX.synchronize do
        AST_CACHE.clear if AST_CACHE.size > AST_CACHE_MAX
        return AST_CACHE[cache_key] if AST_CACHE.key?(cache_key)
      end

      src = read(rel)
      entry =
        if src
          schema_json = src[SCHEMA_RE, 1]
          schema = schema_json ? (self.class.tolerant_json(schema_json) rescue nil) : nil
          body = src.gsub(SCHEMA_RE, "") # 匯入期剝離 schema（25 坑 #7）
          begin
            tpl = Liquid::Template.parse(body, environment: ENVIRONMENT, line_numbers: true)
            { tpl: tpl, schema: schema || {}, types: extract_types(all_settings_defs(schema)) }
          rescue Liquid::SyntaxError => e
            # 🔴 單一檔案的語法錯不得炸整頁（25 §6 ④錯誤策略）。lax 只寬容渲染期，
            #   **parse 期**的 SyntaxError 照樣 raise（Ella 實測：`{% render block %}`
            #   動態名是本尊平台擴充、gem 不收 ⇒ 91 §3.48 登記未實作面）。
            @errors << "#{rel}: #{e.class}: #{e.message[0, 120]}"
            nil
          end
        end
      @warnings << "檔案不存在: #{rel}" if entry.nil? && src.nil?
      AST_MUTEX.synchronize { AST_CACHE[cache_key] = entry }
      entry
    end

    # 🔴 一律以 static_environments 傳 assigns：`{% render %}` 建立隔離子 context 時
    #   只帶 static environments 與 registers，**普通 assigns 會消失**（實測：
    #   snippet 內 `{{ shop }}` 輸出空）。PoC 用普通 assigns ⇒ 這是移植時抓到的
    #   第四個反例，登記 91 §3.48。
    def build_context(assigns, registers)
      Liquid::Context.build(
        static_environments: [ assigns ],
        registers: registers,
        environment: ENVIRONMENT
      )
    end

    def all_settings_defs(schema)
      return [] unless schema.is_a?(Hash)

      defs = schema["settings"] || []
      (schema["blocks"] || []).each { |b| defs += (b["settings"] || []) if b.is_a?(Hash) }
      defs
    end

    # color_scheme_group 存整個 def（definition 子 schema＝scheme.settings 型別
    # 來源——SettingsDrop.coerce 對表；步 13b）；其餘維持型別字串。
    def extract_types(defs)
      defs.each_with_object({}) do |d, h|
        next unless d.is_a?(Hash) && d["id"]

        h[d["id"]] = d["type"] == "color_scheme_group" ? d : d["type"]
      end
    end

    def schema_defaults(defs)
      defs.each_with_object({}) { |d, h| h[d["id"]] = d["default"] if d.is_a?(Hash) && d.key?("default") && d["id"] }
    end

    # ---- section 渲染 -------------------------------------------------------
    def render_section(key, data, page_type: nil)
      c = compiled("sections/#{data['type']}.liquid") or return comment("缺 section #{data['type']}")
      merged = schema_defaults(c[:schema]["settings"] || []).merge(data["settings"] || {})
      sdrop = SectionDrop.new(id: key, data: data.merge("settings" => merged), types: c[:types],
                              blocks: ordered_block_drops(data), schemes: schemes_drop)
      assigns = @global_assigns.merge("section" => sdrop, "closest" => @closest)
      html = c[:tpl].render(build_context(assigns, base_registers.merge(frame: data, section_drop: sdrop)))
      collect_errors("sections/#{data['type']}", c[:tpl])
      tag = c[:schema]["tag"] || "div"
      cls = [ "shopify-section", c[:schema]["class"] ].compact.join(" ")
      editor_attr = @design_mode ? %( data-shopify-editor-section='#{JSON.generate(id: key, type: data['type'])}') : ""
      %(<#{tag} id="shopify-section-#{key}" class="#{cls}"#{editor_attr}>#{html}</#{tag}>#{custom_css_style(key, data)})
    end

    # PR-19：theme 級 Custom CSS（官方：Theme settings → Custom CSS、1500 字、
    # 全頁生效——help add-css 取證 2026-09-02）。無 scope 前綴（全站語義）。
    def theme_custom_css_style
      raw = (@platform_customizations || {})["custom_css"]
      css = raw.is_a?(Array) ? raw.join("\n") : raw.to_s
      return "" if css.strip.empty?

      %(<style data-shopify-custom-css-theme>#{css.gsub("</", "<\\/")}</style>)
    end

    # PR-18：section 級 Custom CSS（官方：存 section data 的 custom_css、
    # 「scoped to that section」——help add-css＋dev json-templates 取證
    # 2026-09-02）。作用域用 CSS 巢狀（#shopify-section-{id} { rules }）——
    # 後代選擇器語義與官方一致；「規則選 wrapper 標籤本身」的邊角＝巢狀下是
    # 後代不含自身，登記 V。儲存型別官方未載 ⇒ String/Array 雙收（V）。
    def custom_css_style(key, data)
      raw = data["custom_css"]
      css = raw.is_a?(Array) ? raw.join("\n") : raw.to_s
      return "" if css.strip.empty?

      safe = css.gsub("</", "<\\/") # style 內容防斷（HTML 不逸出 CSS，只擋閉合）
      %(<style data-shopify-custom-css>#shopify-section-#{key} {\n#{safe}\n}</style>)
    end

    # depth：巢狀 children 遞迴上限（官方 "nested up to 8 levels deep"）——
    # 循環資料兜底，超層＝空 children 不炸。
    def ordered_block_drops(data, depth: 0)
      return [] if depth > 8

      (data["block_order"] || []).filter_map do |bid|
        bdata = (data["blocks"] || {})[bid] or next
        bc = compiled("blocks/#{bdata['type']}.liquid") or next
        settings = schema_defaults(bc[:schema]["settings"] || []).merge(bdata["settings"] || {})
        BlockDrop.new(id: bid, type: bdata["type"], settings: settings, types: bc[:types],
                      data: bdata, design_mode: @design_mode, schemes: schemes_drop,
                      children: ordered_block_drops(bdata, depth: depth + 1))
      end
    end

    # ---- block 渲染（content_for 呼叫；27 §6.4 隔離語義）--------------------
    # closest_overrides：content_for "block" 的 `closest.*` 參數（Ella 商品卡傳遞形）
    #   ——覆寫進 block 子樹的 closest；nil 值不覆蓋既有。
    # extra_assigns：其餘任意參數（官方 static block 參數契約）——不得撞保留鍵。
    def render_block(id, bdata, context, static: false, closest_overrides: nil, extra_assigns: nil)
      type = bdata["type"]
      c = compiled("blocks/#{type}.liquid") or return comment("缺 block #{type}")
      resolved = resolve_dynamic(bdata["settings"] || {}, context)
      settings = schema_defaults(c[:schema]["settings"] || []).merge(resolved)
      bdrop = BlockDrop.new(id: id, type: type, settings: settings, types: c[:types],
                            data: bdata, design_mode: @design_mode, schemes: schemes_drop,
                            children: ordered_block_drops(bdata, depth: 1))
      closest = context["closest"] || @closest
      if closest_overrides.present?
        closest = ClosestDrop.merged(closest, closest_overrides)
      end
      assigns = @global_assigns.merge(
        "section" => context.registers[:section_drop],
        "block" => bdrop,
        "closest" => closest
      )
      if extra_assigns.present?
        extra_assigns.each do |key, value|
          assigns[key] = value unless %w[block section closest settings shop cart].include?(key)
        end
      end
      html = c[:tpl].render(build_context(assigns, base_registers.merge(
        frame: bdata, section_drop: context.registers[:section_drop]
      )))
      collect_errors("blocks/#{type}", c[:tpl])
      wrap = c[:schema].key?("tag") ? c[:schema]["tag"] : nil
      wrap ? %(<#{wrap} class="shopify-block #{c[:schema]['class']}">#{html}</#{wrap}>) : html
    end

    # 動態來源（"{{ closest.product }}"）→ 物件；混合內容 → 迷你渲染（27 §2）。
    def resolve_dynamic(settings, context)
      settings.transform_values do |v|
        next v unless v.is_a?(String)

        if (m = v.match(/\A\s*\{\{\s*([\w.\-\[\]']+)\s*\}\}\s*\z/))
          begin
            context.evaluate(Liquid::Expression.parse(m[1])) || v
          rescue StandardError
            v
          end
        elsif v.include?("{{") || v.include?("{%")
          begin
            Liquid::Template.parse(v, environment: ENVIRONMENT).render(context)
          rescue StandardError
            v
          end
        else
          v
        end
      end
    end

    # ---- groups / 靜態 sections --------------------------------------------
    def render_section_group(name)
      g = load_json("sections/#{name}.json")
      unless g
        @warnings << "section group 不存在（寬容跳過）: #{name}"
        return comment("group #{name} 缺檔")
      end
      (g["order"] || []).map do |k|
        s = @draft_sections[k] || g["sections"][k] or next ""
        s["disabled"] ? "" : render_section(k, s)
      end.join
    end

    def render_static_section(name)
      data = ((@settings_data || {})["sections"] || {})[name] || { "type" => name, "settings" => {} }
      render_section(name, data)
    end

    # ---- 支援 ---------------------------------------------------------------
    class SnippetFS
      def initialize(source) = @source = source

      def read_template_file(path)
        @source.read(File.join("snippets", "#{path}.liquid")) or
          raise Liquid::FileSystemError, "找不到 snippet: #{path}"
      end
    end

    # 步 16a：編輯器橋（design_mode 專屬；14 §F3 postMessage 契約——同源 iframe，
    # origin 用 location.origin 嚴格比對、不用 *）。
    EDITOR_BRIDGE_JS = <<~JS.freeze
      <script>(function(){
        var current=null;
        function outline(el,on){ if(el) el.style.outline = on ? "2px solid #005bd1" : ""; }
        window.addEventListener("message",function(ev){
          if(ev.origin !== location.origin) return;
          var d=ev.data||{};
          if(d.type==="cl:highlight"){
            var el=document.getElementById("shopify-section-"+d.id);
            if(d.blockId && el){
              var hit=null;
              el.querySelectorAll("[data-shopify-editor-block]").forEach(function(b){
                try{ if(JSON.parse(b.getAttribute("data-shopify-editor-block")).id===d.blockId) hit=b; }catch(e){}
              });
              if(hit) el=hit; // PR-17：block 級錨點——高亮縮到 block 元素
            }
            outline(current,false); current=el; outline(el,true);
            if(el) el.scrollIntoView({behavior:"smooth",block:"center"});
          }
          if(d.type==="cl:replace"){
            var target=document.getElementById("shopify-section-"+d.id);
            if(target && typeof d.html==="string"){
              var tpl=document.createElement("template");
              tpl.innerHTML=d.html;
              var next=tpl.content.querySelector("[id^='shopify-section-']")||tpl.content.firstElementChild;
              if(next){ target.replaceWith(next); if(current===target) { current=next; outline(next,true); } }
            }
          }
        });
        document.addEventListener("click",function(ev){
          // PR-23：站內連結不逃出編輯器——攔下改由父頁換預覽 src
          var link=ev.target.closest("a[href]");
          if(link){
            var href=link.getAttribute("href")||"";
            if(href.charAt(0)==="/" && href.indexOf("/admin/")!==0){
              ev.preventDefault();
              parent.postMessage({type:"cl:navigate",path:href},location.origin);
            }
          }
          var host=ev.target.closest("[id^='shopify-section-']");
          if(!host) return;
          var msg={type:"cl:select",id:host.id.replace("shopify-section-","")};
          var blockEl=ev.target.closest("[data-shopify-editor-block]");
          if(blockEl && host.contains(blockEl)){
            try{ msg.blockId=JSON.parse(blockEl.getAttribute("data-shopify-editor-block")).id; }catch(e){}
          }
          parent.postMessage(msg,location.origin);
        },true);
      })();</script>
    JS

    def base_registers
      { runtime: self, locale_dict: @locale_dict, file_system: SnippetFS.new(@source),
        money_symbol: money_symbol, currency: @shop.store_currency,
        render_flags: @render_flags,
        # paginate tag 的頁碼與 parts URL 來源（步 12）：request_params＝字串鍵
        # query 參數；request_path＝**帶前綴**的站內路徑（parts 連結是買家可點 URL）。
        request_params: @params, request_path: "#{@url_prefix}#{@path}",
        asset_base: @asset_base || "/admin/store/preview/#{@theme.id}/assets" }
    end

    # v1 符號表：只對店預設幣別 HKD 承諾正確（鐵律 10 的完整 locale 鏈＝包 34；91 §3.48）。
    def money_symbol
      { "HKD" => "HK$" }.fetch(@shop.store_currency, "#{@shop.store_currency} ")
    end

    def collect_errors(label, tpl)
      tpl.errors.each { |e| @errors << "#{label}: #{e.class}: #{e.message[0, 120]}" }
    end

    # 包 33：layout 原文（fragment 端點解析 {% sections %} 群組名單用）。
    def raw_layout_source
      read("layout/theme.liquid")
    end

    def comment(msg) = "<!-- theme-engine: #{ERB::Util.html_escape(msg)} -->"

    def compat_report
      { errors: @errors.uniq, warnings: @warnings.uniq, top_misses: ThemeEngine.miss_report }
    end
  end
end
