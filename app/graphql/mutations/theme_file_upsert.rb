# frozen_string_literal: true

module Mutations
  # 主題檔案整份寫回（步 16e1；code editor 唯一寫點）。
  #
  # ①🔴 寫入必 touch theme（步 2 紅字：頁快取鍵旋轉；資產被頁面引用同軸）。
  # ②樂觀鎖同 template/settings upsert 構型（顯式底版比對＋AR 原生鎖雙層）。
  # ③路徑白名單：top dir ∈ limits theme_import.allowed_top_dirs、恰兩段、
  #   檔名 A-Za-z0-9._-（官方 code editor 檔名規則）；🔴 **templates/ 與
  #   config/settings_data.json 拒收**——Template／ThemeSetting 已是各自的
  #   覆寫層，雙真相源禁令。
  # ④單檔上限依型引 limits theme_editor（官方 Theme limits 頁；鐵律 6）。
  class ThemeFileUpsert < BaseMutation
    graphql_name "ThemeFileUpsert"
    description "整份寫回主題檔案（DB 覆寫層；樂觀鎖＋touch theme）。"

    user_errors_type Types::Errors::ThemeManageUserErrorType

    argument :content, String, required: true
    argument :lock_version, Integer, required: false
    argument :path, String, required: true
    argument :theme_id, ID, required: true

    field :lock_version, Integer, null: true
    field :path, String, null: true

    def resolve(theme_id:, path:, content:, lock_version: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        theme = find_theme(theme_id, shop)
        return failure("themeId", "找不到主題。", "NOT_FOUND") if theme.nil?

        path_error = validate_path(path)
        return failure("path", path_error, "INVALID") if path_error

        size_error = validate_size(path, content)
        return failure("content", size_error, "INVALID") if size_error

        row = ThemeFileOverlay.find_by(shop_id: shop.id, theme_id: theme.id, path:)
        begin
          if row
            if lock_version && row.lock_version != lock_version
              return failure("lockVersion", "檔案已被其他人修改——請重載後再編輯。", "STALE_OBJECT")
            end
            row.update!(content:)
          else
            row = ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id, path:, content:)
          end
        rescue ActiveRecord::StaleObjectError
          return failure("lockVersion", "檔案已被其他人修改——請重載後再編輯。", "STALE_OBJECT")
        end

        # 🔴 頁快取鍵旋轉（步 2 紅字）：主題檔變更必 touch theme。
        theme.touch

        { path:, lock_version: row.lock_version, user_errors: [] }
      end
    end

    private

    FILE_SEGMENT_RE = /\A[A-Za-z0-9][A-Za-z0-9_.\-]*\z/

    def validate_path(path)
      segments = path.to_s.split("/")
      return "路徑必須是「目錄/檔名」兩段形。" unless segments.length == 2

      top, name = segments
      allowed = Limits.fetch(:theme_import, :allowed_top_dirs)
      return "頂層目錄不在白名單（#{allowed.join('/')}）。" unless allowed.include?(top)
      return "檔名不合法（A-Za-z0-9._- 且不得以符號開頭）。" unless name.match?(FILE_SEGMENT_RE)
      # 🔴 雙真相源禁令：模板 JSON 走 themeTemplateUpsert、佈景設定走 themeSettingsUpsert。
      return "templates/ 由模板編輯器管理（themeTemplateUpsert）。" if top == "templates"
      return "settings_data.json 由佈景設定管理（themeSettingsUpsert）。" if path == "config/settings_data.json"

      nil
    end

    def validate_size(path, content)
      cap_kb = if path.start_with?("assets/")
        Limits.fetch(:theme_editor, :asset_text_max_kb)
      elsif path.start_with?("locales/")
        Limits.fetch(:theme_editor, :locale_file_max_kb)
      elsif path.end_with?(".json")
        Limits.fetch(:theme_editor, :json_file_max_kb)
      else
        Limits.fetch(:theme_editor, :liquid_file_max_kb)
      end
      return nil if content.bytesize <= cap_kb.to_i * 1024

      "檔案超過上限 #{cap_kb} KB（官方 Theme limits）。"
    end

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
      { path: nil, lock_version: nil,
        user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
