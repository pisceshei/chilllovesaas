# frozen_string_literal: true

module Types
  module Inputs
    # 商品系列的宣告式全樹輸入（ML-3；形態與 `ProductSetInput` 對齊：建立與更新同一支）。
    #
    # 語義與商品完全相同（刻意）：缺席＝保持現值、空字串／空陣列＝清除。
    # 兩支 mutation 的語義若不同，商家第一次用系列匯入就會踩到。
    class CollectionSetInput < GraphQL::Schema::InputObject
      graphql_name "CollectionSetInput"
      description "商品系列全樹宣告式 upsert 輸入。"

      argument :id, ID, required: false, description: "既有系列 GID；省略＝建立。"
      argument :lock_version, Integer, required: false, description: "樂觀鎖版本；更新時必填。"
      argument :title, String, required: false, description: "系列標題（建立時必填）。"
      argument :description_html, String, required: false, description: "說明（服務端白名單 sanitize）。"
      argument :handle, String, required: false, description: "URL handle；省略時由標題生成。"
      argument :collection_type, String, required: false, description: "manual／smart（13 §F4）。"
      argument :sort_order, String, required: false, description: "前台排序（manual／best_selling／title_asc…）。"
      argument :seo, Types::Inputs::SeoInput, required: false
      # 🔴 只對手動系列生效：智慧系列的成員是規則的函數，收下它等於製造第二個真相。
      argument :product_ids, [ ID ], required: false,
        description: "手動系列成員（宣告式：未列出＝移除；順序＝陣列順序）。"
      argument :translations, [ Types::Inputs::TranslationInput ], required: false,
        description: "非來源語言的譯文（與商品共用同一張 translations 表）。"
    end
  end
end
