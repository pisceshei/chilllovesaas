# frozen_string_literal: true

# 只在測試中存在的 fixture mutation 與 schema。
#
# 🔴 **為什麼需要它**：本 PR 的 `Types::MutationType` 刻意沒有掛上 `ChillloveSchema`
# （一支真 mutation 都不出），所以 `BaseMutation` 的地基**沒有任何執行路徑**。
# 沒有這份 fixture，「地基能不能用」就只能靠讀程式碼判斷——
# 而本輪 review 抓到的第一條致命傷（`input_object_class` 在
# `GraphQL::Schema::Mutation` 上不存在 ⇒ 類別定義期 NoMethodError）
# **正是「跑一次就會發現」的那種**。
module MutationTestSchema
  class ErrorCode < Types::Errors::BaseCodeEnum
    graphql_name "FixtureUserErrorCode"
    from_pools
    own_value :FIXTURE_ONLY, "fixture 專屬碼（證明 own_value 可用）"
  end

  class UserErrorType < Types::BaseObject
    graphql_name "FixtureUserError"
    implements Types::Interfaces::DisplayableError

    field :code, ErrorCode, null: true, description: "機器可判別的錯誤碼（🔴 ours，本尊泛用 UserError 無此欄）"
  end

  class Widget < Types::BaseObject
    graphql_name "FixtureWidget"
    field :title, String, null: false
  end

  # 一般 mutation：有一個 resource 欄位。
  class WidgetCreate < Mutations::BaseMutation
    graphql_name "fixtureWidgetCreate"
    user_errors_type UserErrorType

    argument :title, String, required: true
    field :widget, Widget, null: true

    def resolve(title:)
      if title.strip.empty?
        return {
          widget: nil,
          user_errors: [ { field: UserErrors::Path.build(:title), message: "標題不得為空白", code: "BLANK" } ]
        }
      end

      { widget: { title: }, user_errors: [] }
    end
  end

  # 🔴 **純副作用 mutation：payload 只有 userErrors，沒有任何 resource 欄位。**
  # 這一支存在的唯一目的，是證明 `BaseMutation` 沒有把「一個 resource ＋ userErrors」
  # 寫死成契約（本尊的 resource 欄位數量下限就是 0）。
  class WidgetTouch < Mutations::BaseMutation
    graphql_name "fixtureWidgetTouch"
    user_errors_type UserErrorType

    argument :id, ID, required: true

    def resolve(id:)
      { user_errors: id == "bad" ? [ { field: nil, message: "找不到", code: "NOT_FOUND" } ] : [] }
    end
  end

  # 陣列元素錯誤：驗證索引段的形態。
  class WidgetBulk < Mutations::BaseMutation
    graphql_name "fixtureWidgetBulk"
    user_errors_type UserErrorType

    argument :titles, [ String ], required: true

    def resolve(titles:)
      errors = titles.each_with_index.filter_map do |title, index|
        next if title.present?

        { field: UserErrors::Path.build(:titles, index, :value), message: "第 #{index + 1} 筆為空", code: "BLANK" }
      end
      { user_errors: errors }
    end
  end

  # 🔴 拋 TypeError 的 mutation：證明 controller 收窄之後，
  # resolver 內部的 TypeError **不再**被渲染成 BAD_USER_INPUT。
  class WidgetTypeError < Mutations::BaseMutation
    graphql_name "fixtureWidgetTypeError"
    user_errors_type UserErrorType

    def resolve
      raise TypeError, "模擬鐵律 3 的金額型別閘門（65 §C L3）"
    end
  end

  # 冪等契約：`resolve` 開頭主動呼叫檢查（graphql-ruby 的 Mutation 沒有 around hook）。
  #
  # 🔴 走真正的 execute 路徑，不用假 context 直接 `new` 一個 mutation——
  # 那樣建出來的實例在 graphql-ruby 2.6 會在第一次碰 context 時就
  # `NoMethodError: undefined method 'types' for an instance of Hash`，
  # 而那個錯誤與被測的行為毫無關係。
  class WidgetIdempotent < Mutations::BaseMutation
    graphql_name "fixtureWidgetIdempotent"
    user_errors_type UserErrorType

    argument :idempotency_key, String, required: false

    def resolve(idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      { user_errors: [] }
    end
  end

  class MutationRoot < Types::BaseObject
    graphql_name "Mutation"
    field :fixture_widget_create, mutation: WidgetCreate
    field :fixture_widget_touch, mutation: WidgetTouch
    field :fixture_widget_bulk, mutation: WidgetBulk
    field :fixture_widget_type_error, mutation: WidgetTypeError
    field :fixture_widget_idempotent, mutation: WidgetIdempotent
  end

  class Schema < GraphQL::Schema
    query Types::QueryType
    mutation MutationRoot
    max_complexity GraphqlLimits.fetch(:max_query_cost_points)
  end
end
