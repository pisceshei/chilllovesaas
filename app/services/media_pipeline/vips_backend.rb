# frozen_string_literal: true

module MediaPipeline
  # libvips 影像後端（第 26 包）。
  #
  # ①🔴 **只有 bt3 有 libvips**（8.18.0，apt 手裝）；本機 Windows 與 CI 都沒有
  #   ——Gemfile:34-42 已記載這是 image_processing 被退回 1.x 的原因。
  #   ⇒ 本類是**可插拔後端**：`available?` 為假時拋 `BackendUnavailable`（環境錯，
  #   由 ProcessFile 上拋走 relay 退避），**不得**把檔案標 failed。
  # ②🔴 **`fail_on: :error` 必須下在 loader，下在 `thumbnail_buffer` 無效**
  #   （2026-08-25 於 bt3 libvips 8.18.0 實測：`thumbnail_buffer(fail_on: :error)`
  #   對只剩 1/3 的 JPEG **不報錯**、只印一行 `VIPS-WARNING error in tile`，回一張
  #   灰底圖；同一份 buffer 走 `new_from_buffer(fail_on: :error)` 則在寫出時拋
  #   `VipsJpeg: premature end of JPEG image`）。⇒ 本類改「**一次 `open` 載入、
  #   四個 variant 共用**」：`fail_on` 在 open 下，解碼錯誤在 derive 寫出時浮現。
  #   代價＝失去 shrink-on-load（改用 `thumbnail_image`），由 20MP 上限兜住最壞情況。
  # ③🔴 `autorot` 在 open 一次做掉：`thumbnail_image` 自動轉正而 `resize` 不轉，
  #   混用會讓直式手機照片一半歪一半正（審查 C1）。統一在來源轉正、後續全部繼承；
  #   autorot 同時移除 orientation metadata，thumbnail_image 不會再轉第二次。
  # ④🔴 **錯誤分類 fail-closed**（審查 C0/C5，本包最重要的一條）：`Vips::Error` 是
  #   libvips 的**唯一**錯誤類——OOM、fd 耗盡、缺 webp saver 全部長一樣。只有訊息
  #   命中「檔案內容問題」白名單才判 `DecodeFailed`（⇒ 終態 failed）；**未知一律
  #   當環境錯上拋**（⇒ 重試）。方向不能反：重試一個壞檔只是浪費幾次退避，
  #   把 OOM 判成壞檔則是永久燒掉使用者的圖且無恢復路徑。
  # ⑤色彩：strip 前先轉 sRGB（審查 C4）——`keep=none` 會連 ICC profile 一起刪，
  #   廣色域來源直接被當 sRGB 解讀會整張偏色。
  class VipsBackend
    class BackendUnavailable < StandardError; end
    class DecodeFailed < StandardError; end
    class TooManyPixels < StandardError; end

    # 判為「檔案內容問題」的訊息片段（libvips 的錯誤訊息帶操作名前綴）。
    # 🔴 白名單制：命中才終態，未知一律當環境錯——見檔頭 ④。
    FILE_FAULT_PATTERNS = [
      /premature end/i, /corrupt/i, /invalid|bogus|bad huffman/i,
      /not a known file format|unable to load|no known loader/i,
      /truncated/i, /insufficient data/i, /unsupported .*(colour|color)space/i
    ].freeze

    # 已載入、已轉正的來源影像（四個 variant 共用；ProcessFile 持有）。
    class Source
      # @param image [Vips::Image] 已 autorot 的來源
      def initialize(image)
        @image = image
      end

      def width = @image.width

      def height = @image.height

      # 產一個衍生尺寸。
      # @param spec [Hash] MediaPipeline::Derivatives::SPECS 的一格
      # @return [Array(String, Integer, Integer)] [webp_bytes, width, height]
      def derive(spec)
        VipsBackend.send(:classify_errors) do
          thumb = case spec.fetch(:mode)
          when :fit
                    # size: :down＝只縮不放；thumbnail 系列自動 premultiply
                    @image.thumbnail_image(spec.fetch(:width), height: spec.fetch(:height), size: :down)
          when :cover
                    @image.thumbnail_image(spec.fetch(:width), height: spec.fetch(:height), crop: :centre)
          else raise ArgumentError, "unknown mode #{spec[:mode]}"
          end
          thumb = thumb.colourspace(:srgb)
          # 🔴 解碼在這一步真正發生——截斷檔的 `premature end` 從這裡拋（見檔頭 ②）。
          out = thumb.write_to_buffer("#{Derivatives::EXTENSION}[Q=82,strip=true]")
          [ out, thumb.width, thumb.height ]
        end
      end
    end

    class << self
      # @return [Boolean] libvips 是否可用（載入失敗＝環境沒裝）
      def available?
        return @available if defined?(@available)

        @available = begin
          require "ruby-vips"
          Vips.version_string
          true
        rescue LoadError, StandardError
          false
        end
      end

      # 測試用：清掉 memoize。
      # 🔴 不可寫成 `def m = expr if cond`——Ruby 解析成 `(def m = expr) if cond`，
      #    條件為假時**方法根本不會被定義**（審查 C15 實證）。
      def reset_availability!
        remove_instance_variable(:@available) if defined?(@available)
      end

      # 載入來源並驗像素上限（header 階段；不解碼像素）。
      # @return [Source]
      # @raise [DecodeFailed] header 就壞的檔
      # @raise [TooManyPixels] 超過像素上限（防解壓炸彈）
      def open(bytes)
        ensure_available!
        image = classify_errors do
          # 🔴 fail_on 下在這裡（檔頭 ②）；不指定 access ⇒ random，四個 variant 可共用
          Vips::Image.new_from_buffer(bytes, "", fail_on: :error).autorot
        end
        pixels = image.width.to_i * image.height.to_i
        max_pixels = Limits.fetch(:content, :files_image_max_megapixels) * 1_000_000
        raise TooManyPixels, "#{pixels} pixels exceeds #{max_pixels}" if pixels > max_pixels

        Source.new(image)
      end

      private

      def ensure_available!
        raise BackendUnavailable, "libvips not available" unless available?
      end

      # 🔴 分類點：命中白名單＝檔案的錯（終態）；其餘一律原樣上拋＝環境的錯（重試）。
      # 🔴 rescue 寫 `StandardError` 再判型別，不寫 `rescue Vips::Error`——後者在
      #    libvips 未載入時**連 rescue 子句的常數都解析不了**，會拋 NameError 蓋掉
      #    契約上的 BackendUnavailable（審查輪的相鄰發現，spec 已釘）。
      def classify_errors
        yield
      rescue StandardError => e
        raise unless vips_error?(e)
        raise DecodeFailed, e.message.to_s.first(500) if file_fault?(e)

        raise
      end

      def vips_error?(error)
        defined?(Vips::Error) && error.is_a?(Vips::Error)
      end

      def file_fault?(error)
        message = error.message.to_s
        FILE_FAULT_PATTERNS.any? { |pattern| message.match?(pattern) }
      end
    end
  end
end
