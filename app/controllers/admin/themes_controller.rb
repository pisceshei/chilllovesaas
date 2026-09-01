# frozen_string_literal: true

module Admin
  # 主題 zip 匯入（步 15b；99 §4——admin「Import theme › Upload zip file」對位）。
  #
  # 🔴 **為什麼是 multipart HTTP 不是 GraphQL themeCreate**：官方 themeCreate 收
  # staged upload URL；我方 staged uploads 目前只收圖片 content types ⇒ zip 走
  # 專用 multipart 端點（UploadsController 同理——二進位走 HTTP 語義）。staged
  # 放寬後補 GraphQL themeCreate（91 §3.68）。
  class ThemesController < BaseController
    # POST /admin/themes/import（multipart：file＋name＋license_attested）
    def import
      authorize Theme, :index?

      file = params.require(:file)
      max_bytes = Limits.fetch(:theme_import, :zip_max_mb).megabytes
      return render json: { error_code: "ZIP_TOO_LARGE" }, status: :content_too_large if file.size > max_bytes

      result = Themes::ImportZip.call(
        shop: Current.shop, zip_path: file.tempfile.path,
        name: params[:name].to_s, zip_filename: file.original_filename.to_s,
        license_attested: ActiveModel::Type::Boolean.new.cast(params[:license_attested])
      )
      if result.success?
        render json: { theme_id: "gid://chilllove/Theme/#{result.theme.id}",
                       checksum: result.theme.content_checksum,
                       report: result.report }, status: :created
      else
        render json: { error_code: result.error_code, error_message: result.error_message },
               status: :unprocessable_content
      end
    end
  end
end
