# frozen_string_literal: true

module Mutations
  # 商品系列的宣告式 upsert（ML-3）。
  #
  # 與 `productSet` 對稱：建立與更新同一支、全樹送出、lockVersion 涵蓋整棵樹（含譯文）。
  # 不需要 idempotencyKey：v1 的系列建立沒有「憑空多出一筆錢」的風險，
  # 且更新是宣告式覆寫（天然冪等）；仍照 MutationType 義務①呼叫 enforce_idempotency_contract!。
  class CollectionSet < BaseMutation
    graphql_name "CollectionSet"
    description "商品系列全樹宣告式 upsert。"

    user_errors_type Types::Errors::CollectionSetUserErrorType

    argument :input, Types::Inputs::CollectionSetInput, required: true

    field :collection, Types::CollectionType, null: true

    def resolve(input:)
      enforce_idempotency_contract!(nil)
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new(I18n.t("errors.collection.login_required"), extensions: { "code" => "ACCESS_DENIED" })
      end

      result = Catalog::SaveCollection.call(shop: context.fetch(:current_shop), input: input.to_h)
      { collection: result.collection, user_errors: result.user_errors }
    end
  end
end
