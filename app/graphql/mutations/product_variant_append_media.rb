# frozen_string_literal: true

module Mutations
  # 變體掛圖／卸圖（28 §契約 `productVariantAppendMedia`／`DetachMedia` 合一）。
  #
  # 官方每變體 1 張（`limits.product.max_images_per_variant`）且**只接受 image**
  # （官方明載變體不支援影片/3D）。`mediaId: null` ＝卸下該變體的圖。
  class ProductVariantAppendMedia < BaseMediaMutation
    description "把一張圖掛到變體上（mediaId 為 null＝卸下）。"

    user_errors_type Types::Errors::MediaUserErrorType

    argument :product_id, ID, required: true
    argument :variant_id, ID, required: true
    argument :media_id, ID, required: false
    argument :idempotency_key, String, required: false

    field :media, [ Types::MediaType ], null: false

    def resolve(product_id:, variant_id:, media_id: nil, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      product = authorized_product!(product_id)
      result = Catalog::MediaSync.append_to_variant(
        shop: context.fetch(:current_shop), product:,
        variant_id: variant_id.to_s[%r{/(\d+)\z}, 1]&.to_i,
        media_id: media_id && legacy_media_id(media_id)
      )
      { media: result.media, user_errors: user_errors_from(result) }
    end
  end
end
