# frozen_string_literal: true

module Mutations
  # 更新一個 publication：`autoPublish` 與批次加／減 publishable（S1）。
  #
  # 本尊對位＝`publicationUpdate(id: ID!, input: PublicationUpdateInput!)`，描述逐字：
  # `Updates a Publication.` ／ `You can add or remove products from the publication,
  # with a maximum of 50 items per operation. The autoPublish field determines whether
  # new products automatically display in this publication.`（取證 2026-08-26）
  #
  # 🔴 **這支是本倉庫第一條 `resource_publications` 的非建立寫入路徑**——
  #   在它之前，發布列只在建立時被寫入（`Publications::Materialize`），
  #   全倉零 UPDATE／DELETE、零 publish／unpublish 入口。
  class PublicationUpdate < BaseMutation
    graphql_name "PublicationUpdate"
    description "更新 publication（autoPublish；批次加／減 publishable，累加語義）。"

    user_errors_type Types::Errors::PublicationUserErrorType

    argument :id, ID, required: true, description: "publication 的 GID。"
    argument :input, Types::Inputs::PublicationUpdateInput, required: true

    field :publication, Types::PublicationType, null: true

    # @param id [String] publication GID
    # @param input [Types::Inputs::PublicationUpdateInput]
    # @return [Hash] payload
    # @note 副作用：見 `Publications::Write.update`。
    def resolve(id:, input:)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)

      publication = Publications::Lookup.call(shop:, gid: id)
      return { publication: nil, user_errors: Publications::Lookup.not_found_errors } unless publication

      result = Publications::Write.update(
        shop:,
        publication:,
        auto_publish: input[:auto_publish],
        publishables_to_add: input[:publishables_to_add],
        publishables_to_remove: input[:publishables_to_remove]
      )

      { publication: result.publication, user_errors: result.user_errors }
    end
  end
end
