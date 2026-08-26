# frozen_string_literal: true

module Mutations
  # 把一個資源自一或多個 publication 取消發布（S5）。
  #
  # 本尊對位＝`publishableUnpublish(id: ID!, input: [PublicationInput!]!)`，
  # 描述逐字（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/publishableUnpublish>，
  # 取證 2026-08-27）：
  #
  # > Unpublishes a resource, such as a `Product` or `Collection`, from one or more
  # > publications. The resource remains in your store but becomes unavailable to customers.
  # >
  # > For products to be visible in a channel, they must have an active `ProductStatus`.
  #
  # 🔴 **與 publish 側唯一的規範性差異在 `id` 參數的描述**：
  #   本支逐字 `The resource to **delete or update** publications for.`，
  #   publish 側逐字 `The resource to **create or update** publications for.`
  #   ——這是整頁**唯一**觸及「那筆發布紀錄被怎麼處理」的措辭，但它描述的是
  #   **參數用途**，沒有說何時是 delete、何時是 update。
  #   ⇒ 「取消發布後紀錄的去向」官方**完全沉默**，我方硬刪列是 ours 裁定，
  #   論證全文見 `Publications::Write.unpublish` 檔頭。
  #
  # 🔴 **`publishDate` 在本支無效果**（官方唯一的規範句：`This field has no effect if
  #   you include it in the publishableUnpublish mutation.`）——不驗證、不生效、不回錯。
  #   欄位仍在 input 型別上，因為兩支**共用同一個 `PublicationInput`**（本尊如此）。
  #
  # ⚠️ **不實作 `channelId`** ⇒ 官方那條「同時給 channelId 與 publicationId 時只用
  #   publicationId」的優先序規則（只出現在本支的 Examples）在我方情境不會發生，
  #   不照抄成我方規則。
  #
  # @see docs/dev/m2-publishable-write.md
  class PublishableUnpublish < BaseMutation
    graphql_name "PublishableUnpublish"
    description "把一個資源自一或多個銷售管道取消發布（資源本身保留，只是顧客看不到）。"

    user_errors_type Types::Errors::PublishableUnpublishUserErrorType

    argument :id, ID, required: true, description: "要取消發布的資源 GID。"
    argument :input, [ Types::Inputs::PublicationInput ], required: true,
      description: "要自哪些 publication 移除。🔴 其中的 publishDate 一律無效果（照抄本尊）。"

    field :publishable, Types::Interfaces::Publishable, null: true,
      description: "已取消發布的資源。"

    # @param id [String] publishable GID
    # @param input [Array<Types::Inputs::PublicationInput>]
    # @return [Hash] payload
    # @note 副作用：見 `Publications::Write.unpublish`。
    def resolve(id:, input:)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)

      result = Publications::Write.unpublish(shop:, publishable_gid: id, entries: normalize(input))

      { publishable: result.publishable, user_errors: result.user_errors }
    end

    private

    # 🔴 本支**不讀 `publish_date`**，連 `key?` 都不查——「無效果」的字面意思
    #   就是不驗證也不報錯。傳了它的請求與沒傳的請求走完全一樣的路。
    #
    # @return [Array<Hash>]
    def normalize(input)
      Array(input).map { |entry| { publication_id: entry[:publication_id] } }
    end
  end
end
