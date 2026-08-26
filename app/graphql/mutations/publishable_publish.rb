# frozen_string_literal: true

module Mutations
  # 把一個資源發布到一或多個 publication（S5）。
  #
  # 本尊對位＝`publishablePublish(id: ID!, input: [PublicationInput!]!)`，
  # 描述逐字（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/publishablePublish>，
  # 取證 2026-08-27）：
  #
  # > Publishes a resource, such as a Product or Collection, to one or more publications.
  # > For products to be visible in a channel, they must have an active ProductStatus.
  # > Products sold exclusively on subscription (requiresSellingPlan: true) can only be
  # > published to online stores. You can schedule future publication by providing a
  # > publish date. Only online store channels support scheduled publishing.
  #
  # ## 🔴 admin 實測：發布是**獨立的 mutation**，不是商品儲存的一部分
  #
  # 測試店實測（`docs/research/82-admin-channels.md` §13，取證 2026-08-27）：
  # 同一顆 `Save` 送出**兩個** POST——`ProductSaveUpdate` 與
  # `ProductSavePublishablePublishUnpublish`；只改發布時**只送後者**，
  # 且兩次的 persisted-query hash 完全相同（一次純新增、一次純移除）。
  # ⇒ ①本尊把兩個方向放在同一個 GraphQL document 裡、逐區塊判 dirty；
  #   ②🔴 **我方不得把 publish／unpublish 併進 `productSet`**。
  # ⚠️ 該 document 內部呼叫的是不是這兩支官方 mutation＝**未取得**
  #   （admin 走 persisted query，POST body 不可觀測，鐵律 14.3）。
  #
  # ## 命名與參數形態的刻意選擇
  #
  # - `publishablePublish` 是 **interfaceVerb** 不是 `28 §0.3` 的 `resourceVerb`
  #   慣例——**照抄本尊**（鐵律 12 的 1:1 優先於我方命名慣例），登記於
  #   `docs/dev/m2-publishable-write.md` §5。
  # - 扁平 `id:` ＋ 舊式 `input:`（不是 `28 §0.3.4` 的具名參數）——引
  #   `docs/dev/m2-publication-lifecycle.md` §5 #3 的**既有豁免**，不重新裁定。
  # - **不跟本尊的 `shop: Shop!` payload 欄位**：我方 `Shop` type 目前沒有
  #   `publicationCount`，跟了就是為零消費者新增一個欄位。登記為刻意偏離。
  #
  # 🔴 **形態範本是 `productCreateMedia`**（全倉唯一與 `(id, [input])` 結構同構
  #   且語義為累加的先例），但**刻意不抄它的 `IDEMPOTENCY_KEY_REQUIRED` 硬擋**
  #   ——理由見 `docs/dev/m2-publishable-write.md` §7（本線天然收斂，
  #   且 `config/limits.yml` 的 `idempotency.required_for` 現值不含本線）。
  #
  # @see docs/dev/m2-publishable-write.md
  # @see docs/research/82-admin-channels.md §13
  class PublishablePublish < BaseMutation
    graphql_name "PublishablePublish"
    description "把一個資源（商品／系列／子類選項）發布到一或多個銷售管道；未來時間＝排程發布。"

    user_errors_type Types::Errors::PublishablePublishUserErrorType

    argument :id, ID, required: true, description: "要發布的資源 GID（Product／Collection／ProductVariant）。"
    argument :input, [ Types::Inputs::PublicationInput ], required: true,
      description: "要發布到哪些 publication。"

    field :publishable, Types::Interfaces::Publishable, null: true,
      description: "已發布的資源。"

    # @param id [String] publishable GID
    # @param input [Array<Types::Inputs::PublicationInput>]
    # @return [Hash] payload
    # @note 副作用：見 `Publications::Write.publish`。
    def resolve(id:, input:)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)

      result = Publications::Write.publish(shop:, publishable_gid: id, entries: normalize(input))

      { publishable: result.publishable, user_errors: result.user_errors }
    end

    private

    # 把 GraphQL input object 攤成純 Hash，服務層才不用認識 GraphQL 型別。
    #
    # 🔴 **`key?` 是用來分辨「省略」與「明確傳 null」的唯一方式**，兩者語義不同：
    #   省略 ⇒ 沿用既有 `published_at`（R5／R7 no-op）；
    #   明確 `null` ⇒ reject（R10——官方對 null 完全沉默，不得自行定義成「取消排程」）。
    #   ⚠️ 只讀 `entry[:publish_date]` 會把兩者壓成同一個 nil，那個 bug 沒有任何
    #   型別檢查抓得到，只有一格反向測試抓得到。
    #
    # @return [Array<Hash>]
    def normalize(input)
      Array(input).map do |entry|
        {
          publication_id: entry[:publication_id],
          publish_date: entry[:publish_date],
          publish_date_given: entry.key?(:publish_date)
        }
      end
    end
  end
end
