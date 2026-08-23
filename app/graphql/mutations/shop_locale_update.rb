# frozen_string_literal: true

module Mutations
  # 更新一個已啟用語言的發布狀態或排序（ML-4）。
  #
  # `published`：對前台開放與否（未發布＝只有預覽連結看得到，29 §1.2）。
  # `position`：切換器與編輯頁欄位順序（67 §C.8「商家唯一能控制切換器順序的地方」）。
  # 🔴 來源語言恆 published、恆 enabled（`SOURCE_LOCALE_IMMUTABLE`，67 §C.3(d)）。
  class ShopLocaleUpdate < BaseMutation
    graphql_name "ShopLocaleUpdate"
    description "更新已啟用語言的發布狀態與排序。"

    user_errors_type Types::Errors::ShopLocaleUserErrorType

    argument :locale, String, required: true
    argument :published, Boolean, required: false, description: "對前台開放；來源語言不可取消。"
    argument :position, Integer, required: false, description: "顯示順序（切換器與編輯頁欄位序）。"

    field :shop_locale, Types::ShopLocaleType, null: true

    def resolve(locale:, published: nil, position: nil)
      enforce_idempotency_contract!(nil)
      shop = context.fetch(:current_shop)
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new(I18n.t("errors.locale.login_required"), extensions: { "code" => "ACCESS_DENIED" })
      end

      tag = Locales::Tag.normalize(locale)
      ActsAsTenant.with_tenant(shop) do
        record = ShopLocale.find_by(locale_tag: tag)
        return not_found unless record

        record.published = published unless published.nil?
        record.position = position unless position.nil?
        unless record.save
          code = record.errors[:published].any? || record.errors[:enabled].any? ? "SOURCE_LOCALE_IMMUTABLE" : "INVALID"
          return { shop_locale: nil, user_errors: [ { field: [ "locale" ], message: record.errors.full_messages.first, code: } ] }
        end

        { shop_locale: record, user_errors: [] }
      end
    end

    private

    def not_found
      { shop_locale: nil, user_errors: [ { field: [ "locale" ], message: I18n.t("errors.locale.not_enabled"), code: "NOT_FOUND" } ] }
    end
  end
end
