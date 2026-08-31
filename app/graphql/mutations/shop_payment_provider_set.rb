# frozen_string_literal: true

module Mutations
  # 宣告式寫入一個 PSP provider 的租戶側設定（G6-3 前半；28 號：宣告式 upsert 用 *Set）。
  #
  # 🔴 **祕密欄 write-only（37 §6.3）**：`apiSecret`／`webhookSecret` **省略＝保持不變**
  # （儲存後表單重載時祕密欄是空的，直接按儲存不得清掉既有 key）；要清空必須明送空字串。
  # 回傳 payload 只有指紋，永無明文。
  #
  # 冪等：settings 形（重放不增殖——(shop_id, provider) UNIQUE 保證 upsert 冪等），
  # 不在 limits `idempotency.required_for` 清單。
  class ShopPaymentProviderSet < BaseMutation
    graphql_name "ShopPaymentProviderSet"
    description "宣告式寫入 PSP provider 的憑證與偏好（祕密欄 write-only：省略＝不變、空字串＝清空）。"

    user_errors_type Types::Errors::ShopPaymentProviderUserErrorType

    argument :provider, String, required: true, description: "pack 代碼（airwallex／paypal）。"
    argument :environment, String, required: false, description: "sandbox|production；省略＝不變（新列預設 sandbox）。"
    argument :client_id, String, required: false, description: "非祕密識別；省略＝不變。"
    argument :api_secret, String, required: false, description: "🔴 write-only：省略＝不變、空字串＝清空。"
    argument :webhook_secret, String, required: false, description: "🔴 write-only：同上。"
    argument :webhook_id, String, required: false, description: "非祕密識別；省略＝不變。"
    argument :enabled_methods, [ String ], required: false,
      description: "商家 method 白名單（⊆ 平台字典；86 詳情頁逐方法 toggle）；省略＝不變。"

    field :shop_payment_provider, Types::ShopPaymentProviderType, null: true

    # 🔴 required: false ⇒ 簽名一律 `arg: nil`（base_mutation.rb：省略呼叫時 kwargs 缺鍵）。
    # 「省略」與「明送 null」在 graphql-ruby 都到達 nil ⇒ 兩者同義＝保持不變；
    # 清空的協定是**空字串**（前端固定送 ""），不是 null——避免 nil 的雙義。
    def resolve(provider:, environment: nil, client_id: nil, api_secret: nil, webhook_secret: nil, webhook_id: nil, enabled_methods: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      unless ShopPaymentProvider.provider_dictionary.include?(provider)
        return invalid("provider", "provider 不在平台 pack 字典內", "PROVIDER_UNKNOWN")
      end

      ActsAsTenant.with_tenant(shop) do
        record = ShopPaymentProvider.find_or_initialize_by(provider:)
        record.environment = environment unless environment.nil?
        record.client_id = client_id unless client_id.nil?
        record.api_secret = presence_or_nil(api_secret) unless api_secret.nil?
        record.webhook_secret = presence_or_nil(webhook_secret) unless webhook_secret.nil?
        record.webhook_id = webhook_id unless webhook_id.nil?
        record.enabled_methods = enabled_methods unless enabled_methods.nil?

        begin
          record.save!
        rescue ActiveRecord::RecordNotUnique
          # (shop_id, provider) UNIQUE 的併發雙擊：後到者重讀既有列再套用一次即冪等；
          # 為簡潔直接回 INVALID_STATE 讓前端重載（settings 頁單人操作，實務打不中）。
          return invalid("provider", "同 provider 設定正在被併發寫入，請重載後再試", "INVALID_STATE")
        rescue ActiveRecord::RecordInvalid
          field_name = record.errors.attribute_names.first.to_s
          return invalid(field_name, record.errors.full_messages.first, "INVALID")
        end

        { shop_payment_provider: record, user_errors: [] }
      end
    end

    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    # write-only 清空協定：空字串 ⇒ nil 落庫（指紋同步清空）。
    def presence_or_nil(value)
      value.presence
    end

    def invalid(field, message, code)
      { shop_payment_provider: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
