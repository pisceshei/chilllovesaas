# frozen_string_literal: true

module Admin
  # staged 上傳收檔＋檔案讀出（第 25 包；B6 自建 presigned POST 的 HTTP 端）。
  #
  # 🔴 **為什麼不是 GraphQL**：與 TranslationsController 同理——二進位走 HTTP 語義
  # （multipart／streaming），資料讀寫仍只走 GraphQL（D5）。
  #
  # ①`create_staged`＝12 §D.7 第 2 步的落點：驗簽（HMAC＋逾期）→ 驗店（key 前綴）→
  #   驗尺寸（🔴 實際 bytes ≤ 簽名內的 content_length_max——「簽小傳大」在這裡擋，
  #   91 §3 F8 的 content-length-range 同構）→ 落 staged 區。
  # ②`show_file`＝已入庫檔案的讀出（第 27/28 包預覽用；租戶範圍內 by id）。
  # ③認證＝admin session（BaseController）＋簽名雙重；CSRF 照常（SPA fetch 帶 token）。
  class UploadsController < BaseController
    # POST /admin/uploads/staged
    def create_staged
      authorize StoredFile, :create?
      verified = Storage::SignedUpload.verify!(
        key: params[:key], expires_at: params[:expires_at],
        content_length_max: params[:content_length_max], signature: params[:signature]
      )
      key = verified.fetch(:key)
      # 簽名蓋不到「哪家店的 session 在用」——key 前綴必須屬當前店（跨店重放拒）
      raise Storage::SignedUpload::InvalidSignature, "tenant mismatch" unless
        key.start_with?("shops/#{Current.shop.id}/#{Storage::SignedUpload::STAGED_PREFIX}/")

      file = params.require(:file)
      raise ActionController::BadRequest, "檔案超過簽名允許的大小。" if
        file.size > verified.fetch(:content_length_max)

      Storage::LocalDisk.write(key, file.tempfile)
      render json: { resourceUrl: Storage::SignedUpload.resource_url(key) },
             status: :created
    rescue Storage::SignedUpload::InvalidSignature
      head :forbidden
    end

    # GET /admin/files/:id/blob[?variant=thumb|card|detail|og]
    #
    # 衍生尺寸與原圖同一支端點：授權面只有一處（StoredFilePolicy#index?），
    # 且 variant 只能取自白名單——key 由 file.id＋variant 推導，不吃使用者輸入的路徑。
    def show_file
      authorize StoredFile, :index?
      file = StoredFile.find(params[:id])
      variant = params[:variant].presence

      if variant
        entry = file.derivatives.is_a?(Hash) ? file.derivatives[variant] : nil
        return head :not_found unless entry && MediaPipeline::Derivatives.names.include?(variant)

        return send_data Storage::LocalDisk.read(entry.fetch("key")),
          filename: "#{::File.basename(file.filename, ".*")}-#{variant}#{MediaPipeline::Derivatives::EXTENSION}",
          type: "image/webp", disposition: "inline"
      end

      send_data Storage::LocalDisk.read(file.storage_key),
        filename: file.filename, type: file.content_type, disposition: "inline"
    end
  end
end
