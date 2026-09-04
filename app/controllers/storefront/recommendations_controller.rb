# frozen_string_literal: true

module Storefront
  # Product Recommendations 端點雙形（步 12b；契約正典＝96 §5）。
  #
  # ①`GET /recommendations/products.json?product_id=&limit=&intent=`：
  #   回 `{"products":[…],"intent":"related|complementary"}`（intent 回聲＝live 實證形）；
  #   product＝Ajax 全形（as_storefront_json，**整數分**——與 suggest 的 decimal 字串
  #   是兩個出口，鐵律 3）＋`pr_*` 歸因參數。
  # ②錯誤（官方逐字）：缺 product_id ⇒ 422 "A product_id value is missing"；
  #   intent 非法 ⇒ 422 "The intent parameter must be one of related, complementary"；
  #   查無或未發布 OS ⇒ 404 "No product with id <id> is published in the online store"。
  # ③演算法 v1（ours，91 §3.61）：related＝共同系列成員（共同系列數多者先、次新
  #   在前）；complementary＝**空陣列**（官方："Complementary recommendations need
  #   to be manually set up."——未配置的真實形即空，live 實證）。
  # ④section 形：`?section_id=`＋`product_id` ⇒ 以 `recommendations` 物件渲染該
  #   section（performed?/products/products_count/intent——官方四屬性）。
  class RecommendationsController < BaseController
    before_action :require_published_theme!, only: :products_section

    INTENTS = %w[related complementary].freeze

    # GET /recommendations/products.json
    def products_json
      product, intent, limit = validate!
      products = recommend(product, intent, limit)
      psid = 0
      payload = products.map do |rec|
        psid += 1
        drop_json(rec, ref: product, seq: psid)
      end
      render json: { "products" => payload, "intent" => intent }
    rescue ParamError => e
      render json: { "message" => e.message }, status: e.status
    end

    # GET /recommendations/products（section 形）
    def products_section
      product, intent, limit = validate!
      sid = params[:section_id].to_s
      return render plain: "", status: :not_found if sid.blank?

      publication = Publication.online_store!
      drops = recommend(product, intent, limit).map do |rec|
        ThemeEngine::ProductDrop.new(rec, url_prefix:, publication:)
      end
      rec_drop = ThemeEngine::BaseDrop.new({
        "performed" => true, "performed?" => true, "products" => drops, # E8b：Ella 讀 `recommendations.performed`（無 ?）
        "products_count" => drops.size, "intent" => intent
      })
      result = renderer.render("/products/#{product.handle}",
                               params: { "section_id" => sid },
                               assigns: { "recommendations" => rec_drop })
      return render plain: "", status: :not_found if result.status == 404

      render html: result.html.html_safe, layout: false
    rescue ParamError => e
      render plain: e.message, status: e.status
    end

    private

    class ParamError < StandardError
      attr_reader :status

      def initialize(message, status)
        super(message)
        @status = status
      end
    end

    def validate!
      raw_id = params[:product_id].to_s
      raise ParamError.new("A product_id value is missing", :unprocessable_content) if raw_id.blank?

      intent = params.fetch(:intent, "related").to_s
      unless INTENTS.include?(intent)
        raise ParamError.new("The intent parameter must be one of related, complementary",
                             :unprocessable_content)
      end

      # limit 超界＝clamp（官方未記載超界行為——ours，91 §3.61）
      limit = params[:limit].to_s[/\A\d+\z/]&.to_i || 10
      limit = limit.clamp(1, 10)

      product = ActsAsTenant.with_tenant(current_shop) do
        Storefront::Lookup.product_by_id(publication: Publication.online_store!, id: raw_id)
      end
      if product.nil?
        raise ParamError.new("No product with id #{raw_id} is published in the online store",
                             :not_found)
      end

      [ product, intent, limit ]
    end

    # related v1＝共同系列成員；complementary＝空（need manual setup——official）。
    def recommend(product, intent, limit)
      return [] if intent == "complementary"

      ActsAsTenant.with_tenant(current_shop) do
        collection_ids = CollectionProduct.where(shop_id: current_shop.id, product_id: product.id)
                                          .pluck(:collection_id)
        picked = collection_ids.empty? ? [] : related_by_collections(product, collection_ids, limit)
        # E12：本尊在共同系列成員不足時仍回其他商品（hoko.vip acme-tee 只在「首頁」系列，`/recommendations/products?section_id=…`
        # 回 bolt-mug、cosy-lamp 兩張卡；兩者都不在該系列）——補位規則官方未逐字（V，91 §3.79）：以其他可見商品依建立時間升冪補到 limit
        # （hoko 兩卡順序＝bolt-mug → cosy-lamp，即建立序）。
        if picked.size < limit
          picked += Product.discoverable(publication: Publication.online_store!)
                           .where.not(id: [ product.id ] + picked.map(&:id))
                           .order(:created_at, :id).limit(limit - picked.size)
                           .includes(product_variants: [ :product_variant_option_values,
                                                         { inventory_item: :inventory_levels },
                                                         { media: :stored_file } ],
                                     product_options: :option_values, media: :stored_file)
                           .to_a
        end
        picked
      end
    end

    def related_by_collections(product, collection_ids, limit)
      ActsAsTenant.with_tenant(current_shop) do
        Product.discoverable(publication: Publication.online_store!)
               .joins(:collection_products)
               .where(collection_products: { collection_id: collection_ids })
               .where.not(id: product.id)
               .group("products.id")
               .order(Arel.sql("COUNT(DISTINCT collection_products.collection_id) DESC, " \
                               "products.created_at DESC, products.id DESC"))
               .limit(limit)
               .includes(product_variants: [ :product_variant_option_values,
                                             { inventory_item: :inventory_levels },
                                             { media: :stored_file } ],
                         product_options: :option_values, media: :stored_file)
               .to_a
      end
    end

    def drop_json(rec, ref:, seq:)
      drop = ThemeEngine::ProductDrop.new(rec, url_prefix:, publication: Publication.online_store!)
      json = drop.as_storefront_json
      json["url"] = "#{url_prefix}/products/#{rec.handle}" \
                    "?pr_prod_strat=collection_fallback&pr_rec_pid=#{rec.id}" \
                    "&pr_ref_pid=#{ref.id}&pr_seq=#{seq}"
      json
    end

    def url_prefix
      @url_prefix ||= begin
        hit = effective_hit # E13：單一真相（前綴命中 > 店預設）；D80：預設語言前綴＝""
        hit ? Markets::UrlPrefix.for(hit.web_presence, hit.locale_tag) : ""
      rescue Markets::UrlPrefix::Error
        ""
      end
    end

    def renderer
      ThemeEngine::PageRenderer.new(
        theme: current_theme, shop: current_shop, publication: Publication.online_store!,
        url_prefix:, host: request.host, asset_base: "/theme-assets",
        locale: effective_hit&.locale_tag, web_presence: effective_hit&.web_presence, # E12：語言跟 URL 前綴（先前 nil ⇒ 英文）；E13：無前綴退回店預設
        market: effective_hit&.market, country_code: effective_hit&.effective_country_code # D80：買家選國覆寫
      )
    end
  end
end
