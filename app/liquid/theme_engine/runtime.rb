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

    # `{% schema %}` 三組：①開 tag ②JSON ③關 tag。載入期只抽掉 JSON、**tag 留在原位**（Swallow 渲染空）——
    # 本尊把 schema 當一般 tag 解析，`-%}` 只吃到 `{% schema %}` 前的空白、`{% endschema %}` 後的檔尾換行照輸出
    # （hoko.vip color-swatches：`{%- endstyle -%}\r\n\r\n{% schema %}…{% endschema %}\r\n` ⇒ `</style>\r\n</div>`）。
    # 原本整段連 tag 一起刪掉，會讓前面的 `-%}` 把 endschema 之後的換行也吞掉（渲染 1:1 對表抓到）。
    SCHEMA_RE = /(\{%-?\s*schema\s*-?%\})(.*?)(\{%-?\s*endschema\s*-?%\})/m
    # 渲染 1:1（2026-09-03，hoko.vip 原始位元組取證）：本尊 Liquid 以 gem 的 `bug_compatible_whitespace_trimming`
    # 模式解析——`{%-` 把前一段純空白文字整段 rstrip 掉時，**保留該段第一個位元組**（liquid 5.13.0
    # block_body.rb `whitespace_handler`：`previous_token << first_byte`）。Ella 全數檔案是 CRLF，故本尊輸出
    # 帶大量孤立 `\r`（首頁 14,762 個 CR；例 `column;\r--gap: 0px;`＝gap-style 開頭 `{% enddoc %}\r\n\r\n{%- liquid`
    # 留下的首位元組；`</svg>\r</span>`＝toolbar-mobile 的 `{%- endif -%}` 前一段）。不開此模式則 CSS 變數串、
    # class 串的空白形與本尊不同。與 `{% schema %}` 載入期剝離相容（剝離只去掉 tag 本體，前後文字原樣保留）。
    PARSE_OPTIONS = { line_numbers: true, bug_compatible_whitespace_trimming: true }.freeze
    # NumericLookup 只在常數被引用時才由 autoload 載入（dev／test 不 eager load）⇒ 在此顯式掛上（幂等）
    Liquid::VariableLookup.prepend(NumericLookup) unless Liquid::VariableLookup.ancestors.include?(NumericLookup)
    Liquid::Condition.prepend(NilEmpty) unless Liquid::Condition.ancestors.include?(NilEmpty)

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
        "cart" => CartDrop.new(currency: shop.store_currency, cart_json: @cart_json,
                               taxes_included: shop.respond_to?(:taxes_included) && shop.taxes_included,
                               money_format: shop.money_format), # E8b：currency.symbol 退路（Currencies）
        "routes" => RoutesDrop.new(prefix: url_prefix),
        "request" => RequestDrop.new(page_type:, design_mode:, locale:, host:, path:),
        # localization 真值（67 §F.2 切換器規則）：有 presence（公開店面）＝開放∧已發布集；
        # 無 presence（預覽面／fragment）＝維持合成單語（包 30 行為不變）。
        "localization" => web_presence ? Storefront::LocalizationContext.drop(web_presence:, locale_tag: locale || "en")
                                       : LocalizationDrop.new(language:, available_languages: [ language ]),
        "linklists" => LinkListsDrop.new(shop, url_prefix: url_prefix, current_path: "#{url_prefix}#{path}"),
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
        # E8b：頁面初次渲染的 recommendations——hoko.vip 商品頁 `data-recommendations-performed="false"`（Ella 印 `{{ recommendations.performed }}`）
        # ＋3 個 skeleton；只有 /recommendations/products?section_id= 的 section 渲染才 populated（RecommendationsController）。
        # 官方逐字（objects/recommendations，取證 2026-09-04）：performed?＝"Returns `true` when being referenced inside a section that's been
        # rendered using the Product Recommendations API and the Section Rendering API. Returns `false` if not."；performed? false 時
        # products＝EmptyDrop、products_count＝0、intent＝nil。Ella 讀 `performed`（無 ?），本尊同印 false ⇒ 兩鍵同值；nil 會印空字串。
        "recommendations" => BaseDrop.new({ "performed" => false, "performed?" => false, "products" => [],
                                             "products_count" => 0, "intent" => nil }),
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

          # 主題檔可能只有本尊碼形（Ella：zh-CN.json／zh-TW.json，無 zh-Hans／zh-Hant）⇒ 逐候選併入（LocaleTags）
          LocaleTags.theme_file_names(name).each do |file_name|
            layer = load_json("locales/#{file_name}.json")
            dict = deep_merge_dict(dict, layer) if layer
          end
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
          schema_json = src[SCHEMA_RE, 2]
          schema = schema_json ? (self.class.tolerant_json(schema_json) rescue nil) : nil
          body = src.gsub(SCHEMA_RE, '\1\3') # 匯入期剝離 schema JSON（25 坑 #7）；tag 留位保空白形
          begin
            tpl = Liquid::Template.parse(body, environment: ENVIRONMENT, **PARSE_OPTIONS)
            # 錯誤訊息用檔案路徑名（本尊 partial 形 `Liquid error (snippets/section line 43)`；section／block／layout
            # 的路徑形＝未取得，依同一規則取 `sections/x`／`blocks/x`／`layout/x`，登記 V）
            tpl.name = rel.delete_suffix(".liquid")
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
    # 來源——SettingsDrop.coerce 對表；步 13b）；color_scheme 也存整個 def（coerce 的
    # 三段退回需要 `default`——引擎缺口 PR-3）；其餘維持型別字串。
    def extract_types(defs)
      defs.each_with_object({}) do |d, h|
        next unless d.is_a?(Hash) && d["id"]

        h[d["id"]] = %w[color_scheme_group color_scheme].include?(d["type"]) ? d : d["type"]
      end
    end

    # 無 `default` 鍵時的官方隱含預設（shopify.dev settings/input-settings，取證 2026-09-02）：
    #   checkbox "If `default` is unspecified, then the value is `false` by default."
    #   select／radio "If `default` is unspecified, then the first option is selected by default."
    #   color_scheme：先佔 nil 鍵讓 SettingsDrop 走 coerce 的三段退回（default → 第一組）。
    # 原實作只搬 `default` ⇒ 這三型在主題沒寫 default 時拿到 nil／被計成 miss
    # （Minimog `settings.loading_design_mode`／`settings.drawer_popup_color_scheme`、
    # Kalles `settings.enable_scroll_badge` 等，`tools/theme-conformance/evidence/preclassify-*.json`）。
    def schema_defaults(defs)
      defs.each_with_object({}) do |d, h|
        next unless d.is_a?(Hash) && d["id"]

        if d.key?("default")
          h[d["id"]] = d["default"]
        else
          case d["type"]
          when "checkbox" then h[d["id"]] = false
          when "select", "radio"
            first = Array(d["options"]).find { |o| o.is_a?(Hash) && o.key?("value") }
            h[d["id"]] = first["value"] if first
          when "color_scheme" then h[d["id"]] = nil
          end
        end
      end
    end

    # ---- section 渲染 -------------------------------------------------------
    # scope（引擎缺口 PR-7；真店三套主題金標本逐字，2026-09-03）：section 的 DOM id 與 Liquid
    # `section.id` 帶來源前綴——JSON 模板的 section＝`template--{template}__{key}`、section group 的
    # section＝`sections--{group}__{key}`、靜態 `{% section %}`＝裸名（官方頁對此未逐字，真店形＝
    # `shopify-section-template--19765269299303__main`／`shopify-section-sections--19765270577255__header_default`；
    # 數字段是本尊內部 id，我方以模板鍵／群組名代之——形同、值為 ours，登記）。主題 CSS／JS 以
    # `#shopify-section-{{ section.id }}` 定位，故 wrapper id 與 `section.id` 必須同一個值。
    # group section 另帶 class `shopify-section-group-{group}`（真店逐字，緊接 `shopify-section` 之後）。
    # 編輯器橋（EDITOR_BRIDGE_JS）與 data-shopify-editor-section 仍用裸 key（編輯器 op 以 key 定址）。
    # @param index [Integer, nil] 該 section 在其 location 內的 1-based 位置（官方 section.index：
    #   "The 1-based index of the current section within its location."；static section／編輯器／
    #   Section Rendering API 一律 nil——官方逐字 "Returns nil in: static sections, online store editor
    #   rendering, and Section Rendering API contexts."，取證 2026-09-03）。呼叫端只在整頁渲染的
    #   template／group 迴圈給值；此處再以 design_mode 蓋成 nil。
    # @param location [String, nil] 官方 section.location："template"／群組 type（header／footer／
    #   custom.<type>）／"static"；nil ⇒ 由 scope 推：template→"template"、群組→該群組 JSON 的 type、無 scope→"static"。
    def render_section(key, data, page_type: nil, scope: nil, index: nil, location: nil)
      c = compiled("sections/#{data['type']}.liquid") or return comment("缺 section #{data['type']}")
      raw = data["settings"] || {}
      # E8b：section 級動態來源（Ella product-recommendations 的 section 設定 `"product": "{{ closest.product }}"`）——
      # 本尊初次渲染 `section.settings.product`＝當頁商品 ⇒ 走 skeleton 分支；先前只在 block 層解析（RF21）⇒ section 層為 nil
      # ⇒ Ella 進 onboarding 佔位卡分支（hoko.vip 商品頁 3 個 skeleton，我方 swiper 佔位卡；docs/dev/e8-render-parity.md §2 #28）。
      if raw.values.any? { |v| v.is_a?(String) && (v.include?("{{") || v.include?("{%")) }
        raw = resolve_dynamic(raw, build_context(@global_assigns.merge("closest" => @closest), base_registers))
      end
      merged = schema_defaults(c[:schema]["settings"] || []).merge(raw)
      full_id = section_full_id(key, scope)
      location ||= section_location(scope)
      @block_occurrences = Hash.new(0) # 每個 section 渲染重新計數（見 render_block 尾綴規則）
      sdrop = SectionDrop.new(id: full_id, data: data.merge("settings" => merged), types: c[:types],
                              blocks: ordered_block_drops(data, local_defs: c[:schema]["blocks"], section_id: full_id),
                              schemes: schemes_drop, index: @design_mode ? nil : index, location: location)
      assigns = @global_assigns.merge("section" => sdrop, "closest" => @closest)
      html = c[:tpl].render(build_context(assigns, base_registers.merge(frame: data, section_drop: sdrop)))
      collect_errors("sections/#{data['type']}", c[:tpl])
      tag = c[:schema]["tag"] || "div"
      group_class = scope && scope[:kind] == "sections" ? "shopify-section-group-#{scope[:name]}" : nil
      cls = [ "shopify-section", group_class, c[:schema]["class"].presence ].compact.join(" ")
      editor_attr = @design_mode ? %( data-shopify-editor-section='#{JSON.generate(id: key, type: data['type'])}') : ""
      %(<#{tag} id="shopify-section-#{full_id}" class="#{cls}"#{editor_attr}>#{html}</#{tag}>#{custom_css_style(full_id, data)})
    end

    # settings_schema.json 的 `theme_info` 元素（theme_name／theme_version…；Ella 為 JSONC ⇒ tolerant_json）。
    # 供 window.Shopify.theme.schema_name／schema_version（本尊：`"schema_name":"Ella","schema_version":"7.2.0"`）。
    def theme_info
      @theme_info ||= (load_json("config/settings_schema.json") || []).find { |c| c.is_a?(Hash) && c["name"] == "theme_info" } || {}
    end

    # @param scope [Hash, nil] { kind: "template"|"sections", name: String }
    def section_full_id(key, scope)
      scope ? "#{scope[:kind]}--#{scope[:name]}__#{key}" : key.to_s
    end

    # section.location（官方值域見 render_section）：群組 type 取自 `sections/{name}.json` 的 `type`
    # （Ella：header／footer／aside／custom.popup）；群組檔缺 type 時回落群組名（未取得本尊此況形，登記）。
    def section_location(scope)
      return "static" if scope.nil?
      return "template" if scope[:kind] == "template"

      ((load_json("sections/#{scope[:name]}.json") || {})["type"].presence || scope[:name]).to_s
    end

    # 模板鍵 → scope 名（`product.alt` ⇒ `product-alt`：id 進 CSS 選擇器不得帶點）。
    def self.template_scope(template_key)
      { kind: "template", name: template_key.to_s.tr(".", "-") }
    end

    # SRA／編輯器可能傳完整 id（`template--index__hero`）或裸 key（`hero`）——取 `__` 之後。
    def self.section_key_from_id(sid)
      s = sid.to_s
      i = s.rindex("__")
      i ? s[(i + 2)..] : s
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
    # local_defs：section schema 的 `blocks` 陣列（section 本地 block 定義——官方 section-schema
    #   "Blocks are reusable modules of content that can be added, removed, and reordered within a
    #   section"，每型有自己的 `settings`）。無 `blocks/{type}.liquid` 檔的 type 以本地定義建 drop
    #   （settings 預設取自該定義）——原實作只認 theme block 檔 ⇒ Kalles／Minimog 幾十個
    #   `{% for block in section.blocks %}` 的 section 靜默空掉（hoko 稽核候選）。
    # 🔴 `disabled: true` 的 block 不進 `section.blocks`（help.shopify.com sections-and-blocks：
    #   "To hide a section or block from your online store … click the Hide button"；JSON 形＝
    #   Kalles Demo Data 匯出的 block 級 `"disabled": true`，與 section 級同鍵同義）。
    # @param section_id [String, nil] 所屬 section 完整 id（BlockIds seed）
    # @param path [Array<String>] 父 block key 路徑（自 section 根起）
    # @param suffix [String] 祖先重複渲染的尾綴（"-1"…），子孫同尾綴
    def ordered_block_drops(data, depth: 0, local_defs: nil, section_id: nil, path: [], suffix: "")
      return [] if depth > 8

      (data["block_order"] || []).filter_map do |bid|
        bdata = (data["blocks"] || {})[bid] or next
        next if bdata["disabled"]

        type = bdata["type"]
        bpath = path + [ bid ]
        instance_id = BlockIds.instance_id(section_id, bpath) + suffix
        if (bc = compiled("blocks/#{type}.liquid"))
          settings = schema_defaults(bc[:schema]["settings"] || []).merge(bdata["settings"] || {})
          BlockDrop.new(id: bid, type: type, settings: settings, types: bc[:types],
                        data: bdata, design_mode: @design_mode, schemes: schemes_drop,
                        instance_id: instance_id, path: bpath, section_id: section_id,
                        children: ordered_block_drops(bdata, depth: depth + 1, section_id: section_id, path: bpath, suffix: suffix))
        elsif (local = local_block_def(local_defs, type))
          defs = local["settings"] || []
          # E8b：傳統 block（section schema `blocks` 定義、無 blocks/*.liquid 檔）的 `block.id`＝JSON 裸 key，**不帶** `A…__` 實例前綴
          # （hoko.vip 商品頁 Ella product-tabs `href="#tabs-html_NRR4gL"`；同頁 theme block 才是 `AUE9ZR2hhSFFzQ0hjK__radio_f7Eh9J`）。
          # 官方 objects/block 只說 "The ID is dynamically generated by Shopify and is subject to change"，兩型差異以真店為準。
          BlockDrop.new(id: bid, type: type, settings: schema_defaults(defs).merge(bdata["settings"] || {}),
                        types: extract_types(defs), data: bdata, design_mode: @design_mode,
                        schemes: schemes_drop, path: bpath, section_id: section_id)
        end
      end
    end

    def local_block_def(defs, type)
      return nil unless defs.is_a?(Array)

      defs.find { |d| d.is_a?(Hash) && d["type"] == type && !d["type"].to_s.start_with?("@") }
    end

    # ---- block 渲染（content_for 呼叫；27 §6.4 隔離語義）--------------------
    # closest_overrides：content_for "block" 的 `closest.*` 參數（Ella 商品卡傳遞形）
    #   ——覆寫進 block 子樹的 closest；nil 值不覆蓋既有。
    # extra_assigns：其餘任意參數（官方 static block 參數契約）——不得撞保留鍵。
    # @param id [String] block 裸 key（JSON 鍵；靜態 block＝content_for 的 id）
    # @param path [Array<String>, nil] 自 section 根起的 key 路徑；nil ⇒ 由 registers[:block_path]（父路徑）＋id 推
    def render_block(id, bdata, context, static: false, closest_overrides: nil, extra_assigns: nil, path: nil)
      return "" if bdata["disabled"] # 隱藏的 block 不渲染（同 ordered_block_drops 註）

      type = bdata["type"]
      c = compiled("blocks/#{type}.liquid") or return comment("缺 block #{type}")
      # closest 先合併覆寫再求值動態來源：靜態 block 自己的 setting `"product": "{{ closest.product }}"`（Ella 商品卡）
      # 指的是**本 block 的 closest**（含 `closest.product:` 參數），不是父層的——原本先求值再合併 ⇒ 拿到父層空 closest、
      # 值變成裸字串 `{{ closest.product }}` ⇒ 查無 ⇒ nil ⇒ `card--text`（hoko.vip：`card--media`）。
      closest = context["closest"] || @closest
      if closest_overrides.present?
        closest = ClosestDrop.merged(closest, closest_overrides)
      end
      resolved = nil
      context.stack do
        context["closest"] = closest
        resolved = resolve_dynamic(bdata["settings"] || {}, context)
      end
      settings = schema_defaults(c[:schema]["settings"] || []).merge(resolved)
      section_id = context.registers[:section_drop]&.id
      bpath = path || (Array(context.registers[:block_path]) + [ id ])
      # 本尊：同一 section 內同一 block（同路徑）第 n 次渲染（n≥2）的 block.id 在 key 後加 `-{n-1}`，其子孫同尾綴、
      # 前綴不變（hoko.vip：product-grid 三張靜態卡的子 block `card_product_information_4wqAip`／`-1`／`-2` 共用前綴
      # `AcENnN0ZtV1Q3M3dnK`；lookbook 子 block 二次 render 為 `lookbook_item_cUNxE6-1`）。計數每個 section 渲染重置。
      @block_occurrences ||= Hash.new(0)
      occurrence = @block_occurrences[[ section_id, bpath ]]
      @block_occurrences[[ section_id, bpath ]] += 1
      inherited = context.registers[:block_suffix].to_s
      suffix = inherited.empty? ? (occurrence.zero? ? "" : "-#{occurrence}") : inherited
      instance_id = BlockIds.instance_id(section_id, bpath) + suffix
      bdrop = BlockDrop.new(id: id, type: type, settings: settings, types: c[:types],
                            data: bdata, design_mode: @design_mode, schemes: schemes_drop,
                            instance_id: instance_id, path: bpath, section_id: section_id,
                            children: ordered_block_drops(bdata, depth: 1, section_id: section_id, path: bpath, suffix: suffix))
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
        frame: bdata, section_drop: context.registers[:section_drop], block_path: bpath, block_suffix: suffix
      )))
      collect_errors("blocks/#{type}", c[:tpl])
      # 本尊每個 block 渲染輸出**尾接一個 LF**（hoko.vip 首頁原始位元組：36 個 `shopify-block-` wrapper 的 `</div>` 後
      # 全是 `\n`、`</div><div id="shopify-block-` 緊貼形零個；render 變數形／content_for 'blocks'／'block' 三路皆同）。
      "#{block_wrapper(instance_id, c[:schema], html)}\n"
    end

    # theme block 包裝（官方 theme-blocks/schema，取證 2026-09-02）：
    #   tag 預設 "By default, when Shopify renders a block, it's wrapped in a `<div>` element with a
    #   unique `id` attribute"（`<div id="shopify-block-[id]" class="shopify-block">`）；
    #   `"tag": null` ⇒ "Shopify doesn't wrap the contents of the block in a wrapper element"；
    #   class ⇒ "You can append other classes by using the class attribute"。
    # 真店 hoko.vip（Ella，2026-09-02）逐字：`<div id="shopify-block-{id}" class="shopify-block icon-block">`，
    #   包裝上沒有其他屬性；`{% render child_block %}` 的子塊同樣帶包裝。
    # 原實作＝無 `tag` 鍵就不包、包時也沒有 id ⇒ 主題 JS／CSS 以 `#shopify-block-…` 定位全失效。
    def block_wrapper(id, schema, html)
      tag = schema.key?("tag") ? schema["tag"] : "div"
      return html if tag.nil?

      cls = [ "shopify-block", schema["class"].presence ].compact.join(" ")
      %(<#{tag} id="shopify-block-#{id}" class="#{cls}">#{html}</#{tag}>)
    end

    # 動態來源（"{{ closest.product }}"）→ 物件；混合內容 → 迷你渲染（27 §2）。
    def resolve_dynamic(settings, context)
      settings.transform_values do |v|
        next v unless v.is_a?(String)

        if (m = v.match(/\A\s*\{\{\s*([\w.\-\[\]']+)\s*\}\}\s*\z/))
          begin
            # E8b：解成 nil 就是 nil（blank）——hoko.vip 集合頁描述塊 `"text": "{{ closest.collection.description }}"` 無描述 ⇒
            # Ella text 區塊 `plain_text != blank` 不成立 ⇒ 整塊不輸出；先前 `|| v` 退回裸字串 ⇒ 非 blank ⇒ 印出
            # `{{ closest.collection.description }}`（rte-formatter＋collapsible-text）。資源型 setting 的 nil 走 SettingsDrop#coerce
            # 「未選 ⇒ 空字串」（與裸字串查無 ⇒ nil 同為 blank；PP1 首頁 onboarding 分支不變）。
            context.evaluate(Liquid::Expression.parse(m[1]))
          rescue StandardError
            v
          end
        elsif v.include?("{{") || v.include?("{%")
          begin
            Liquid::Template.parse(v, environment: ENVIRONMENT, **PARSE_OPTIONS).render(context)
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
        # 本尊對不存在的群組檔**零輸出**（hoko.vip 2026-09-03：theme.liquid `sections 'toolbar-mobile'` 無對應
        # JSON，輸出裡 `<!-- END sections: general-group -->` 直接接 `<main`，連註解都沒有）；警告只進 @warnings。
        @warnings << "section group 不存在（寬容跳過）: #{name}"
        return ""
      end
      # 真店逐字（三套主題金標本，2026-09-03；hoko.vip 原始位元組複核）：`<!-- BEGIN sections: {name} -->` 後接 LF、
      # 各 section wrapper 之間**無任何分隔**、最後一個 wrapper 後 LF 再接 `<!-- END sections: {name} -->`；
      # 群組內 section 帶 `sections--{name}__` 前綴與群組 class。section.index 只數實際渲染（非 disabled）的
      # section（disabled 是否佔位＝官方未取得，登記 V）。
      scope = { kind: "sections", name: name }
      location = (g["type"].presence || name).to_s
      position = 0
      body = (g["order"] || []).map do |k|
        s = @draft_sections[k] || g["sections"][k] or next ""
        next "" if s["disabled"]

        position += 1
        render_section(k, s, scope: scope, index: position, location: location)
      end.join
      "<!-- BEGIN sections: #{name} -->\n#{body}\n<!-- END sections: #{name} -->"
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
    # E6：橋腳本抽成 `app/assets/javascripts/editor-bridge.js`（同一份給引擎注入與 vitest（jsdom）執行），
    # 載入時讀進常數（平台檔隨版本部署，與 FontLibrary registry 同類）。契約見該檔檔頭。
    EDITOR_BRIDGE_JS = "<script>#{File.read(Rails.root.join('app/assets/javascripts/editor-bridge.js'))}</script>".freeze

    # PartialCache 以 `registers[:template_factory].for(name)` 造 partial，`partial.name ||= name`——
    # 先給 `snippets/{name}` 即得本尊錯誤訊息形（hoko.vip：`Liquid error (snippets/section line 43): divided by 0`）。
    class PartialNamer
      def for(name) = Liquid::Template.new.tap { |t| t.name = "snippets/#{name}" }
    end
    PARTIAL_NAMER = PartialNamer.new

    def base_registers
      { runtime: self, locale_dict: @locale_dict, file_system: SnippetFS.new(@source),
        template_factory: PARTIAL_NAMER,
        # D81：店級金額格式兩欄直注（渲染邏輯一份＝ThemeEngine::MoneyFormat）。
        money_format: @shop.money_format, money_with_currency_format: @shop.money_with_currency_format,
        currency: @shop.store_currency,
        render_flags: @render_flags,
        # paginate tag 的頁碼與 parts URL 來源（步 12）：request_params＝字串鍵
        # query 參數；request_path＝**帶前綴**的站內路徑（parts 連結是買家可點 URL）。
        request_params: @params, request_path: "#{@url_prefix}#{@path}",
        asset_base: @asset_base || "/admin/store/preview/#{@theme.id}/assets" }
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
