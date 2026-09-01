# frozen_string_literal: true

module MediaPipeline
  # PR-14：歷史圖片列尺寸回填（配合 StoredFile 的尺寸不變量驗證）。
  #
  # ①這是什麼：對「image/* ∧ ready ∧ 缺 width/height」的存量列，從 blob 讀出
  #   實際尺寸補寫；blob 缺失或解碼失敗 ⇒ 轉 failed（同 ProcessFile 的終態語義，
  #   讀取面對 failed 已有處置）。
  # ②為什麼是服務不是 migration：探測要開 vips 讀 blob，遷移期跑重活兼綁
  #   image 后端；服務可在部署後由 runner 執行並留輸出證據（worklog 登記）。
  # ③冪等：條件式 scope，補完即出集合；重跑零工作。
  class BackfillDimensions
    Result = Struct.new(:fixed, :failed, :skipped, keyword_init: true)

    # backend 可插拔（同 ProcessFile：本機/CI 無 libvips，spec 用替身）
    def self.call(backend: VipsBackend) = new(backend:).call

    def initialize(backend: VipsBackend)
      @backend = backend
    end

    def call
      fixed = failed = 0
      scope.find_each do |file|
        begin
          bytes = Storage::LocalDisk.read(file.storage_key)
          raise "blob missing: #{file.storage_key}" if bytes.nil?

          source = @backend.open(bytes)
          file.update!(width: source.width, height: source.height)
          fixed += 1
        rescue StandardError => e
          file.update!(status: "failed", processing_error: e.message.to_s.first(1000))
          failed += 1
        end
      end
      Result.new(fixed:, failed:, skipped: 0)
    end

    private

    # 🔴 without_tenant＋逐列帶 shop_id 的資料（鐵律 2 條款②——維運面全租戶掃描）
    def scope
      ActsAsTenant.without_tenant do
        StoredFile.unscoped.where(status: "ready")
                  .where("content_type LIKE 'image/%'")
                  .where("width IS NULL OR height IS NULL OR width <= 0 OR height <= 0")
      end
    end
  end
end
