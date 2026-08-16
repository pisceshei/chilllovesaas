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
  #       def resolve(product: nil) ... end
  #     end
  #
  # 🔴 **`required: false` 的參數，`resolve` 簽名一律寫 `arg: nil`**（2026-08-15 修）。
  # graphql-ruby 對「`required: false` 且無 default」的 argument，呼叫端**省略**時
  # **不會把該 keyword 放進 kwargs**（明確傳 `null` 才會）⇒ 寫成 `def resolve(product:)`
  # 得到的是 `ArgumentError: missing keyword: :product`。
  # ⚠️ 而它**穿透 `ChillloveSchema.execute`**（本專案 schema 沒有 `rescue_from`）
  # ⇒ 落到 Rails ⇒ **HTTP 500，不是 `userErrors`**，違反鐵律 4 ①。
  #
  # 🔴 **不要改成 `required: true` 來「修」它**：`docs/research/28` §0.3.3 明文
  # `productCreate(product: ProductCreateInput)` 就是 nullable——因為 deprecated 的
  # `input: ProductInput` 仍共存，兩個互斥參數不可能同時 non-null。
  # ⇒ **省略是正常呼叫，不是邊角**；nullable 是規格要求，錯的是 resolve 簽名。
  #
  # ⚠️ 本樣板寫錯的代價特別高：`app/graphql/mutations/` 底下目前**一支具體 mutation 都沒有**，
  # 它是下一位作者唯一的形狀來源。
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
    # `docs/worklog/2026-08-15-冪等指紋.md` 的四個未決點）。
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
