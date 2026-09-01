# frozen_string_literal: true

module Mutations
  # 模板整份寫回（步 16b；14 §F3 儲存語義＝整份 JSON＋樂觀鎖）。
  #
  # ①🔴 **寫入必 touch theme**（步 2 紅字前提：頁快取 key 以 theme.updated_at
  #   兼任 template 維度——漏 touch＝前台永遠舊頁）。
  # ②樂觀鎖：既有列帶 lockVersion 比對（StaleObjectError ⇒ STALE，editor 提示
  #   重載）；新列（首次覆寫檔案版）免帶。
  # ③template_type 由 key 導出（`product.custom` ⇒ `product`——Template 模型
  #   值域閘擋未知型）。content 輕驗形（Hash＋sections/order 鍵型）。
  class ThemeTemplateUpsert < BaseMutation
    graphql_name "ThemeTemplateUpsert"
    description "整份寫回模板 JSON（DB 覆寫層；樂觀鎖）。"

    user_errors_type Types::Errors::ThemeManageUserErrorType

    argument :content, GraphQL::Types::JSON, required: true
    argument :key, String, required: true
    argument :lock_version, Integer, required: false
    argument :theme_id, ID, required: true

    field :lock_version, Integer, null: true
    field :template_key, String, null: true

    def resolve(theme_id:, key:, content:, lock_version: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        theme = find_theme(theme_id, shop)
        return failure("themeId", "找不到主題。", "NOT_FOUND") if theme.nil?
        return failure("key", "模板 key 非法。", "INVALID") unless key.match?(/\A[\w.\-]+\z/)
        unless content.is_a?(Hash) && content["sections"].is_a?(Hash) &&
               (content["order"].nil? || content["order"].is_a?(Array))
          return failure("content", "模板 JSON 形不合（需 sections hash＋order array）。", "INVALID")
        end

        template_type = key.split(".", 2).first
        row = Template.find_by(shop_id: shop.id, theme_id: theme.id, key:)
        begin
          if row
            # 🔴 直接賦值 lock_version 不會武裝 AR 樂觀鎖（WHERE 用的是載入值）——
            # 顯式比對 client 底版；AR 原生鎖仍保並發寫者（雙層）。
            if lock_version && row.lock_version != lock_version
              return failure("lockVersion", "模板已被其他人修改——請重載後再編輯。", "STALE_OBJECT")
            end
            row.update!(content:)
          else
            row = Template.create!(shop_id: shop.id, theme_id: theme.id, key:,
                                   template_type:, content:)
          end
        rescue ActiveRecord::StaleObjectError
          return failure("lockVersion", "模板已被其他人修改——請重載後再編輯。", "STALE_OBJECT")
        rescue ActiveRecord::RecordInvalid
          return failure("key", row.errors.full_messages.first.to_s, "INVALID")
        end

        # 🔴 頁快取鍵旋轉（步 2 紅字）：DB 模板變更必 touch theme。
        theme.touch

        { template_key: key, lock_version: row.lock_version, user_errors: [] }
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
      { template_key: nil, lock_version: nil,
        user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
