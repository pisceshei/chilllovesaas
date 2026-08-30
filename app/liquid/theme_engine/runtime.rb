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

    # 寬容 JSON（25 坑 #11：第三方原始碼包帶註解/尾逗號）。
    def self.tolerant_json(str)
      s = str.dup.force_encoding("UTF-8").scrub
      s.gsub!(%r{/\*.*?\*/}m, "")
      s.gsub!(/,(\s*[}\]])/, '\1')
      JSON.parse(s)
    end

    # @param locale_dict [Hash] t filter 的字典（v1＝主題 locales/en.default.json；包 34 接真值鏈）
    def initialize(theme:, shop:, source: nil, url_prefix: "", locale: nil,
                   design_mode: false, page_type: "index", path: "/", host: nil,
                   cart_json: nil, asset_base: nil)
      @theme, @shop = theme, shop
      @cart_json = cart_json
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

      @settings_data = db_settings || file_settings_current
      schema = load_json("config/settings_schema.json") || []
      @theme_types = extract_types(schema.flat_map { |c| c.is_a?(Hash) ? (c["settings"] || []) : [] })
      @locale_dict = load_json("locales/en.default.json") || {}

      language = { "iso_code" => locale || "en", "endonym_name" => locale || "en", "root_url" => url_prefix.presence || "/" }
      @global_assigns = {
        "settings" => SettingsDrop.new(@settings_data, @theme_types, label: "settings"),
        "shop" => ShopDrop.new(shop),
        "cart" => CartDrop.new(currency: shop.store_currency, cart_json: @cart_json),
        "routes" => RoutesDrop.new(prefix: url_prefix),
        "request" => RequestDrop.new(page_type:, design_mode:, locale:, host:, path:),
        "localization" => LocalizationDrop.new(language:, available_languages: [ language ]),
        "linklists" => LinkListsDrop.new(shop, url_prefix: url_prefix),
        "template" => TemplateDrop.new(page_type),
        "content_for_header" => "",
        "canonical_url" => host ? "https://#{host}#{path}" : path,
        "page_title" => shop.name,
        "page_description" => nil,
        "current_tags" => nil,
        "collections" => nil,
        "all_products" => nil,
        "predictive_search" => nil,
        "recommendations" => nil
      }
    end

    def global_assigns = @global_assigns

    def assign(key, value)
      @global_assigns[key.to_s] = value
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

    # DB 覆寫層：templates row → 來源檔 fallback（D77 讀取順序）。
    def template_json(key)
      row = Template.find_by(shop_id: @shop.id, theme_id: @theme.id, key: key.to_s)
      return row.content if row

      load_json("templates/#{key}.json")
    end

    def db_settings
      row = ThemeSetting.find_by(shop_id: @shop.id, theme_id: @theme.id)
      row&.settings
    end

    def file_settings_current
      (load_json("config/settings_data.json") || {})["current"] || {}
    end

    def compiled(rel)
      cache_key = [ Sources.key_for(@theme), rel ]
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

    def extract_types(defs)
      defs.each_with_object({}) { |d, h| h[d["id"]] = d["type"] if d.is_a?(Hash) && d["id"] }
    end

    def schema_defaults(defs)
      defs.each_with_object({}) { |d, h| h[d["id"]] = d["default"] if d.is_a?(Hash) && d.key?("default") && d["id"] }
    end

    # ---- section 渲染 -------------------------------------------------------
    def render_section(key, data, page_type: nil)
      c = compiled("sections/#{data['type']}.liquid") or return comment("缺 section #{data['type']}")
      merged = schema_defaults(c[:schema]["settings"] || []).merge(data["settings"] || {})
      sdrop = SectionDrop.new(id: key, data: data.merge("settings" => merged), types: c[:types],
                              blocks: ordered_block_drops(data))
      assigns = @global_assigns.merge("section" => sdrop, "closest" => @closest)
      html = c[:tpl].render(build_context(assigns, base_registers.merge(frame: data, section_drop: sdrop)))
      collect_errors("sections/#{data['type']}", c[:tpl])
      tag = c[:schema]["tag"] || "div"
      cls = [ "shopify-section", c[:schema]["class"] ].compact.join(" ")
      editor_attr = @design_mode ? %( data-shopify-editor-section='#{JSON.generate(id: key, type: data['type'])}') : ""
      %(<#{tag} id="shopify-section-#{key}" class="#{cls}"#{editor_attr}>#{html}</#{tag}>)
    end

    def ordered_block_drops(data)
      (data["block_order"] || []).filter_map do |bid|
        bdata = (data["blocks"] || {})[bid] or next
        bc = compiled("blocks/#{bdata['type']}.liquid") or next
        settings = schema_defaults(bc[:schema]["settings"] || []).merge(bdata["settings"] || {})
        BlockDrop.new(id: bid, type: bdata["type"], settings: settings, types: bc[:types],
                      data: bdata, design_mode: @design_mode)
      end
    end

    # ---- block 渲染（content_for 呼叫；27 §6.4 隔離語義）--------------------
    def render_block(id, bdata, context, static: false)
      type = bdata["type"]
      c = compiled("blocks/#{type}.liquid") or return comment("缺 block #{type}")
      resolved = resolve_dynamic(bdata["settings"] || {}, context)
      settings = schema_defaults(c[:schema]["settings"] || []).merge(resolved)
      bdrop = BlockDrop.new(id: id, type: type, settings: settings, types: c[:types],
                            data: bdata, design_mode: @design_mode)
      assigns = @global_assigns.merge(
        "section" => context.registers[:section_drop],
        "block" => bdrop,
        "closest" => context["closest"] || @closest
      )
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
        s = g["sections"][k] or next ""
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

    def base_registers
      { runtime: self, locale_dict: @locale_dict, file_system: SnippetFS.new(@source),
        money_symbol: money_symbol, currency: @shop.store_currency,
        render_flags: @render_flags,
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
