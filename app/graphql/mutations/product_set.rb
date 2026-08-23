# frozen_string_literal: true

module Mutations
  # admin 商品頁 SaveBar 的唯一寫入映射（63 §B.4；`catalog_flow.product_write_entry_mutation`）。
  #
  # ## 冪等（條件強制，2026-08-23 裁定）
  #
  # `limits.idempotency` 的名單以 mutation 名為鍵，表達不了「同一支、建立態才強制」
  # ——而 productSet 正是這種：**無 id（建立）＝重放憑空多一個商品**（handle 自動
  # 尾碼＋title 可合法重複 ⇒ 沒有業務唯一鍵兜底，`required_for_catalog_create` 的
  # 判準逐字適用）；**有 id（更新）＝宣告式覆寫天然冪等**（該區塊「刻意不列入」
  # 的理由只對這一態成立，防線是 lock_version）。
  # ⇒ 條件在本 resolver 落地：建立態缺 key 走既有的 top-level
  # `IDEMPOTENCY_KEY_REQUIRED`（S4 暫行機制，enum 歸屬未決點 3 照舊）。
  # 名單表達力缺口已登記 docs/specs/91。
  #
  # ## 回放
  #
  # `Idempotency::Guard`（11 §2.1）：succeeded ⇒ 依 result_ref 重載 Product 重跑
  # serializer；物件已被刪 ⇒ `NOT_FOUND` userError（「原請求成功，但關聯資料隨後
  # 被刪除」）；processing／指紋不符 ⇒ CONCURRENCY 池碼走 userErrors。
  #
  # @see docs/specs/63-product-data-flow.md §B.4
  # @see docs/specs/11-production-baseline.md §2.1
  # @see docs/dev/m1-product-set-foundation.md
  class ProductSet < BaseMutation
    user_errors_type Types::Errors::ProductSetUserErrorType

    argument :input, Types::Inputs::ProductSetInput, required: true,
      description: "商品全樹（B.4：前端必須送完整樹，不得送 dirty fields）。"
    argument :idempotency_key, String, required: false,
      description: "冪等鍵（UUID v4/v7）。建立態（無 id）必填。"

    field :product, Types::ProductType, null: true,
      description: "儲存後的商品；失敗時為 null。"

    # @param input [Types::Inputs::ProductSetInput]
    # @param idempotency_key [String, nil]
    # @return [Hash] `{ product:, user_errors: }`
    # @raise [GraphQL::ExecutionError] 未授權（ACCESS_DENIED）或建立態缺 key
    def resolve(input:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      authorize_write!
      enforce_creation_key!(input, idempotency_key)

      shop = context.fetch(:current_shop)
      input_hash = input.to_h

      # 更新態可不帶 key（宣告式覆寫天然冪等）——無 key 就不進 claim/replay，
      # 防線是 lock_version（63 §A.4），不是 idempotency_keys。
      if idempotency_key.blank?
        result = Catalog::SaveProduct.call(shop:, input: input_hash)
        return { product: result.product, user_errors: result.user_errors }
      end

      outcome = Idempotency::Guard.with(
        shop: shop,
        key: idempotency_key,
        mutation_name: self.class.graphql_name,
        input: input_hash.deep_stringify_keys
      ) do
        result = Catalog::SaveProduct.call(shop:, input: input_hash)
        [ result.product, result.user_errors ]
      end

      if outcome[:replayed] && outcome[:resource].nil?
        return { product: nil, user_errors: [ replay_target_missing_error ] }
      end

      { product: outcome[:resource], user_errors: outcome[:user_errors] }
    rescue Idempotency::Guard::Conflict => conflict
      { product: nil,
        user_errors: [ { field: nil, message: conflict.message, code: conflict.code } ] }
    end

    private

    # 與 query 的 authorize_products! 同形態（ACCESS_DENIED 走 top-level errors，
    # HTTP 仍 200——28 §0.3 的承載層）。寫入權限鍵＝products.edit（12 F3）。
    def authorize_write!
      staff = context[:current_staff]
      return if staff && ProductPolicy.new(staff, Product).create?

      raise GraphQL::ExecutionError.new(
        "沒有權限寫入商品。",
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end

    # 建立態（無 id）強制冪等鍵；理由見類別註釋。
    def enforce_creation_key!(input, idempotency_key)
      return if input.id.present? || idempotency_key.present?

      raise GraphQL::ExecutionError.new(
        "productSet 建立商品（未帶 id）時必須提供 idempotencyKey。",
        extensions: { "code" => "IDEMPOTENCY_KEY_REQUIRED" }
      )
    end

    def replay_target_missing_error
      {
        field: nil,
        message: "原請求已成功，但該商品隨後已被刪除。",
        code: "NOT_FOUND"
      }
    end
  end
end
