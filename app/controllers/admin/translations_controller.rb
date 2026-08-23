# frozen_string_literal: true

module Admin
  # 翻譯 CSV 匯出／匯入（docs/specs/67 §E.6；ML-5b）。
  #
  # 🔴 **為什麼不是 GraphQL**：檔案上傳與檔案下載走 HTTP 語義（multipart／Content-Disposition）
  # 才自然；admin SPA 的資料讀寫仍然只走 GraphQL（D5），這兩個 action 是**檔案通道**不是資料 API。
  #
  # 匯入是兩步（`i18n.import.preview_required`）：
  #   `preview`（dry_run）⇒ 回四類計數與逐行錯誤 → 商家確認 → `import`（實際寫入）。
  # 🔴 覆寫與清空都要在預覽時**分別計數**：「明示動作」只解決了『是不是故意的』，
  #    沒有解決『知不知道有多大』——爆炸半徑仍是整份檔案（§E.6(a) ③）。
  class TranslationsController < BaseController
    # 匯出：CSV 直接回傳（單店資料量在 v1 內同步產出即可；非同步交付屬後續包）。
    #
    # @note 副作用：唯讀。
    def export
      authorize :admin_shell, :show?
      result = Translations::CsvExport.call(
        shop: Current.shop,
        locales: split_param(params[:locales]),
        fields: split_param(params[:fields]),
        resource_type: normalized_resource_type
      )
      send_data result.csv,
        filename: result.filename,
        type: "text/csv; charset=utf-8",
        disposition: "attachment"
    end

    # 匯入預覽：只算不寫（dry_run），讓商家在按下確認前看見四個數字。
    def preview
      authorize :admin_shell, :show?
      render json: outcome_payload(run_import(dry_run: true))
    end

    # 匯入執行：`overwrite_existing` 預設 false（只補新的、不動既有）。
    def import
      authorize :admin_shell, :show?
      render json: outcome_payload(run_import(dry_run: false))
    end

    private

    def run_import(dry_run:)
      Translations::CsvImport.call(
        shop: Current.shop,
        csv_text: uploaded_csv,
        overwrite_existing: ActiveModel::Type::Boolean.new.cast(params[:overwrite_existing]) || false,
        dry_run:
      )
    end

    def uploaded_csv
      file = params[:file]
      return "" if file.blank?

      maximum = Limits.fetch(:csv, :product_max_upload_mb).to_i.megabytes
      raise ActionController::BadRequest, "CSV too large" if file.size > maximum

      file.read.force_encoding(Encoding::UTF_8)
    end

    def outcome_payload(outcome)
      {
        created: outcome.created,
        updated: outcome.updated,
        cleared: outcome.cleared,
        skipped: outcome.skipped,
        digestMismatch: outcome.digest_mismatch,
        applied: outcome.applied,
        errors: outcome.errors
      }
    end

    def split_param(raw)
      raw.to_s.split(",").map(&:strip).reject(&:empty?).presence
    end

    def normalized_resource_type
      value = params[:resource_type].to_s.upcase
      Translation::RESOURCE_TYPES.include?(value) ? value : "PRODUCT"
    end
  end
end
