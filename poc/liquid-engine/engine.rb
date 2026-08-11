# frozen_string_literal: true
# CHILL LOVE PoC — ThemeRuntime：載入主題、寬容解析、AST 快取、section/block 渲染
# 對應規格：docs/research/25 §6（渲染服務）、24 §2（資料模型）、27 §6（渲染細節）

require "liquid"
require "json"
require "time"

# ★ 一級相容坑（實測發現）：gem 的 `x == blank` 走 MethodLiteral(:blank?)，行為依賴宿主
# 定義 Object#blank?（ActiveSupport）。Shopify 跑 Rails 所以 `undefined == blank → true`；
# 裸 gem 下 nil 不 respond_to?(:blank?) → 條件恆 false，主題的 `if x == blank` 慣用法全滅。
# Rails 環境免費獲得；PoC 補最小 core_ext（語義照抄 ActiveSupport）。
class Object;     def blank? = respond_to?(:empty?) ? !!empty? : !self; def present? = !blank?; end
class NilClass;   def blank? = true;  end
class FalseClass; def blank? = true;  end
class TrueClass;  def blank? = false; end
class Numeric;    def blank? = false; end
class String;     def blank? = /\A[[:space:]]*\z/.match?(self); end

require_relative "drops"
require_relative "filters"
require_relative "tags"

module ChillLove
  class SnippetFS
    def initialize(dir) = @dir = dir
    def read_template_file(path)
      f = File.join(@dir, "snippets", "#{path}.liquid")
      raise Liquid::FileSystemError, "找不到 snippet: #{path}" unless File.exist?(f)
      File.read(f)
    end
  end

  class ThemeRuntime
    attr_reader :dir, :errors, :warnings, :design_mode

    # 寬容 JSON（25 坑 #11：第三方原始碼包帶註解/尾逗號）
    def self.tolerant_json(str)
      s = str.dup.force_encoding("UTF-8").scrub
      s.gsub!(%r{/\*.*?\*/}m, "")
      s.gsub!(/,(\s*[}\]])/, '\1')
      JSON.parse(s)
    end

    def initialize(dir, design_mode: false)
      @dir = dir
      @design_mode = design_mode
      @errors, @warnings = [], []
      @tpl_cache = {}   # 路徑 → {tpl:, schema:, types:}（AST cache，25 §6 規則 2）
      @assets = {}

      Tags.register!(Liquid::Template)
      Liquid::Template.register_filter(Filters)

      @settings_data  = load_json("config/settings_data.json")
      schema          = load_json("config/settings_schema.json") || []
      @theme_types    = extract_types(schema.flat_map { |c| c.is_a?(Hash) ? (c["settings"] || []) : [] })
      @locale         = load_json("locales/en.default.json") || {}
      @schema_locale  = load_json("locales/en.default.schema.json") || {}

      current = (@settings_data || {})["current"] || {}
      @global_assigns = {
        "settings"           => SettingsDrop.new(current, @theme_types, label: "settings"),
        "shop"               => ShopDrop.new,
        "cart"               => CartDrop.new,
        "routes"             => RoutesDrop.new,
        "request"            => RequestDrop.new(design_mode: design_mode),
        "localization"       => LocalizationDrop.new,
        "template"           => TemplateDrop.new("index"),
        "content_for_header" => "",
        "canonical_url"      => "https://chill.deals/",
        "page_title"         => "CHILL LOVE",
        "page_description"   => "PoC",
        "current_tags"       => nil,
        "linklists"          => nil,
        "collections"        => nil,
        "all_products"       => nil,
        "predictive_search"  => nil,
        "recommendations"    => nil,
      }
      @closest = ClosestDrop.new
    end

    attr_writer :closest
    def global_assigns = @global_assigns

    def asset(name)
      @assets[name] ||= begin
        f = File.join(@dir, "assets", name)
        File.exist?(f) ? File.read(f) : ""
      end
    end

    # ---- 載入與快取 ---------------------------------------------------------
    def load_json(rel)
      f = File.join(@dir, rel)
      return nil unless File.exist?(f)
      self.class.tolerant_json(File.read(f))
    rescue JSON::ParserError => e
      @warnings << "JSON 解析失敗 #{rel}: #{e.message[0, 80]}"
      nil
    end

    SCHEMA_RE = /\{%-?\s*schema\s*-?%\}(.*?)\{%-?\s*endschema\s*-?%\}/m

    def compiled(rel) # → {tpl:, schema:, types:} or nil
      @tpl_cache[rel] ||= begin
        f = File.join(@dir, rel)
        if File.exist?(f)
          src = File.read(f)
          schema_json = src[SCHEMA_RE, 1]
          schema = schema_json ? (self.class.tolerant_json(schema_json) rescue nil) : nil
          body = src.gsub(SCHEMA_RE, "") # 匯入期剝離 schema（25 坑 #7）
          tpl = Liquid::Template.parse(body, error_mode: :lax, line_numbers: true)
          { tpl: tpl, schema: schema || {}, types: extract_types(all_settings_defs(schema)) }
        else
          @warnings << "檔案不存在: #{rel}"
          nil
        end
      end
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

    # ---- section 渲染（25 §6 ThemeRuntime）----------------------------------
    def render_section(key, data, page_type: "index")
      c = compiled("sections/#{data['type']}.liquid") or return comment("缺 section #{data['type']}")
      merged = schema_defaults(c[:schema]["settings"] || []).merge(data["settings"] || {})
      sdrop = SectionDrop.new(id: key, data: data.merge("settings" => merged), types: c[:types],
                              blocks: ordered_block_drops(data, c))
      assigns = @global_assigns.merge(
        "section" => sdrop, "closest" => @closest,
        "request" => RequestDrop.new(page_type: page_type, design_mode: @design_mode)
      )
      html = c[:tpl].render(assigns, registers: base_registers.merge(frame: data, section_drop: sdrop))
      collect_errors("sections/#{data['type']}", c[:tpl])
      tag = c[:schema]["tag"] || "div"
      cls = ["shopify-section", c[:schema]["class"]].compact.join(" ")
      editor_attr = @design_mode ? %( data-shopify-editor-section='#{JSON.generate(id: key, type: data['type'])}') : ""
      %(<#{tag} id="shopify-section-#{key}" class="#{cls}"#{editor_attr}>#{html}</#{tag}>)
    end

    def ordered_block_drops(data, _c)
      (data["block_order"] || []).filter_map do |bid|
        bd = (data["blocks"] || {})[bid] or next
        bc = compiled("blocks/#{bd['type']}.liquid") || compiled_local_block_stub
        next unless bc
        settings = schema_defaults(bc[:schema]["settings"] || []).merge(bd["settings"] || {})
        BlockDrop.new(id: bid, type: bd["type"], settings: settings, types: bc[:types],
                      data: bd, design_mode: @design_mode)
      end
    end

    def compiled_local_block_stub = nil

    # ---- block 渲染（content_for 呼叫；27 §6.4 隔離語義）---------------------
    def render_block(id, bdata, context, static: false)
      type = bdata["type"]
      c = compiled("blocks/#{type}.liquid") or return comment("缺 block #{type}")
      resolved = resolve_dynamic(bdata["settings"] || {}, context)
      settings = schema_defaults(c[:schema]["settings"] || []).merge(resolved)
      bdrop = BlockDrop.new(id: id, type: type, settings: settings, types: c[:types],
                            data: bdata, design_mode: @design_mode)
      assigns = @global_assigns.merge(
        "section" => context.registers[:section_drop],
        "block"   => bdrop,
        "closest" => context["closest"] || @closest
      )
      html = c[:tpl].render(assigns, registers: base_registers.merge(
        frame: bdata, section_drop: context.registers[:section_drop]
      ))
      collect_errors("blocks/#{type}", c[:tpl])
      # theme block 包裹：schema.tag 指定才包（Ella 慣例 tag:null＋手放 shopify_attributes）
      wrap = c[:schema].key?("tag") ? c[:schema]["tag"] : nil
      wrap ? %(<#{wrap} class="shopify-block #{c[:schema]['class']}">#{html}</#{wrap}>) : html
    end

    # 動態來源（"{{ closest.product }}"）→ 物件（27 §2 preset 動態來源）
    def resolve_dynamic(settings, context)
      settings.transform_values do |v|
        next v unless v.is_a?(String)
        if (m = v.match(/\A\s*\{\{\s*([\w.\-\[\]']+)\s*\}\}\s*\z/)) # 純單一引用 → 物件
          begin
            context.evaluate(Liquid::Expression.parse(m[1])) || v
          rescue StandardError
            v
          end
        elsif v.include?("{{") || v.include?("{%") # 混合內容 → 迷你渲染成字串
          begin
            Liquid::Template.parse(v, error_mode: :lax).render(context)
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
      (g["order"] || []).map { |k| s = g["sections"][k] or next ""; s["disabled"] ? "" : render_section(k, s) }.join
    end

    def render_static_section(name)
      data = ((@settings_data || {}).dig("current", "sections") || {})[name] || { "type" => name, "settings" => {} }
      render_section(name, data)
    end

    # ---- 支援 ---------------------------------------------------------------
    def base_registers
      { runtime: self, locale: @locale, file_system: SnippetFS.new(@dir) }
    end

    def collect_errors(label, tpl)
      tpl.errors.each { |e| @errors << "#{label}: #{e.class}: #{e.message[0, 120]}" }
    end

    def comment(msg) = "<!-- PoC: #{msg} -->"

    def compat_report
      { errors: @errors.uniq, warnings: @warnings.uniq,
        top_misses: MISSES.sort_by { |_, c| -c }.first(40).to_h }
    end
  end
end
