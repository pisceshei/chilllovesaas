# frozen_string_literal: true

module MediaPipeline
  # libvips 影像後端（第 26 包）。
  #
  # ①🔴 **只有 bt3 有 libvips**（8.18.0，apt 手裝）；本機 Windows 與 CI 都沒有
  #   ——Gemfile:34-42 已記載這是 image_processing 被退回 1.x 的原因。
  #   ⇒ 本類是**可插拔後端**：`available?` 為假時拋 `BackendUnavailable`（環境錯，
  #   由 ProcessFile 上拋走 relay 退避），**不得**把檔案標 failed。
  # ②🔴 **一律走 `thumbnail_buffer`**（審查 C1/C3）：它是 libvips 的 shrink-on-load
  #   路徑，且**自動 autorot 與 premultiply**。手寫 `resize` 的版本被推翻——
  #   `thumbnail_image` 自動轉正、`resize` 不轉，兩者混用會讓直式手機照片的
  #   thumb/card/detail 全歪而 og 是正的（strip 又把 orientation tag 刪掉，
  #   瀏覽器無從補救）；`resize` 也不 premultiply，透明圖邊緣會有色暈。
  # ③🔴 `fail_on: :error`（審查 C2）：libvips 預設 `VIPS_FAIL_ON_NONE`——**截斷檔
  #   不報錯**，用灰色填滿當成正常圖存下。要讓壞檔真的走 failed 分支就得顯式設定。
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

    Probe = Data.define(:width, :height)

    # 判為「檔案內容問題」的訊息片段（libvips 的錯誤訊息帶操作名前綴）。
    # 🔴 白名單制：命中才終態，未知一律當環境錯——見檔頭 ④。
    FILE_FAULT_PATTERNS = [
      /premature end/i, /corrupt/i, /invalid|bogus|bad huffman/i,
      /not a known file format|unable to load|no known loader/i,
      /truncated/i, /insufficient data/i, /unsupported .*(colour|color)space/i
    ].freeze

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

      # 讀 header 取尺寸（不解碼全圖）＋像素上限。
      # @raise [DecodeFailed] header 就壞的檔
      # @raise [TooManyPixels] 超過像素上限（防解壓炸彈）
      def probe(bytes)
        ensure_available!
        width, height = classify_errors do
          image = Vips::Image.new_from_buffer(bytes, "", access: :sequential)
          # 🔴 autorot 後的視覺尺寸才是「這張圖多大」——直式照片的 header 是橫的。
          #    沒有 orientation 欄位時 get 會拋，視同 1（不旋轉）。
          orientation = begin
            image.get("orientation").to_i
          rescue StandardError
            1
          end
          orientation.between?(5, 8) ? [ image.height, image.width ] : [ image.width, image.height ]
        end
        pixels = width.to_i * height.to_i
        max_pixels = Limits.fetch(:content, :files_image_max_megapixels) * 1_000_000
        raise TooManyPixels, "#{pixels} pixels exceeds #{max_pixels}" if pixels > max_pixels

        Probe.new(width:, height:)
      end

      # 產一個衍生尺寸。
      # @param spec [Hash] MediaPipeline::Derivatives::SPECS 的一格
      # @return [Array(String, Integer, Integer)] [webp_bytes, width, height]
      def derive(bytes, spec)
        ensure_available!
        image = classify_errors do
          case spec.fetch(:mode)
          when :fit
            # size: :down＝只縮不放；thumbnail 自動 autorot＋premultiply
            Vips::Image.thumbnail_buffer(bytes, spec.fetch(:width), height: spec.fetch(:height),
                                         size: :down, fail_on: :error)
          when :cover
            Vips::Image.thumbnail_buffer(bytes, spec.fetch(:width), height: spec.fetch(:height),
                                         crop: :centre, fail_on: :error)
          else raise ArgumentError, "unknown mode #{spec[:mode]}"
          end
        end
        image = classify_errors { image.colourspace(:srgb) }
        # strip: true ⇒ keep=none（EXIF/GPS 與 ICC 都去掉；上一行已轉 sRGB）
        out = classify_errors { image.write_to_buffer("#{Derivatives::EXTENSION}[Q=82,strip=true]") }
        [ out, image.width, image.height ]
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
