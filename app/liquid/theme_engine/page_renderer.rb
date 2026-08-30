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
    Result = Struct.new(:status, :html, :page_type, keyword_init: true)

    def initialize(theme:, shop:, publication:, url_prefix: "", design_mode: false, host: nil, source: nil)
      @theme, @shop, @publication = theme, shop, publication
      @url_prefix, @design_mode, @host = url_prefix, design_mode, host
      @source = source
    end

    # @param path [String] 前綴已剝除的站內路徑（如 "/products/rose-serum"）
    # @return [Result]
    # @note 整段在租戶脈絡內執行（引擎的全部 DB 讀取——templates／theme_settings／
    #   menus／lookup——都要 tenant；巢狀 with_tenant 冪等，controller 已設也無妨）。
    def render(path)
      ActsAsTenant.with_tenant(@shop) { render_inside_tenant(path) }
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
          found && Product.where(shop_id: @shop.id, id: found.id)
                          .includes(:product_variants, :product_options).first
        end
        product ? [ "product", { "product" => ProductDrop.new(product, url_prefix: @url_prefix) }, 200 ] : not_found
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
