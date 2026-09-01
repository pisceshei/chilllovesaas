# frozen_string_literal: true

module Mutations
  # 主題複製（41 §634 動作選單 Duplicate；官方 GraphQL 無對應 mutation——admin UI
  # 行為對位）。命名＝"Copy of "＋原名（help 逐字 "Copy Of"）＋撞名尾碼。
  #
  # 🔴 零複製：匯入主題共享 content_checksum（storage 目錄不可變——15a 地基）；
  #   first_party 主題共享名稱鍵目錄。DB 覆寫層（templates／theme_setting）一併拷貝
  #   ——不拷等於「複製後編輯全丟」。
  class ThemeDuplicate < BaseMutation
    graphql_name "ThemeDuplicate"
    description "複製主題（零複製共享內容；DB 覆寫層一併拷貝）。"

    user_errors_type Types::Errors::ThemeManageUserErrorType

    argument :id, ID, required: true

    field :theme, Types::ThemeType, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        source = find_theme(id, shop)
        return { theme: nil }.merge(invalid("id", "找不到主題。", "NOT_FOUND")) if source.nil?

        copy = nil
        ActiveRecord::Base.transaction do
          copy = Theme.create!(shop_id: shop.id, name: copy_name(shop, source.name),
                               role: "draft", source: source.source,
                               license_attested: source.license_attested,
                               content_checksum: source.content_checksum,
                               version: source.version)
          Template.where(shop_id: shop.id, theme_id: source.id).find_each do |row|
            Template.create!(shop_id: shop.id, theme_id: copy.id, key: row.key,
                             template_type: row.template_type, content: row.content)
          end
          if (setting = ThemeSetting.find_by(shop_id: shop.id, theme_id: source.id))
            ThemeSetting.create!(shop_id: shop.id, theme_id: copy.id, settings: setting.settings)
          end
        end
        { theme: copy, user_errors: [] }
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

    # "Copy of X"（help 逐字形）＋撞名 -N；同時吃 50 字上限（官方）。
    def copy_name(shop, base_name)
      max = Limits.fetch(:theme_import, :theme_name_max)
      base = "Copy of #{base_name}"[0, max]
      candidate = base
      1.step do |n|
        return candidate unless Theme.exists?(shop_id: shop.id, name: candidate)

        suffix = " #{n}"
        candidate = "#{base[0, max - suffix.length]}#{suffix}"
      end
    end

    def invalid(field, message, code)
      { user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
