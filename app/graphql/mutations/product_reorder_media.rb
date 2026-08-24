# frozen_string_literal: true

module Mutations
  # 重排商品媒體（28 §契約 `productReorderMedia`）。
  #
  # 🔴 **宣告式全量**（送入順序即 position）而非官方的 `moves[]` 增量形——
  #   偏離登記於 worklog：拖曳後前端本來就持有完整順序，全量比 moves 少一層
  #   「誰移到哪」的換算，且缺項會被明確擋下（reorder_incomplete）而不是靜默錯位。
  # 🔴 兩階段落位——`uq_media_product_id_position` 是 unique（見 MediaSync ②）。
  class ProductReorderMedia < BaseMediaMutation
    description "重排商品媒體（宣告式全量：送入順序即展示序，第一格＝精選圖）。"

    user_errors_type Types::Errors::MediaUserErrorType

    argument :product_id, ID, required: true
    argument :media_ids, [ ID ], required: true,
      description: "必須恰為該商品的全部媒體；缺項或多項一律 INVALID。"
    argument :idempotency_key, String, required: false

    field :media, [ Types::MediaType ], null: false

    def resolve(product_id:, media_ids:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      product = authorized_product!(product_id)
      result = Catalog::MediaSync.reorder(
        shop: context.fetch(:current_shop), product:,
        media_ids: media_ids.map { |gid| legacy_media_id(gid) }
      )
      { media: result.media, user_errors: user_errors_from(result) }
    end
  end
end
