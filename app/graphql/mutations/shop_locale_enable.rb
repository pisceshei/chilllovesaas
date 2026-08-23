# frozen_string_literal: true

module Mutations
  # 為本店啟用一個內容語言（docs/specs/67 §A.2／§C.1；ML-4）。
  #
  # 🔴 **這裡不建表、不跑 migration**——語言集合是資料：啟用＝往 `shop_locales` 插一列，
  # 商品／Collection 編輯頁下次載入就多出那一格（欄位由 `Query.shopLocales` 驅動）。
  # 新語言的譯文與既有語言共用同一張 `translations`（resource × locale × field 一列）。
  #
  # 預設 `published: false`：語言一啟用就對前台開放，等於把**沒有任何譯文**的頁面推給買家；
  # 商家補完譯文再自行發布（67 §C.1／29 §1.2）。
  class ShopLocaleEnable < BaseMutation
    graphql_name "ShopLocaleEnable"
    description "為本店啟用一個內容語言。"

    user_errors_type Types::Errors::ShopLocaleUserErrorType

    argument :locale, String, required: true, description: "平台字典中的 BCP-47 標籤。"

    field :shop_locale, Types::ShopLocaleType, null: true, description: "啟用後的語言列；失敗時為 null。"

    def resolve(locale:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      tag = Locales::Tag.validate!(locale)
      platform = PlatformLocale.available.find_by(tag:)
      return invalid(I18n.t("errors.locale.not_in_catalog"), "NOT_FOUND") unless platform

      ActsAsTenant.with_tenant(shop) do
        existing = ShopLocale.find_by(locale_tag: tag)
        # 曾經停用過的語言＝重新啟用（譯文一直都在，67 §C.1「刪語言不清資料」）。
        if existing
          return invalid(I18n.t("errors.locale.already_enabled"), "ALREADY_EXISTS") if existing.enabled

          existing.update!(enabled: true)
          return { shop_locale: existing, user_errors: [] }
        end

        record = ShopLocale.new(
          locale_tag: tag,
          is_source: false,
          published: false,
          enabled: true,
          position: (ShopLocale.maximum(:position) || 0) + 1
        )
        return invalid(record.errors.full_messages.first, limit_error_code(record)) unless record.save

        { shop_locale: record, user_errors: [] }
      end
    rescue Locales::Tag::Invalid => error
      invalid(error.message, "INVALID")
    end

    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new(I18n.t("errors.locale.login_required"), extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def invalid(message, code)
      { shop_locale: nil, user_errors: [ { field: [ "locale" ], message:, code: } ] }
    end

    # 上限訊息來自 model 驗證（limits `i18n.max_shop_locales`）；其餘視為 INVALID。
    def limit_error_code(record)
      record.errors[:base].any? { |message| message.include?("LOCALE_LIMIT_EXCEEDED") } ? "LOCALE_LIMIT_EXCEEDED" : "INVALID"
    end
  end
end
