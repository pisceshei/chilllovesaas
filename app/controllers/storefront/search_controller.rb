# frozen_string_literal: true

module Storefront
  # Predictive Search 端點雙形（步 12b；契約正典＝96 §4）。
  #
  # ①`GET /search/suggest.json`（官方 Ajax 形）：參數 `q`＋`resources[type|limit|
  #   limit_scope|options[...]]`；回 `{resources:{results:{<請求型>:[…]}}}`——
  #   **只回請求的型別鍵**（live 實證），product 條目 16 鍵＋decimal 字串金額＋
  #   `_pos/_psq/_psid/_ss=e` 歸因參數（96 §4.2 逐鍵）。
  # ②`GET /search/suggest`（section 形；Ella header 搜尋實際打的那形——96 §4.3）：
  #   `section_id`＝**section 檔名**，回該 section 以 `predictive_search` 物件渲染
  #   的 HTML；未知檔 ⇒ 404（官方 "Section not found"）。
  # ③參數非法一律 422（官方 "Invalid parameter error"；body 細形官方未逐字公開，
  #   對位 cart 錯誤三鍵形——91 §3.61）。
  # ④query 型建議 v1 恆空陣列（官方僅英文＋內部 ML——91 §3.61）。
  class SearchController < BaseController
    before_action :require_published_theme!, only: :suggest_section

    RESOURCE_TYPES = %w[product page article collection query].freeze
    DEFAULT_TYPES = %w[query product collection page].freeze # 官方預設——不含 article
    PER_TYPE_CAP = 10 # 官方："no more than 10 predictive suggestions per request type"

    # GET /search/suggest.json
    def suggest_json
      types, limit, limit_scope, fields = validate_params!
      results = build_results(types:, limit:, limit_scope:, fields:)
      render json: { "resources" => { "results" => results } }
    rescue ParamError => e
      render json: { "status" => 422, "message" => "Invalid parameter error",
                     "description" => e.message }, status: :unprocessable_content
    end

    # GET /search/suggest（section 形）
    def suggest_section
      sid = params[:section_id].to_s
      if sid.blank? || current_theme.nil?
        return render plain: "", status: :not_found
      end

      types, limit, limit_scope, fields = validate_params!
      drops = build_drop_results(types:, limit:, limit_scope:, fields:)
      drop = ThemeEngine::PredictiveSearchDrop.new(
        terms: query_param, resources: drops, types: types & %w[product page article collection]
      )
      result = renderer.render("/search", params: { "section_id" => sid },
                                          assigns: { "predictive_search" => drop })
      return render plain: "", status: :not_found if result.status == 404

      render html: result.html.html_safe, layout: false
    rescue ParamError
      render plain: "", status: :unprocessable_content
    end

    private

    class ParamError < StandardError; end

    def query_param = params[:q].to_s

    # 官方值域驗證（96 §4.1）：type ⊆ 5 值；limit 1–10；limit_scope all|each；
    # options[fields] ⊆ 官方九值。非法 ⇒ 422。
    def validate_params!
      resources = params[:resources].respond_to?(:to_unsafe_h) ? params[:resources].to_unsafe_h : {}
      types = resources["type"].to_s.split(",").map(&:strip).reject(&:empty?)
      types = DEFAULT_TYPES if types.empty?
      bad = types - RESOURCE_TYPES
      raise ParamError, "Invalid resources[type]: #{bad.join(',')}" if bad.any?

      limit = resources.key?("limit") ? resources["limit"].to_s : "10"
      raise ParamError, "Invalid resources[limit]" unless limit.match?(/\A\d+\z/) &&
                                                          limit.to_i.between?(1, 10)

      limit_scope = resources.fetch("limit_scope", "all")
      raise ParamError, "Invalid resources[limit_scope]" unless %w[all each].include?(limit_scope)

      fields = (resources.dig("options", "fields") || "").to_s.split(",").map(&:strip).reject(&:empty?)
      fields = SearchQuery::PREDICTIVE_DEFAULT_FIELDS if fields.empty?
      bad_fields = fields - SearchQuery::FIELD_ATOMS
      raise ParamError, "Invalid resources[options][fields]" if bad_fields.any?

      unavailable = resources.dig("options", "unavailable_products")
      if unavailable.present? && !%w[show hide last].include?(unavailable)
        raise ParamError, "Invalid resources[options][unavailable_products]"
      end

      [ types, limit.to_i, limit_scope, fields ]
    end

    # 各型結果的 AR 列集合（依 limit_scope 分配；型別順序＝官方預設鍵序）。
    def fetch_rows(types:, limit:, limit_scope:, fields:)
      publication = Publication.online_store!
      caps = types.index_with { |_t| limit_scope == "each" ? [ limit, PER_TYPE_CAP ].min : nil }
      remaining = limit_scope == "all" ? [ limit, PER_TYPE_CAP ].min : nil
      rows = {}
      ActsAsTenant.with_tenant(current_shop) do
        %w[query product collection page article].each do |type|
          next unless types.include?(type)

          cap = caps[type] || remaining || 0
          list = case type
          when "product"
            query_param.present? && cap.positive? ? SearchQuery.products(
              shop: current_shop, publication:, query: query_param, fields:
            ).order(:title, :id).limit(cap).includes(
              product_variants: [ :product_variant_option_values,
                                  { inventory_item: :inventory_levels },
                                  { media: :stored_file } ],
              product_options: :option_values, media: :stored_file
            ).to_a : []
          when "collection"
            query_param.present? && cap.positive? ? SearchQuery.collections(
              publication:, query: query_param
            ).order(:title, :id).limit(cap).to_a : []
          when "page"
            query_param.present? && cap.positive? ? SearchQuery.pages(
              shop: current_shop, query: query_param
            ).order(:title, :id).limit(cap).to_a : []
          when "article"
            query_param.present? && cap.positive? ? SearchQuery.articles(
              shop: current_shop, query: query_param
            ).includes(:blog).order(:title, :id).limit(cap).to_a : []
          else [] # query 建議 v1 空（91 §3.61）
          end
          rows[type] = list
          remaining = [ remaining - list.size, 0 ].max if remaining
        end
      end
      rows
    end

    # .json 形：官方 16 鍵序列化（96 §4.2）。
    def build_results(types:, limit:, limit_scope:, fields:)
      rows = fetch_rows(types:, limit:, limit_scope:, fields:)
      psid = SecureRandom.hex(5)[0, 9]
      results = {}
      types.each do |type|
        key = type == "query" ? "queries" : "#{type}s"
        results[key] = case type
        when "product"
          rows.fetch("product", []).each_with_index.map do |product, index|
            product_suggestion_json(product, position: index + 1, psid:)
          end
        when "collection"
          rows.fetch("collection", []).map { |c| collection_suggestion_json(c) }
        when "page"
          rows.fetch("page", []).map { |p| page_suggestion_json(p) }
        when "article"
          rows.fetch("article", []).map { |a| article_suggestion_json(a) }
        else []
        end
      end
      results
    end

    # section 形：drop 陣列（PredictiveSearchDrop.resources）。
    def build_drop_results(types:, limit:, limit_scope:, fields:)
      rows = fetch_rows(types:, limit:, limit_scope:, fields:)
      publication = Publication.online_store!
      {
        "products" => rows.fetch("product", []).map do |product|
          ThemeEngine::ProductDrop.new(product, url_prefix:, publication:)
        end,
        "collections" => rows.fetch("collection", []).map do |collection|
          ThemeEngine::CollectionDrop.new(collection, url_prefix:, publication:)
        end,
        "pages" => rows.fetch("page", []).map { |page| ThemeEngine::PageDrop.new(page, url_prefix:) },
        "articles" => rows.fetch("article", []).map do |article|
          ThemeEngine::ArticleDrop.new(article, url_prefix:)
        end
      }
    end

    # cents → "365.00"（divmod 紀律；96 §4.2 live 實證 decimal 字串——與
    # recommendations 的整數分是兩個出口，鐵律 3 不得合併）。
    def decimal_string(cents)
      format("%d.%02d", cents / 100, cents % 100)
    end

    def product_suggestion_json(product, position:, psid:)
      variants = product.product_variants.sort_by(&:position)
      prices = variants.map(&:price_cents)
      compares = variants.filter_map(&:compare_at_price_cents)
      image = product.media.min_by(&:position)&.stored_file
      image_url = image && Storage::LocalDisk.url_for(image.storage_key)
      available = variants.any? { |v| variant_available?(v) }
      {
        "available" => available,
        "body" => product.description_html,
        "compare_at_price_max" => compares.max ? decimal_string(compares.max) : nil,
        "compare_at_price_min" => compares.min ? decimal_string(compares.min) : nil,
        "handle" => product.handle,
        "id" => product.id,
        "image" => image_url,
        "price" => decimal_string(prices.min || 0),
        "price_max" => decimal_string(prices.max || 0),
        "price_min" => decimal_string(prices.min || 0),
        "tags" => product.tags.to_a,
        "title" => product.title,
        "type" => product.product_type.to_s,
        "url" => "#{url_prefix}/products/#{product.handle}" \
                 "?_pos=#{position}&_psq=#{ERB::Util.url_encode(query_param)}&_psid=#{psid}&_ss=e",
        "variants" => [],
        "vendor" => product.vendor,
        "featured_image" => image && {
          "alt" => image.alt_text, "aspect_ratio" => image_aspect(image),
          "height" => image.height, "url" => image_url, "width" => image.width
        }
      }
    end

    def collection_suggestion_json(collection)
      { "id" => collection.id, "handle" => collection.handle, "title" => collection.title,
        "body" => collection.description_html.presence,
        "url" => "#{url_prefix}/collections/#{collection.handle}" }
    end

    def article_suggestion_json(article)
      { "id" => article.id, "handle" => "#{article.blog.handle}/#{article.handle}",
        "title" => article.title, "body" => article.body_html,
        "url" => "#{url_prefix}/blogs/#{article.blog.handle}/#{article.handle}" }
    end

    def page_suggestion_json(page)
      { "id" => page.id, "handle" => page.handle, "title" => page.title,
        "body" => page.body_html, "url" => "#{url_prefix}/pages/#{page.handle}" }
    end

    def image_aspect(file)
      file.width && file.height && file.height.positive? ? file.width.to_f / file.height : nil
    end

    # 可用性（同 VariantDrop.available 語義：未追蹤＝可售；追蹤看跨地點合計
    # 或 inventory_policy=continue 超賣）。
    def variant_available?(variant)
      item = variant.inventory_item
      return true if item.nil? || !item.tracked

      return true if variant.inventory_policy == "continue"

      item.inventory_levels.sum { |level| level.available.to_i }.positive?
    end

    # 前綴：帶前綴路由給 locale_prefix param；裸路由退回預設 presence 前綴（67 §F.1）。
    def url_prefix
      @url_prefix ||= begin
        prefix = params[:locale_prefix].to_s
        if prefix.present?
          "/#{prefix}"
        else
          ActsAsTenant.with_tenant(current_shop) do
            market = Market.find_by(is_primary: true)
            presence = market&.market_web_presences&.first
            presence ? Markets::UrlPrefix.for(presence, presence.default_shop_locale) : ""
          end
        end
      rescue Markets::UrlPrefix::Error
        ""
      end
    end

    # section 形 v1 用預設字典（locale: nil）——完整 locale 解析需 PrefixIndex 域名
    # 鏈，預測下拉的字串面小；91 §3.61 ⚪。
    def renderer
      ThemeEngine::PageRenderer.new(
        theme: current_theme, shop: current_shop, publication: Publication.online_store!,
        url_prefix:, host: request.host, asset_base: "/theme-assets", locale: nil
      )
    end
  end
end
