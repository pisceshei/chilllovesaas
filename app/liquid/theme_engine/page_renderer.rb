# frozen_string_literal: true

# 整頁渲染（包 30；路由 → template → sections → layout 的組裝層）。
#
# ①這是什麼：`Runtime` 之上的一層——解析 JSON template（DB 覆寫 → 來源檔）、
#   依 `order` 渲染 sections、把結果塞進 `layout/theme.liquid` 的
#   `content_for_layout`。可見性判準＝`Storefront::Lookup`（specs/93 §C：
#   直連 purchasable；查無 ⇒ :not_found，controller 層轉 404）。
# ②路由值域（v1）：`/`＝index；`/products/:handle`；`/collections/:handle`；
#   `/pages/:handle`；其餘 ⇒ 404 template（78 §4 的 11 型之一）。
#   搜尋／購物車／帳戶等路由隨對應功能線（W6 後續包）。
module ThemeEngine
  class PageRenderer
    # content_type：:html（整頁／單 section）或 :json（?sections= map）。
    Result = Struct.new(:status, :html, :page_type, :content_type, keyword_init: true)

    def initialize(theme:, shop:, publication:, url_prefix: "", design_mode: false, host: nil, source: nil)
      @theme, @shop, @publication = theme, shop, publication
      @url_prefix, @design_mode, @host = url_prefix, design_mode, host
      @source = source
    end

    # @param path [String] 前綴已剝除的站內路徑（如 "/products/rose-serum"）
    # @param params [Hash] query 參數（缺口分析 A2：`variant` 進選中態；
    #   其餘參數目前忽略——`section_id`／`sections` 端點面歸包 33）。
    # @return [Result]
    # @note 整段在租戶脈絡內執行（引擎的全部 DB 讀取——templates／theme_settings／
    #   menus／lookup——都要 tenant；巢狀 with_tenant 冪等，controller 已設也無妨）。
    def render(path, params: {})
      @params = params || {}
      ActsAsTenant.with_tenant(@shop) do
        # Section Rendering API（包 33；契約＝83 §3.4＋§12.3 真店逐格）：
        # 兩參數並存時 `sections` 壓過 `section_id`（實測：回 JSON）。
        if @params["sections"].present?
          render_sections_json(path)
        elsif @params["section_id"].present?
          render_single_section(path)
        else
          render_inside_tenant(path)
        end
      end
    end

    private

    def render_inside_tenant(path)
      page_type, assigns, status = resolve(path)
      runtime = Runtime.new(theme: @theme, shop: @shop, url_prefix: @url_prefix,
                            design_mode: @design_mode, page_type: page_type,
                            path: path, host: @host, source: @source)
      assigns.each { |k, v| runtime.assign(k, v) }
      if (product = assigns["product"])
        runtime.closest = ClosestDrop.new(product: product)
      end

      body = render_template_sections(runtime, page_type)
      html = render_layout(runtime, body)
      Result.new(status: status, html: html, page_type: page_type)
    end

    # @return [Array(String, Hash, Integer)] [template key, 額外 assigns, HTTP status]
    def resolve(path)
      at = Time.current
      case path
      when "/", ""
        [ "index", {}, 200 ]
      when %r{\A/products/([^/]+)\z}
        product = ActsAsTenant.with_tenant(@shop) do
          found = Storefront::Lookup.product_by_handle(publication: @publication, handle: Regexp.last_match(1), at: at)
          # preload 面＝drops 的讀取契約（缺口分析 A′）：庫存鏈（available/
          # inventory_quantity）、變體選項座標（A3 分組）、變體專圖與商品媒體。
          found && Product.where(shop_id: @shop.id, id: found.id)
                          .includes(
                            product_variants: [ :product_variant_option_values,
                                                { inventory_item: :inventory_levels },
                                                { media: :stored_file } ],
                            product_options: :option_values,
                            media: :stored_file
                          ).first
        end
        product ? [ "product", { "product" => ProductDrop.new(product, url_prefix: @url_prefix,
                                                              selected_variant_id: selected_variant_id) }, 200 ] : not_found
      when %r{\A/collections/([^/]+)\z}
        collection = ActsAsTenant.with_tenant(@shop) do
          Storefront::Lookup.collection_by_handle(publication: @publication, handle: Regexp.last_match(1), at: at)
        end
        collection ? [ "collection", { "collection" => CollectionDrop.new(collection, url_prefix: @url_prefix) }, 200 ] : not_found
      when %r{\A/pages/([^/]+)\z}
        page = ActsAsTenant.with_tenant(@shop) do
          Page.visible(at: at).find_by(shop_id: @shop.id, handle: Regexp.last_match(1))
        end
        page ? [ "page", { "page" => PageDrop.new(page, url_prefix: @url_prefix) }, 200 ] : not_found
      else
        not_found
      end
    end

    def not_found = [ "404", {}, 404 ]

    # ── Section Rendering API（包 33） ─────────────────────────────────────
    # 真店契約（83 §12.3，2026-08-31 乾淨態）：
    #   單 id：200 text/html 帶 wrapper；未知 id ⇒ 404 **空 body**（不是主題 404 頁）。
    #   多 id：200 application/json map；未知鍵值＝null；>5 ⇒ 400 空 body。
    #   context 繼承請求頁（含 ?variant= 選中態——Ella 變體切換就靠這疊加）。
    # 🔴 id 語義差異（登記）：本尊＝`template--N__key`／`sections--N__key` 動態
    #   實例 id；我方 v1 無實例編號 ⇒ id＝template JSON 的 section 鍵或群組 JSON
    #   的 section 鍵（DB 實例化隨編輯器寫入面）。
    def render_single_section(path)
      page_type, assigns, = resolve(path)
      runtime = build_runtime(page_type, assigns)
      sid = @params["section_id"].to_s
      data = section_data_for(runtime, page_type, sid)
      return Result.new(status: 404, html: "", page_type: page_type) if data.nil?

      Result.new(status: 200, html: runtime.render_section(sid, data), page_type: page_type)
    end

    def render_sections_json(path)
      ids = @params["sections"].to_s.split(",").map(&:strip).reject(&:empty?)
      max = Limits.fetch(:theme_engine, :section_rendering_max_ids)
      return Result.new(status: 400, html: "", page_type: nil) if ids.size > max

      page_type, assigns, = resolve(path)
      runtime = build_runtime(page_type, assigns)
      map = ids.to_h do |sid|
        data = section_data_for(runtime, page_type, sid)
        [ sid, data && runtime.render_section(sid, data) ]
      end
      Result.new(status: 200, html: JSON.generate(map), page_type: page_type, content_type: :json)
    end

    def build_runtime(page_type, assigns)
      runtime = Runtime.new(theme: @theme, shop: @shop, url_prefix: @url_prefix,
                            design_mode: @design_mode, page_type: page_type,
                            path: nil, host: @host, source: @source)
      assigns.each { |k, v| runtime.assign(k, v) }
      if (product = assigns["product"])
        runtime.closest = ClosestDrop.new(product: product)
      end
      runtime
    end

    # id 解析：①請求頁 template 的 sections ②layout 引用的各群組 JSON 的 sections。
    # 找不到 ⇒ nil（呼叫端依端點轉 404／null）。
    def section_data_for(runtime, page_type, sid)
      tj = runtime.template_json(page_type)
      data = tj && (tj["sections"] || {})[sid]
      return data if data

      layout_group_names(runtime).each do |name|
        g = runtime.load_json("sections/#{name}.json") or next
        found = (g["sections"] || {})[sid]
        return found if found
      end
      nil
    end

    # layout theme.liquid 裡 {% sections 'name' %} 的名單（引擎渲染群組的同一來源）。
    def layout_group_names(runtime)
      layout = runtime.compiled("layout/theme.liquid")
      return [] if layout.nil?

      src = runtime.raw_layout_source
      return [] if src.nil?

      src.scan(/\{%-?\s*sections\s+'([^']+)'/).flatten.uniq
    end

    # A2：`?variant=` → Integer；非數字／缺席 ⇒ nil（壞值忽略＝ours，
    # 本尊壞值行為未取證，缺口分析 §D 登記）。
    def selected_variant_id
      raw = @params["variant"] || @params[:variant]
      raw.to_s =~ /\A\d+\z/ ? raw.to_i : nil
    end

    def render_template_sections(runtime, key)
      tj = runtime.template_json(key)
      return runtime.comment("缺 template #{key}") if tj.nil?

      order = tj["order"] || tj.dig("sections") && tj["sections"].keys || []
      Array(order).map do |k|
        data = (tj["sections"] || {})[k] or next ""
        data["disabled"] ? "" : runtime.render_section(k, data)
      end.join
    end

    def render_layout(runtime, content)
      layout = runtime.compiled("layout/theme.liquid")
      return content if layout.nil? # 缺 layout 寬容（測試最小主題可無 layout）

      assigns = runtime.global_assigns.merge("content_for_layout" => content)
      html = layout[:tpl].render(runtime.build_context(assigns, runtime.base_registers.merge(frame: {})))
      runtime.collect_errors("layout/theme.liquid", layout[:tpl])
      html
    end
  end
end
