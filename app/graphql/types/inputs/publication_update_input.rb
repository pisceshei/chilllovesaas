# frozen_string_literal: true

module Types
  module Inputs
    # 更新 publication 的輸入。
    #
    # 本尊對位＝`PublicationUpdateInput`，**恰三個欄位**（該頁 Fields 區塊沒有
    # `publicationId`、沒有 `name`、也沒有 `catalogId`；取證 2026-08-26）。
    #
    # 🔴 **累加／扣除語義，不是宣告式全量**（`docs/research/82` §11.5 實測）：
    #   本尊的發布 modal 一律以「全部未勾」開場，即使選取的商品已經在某些管道上
    #   ⇒ 沒被列進 `publishablesToRemove` 的資源**不會**被移除。
    #   ⚠️ 這與本倉庫的 `productSet`／`collectionSet` 家族**語義相反**（那兩支是宣告式全量，
    #   未列出＝移除）。照那個習慣實作，商家的一次勾選會清空整個管道。
    #
    # @see docs/plans/2026-08-26-S1-規格草案.md §1.2
    class PublicationUpdateInput < GraphQL::Schema::InputObject
      graphql_name "PublicationUpdateInput"
      description "更新 publication 的輸入（加／減為累加語義，非宣告式全量）。"

      # 官方逐字：`Whether new products should be automatically published to the publication.`
      # 🔴 **本欄在官方 input object 頁未標 default**（與另兩欄不同）
      #   ⇒ update 的預設值＝**未取得**，不得外推 create 頁的 `false`。
      #   我方處置：缺席＝**保持現值**（宣告式家族的一致語義），並在此登記官方未取得。
      argument :auto_publish, Boolean, required: false,
        description: "新商品是否自動發布到本 publication。缺席＝保持現值（🔴 官方未標 default）。"

      # 官方逐字：`A list of publishable IDs to add. The maximum number of publishables to update simultaneously is 50.`
      argument :publishables_to_add, [ ID ], required: false, default_value: [],
        description: "要加入的 publishable GID（Product／Collection／ProductVariant）。"

      # 官方逐字：`A list of publishable IDs to remove. The maximum number of publishables to update simultaneously is 50.`
      argument :publishables_to_remove, [ ID ], required: false, default_value: [],
        description: "要移除的 publishable GID。"
    end
  end
end
