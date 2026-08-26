# frozen_string_literal: true

module Mutations
  # 刪除一個 publication（S1）。
  #
  # 本尊對位＝`publicationDelete(id: ID!)`。🔴 **官方全文只有一句** `Deletes a publication.`
  # （同一 URL 抓兩次字串完全相同，取證 2026-08-26），payload 恰兩欄
  # `deletedId: ID` ＋ `userErrors: [PublicationUserError!]!`。
  #
  # 🔴 **刪除副作用官方完全沉默**：既有 resource publications 會不會被級聯刪、
  #   已發布資源會不會被 unpublish、哪些 publication 不可刪、是否可逆、是否觸發 webhook
  #   ——官方**既未說會、也未說不會**。我方的處置逐條寫在 `Publications::Write.delete`，
  #   全部標為 **ours**，不得讀成照抄本尊。
  #
  # 🔴 **參數是扁平 `id: ID!`，沒有 input object**——本尊沒有 `PublicationDeleteInput`。
  #   ⚠️ 連帶後果：本支的 `userErrors.field` path 第一段是 **`id`**，
  #   與 create／update 的 `input` 不同。這不是不一致，是照抄本尊的參數形態。
  class PublicationDelete < BaseMutation
    graphql_name "PublicationDelete"
    description "刪除一個 publication（綁著管道的不可刪）。"

    user_errors_type Types::Errors::PublicationUserErrorType

    argument :id, ID, required: true, description: "publication 的 GID。"

    field :deleted_id, ID, null: true, description: "被刪除的 publication GID。"

    # @param id [String] publication GID
    # @return [Hash] payload
    # @note 副作用：見 `Publications::Write.delete`。
    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)

      publication = Publications::Lookup.call(shop:, gid: id)
      # 🔴 共用的只有 `userErrors` 那一半——本支的 payload 欄位是 `deletedId` 不是
      #   `publication`，所以不能共用整個 payload。形狀一致的是**錯誤**，不是回傳值。
      return { deleted_id: nil, user_errors: Publications::Lookup.not_found_errors } unless publication

      result = Publications::Write.delete(shop:, publication:)
      return { deleted_id: nil, user_errors: result.user_errors } unless result.ok?

      { deleted_id: "gid://chilllove/Publication/#{result.publication.id}", user_errors: [] }
    end
  end
end
