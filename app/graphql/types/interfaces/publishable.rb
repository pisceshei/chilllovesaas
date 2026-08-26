# frozen_string_literal: true

# GraphQL schema type 的 namespace。
module Types
  # GraphQL interface 的 namespace。
  module Interfaces
    # 可以被發布到管道的資源（本尊 `Publishable`）。
    #
    # 實作者恰三個：`Product`／`Collection`／`ProductVariant`
    # ——與 `ResourcePublication::PUBLISHABLE_TYPES` 同一份集合（鐵律 7）。
    #
    # ## 🔴 我方只實作本尊的一部分欄位，逐條說明為什麼
    #
    # 本尊 `Publishable` 的**非** deprecated 欄位共六個（取證 2026-08-26，
    # <https://shopify.dev/docs/api/admin-graphql/latest/interfaces/Publishable>）：
    #
    # | 本尊欄位 | 我方 | 理由 |
    # |---|---|---|
    # | `resourcePublicationsV2` | ✅ 實作 | S2 的本體。見下方形狀差異 |
    # | `resourcePublications`（V1） | ❌ **刻意不做** | V1 的 `isPublished` 把「已排程」也算 true、`publishDate` 用 epoch 哨兵 ⇒ 兩個已知誤用源。理由全文＝`Types::ResourcePublicationV2Type` 檔頭 |
    # | `publishedOnPublication(publicationId)` | ❌ 延後 | 單點查詢，可由 `resourcePublicationsV2` 導出；沒有呼叫端之前不開 |
    # | `resourcePublicationsCount` | ❌ 延後 | 同上；且本尊該欄逐字含 `including publications with feedback errors`，而我方**沒有 feedback 概念** ⇒ 照抄名字會給出不同語義 |
    # | `availablePublicationsCount` | ❌ 延後 | 同上（逐字 `without feedback errors`） |
    # | `unpublishedPublications` | ❌ 延後 | 需要「本店全部 publication 減去已發布」的差集查詢；沒有呼叫端之前不開 |
    #
    # 🔴 **本尊另有五個已 deprecated 的欄位**（`publicationCount`／`publishedOnChannel`／
    #   `publishedOnCurrentChannel`／`publishedOnCurrentPublication`／`unpublishedChannels`）
    #   ——**一個都不實作**。新建系統照抄別人的技術債沒有任何理由。
    #
    # ## ⚠️ 形狀差異：本尊是 connection，我方回 list
    #
    # 本尊 `resourcePublicationsV2: ResourcePublicationV2Connection!`（帶 cursor 分頁）。
    # 我方回 `[ResourcePublicationV2!]!`。理由與 `QueryType#publications` 同一份：
    # 這個集合的大小由**本店 publication 數**界定，而 `config/limits.yml` 的
    # `sales_channels.max_channels` 是 **null（文檔未載）**、實測本尊測試店恰三個管道。
    # 為個位數集合套 keyset 分頁，前端要寫一整套 cursor 處理卻永遠只有一頁。
    # ⚠️ **S10 的 catalog publication 大量出現時要改成 connection**，已登記 `91` §3.21。
    #
    # @see docs/dev/m2-resource-publication-semantics.md
    module Publishable
      include GraphQL::Schema::Interface

      description "可以被發布到管道的資源（Product／Collection／ProductVariant）。"

      field :resource_publications_v2, [ Types::ResourcePublicationV2Type ], null: false,
        description: "本資源在各管道的發布狀態（**已發布或已排程**；未發布的管道不會出現在這裡）。" do
        # 本尊同名參數逐字：`Whether to return only the resources that are currently published`，
        # 官方 default **true**。我方照抄名稱、型別與預設值。
        argument :only_published, Boolean, required: false, default_value: true,
          description: "只回**已到點**的（本尊 Default:true）。false＝連已排程未到點的一起回。"
      end

      # @param only_published [Boolean]
      # @return [Array<ResourcePublication>] 依 publication id 序（穩定順序）
      # @note 副作用：一次 tenant-scoped SELECT ＋ 一次 publication preload。
      def resource_publications_v2(only_published: true)
        scope = object.resource_publications.includes(:publication)
        # 🔴 判準走 model scope，**不在這裡寫時間比較**（鐵律 7）——
        #   `currently_published` / `published_or_staged` 是唯一產生處。
        scope = only_published ? scope.currently_published : scope.published_or_staged
        scope.order(:publication_id).to_a
      end
    end
  end
end
