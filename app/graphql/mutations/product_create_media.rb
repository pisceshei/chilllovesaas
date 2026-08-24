# frozen_string_literal: true

module Mutations
  # 掛媒體到商品（28 §契約「媒體」列 `productCreateMedia`）。
  #
  # 🔴 建立型 ⇒ 強制帶 idempotencyKey（limits `idempotency.required_for_catalog_create`
  #   含 productCreateMedia）：無 key 的重複點擊會憑空多出媒體列與檔案。
  #   （完整 claim/replay 與 fileCreate 同受 91 §3.8 登記的限制。）
  class ProductCreateMedia < BaseMediaMutation
    description "把一批媒體掛到商品上（originalSource 建新檔／fileId 用既有檔）。"

    user_errors_type Types::Errors::MediaUserErrorType

    argument :product_id, ID, required: true
    argument :media, [ Types::Inputs::CreateMediaInput ], required: true
    argument :idempotency_key, String, required: false

    field :media, [ Types::MediaType ], null: false
    field :product, Types::ProductType, null: true

    def resolve(product_id:, media:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      raise GraphQL::ExecutionError.new(
        "productCreateMedia 必須提供 idempotencyKey。",
        extensions: { "code" => "IDEMPOTENCY_KEY_REQUIRED" }
      ) if idempotency_key.blank?

      product = authorized_product!(product_id)
      result = Catalog::MediaSync.create(
        shop: context.fetch(:current_shop), product:,
        entries: media.map do |entry|
          # 🔴 錨定型別（審查 C16）：無錨的尾段比對會讓任何 `.../123` 形狀的 GID
          #    （含 Product GID）被當成 File GID，解析成同號的別種資源。
          { original_source: entry.original_source, alt: entry.alt,
            file_id: entry.file_id.to_s[%r{\Agid://chilllove/File/(\d+)\z}, 1] }
        end,
        idempotency_key:
      )
      { media: result.media, product: product.reload, user_errors: user_errors_from(result) }
    end
  end
end
