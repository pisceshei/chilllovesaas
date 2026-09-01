# frozen_string_literal: true

module Storefront
  # 前台搜尋的查詢組裝（步 12b；96 §3/§4）。
  #
  # ①射程：products＝discoverable（模型正典：搜尋用 discoverable）；collections＝
  #   published_on；pages＝visible。articles v1 無表 ⇒ 呼叫端回空集。
  # ②匹配語義（ours，96 §8-4——官方未逐字列整頁搜尋欄位集）：詞以空白切分、
  #   **每個詞都要命中至少一個欄位**（AND across terms、OR across fields）；
  #   LIKE 萬用字元跳脫（sanitize_sql_like）。
  # ③predictive 預設欄位集＝官方逐字 "title, product_type, variants.title, and
  #   vendor"（96 §4.1）；整頁搜尋另加 body（ours）。
  # ④`options[prefix]`/`options[unavailable_products]` v1 不改變匹配（91 §3.61 ⚪）
  #   ——LIKE %term% 是官方末詞前綴比對的超集。
  module SearchQuery
    module_function

    # options[fields] 官方值域（96 §4.1 逐字九值；author 對 v1 無 articles＝空集欄）。
    FIELD_ATOMS = %w[author body product_type tag title variants.barcode variants.sku
                     variants.title vendor].freeze
    PREDICTIVE_DEFAULT_FIELDS = %w[title product_type variants.title vendor].freeze
    PAGE_SEARCH_PRODUCT_FIELDS = %w[title vendor product_type body variants.title
                                    variants.sku].freeze

    PRODUCT_COLUMN_SQL = {
      "title" => "products.title LIKE :like",
      "vendor" => "products.vendor LIKE :like",
      "product_type" => "products.product_type LIKE :like",
      "body" => "products.description_html LIKE :like",
      "tag" => "JSON_SEARCH(products.tags, 'one', :like) IS NOT NULL"
    }.freeze
    VARIANT_COLUMN_SQL = {
      "variants.title" => "pv.title LIKE :like",
      "variants.sku" => "pv.sku LIKE :like",
      "variants.barcode" => "pv.barcode LIKE :like"
    }.freeze

    def terms_of(query)
      query.to_s.strip.split(/\s+/).first(10)
    end

    # @return [ActiveRecord::Relation] discoverable ∧ 全詞命中
    def products(shop:, publication:, query:, fields: PAGE_SEARCH_PRODUCT_FIELDS, at: Time.current)
      relation = Product.discoverable(publication:, at:)
      terms_of(query).each do |term|
        relation = relation.where(term_condition(shop, term, fields))
      end
      relation
    end

    def collections(publication:, query:, at: Time.current)
      relation = Collection.published_on(publication, at:)
      terms_of(query).each do |term|
        relation = relation.where(Collection.sanitize_sql_array(
          [ "collections.title LIKE :like", { like: like(term) } ]
        ))
      end
      relation
    end

    def pages(shop:, query:, at: Time.current)
      relation = Page.visible(at:).where(shop_id: shop.id)
      terms_of(query).each do |term|
        relation = relation.where(Page.sanitize_sql_array(
          [ "(pages.title LIKE :like OR pages.body_html LIKE :like)", { like: like(term) } ]
        ))
      end
      relation
    end

    def like(term)
      "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    end

    # 單詞 × 欄位集 ⇒ OR 片段（變體欄位走 EXISTS 子查詢，帶 shop_id 條件——鐵律 2③）。
    def term_condition(shop, term, fields)
      pieces = []
      fields.each do |field|
        if (sql = PRODUCT_COLUMN_SQL[field])
          pieces << sql
        elsif VARIANT_COLUMN_SQL.key?(field)
          pieces << "EXISTS (SELECT 1 FROM product_variants pv WHERE pv.shop_id = :shop_id " \
                    "AND pv.product_id = products.id AND #{VARIANT_COLUMN_SQL.fetch(field)})"
        end
      end
      return "1=0" if pieces.empty?

      Product.sanitize_sql_array(
        [ "(#{pieces.join(' OR ')})", { like: like(term), shop_id: shop.id } ]
      )
    end
  end
end
