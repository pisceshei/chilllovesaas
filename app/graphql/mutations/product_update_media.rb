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
        # 🔴 `key?` 而不是直接取值（同 `fileUpdate` 的紀律）：`alt` 是 optional，
        #    「沒送」與「送空字串清除」是兩件事。直接 `alt: entry.alt` 會讓沒送 alt 的
        #    呼叫變成 nil ⇒ 清除——D48 之後那是**清掉所有引用此檔的商品看到的 alt**，
        #    爆炸半徑從一列變成全站。
        entries: media.map do |entry|
          row = { id: legacy_media_id(entry.id) }
          row[:alt] = entry.alt if entry.key?(:alt)
          row
        end
      )
      { media: result.media, user_errors: user_errors_from(result) }
    end
  end
end
