# frozen_string_literal: true

module Mutations
  # 停用一個內容語言（ML-4）。
  #
  # 🔴 **停用不是刪除資料**：`enabled=false`，`translations` 一列都不動——
  # 商家把語言加回來時譯文原樣回來（67 §C.1；SHOPLINE 也是這個承諾，109 號可採項）。
  # 因此本 mutation **不接受 destroy 語義**；真的要清譯文是另一件事（且不在 v1 射程）。
  #
  # 🔴 來源語言不可停用（`SOURCE_LOCALE_IMMUTABLE`）：base row 的文字就是它，
  # 停用它等於讓整店內容沒有語言可判定（67 §C.3(b)(d)）。
  class ShopLocaleDisable < BaseMutation
    graphql_name "ShopLocaleDisable"
    description "停用一個內容語言（保留譯文；重新啟用即復原）。"

    user_errors_type Types::Errors::ShopLocaleUserErrorType

    argument :locale, String, required: true

    field :shop_locale, Types::ShopLocaleType, null: true
    field :retained_translations, Integer, null: false,
      description: "保留的譯文列數（讓 UI 能誠實說出「保留 N 筆譯文」）。"

    def resolve(locale:)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new(I18n.t("errors.locale.login_required"), extensions: { "code" => "ACCESS_DENIED" })
      end

      tag = Locales::Tag.normalize(locale)
      ActsAsTenant.with_tenant(shop) do
        record = ShopLocale.find_by(locale_tag: tag)
        return reject(I18n.t("errors.locale.not_enabled"), "NOT_FOUND") unless record

        if record.is_source
          return reject(I18n.t("errors.locale.source_immutable"), "SOURCE_LOCALE_IMMUTABLE")
        end

        retained = Translation.where(shop_id: shop.id, locale_tag: tag).count
        record.update!(enabled: false, published: false)
        { shop_locale: record, retained_translations: retained, user_errors: [] }
      end
    end

    private

    def reject(message, code)
      { shop_locale: nil, retained_translations: 0, user_errors: [ { field: [ "locale" ], message:, code: } ] }
    end
  end
end
