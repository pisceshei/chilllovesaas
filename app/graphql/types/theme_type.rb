# frozen_string_literal: true

module Types
  # 主題（包 30／D77）。本尊對位＝`OnlineStoreTheme`；v1 只曝露清單頁需要的欄。
  class ThemeType < BaseObject
    graphql_name "Theme"
    description "主題庫項目（清單頁子集；本尊 OnlineStoreTheme 的對位）。"

    field :id, ID, null: false
    field :license_attested, Boolean, null: false, description: "匯入時的授權聲明（鐵律 9 gate）。"
    field :name, String, null: false
    field :role, String, null: false, description: "draft／published（published_slot 唯一索引保證同店至多一個 published）。"
    field :source, String, null: false, description: "first_party／licensed／import。"
    field :version, String, null: true
    field :published_at, GraphQL::Types::ISO8601DateTime, null: true
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :preview_url, String, null: false, description: "登入後預覽入口（noindex；admin session 內有效）。"
    # 步 15b（99 §1）：filenames 萬用字元過濾（官方 "At most 50 filenames…Use '*'
    # to match zero or more characters."）＋first 上限。
    field :files, [ ThemeFileType ], null: false do
      argument :filenames, [ String ], required: false
      argument :first, Integer, required: false
    end
    field :import_report, GraphQL::Types::JSON, null: true,
      description: "最近一次匯入的相容掃描報告（非匯入主題為 null）。"
    # 步 16a：編輯器 bootstrap——🔴 DB 覆寫優先（Template row → 來源檔；
    # Runtime#template_json 同一讀序）。key 白名單防逃逸。
    field :template_json, GraphQL::Types::JSON, null: true do
      argument :key, String, required: true
    end
    # 16b：編輯器樂觀鎖底值（DB 列不存在＝null——首存免帶）。
    field :template_lock_version, Integer, null: true do
      argument :key, String, required: true
    end
    # 16c：add-section picker 目錄——🔴 只列**帶 presets** 的區段（24 §1.4：
    # 本尊「加入區段」清單＝presets 驅動；main-*/hero 這類骨架區段無 preset
    # 不可手加）。preset 取第一個（我方 minimal 每區段至多一個）。
    field :section_catalog, GraphQL::Types::JSON, null: false
    # PR-5（編輯器群組）：layout `{% sections '...' %}` 引用的 section groups
    # ——樹的 Header/Footer 帶（24 §1：本尊樹形＝Header group／Template／
    # Footer group 三段）。內容經 source 讀（吃 16e1 檔案覆寫層）；
    # lockVersion＝該 JSON 檔的 overlay 鎖底版（寫回走 themeFileUpsert）。
    field :section_groups, GraphQL::Types::JSON, null: false
    # 16d：全部區段的 settings 定義（schema 驅動控件；26 §5 型別全表）。
    # 與 catalog 不同：**不過濾 presets**——樹上選中的 main-* 也要有控件。
    field :section_schemas, GraphQL::Types::JSON, null: false
    # PR-11：模板→預覽路徑對映（資源語境——product 模板編輯帶真商品）。
    # 取各型第一個已發布資源；無資源的型不出鍵（前端回落首頁）。
    field :preview_paths, GraphQL::Types::JSON, null: false
    # 16d2：佈景設定三件——分組定義（settings_schema.json 去 theme_info）、
    # 生效值（DB 覆寫 → 檔案 current，與 Runtime 同讀序）、樂觀鎖底版。
    field :settings_schema, GraphQL::Types::JSON, null: false
    field :theme_settings_json, GraphQL::Types::JSON, null: false
    field :theme_settings_lock_version, Integer, null: true
    # 16e2：code editor 的檔案鎖底版（overlay 列不存在＝null——首存免帶）。
    field :file_lock_version, Integer, null: true do
      argument :path, String, required: true
    end
    # 16e3：覆寫狀態圖——path → "overlaid"（base 檔被蓋＝可還原）｜"new"
    # （overlay-only 新檔＝可刪除）。未覆寫檔不出現。
    field :overlay_state, GraphQL::Types::JSON, null: false

    def id = "gid://chilllove/Theme/#{object.id}"
    def preview_url = "/admin/store/preview/#{object.id}"

    def section_catalog
      source = ThemeEngine::Sources.resolve(object)
      return [] if source.nil?

      translate = ThemeEngine::SchemaLocale.resolver_for(source)
      each_section_schema(source).filter_map do |type, schema|
        next if schema["presets"].blank?

        preset = schema["presets"].first || {}
        { "type" => type,
          "name" => translate.call(schema["name"] || type),
          "preset" => { "settings" => preset["settings"] || {}, "blocks" => preset["blocks"] } }
      end
    end

    def preview_paths
      shop_id = object.shop_id
      paths = {}
      product = Product.where(shop_id:, status: "active").order(:id).pick(:handle)
      paths["product"] = "/products/#{product}" if product
      collection = Collection.where(shop_id:).order(:id).pick(:handle)
      paths["collection"] = "/collections/#{collection}" if collection
      page = Page.where(shop_id:).order(:id).pick(:handle) if defined?(Page)
      paths["page"] = "/pages/#{page}" if page
      blog = Blog.where(shop_id:).order(:id).pick(:handle) if defined?(Blog)
      paths["blog"] = "/blogs/#{blog}" if blog
      paths["cart"] = "/cart"
      paths["search"] = "/search"
      paths["list-collections"] = "/collections"
      paths
    end

    def section_groups
      source = ThemeEngine::Sources.resolve(object)
      return [] if source.nil?

      layout = source.read("layout/theme.liquid").to_s
      layout.scan(/\{%-?\s*sections\s+'([^']+)'/).flatten.uniq.filter_map do |name|
        raw = source.read("sections/#{name}.json")
        json = begin
          raw ? ThemeEngine::Runtime.tolerant_json(raw) : nil
        rescue JSON::ParserError
          nil
        end
        next if json.nil?

        path = "sections/#{name}.json"
        { "name" => name, "path" => path, "json" => json.slice("sections", "order"),
          "lockVersion" => ThemeFileOverlay.where(shop_id: object.shop_id, theme_id: object.id,
                                                  path:).pick(:lock_version) }
      end
    end

    def section_schemas
      source = ThemeEngine::Sources.resolve(object)
      return {} if source.nil?

      translate = ThemeEngine::SchemaLocale.resolver_for(source)
      theme_blocks = theme_block_defs(source, translate) # blocks/*.liquid（@theme 白名單展開）
      each_section_schema(source).to_h do |type, schema|
        [ type, { "name" => translate.call(schema["name"] || type),
                  "settings" => translate_defs(Array(schema["settings"]), translate),
                  "max_blocks" => schema["max_blocks"],
                  "blocks" => block_defs_for(schema, theme_blocks, translate) } ]
      end
    end

    # PR-6：section schema 的 block 定義面（樹的 add-block 白名單＋block 設定
    # 面板資料源）。本地 blocks＝逐 def 帶 settings；`{"type":"@theme"}`＝
    # 展開 blocks/*.liquid 全集（24 §2.4：presets 必須有才進 picker——但
    # add-block 白名單是 blocks 定義本身，不看 preset）。@app 先跳過（無 app 層）。
    def block_defs_for(schema, theme_blocks, translate)
      Array(schema["blocks"]).flat_map do |bdef|
        next [] unless bdef.is_a?(Hash)
        next theme_blocks if bdef["type"] == "@theme"
        next [] if bdef["type"] == "@app"

        [ { "type" => bdef["type"],
            "name" => translate.call(bdef["name"] || bdef["type"]),
            "limit" => bdef["limit"],
            "settings" => translate_defs(Array(bdef["settings"]), translate) } ]
      end
    end

    def theme_block_defs(source, translate)
      source.list.filter_map do |rel|
        next unless rel.start_with?("blocks/") && rel.end_with?(".liquid")

        raw = source.read(rel)
        schema_json = raw && raw[ThemeEngine::Runtime::SCHEMA_RE, 1]
        schema = begin
          schema_json && ThemeEngine::Runtime.tolerant_json(schema_json)
        rescue JSON::ParserError
          nil
        end
        next if schema.nil?

        type = File.basename(rel, ".liquid")
        { "type" => type, "name" => translate.call(schema["name"] || type),
          "settings" => translate_defs(Array(schema["settings"]), translate) }
      end
    end

    def files(filenames: nil, first: nil)
      source = ThemeEngine::Sources.resolve(object)
      return [] if source.nil?

      rels = source.list
      if filenames.present?
        patterns = filenames.first(50) # 官方上限
        rels = rels.select { |rel| patterns.any? { |pattern| File.fnmatch?(pattern, rel) } }
      end
      rels = rels.first([ first || 250, 2500 ].min) # 官方 "At most 2500"
      rels.map { |rel| { filename: rel, size: source.size_of(rel).to_i, source: } }
    end

    def settings_schema
      source = ThemeEngine::Sources.resolve(object)
      return [] if source.nil?

      raw = source.read("config/settings_schema.json")
      groups = begin
        raw ? ThemeEngine::Runtime.tolerant_json(raw) : []
      rescue JSON::ParserError
        []
      end
      return [] unless groups.is_a?(Array)

      translate = ThemeEngine::SchemaLocale.resolver_for(source)
      groups.filter_map do |group|
        next unless group.is_a?(Hash)
        next if group["name"] == "theme_info" # 首項中繼資料，非設定分組（24 §2.5）

        { "name" => translate.call(group["name"].to_s),
          "settings" => translate_defs(Array(group["settings"]), translate) }
      end
    end

    # 生效值＝DB 覆寫層優先（與 Runtime#db_settings → file current 同讀序）。
    def theme_settings_json
      row = ThemeSetting.find_by(shop_id: object.shop_id, theme_id: object.id)
      return row.settings if row

      source = ThemeEngine::Sources.resolve(object)
      raw = source&.read("config/settings_data.json")
      data = begin
        raw ? ThemeEngine::Runtime.tolerant_json(raw) : {}
      rescue JSON::ParserError
        {}
      end
      data["current"] || {}
    end

    def overlay_state
      base = ThemeEngine::Sources.base_resolve(object)
      base_list = base ? base.list : []
      ThemeFileOverlay.where(shop_id: object.shop_id, theme_id: object.id)
                      .pluck(:path)
                      .to_h { |path| [ path, base_list.include?(path) ? "overlaid" : "new" ] }
    end

    def file_lock_version(path:)
      ThemeFileOverlay.where(shop_id: object.shop_id, theme_id: object.id, path:).pick(:lock_version)
    end

    def theme_settings_lock_version
      ThemeSetting.where(shop_id: object.shop_id, theme_id: object.id).pick(:lock_version)
    end

    # 控件定義子集化＋label/info/content 與 options[].label 的 t: 解析（26 §5）。
    def translate_defs(defs, translate)
      defs.filter_map do |setting|
        next unless setting.is_a?(Hash)

        translated = setting.slice("id", "type", "label", "info", "content", "default",
                                   "placeholder", "min", "max", "step", "unit", "options", "limit")
        %w[label info content].each do |key|
          translated[key] = translate.call(translated[key]) if translated[key]
        end
        if translated["options"].is_a?(Array)
          translated["options"] = translated["options"].map do |option|
            option.is_a?(Hash) ? option.merge("label" => translate.call(option["label"])) : option
          end
        end
        translated
      end
    end

    # @return [Enumerator] (type, parsed schema) —— schema-less 檔跳過
    def each_section_schema(source)
      return to_enum(:each_section_schema, source) unless block_given?

      source.list.each do |rel|
        next unless rel.start_with?("sections/") && rel.end_with?(".liquid")

        raw = source.read(rel)
        schema_json = raw && raw[ThemeEngine::Runtime::SCHEMA_RE, 1]
        schema = begin
          schema_json && ThemeEngine::Runtime.tolerant_json(schema_json)
        rescue JSON::ParserError
          nil
        end
        yield File.basename(rel, ".liquid"), schema unless schema.nil?
      end
    end

    def import_report
      report = ThemeImportReport.where(shop_id: object.shop_id, theme_id: object.id)
                                .order(:id).last
      report&.report
    end

    def template_lock_version(key:)
      return nil unless key.match?(/\A[\w.\-]+\z/)

      Template.where(shop_id: object.shop_id, theme_id: object.id, key:).pick(:lock_version)
    end

    def template_json(key:)
      return nil unless key.match?(/\A[\w.\-]+\z/) # 防路徑逃逸

      row = Template.find_by(shop_id: object.shop_id, theme_id: object.id, key:)
      return row.content if row

      raw = ThemeEngine::Sources.resolve(object)&.read("templates/#{key}.json")
      raw && ThemeEngine::Runtime.tolerant_json(raw)
    rescue JSON::ParserError
      nil
    end
  end
end
