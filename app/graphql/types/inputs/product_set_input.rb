# frozen_string_literal: true

module Types
  module Inputs
    # `productSet` 的全樹宣告式輸入（63 §B.4：建立與更新同一支，差別只在有無 id）。
    #
    # v1 射程＝建立態＋隱含變體；`id` 已宣告但服務端暫回 INVALID（更新態屬
    # 後續包）——欄位先進 schema 是刻意的：**schema 形狀是客戶端寫死的東西**，
    # 之後補行為不補欄位，客戶端不用改 query。
    #
    # @see docs/specs/63-product-data-flow.md §B.4
    class ProductSetInput < GraphQL::Schema::InputObject
      graphql_name "ProductSetInput"
      description "商品全樹宣告式 upsert 輸入。"

      argument :id, ID, required: false,
        description: "既有商品 GID；省略＝建立。"
      argument :lock_version, Integer, required: false,
        description: "樂觀鎖版本（63 §A.4：涵蓋整棵樹）。更新（帶 id）時必填。"
      argument :title, String, required: false, description: "商品標題（建立時必填）。"
      argument :description_html, String, required: false,
        description: "富文本說明（服務端依白名單 sanitize）。"
      argument :status, Types::ProductStatusEnum, required: false,
        description: "商品狀態；建立未帶時預設 DRAFT。"
      argument :handle, String, required: false,
        description: "URL handle（a-z0-9-）；省略時由標題自動生成。手填衝突一律拒絕。"
      argument :options, [ Types::Inputs::ProductSetOptionInput ], required: false,
        description: "選項樹（宣告式全量：未列出的既有選項視為刪除；缺席＝不動選項面）。"
      argument :variants, [ Types::Inputs::ProductSetVariantInput ], required: false,
        description: "變體全樹（宣告式：未列出視為刪除）。v1 恰一筆（隱含變體）。"
      # ── 組織分類＋SEO（91 §11–12 對齊，P1 包）。缺席（nil）＝更新態保持現值；
      #    空字串／空陣列＝清除——admin SPA 是宣告式恆送，缺席只發生在 API 直呼叫，
      #    語義與 status 的「缺席＝保持現值」一致（normalize 註釋）。──
      argument :vendor, String, required: false,
        description: "廠商；空字串＝清除，缺席＝保持現值。"
      argument :product_type, String, required: false,
        description: "產品類型（自由文字，search-or-create）；空字串＝清除。"
      argument :tags, [ String ], required: false,
        description: "標籤全量（宣告式覆寫）；空陣列＝清空。上限引 product.max_tags。"
      argument :seo, Types::Inputs::SeoInput, required: false,
        description: "SEO 覆寫；子欄位各自缺席＝保持現值。"
      # 內容翻譯（ML-2；67 §C.2）。缺席＝不動該譯文；空字串＝刪除該譯文列（回落來源語言）。
      # 🔴 來源語言的文字在 base row（title／descriptionHtml／seo），**不得**經這裡寫。
      argument :translations, [ Types::Inputs::TranslationInput ], required: false,
        description: "非來源語言的譯文（title／body_html／meta_title／meta_description）。"
    end
  end
end
