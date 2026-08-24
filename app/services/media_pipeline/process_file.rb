# frozen_string_literal: true

module MediaPipeline
  # 檔案處理管線本體（第 26 包；13 §F3-3）。
  #
  # ①這是什麼：`files` 一列 → 四個衍生尺寸＋EXIF strip＋webp，狀態機
  #   `uploaded → processing → ready／failed`（90-blueprint/01 §B.3 G22 四態）。
  # ②🔴 **兩類失敗必須分開**（13 §F3 坑＋整合規格 §1.3 逐字「不無限重試」）：
  #   - **檔案本身的錯**（損壞、超像素上限）＝`failed` **終態**，訊息落
  #     `processing_error`；不 raise ⇒ delivery 記 done ⇒ 不重試。
  #   - **環境的錯**（libvips 沒裝、磁碟 IO、OOM）＝**raise** ⇒ relay 指數退避重試。
  #     🔴 raise 前把 status **還原成 `uploaded`**（審查 C7）：留在 processing 會變成
  #     沒有出路的孤兒態——事件走到 dead 之後沒有任何機制把它撿回來，而錯誤訊息
  #     也會隨 outbox purge 一起消失。還原後重試從乾淨態開始，錯誤留在
  #     `processing_error` 供檔案庫（第 28 包）顯示。
  # ③🔴 fs 在 DB transaction 之外（承第 25 包審查 C2/C3/C8 的紀律）：先寫全部
  #   衍生 blob → 一個 transaction 只更新 metadata → 失敗補償刪剛寫的衍生。
  # ④🔴 並發安全（審查 C6/C9）：衍生 key **帶內容 checksum 前綴**——同一 file 因
  #   replace 換了內容而有兩個事件在飛時，兩輪各寫各的 key，不互相覆蓋；
  #   metadata 寫回帶 `checksum` 條件（內容已被換掉就丟棄本輪結果，不覆蓋新值）。
  # ⑤冪等（at-least-once：同一事件可能重叫）：已 ready、derivatives 齊全**且 blob
  #   實際存在**才跳過（審查 C8：只看 JSON 會讓被刪的衍生永不重生、讀取面 500）。
  # ⑥跨功能影響：`MediaPipeline::ProcessConsumer`（唯一呼叫端）、`Types::ImageType`、
  #   `ProductType.featuredImage`、第 27 包媒體卡。
  class ProcessFile
    Result = Data.define(:status, :derivatives)

    class << self
      # @param file [StoredFile]
      # @return [Result]
      # @raise [StandardError] 環境錯（可恢復；呼叫端讓它上拋走 relay 退避）
      def call(file)
        return Result.new(status: file.status, derivatives: file.derivatives) if complete?(file)

        original_checksum = file.checksum
        file.update!(status: "processing", processing_error: nil)

        begin
          bytes = Storage::LocalDisk.read(file.storage_key)
          # 一次載入四個 variant 共用（`fail_on` 必須下在 loader，見 VipsBackend ②）
          source = backend.open(bytes)
          written = write_derivatives!(file, source, original_checksum)
        rescue VipsBackend::DecodeFailed, VipsBackend::TooManyPixels => e
          # 檔案本身的錯＝終態，不重試。derivatives 一併清空（審查 C9：
          # 舊的一組已作廢，留著會讓讀取面指向不存在的 blob）。
          file.update!(status: "failed", derivatives: nil,
                       processing_error: e.message.to_s.first(1000))
          return Result.new(status: "failed", derivatives: nil)
        rescue StandardError => e
          # 環境的錯＝可恢復。還原 uploaded 讓重試從乾淨態開始（審查 C7）。
          file.update!(status: "uploaded", processing_error: e.message.to_s.first(1000))
          raise
        end

        # 內容在本輪期間被 replace 換掉 ⇒ 丟棄本輪結果（新內容自有事件在跑）。
        # 🔴 `delete_with_empty_parents` 而不是 `delete`：衍生 key 是
        #   `.../derivatives/{file_id}/{checksum}/…`，只 rm 檔案會留下兩層空目錄
        #   ——與 `Storage::FileWrite.delete` 同一個孤兒目錄產生者（2026-08-25 bt3 實測）。
        unless file.reload.checksum == original_checksum
          written.each_value { |entry| Storage::LocalDisk.delete_with_empty_parents(entry["key"]) }
          return Result.new(status: file.status, derivatives: file.derivatives)
        end

        file.update!(status: "ready", width: source.width, height: source.height,
                     derivatives: written, processing_error: nil)
        Result.new(status: "ready", derivatives: written)
      end

      # 後端注入點（測試替身用；生產恆為 VipsBackend）。
      def backend = @backend ||= VipsBackend

      attr_writer :backend

      def reset_backend! = (@backend = nil)

      private

      def complete?(file)
        return false unless file.status == "ready" && file.derivatives.is_a?(Hash)
        return false unless (Derivatives.names - file.derivatives.keys).empty?

        # 🔴 JSON 說有 ≠ 磁碟上有（審查 C8）
        file.derivatives.values.all? { |entry| Storage::LocalDisk.exist?(entry["key"]) }
      end

      # 🔴 全部衍生先落磁碟（txn 外）；任一步失敗清掉本輪已寫的，不留孤兒。
      def write_derivatives!(file, source, checksum)
        written = {}
        begin
          Derivatives::SPECS.each do |variant, spec|
            derived, width, height = source.derive(spec)
            key = Derivatives.key_for(file, variant, checksum:)
            Storage::LocalDisk.write(key, StringIO.new(derived))
            written[variant] = { "key" => key, "width" => width, "height" => height,
                                 "byte_size" => derived.bytesize }
          end
        rescue StandardError
          written.each_value { |entry| Storage::LocalDisk.delete_with_empty_parents(entry["key"]) }
          raise
        end
        written
      end
    end
  end
end
