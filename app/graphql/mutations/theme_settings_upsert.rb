# frozen_string_literal: true

module Mutations
  # 佈景設定整份寫回（步 16d2；settings_data current 的 DB 覆寫層＝ThemeSetting）。
  #
  # ①🔴 **寫入必 touch theme**（步 2 紅字：頁快取 key 以 theme.updated_at 兼任
  #   settings 維度——漏 touch＝前台永遠舊頁）。
  # ②樂觀鎖與 themeTemplateUpsert 同構：直接賦值 lock_version 不武裝 AR 樂觀鎖
  #   （WHERE 用載入值）⇒ 顯式比對 client 底版；AR 原生鎖保並發寫者（雙層）。
  # ③settings 輕驗形（Hash——值可巢狀：color_scheme_group 存 map）。
  class ThemeSettingsUpsert < BaseMutation
    graphql_name "ThemeSettingsUpsert"
    description "整份寫回佈景設定（settings_data current 的 DB 覆寫層；樂觀鎖）。"

    user_errors_type Types::Errors::ThemeManageUserErrorType

    argument :lock_version, Integer, required: false
    argument :settings, GraphQL::Types::JSON, required: true
    argument :theme_id, ID, required: true

    field :lock_version, Integer, null: true

    def resolve(theme_id:, settings:, lock_version: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        theme = find_theme(theme_id, shop)
        return failure("themeId", "找不到主題。", "NOT_FOUND") if theme.nil?
        return failure("settings", "佈景設定形不合（需 Hash）。", "INVALID") unless settings.is_a?(Hash)

        row = ThemeSetting.find_by(shop_id: shop.id, theme_id: theme.id)
        begin
          if row
            if lock_version && row.lock_version != lock_version
              return failure("lockVersion", "佈景設定已被其他人修改——請重載後再編輯。", "STALE_OBJECT")
            end
            row.update!(settings:)
          else
            row = ThemeSetting.create!(shop_id: shop.id, theme_id: theme.id, settings:)
          end
        rescue ActiveRecord::StaleObjectError
          return failure("lockVersion", "佈景設定已被其他人修改——請重載後再編輯。", "STALE_OBJECT")
        end

        # 🔴 頁快取鍵旋轉（步 2 紅字）：佈景設定變更必 touch theme。
        theme.touch

        { lock_version: row.lock_version, user_errors: [] }
      end
    end

    private

    def authorized_shop!
      unless ThemePolicy.new(context[:current_staff], Theme).index?
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def find_theme(gid, shop)
      numeric = gid.to_s[%r{\Agid://chilllove/Theme/(\d+)\z}, 1]
      numeric && Theme.find_by(shop_id: shop.id, id: numeric)
    end

    def failure(field, message, code)
      { lock_version: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
