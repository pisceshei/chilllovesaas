# frozen_string_literal: true

module Types
  # 一個 publishable 在一個 publication 上的發布狀態（S2）。
  #
  # ## 🔴 我方只實作 **V2** 語義，不提供 V1（ours 偏離，登記在此）
  #
  # 本尊有**兩個讀出投影**，而同名的 `isPublished` 在「已排程但尚未到點」這一格
  # **給出相反的答案**。官方原文逐字（取證 2026-08-26）：
  #
  # - `ResourcePublication`（V1）：
  #   `Whether the resource publication is published. Also returns true if the resource
  #   publication is scheduled to be published. If false, then the resource publication is
  #   neither published nor scheduled to be published.`
  #   （<https://shopify.dev/docs/api/admin-graphql/latest/objects/ResourcePublication>）
  # - `ResourcePublicationV2`：
  #   `Whether the resource publication is published. If true, then the resource publication
  #   is published to the publication. If false, then the resource publication is staged to
  #   be published to the publication.`
  #   （<https://shopify.dev/docs/api/admin-graphql/latest/objects/ResourcePublicationV2>）
  #
  # | 實際狀態 | V1 `isPublished` | V2 `isPublished` |
  # |---|---|---|
  # | 已發布（到點） | true | true |
  # | 🔴 已排程未到點 | **true** | **false**（staged） |
  # | 既未發布也未排程 | false | **該列不存在** |
  #
  # 最後一列的官方依據逐字：`Unlike ResourcePublication, an instance of
  # ResourcePublicationV2 can't be unpublished. It must either be published or scheduled
  # to be published.`
  #
  # **為什麼只出 V2**（逐條）：
  # 1. admin SPA 是唯一客戶端；V1 存在的理由（`Channel.*PublicationsV3` 那條線）我方沒有。
  # 2. V1 帶兩個已知誤用源：`isPublished=true` 涵蓋排程態、`publishDate` 用 **epoch 哨兵**
  #    （官方逐字 `If the product isn't published, then this field returns an epoch timestamp.`
  #    且型別是 `DateTime!` **不可為 null**）。兩者都是「在非排程態下 100% 測綠」的形態。
  # 3. V2 的 `catalogType` 參數是唯一能表達 market／company_location 目錄發布狀態的路徑；V1 沒有。
  # 4. `resourcePublicationsV2` **有** `onlyPublished`（Boolean, default true）
  #    ⇒ V2 是 V1 的功能超集，只出 V2 沒有缺口（本輪定點複驗
  #    <https://shopify.dev/docs/api/admin-graphql/latest/interfaces/Publishable>，2026-08-26）。
  #
  # 🔴 **不得寫「官方建議改用 V2」或「V1 是 legacy」**——官方**沒有這句**（未取得）。
  #   可以說的只有「官方指南只教 V2」。兩者在 latest 皆**無** deprecation 標記。
  #
  # 🔴 **日後若要補 V1 相容面，必須用不同型別承載**（不得共用同一個 `is_published` 欄名）——
  #   形態與鐵律 3 的 `Money::Storage` / `Money::PspMinor` 型別隔離同構：
  #   同名不同義的兩個值放同一個型別上，遲早有人拿錯。
  #
  # ## ⚠️ `isPublished` 只是三層 AND 的**第二層**
  #
  # `docs/specs/88` §1 的可見性是 Publishable × Publication × Catalog 三層 AND。
  # 本欄位**不含 catalog 層**（第三層屬 S10，在它落地前恆真）。
  # ⇒ 前台可見性請用 `Product.purchasable`／`discoverable`，**不要**拿本欄位當可見性判準。
  #
  # @see docs/dev/m2-resource-publication-semantics.md
  # @see docs/research/82-admin-channels.md §12
  class ResourcePublicationV2Type < BaseObject
    graphql_name "ResourcePublicationV2"
    description "一個資源在一個管道上的發布狀態（已發布或已排程；未發布的列不存在）。"

    field :publication, Types::PublicationType, null: false,
      description: "發布到的管道。"
    field :is_published, Boolean, null: false,
      description: "true＝已到點發布；**false＝已排程尚未到點（staged）**。🔴 與本尊 V1 投影語義相反，見型別說明。"
    field :publish_date, GraphQL::Types::ISO8601DateTime, null: true,
      description: "發布時刻（已發布＝過去，已排程＝未來）。🔴 本尊 V1 在未發布時回 epoch 哨兵，V2 與我方一律用真值／null。"

    # 🔴 判準走 model 的 `published?`，**不在這裡再寫一次比較**（鐵律 7）。
    #   `ResourcePublication::PUBLISHED_SQL` 與 `#published?` 已經是同一條規則的兩個面，
    #   在序列化層開第三份會讓「到點」在三個地方各判一次。
    #
    # @return [Boolean]
    def is_published
      object.published?
    end

    # @return [Time, nil]
    def publish_date = object.published_at
  end
end
