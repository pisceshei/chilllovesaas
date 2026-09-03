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
    # E3：theme blocks 全表（type → {name, settings, blocks: 可接受子型別}）——巢狀 block 的
    # 樹列與設定面板資料源；`section_schemas[type].blocks` 只覆蓋 section 直屬那層。
    field :theme_blocks, GraphQL::Types::JSON, null: false
    # PR-11：模板→預覽路徑對映（資源語境——product 模板編輯帶真商品）。
    # 取各型第一個已發布資源；無資源的型不出鍵（前端回落首頁）。
    field :preview_paths, GraphQL::Types::JSON, null: false
    # E2（D79 主題編輯器 shell）：頂欄模板選擇器的兩份資料——
    #   template_keys＝來源 `templates/*.json` 的 key ∪ DB Template 列的 key（編輯器
    #   「Create template」建立的替代模板只存在 DB，`files` 讀不到）；不含 `customers/`。
    #   template_assignments＝各資源型依 `template_suffix` 分組的指派數，鍵 ""＝預設模板
    #   （本尊逐字 "Assigned to N products"，`docs/research/100` §1.1）。
    field :template_keys, [ String ], null: false
    field :template_assignments, GraphQL::Types::JSON, null: false
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

    # E2：來源模板 key ∪ DB Template key（`product.custom` 這種 DB-only 替代模板也要出現在
    # 選擇器）。只認 `templates/<key>.json` 一層（`customers/…` 不列——本尊把客戶帳號頁放在
    # 「Checkout and customer accounts」入口，不在此清單）。
    def template_keys
      source = ThemeEngine::Sources.resolve(object)
      from_source = source ? source.list.filter_map { |rel| rel[%r{\Atemplates/([\w.\-]+)\.json\z}, 1] } : []
      from_db = Template.where(shop_id: object.shop_id, theme_id: object.id).pluck(:key)
      (from_source + from_db).uniq.sort
    end

    # E2：`{ "product" => { "" => 3, "custom" => 0 } }` 形——鍵 ""＝預設模板；只列實際有列的
    # suffix（前端對沒有指派的替代模板補 0）。五個資源型與 `Template::TEMPLATE_TYPES` 中可指派
    # 替代模板的型一致（product／collection／page／blog／article）。
    def template_assignments
      shop_id = object.shop_id
      { "product" => suffix_counts(Product.where(shop_id:)),
        "collection" => suffix_counts(Collection.where(shop_id:)),
        "page" => suffix_counts(Page.where(shop_id:)),
        "blog" => suffix_counts(Blog.where(shop_id:)),
        "article" => suffix_counts(Article.where(shop_id:)) }
    end

    def section_groups
      source = ThemeEngine::Sources.resolve(object)
      return [] if source.nil?

      layout = source.read("layout/theme.liquid").to_s
      # E3：群組相對於 `content_for_layout` 的位置——之前的群組列在樹的 Template 帶上方、
      # 之後的列在下方（本尊樹形 100 §2：Header／Popup／General group 在上、Footer group 在下）。
      layout_index = layout.index(/\{\{-?\s*content_for_layout\s*-?\}\}/) || layout.length
      layout.scan(/\{%-?\s*sections\s+'([^']+)'/).flatten.uniq.filter_map do |name|
        raw = source.read("sections/#{name}.json")
        json = begin
          raw ? ThemeEngine::Runtime.tolerant_json(raw) : nil
        rescue JSON::ParserError
          nil
        end
        next if json.nil?

        path = "sections/#{name}.json"
        tag_index = layout.index(/\{%-?\s*sections\s+'#{Regexp.escape(name)}'/) || 0
        { "name" => name, "path" => path, "json" => json.slice("sections", "order"),
          # E3：群組 JSON 自帶 `name`（"Header group"）／`type`（"header"）——本尊小標與
          # `enabled_on.groups` 的比對鍵；無 `name` 時以檔名人性化（"header-group" → "Header group"）。
          "label" => json["name"].presence || name.tr("-_", "  ").capitalize,
          "type" => json["type"].presence || name.sub(/-group\z/, ""),
          "position" => tag_index < layout_index ? "before" : "after",
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
                  # E3／E5：官方 section schema 的可用性三鍵（`enabled_on`／`disabled_on` 的
                  # `templates`／`groups` 清單、`limit`）——群組小標下的 "Add section" 只列可加者、
                  # 已達 limit 的灰化並標 "(1/1)"（100 §4）。
                  "enabled_on" => schema["enabled_on"],
                  "disabled_on" => schema["disabled_on"],
                  "limit" => schema["limit"],
                  "blocks" => block_defs_for(schema, theme_blocks, translate) } ]
      end
    end

    # E3：theme blocks（`blocks/*.liquid`）全表——巢狀 block 的樹列名稱、設定面板與 add-block
    # 白名單都由這張表解析（`section_schemas[type].blocks` 只覆蓋 section 直屬那層）。
    def theme_blocks
      source = ThemeEngine::Sources.resolve(object)
      return {} if source.nil?

      translate = ThemeEngine::SchemaLocale.resolver_for(source)
      theme_block_defs(source, translate).to_h { |bdef| [ bdef["type"], bdef ] }
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
        # E3：可接受的子 block 型別（官方 theme block schema `blocks`：`{"type": "@theme"}`＝全部
        # theme blocks、`{"type": "@app"}`＝app blocks（無 app 層，略）、其餘＝具名型別）。
        # 保留 "@theme" 字面給前端展開（全表在 `theme_blocks`），不在這裡把 N 個 block 各自複製 N 份。
        accepts = Array(schema["blocks"]).filter_map do |bdef|
          next unless bdef.is_a?(Hash)
          next if bdef["type"] == "@app"

          bdef["type"]
        end
        { "type" => type, "name" => translate.call(schema["name"] || type),
          "settings" => translate_defs(Array(schema["settings"]), translate),
          "blocks" => accepts }
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
    # E2：`template_suffix` 分組計數（nil ⇒ ""＝預設模板）。
    # 🔴 我方 schema 只有 pages／blogs／articles 帶 `template_suffix`（`db/schema.rb`），
    #   products／collections 尚無指派欄（商品表單的 "Theme template" 選單是後續包）——
    #   無此欄的資源型全數計入預設模板，不得 raise 把整份 bootstrap 拖垮。
    def suffix_counts(relation)
      if relation.klass.column_names.include?("template_suffix")
        relation.group(:template_suffix).count.transform_keys(&:to_s)
      else
        { "" => relation.count }
      end
    end

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
