# frozen_string_literal: true

module Types
  module Inputs
    # 建立 publication 的輸入。
    #
    # 本尊對位＝`PublicationCreateInput`，**恰三個欄位**（經定點複驗「無其他欄位」，取證 2026-08-26）。
    # 我方多一個 `title`，理由見下。
    #
    # @see docs/plans/2026-08-26-S1-規格草案.md §1.1
    class PublicationCreateInput < GraphQL::Schema::InputObject
      graphql_name "PublicationCreateInput"
      description "建立 publication 的輸入。"

      # 🔴 **本尊沒有這個欄位，這是我方新增的（ours）**。
      #   本尊建立 publication 時名字來自 `catalogId` 指向的那個 catalog；
      #   而我方允許省略 `catalogId`（省略就自己建一個 catalog），那時就需要一個名字。
      #   ⚠️ 傳了 `catalogId` 時本欄**被忽略**——顯示名的權威在 catalog 身上（S0 PR A），
      #   在這裡二次指定會製造第二個真相。
      argument :title, String, required: true,
        description: "顯示名。🔴 ours（本尊無此欄）。傳 catalogId 時本欄被忽略——名字以該 catalog 為準。"

      # 官方逐字：`Whether to automatically add newly created products to this publication.`
      # 官方明文 `Default:false`。
      argument :auto_publish, Boolean, required: false, default_value: false,
        description: "新建立的商品是否自動納入本 publication（本尊 Default:false）。"

      # 官方逐字：`The ID of the catalog.`（官方描述只有這一句，無後續）
      # ⚠️ 官方標 nullable；「省略時實際會怎樣」＝官方未取得。我方處置＝自己建一個。
      argument :catalog_id, ID, required: false,
        description: "既有 catalog 的 GID；省略＝本 mutation 自建一個（我方處置，官方對省略行為未載明）。"

      # 官方逐字：`Whether to create an empty publication or prepopulate it with all products.`
      # 官方明文 `Default:EMPTY`。
      argument :default_state, Types::PublicationDefaultStateEnum, required: false, default_value: "EMPTY",
        description: "初始成員狀態（本尊 Default:EMPTY）。ALL_PRODUCTS 本步尚未支援。"
    end
  end
end
