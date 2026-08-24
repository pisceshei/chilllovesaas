# frozen_string_literal: true

module Mutations
  # 刪除商品媒體（28 §契約 `productDeleteMedia`）。
  #
  # 引用計數（`file_usages`）同步釋放——第 28 包的刪除確認要據此說明
  # 「哪些檔會一併刪、共用檔保留」（93 實測文案）。blob 本身在此不刪：
  # 檔案可能還掛在別的商品上，清掃是檔案庫的責任。
  class ProductDeleteMedia < BaseMediaMutation
    description "從商品移除媒體（釋放引用計數；blob 去留由檔案庫決定）。"

    user_errors_type Types::Errors::MediaUserErrorType

    argument :product_id, ID, required: true
    argument :media_ids, [ ID ], required: true
    argument :idempotency_key, String, required: false

    field :deleted_media_ids, [ ID ], null: false
    field :product, Types::ProductType, null: true

    def resolve(product_id:, media_ids:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      product = authorized_product!(product_id)
      result = Catalog::MediaSync.delete(
        shop: context.fetch(:current_shop), product:,
        media_ids: media_ids.map { |gid| legacy_media_id(gid) }
      )
      ids = result.media.map { |id| "gid://chilllove/Media/#{id}" }
      { deleted_media_ids: ids, product: product.reload, user_errors: user_errors_from(result) }
    end
  end
end
