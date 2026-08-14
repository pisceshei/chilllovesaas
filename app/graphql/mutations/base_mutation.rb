# mutation resolver 的 namespace。
module Mutations
  # 所有 Admin API mutation 的抽象基底。
  #
  # ## 🔴 為什麼繼承 `GraphQL::Schema::Mutation` 而不是 `RelayClassicMutation`
  #
  # 本尊的 Admin GraphQL **沒有 `clientMutationId`**（payload 與 input object 兩側都沒有）。
  # `RelayClassicMutation` 會自動把該欄位注入兩側 ⇒ 用它就是偏離本尊的 schema 形狀，
  # 而 schema 形狀是客戶端寫死的東西。
  #
  # ⚠️ 連帶後果：`GraphQL::Schema::Mutation` **沒有** `input_object_class` 這個類別方法
  # （它定義在 `HasSingleInputArgument`，只被 `RelayClassicMutation` include）。
  # 在這裡呼叫它會在**類別定義期**就 `NoMethodError`——Zeitwerk eager load 一跑，
  # 整個 app 載入失敗，連測試都跑不起來。⇒ 每支 mutation 自己宣告
  # `argument :input, Types::XxxInput` 或具名參數。
  #
  # ## 🔴 為什麼不提供泛型的 `resource` 欄位
  #
  # 本尊 payload 的 resource 欄位**數量下限是 0**（純副作用 mutation 只有 userErrors），
  # 上限是 N（多資源 ＋ `Shop!` ＋ `Job` ＋ async operation）。唯一恆定的只有
  # `userErrors: [X!]!`。把「一個 resource ＋ userErrors」寫死成契約，
  # 第一支純副作用或多資源的 mutation 就得繞過基底。
  #
  # ## 用法
  #
  #     class Mutations::ProductCreate < Mutations::BaseMutation
  #       user_errors_type Types::Errors::ProductCreateUserErrorType
  #       argument :product, Types::ProductCreateInput, required: false
  #       field :product, Types::ProductType, null: true
  #       def resolve(product:) ... end
  #     end
  #
  # @see docs/research/28-api-contract.md §0.3.2–§0.3.4
  # @see docs/DECISIONS.md D14
  class BaseMutation < GraphQL::Schema::Mutation
    object_class Types::BaseObject

    class << self
      # 宣告本 mutation 的 user error 型別，並自動加上 `userErrors` 欄位。
      #
      # 🔴 `[type], null: false` 在 graphql-ruby 渲染成 **`[X!]!`**——
      # 非空 list of 非空，與本尊一字不差。成功時回 `[]`，**絕不是 `nil`**。
      #
      # @param type [Class<Types::BaseObject>] 該 mutation 專屬的 user error type
      # @return [void]
      # @note 副作用：在本 mutation 上定義 `userErrors` 欄位。
      # @see docs/research/28-api-contract.md §0.3.3
      def user_errors_type(type)
        @user_errors_type = type
        field :user_errors, [ type ], null: false,
          description: "業務錯誤；成功時為空陣列。HTTP 一律 200（鐵律 4）。"
      end

      # @return [Class, nil] 已宣告的 user error type
      def declared_user_errors_type
        @user_errors_type
      end

      # 本 mutation 是否強制帶 `idempotencyKey`。
      #
      # 判準來自 `config/limits.yml` 的 `idempotency.required_for`（鐵律 6），
      # 不在程式碼裡各自列一份清單。
      #
      # @return [Boolean]
      # @note 副作用：無；只讀設定。
      def idempotency_required?
        Idempotency::RequiredMutations.required?(graphql_name)
      end
    end

    # 執行前的契約檢查。子類的 `resolve` 由 graphql-ruby 呼叫，
    # 本方法由子類在 `resolve` 開頭主動呼叫（graphql-ruby 的 Mutation 沒有 around hook）。
    #
    # 🔴 **本方法不做去重**。它只檢查「該帶 key 的 mutation 有沒有帶 key」，
    # 不 claim、不查重、不回放。claim/replay 狀態機刻意延後（見
    # `docs/worklog/2026-08-15-冪等清單與指紋.md` 的四個未決點）。
    # 寫在這裡是因為**下一支 mutation 的作者最可能誤以為「冪等已經處理好了」**。
    #
    # @param idempotency_key [String, nil] 呼叫端傳入的冪等鍵
    # @return [nil] 通過時回 nil
    # @raise [GraphQL::ExecutionError] 該帶而未帶時拋出（走 top-level errors）
    # @note 副作用：無。
    # @see docs/specs/11-production-baseline.md §2.1
    def enforce_idempotency_contract!(idempotency_key)
      return if !self.class.idempotency_required? || idempotency_key.present?

      raise GraphQL::ExecutionError.new(
        "#{self.class.graphql_name} 必須提供 idempotencyKey。",
        extensions: { "code" => "IDEMPOTENCY_KEY_REQUIRED" }
      )
    end
  end
end
