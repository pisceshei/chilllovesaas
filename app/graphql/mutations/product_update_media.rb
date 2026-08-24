# frozen_string_literal: true

module Mutations
  # 更新媒體 alt（28 §契約 `productUpdateMedia`）。宣告式覆寫、天然冪等 ⇒ 不強制 key。
  class ProductUpdateMedia < BaseMediaMutation
    description "更新商品媒體的 alt 文字。"

    user_errors_type Types::Errors::MediaUserErrorType

    argument :product_id, ID, required: true
    argument :media, [ Types::Inputs::UpdateMediaInput ], required: true
    argument :idempotency_key, String, required: false

    field :media, [ Types::MediaType ], null: false

    def resolve(product_id:, media:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      product = authorized_product!(product_id)
      result = Catalog::MediaSync.update(
        shop: context.fetch(:current_shop), product:,
        entries: media.map { |entry| { id: legacy_media_id(entry.id), alt: entry.alt } }
      )
      { media: result.media, user_errors: user_errors_from(result) }
    end
  end
end
