# frozen_string_literal: true

module Storage
  # staged 上傳簽名（第 25 包；12 §D.7 兩段式的第 1 步——B6 自建 presigned POST）。
  #
  # ①這是什麼：`stagedUploadsCreate` 的簽名引擎——發出「上傳目標 URL＋一次性簽名
  #   參數＋resourceUrl」，並在上傳端點驗回。
  # ②簽名內容＝`key|expires_at|content_length_max` 的 HMAC-SHA256
  #   （鍵＝secret_key_base）。🔴 `content_length_max` 進簽名＝presigned POST 的
  #   content-length-range 同構（91 §3 F8 登記的缺口：預檢過的尺寸上限必須被簽名
  #   釘住，否則簽小傳大）。
  # ③有效期＝limits `media.staged_upload_ttl_seconds`（官方未明文＝ours 裁定）。
  # ④跨功能影響：Mutations::StagedUploadsCreate（發簽）、Admin::UploadsController
  #   （驗簽收檔）、Catalog::FileCreate（staged resourceUrl 換 storage_key）。
  class SignedUpload
    Target = Data.define(:url, :parameters, :resource_url, :key)

    class InvalidSignature < StandardError; end

    STAGED_PREFIX = "staged"

    class << self
      # @param shop [Shop]
      # @param filename [String] 已通過 mutation 驗證的檔名
      # @param byte_size [Integer] 宣告大小（進簽名＝上限）
      # @return [Target]
      def issue(shop:, filename:, byte_size:)
        key = staged_key(shop, filename)
        expires_at = Time.current.to_i + Limits.fetch(:media, :staged_upload_ttl_seconds)
        signature = sign(key, expires_at, byte_size)
        parameters = [
          { name: "key", value: key },
          { name: "expires_at", value: expires_at.to_s },
          { name: "content_length_max", value: byte_size.to_s },
          { name: "signature", value: signature }
        ]
        Target.new(url: upload_path, parameters:, resource_url: resource_url(key), key:)
      end

      # 上傳端點驗簽（時序安全比較；逾期／竄改一律拒）。
      # @return [Hash] { key:, content_length_max: }
      def verify!(key:, expires_at:, content_length_max:, signature:)
        expected = sign(key.to_s, Integer(expires_at), Integer(content_length_max))
        unless ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
          raise InvalidSignature, "signature mismatch"
        end
        raise InvalidSignature, "signature expired" if Integer(expires_at) < Time.current.to_i

        { key: key.to_s, content_length_max: Integer(content_length_max) }
      rescue ArgumentError, TypeError
        raise InvalidSignature, "malformed parameters"
      end

      # staged resourceUrl 判別＋還原 key（fileCreate 用；非本家形態回 nil）。
      def staged_key_from(resource_url, shop:)
        prefix = "#{resource_url_base}/"
        return nil unless resource_url.to_s.start_with?(prefix)

        key = resource_url.to_s.delete_prefix(prefix)
        key.start_with?("shops/#{shop.id}/#{STAGED_PREFIX}/") ? key : nil
      end

      def resource_url_base = "#{base_origin}/admin/uploads/staged-blob"

      def resource_url(key) = "#{resource_url_base}/#{key}"

      private

      def staged_key(shop, filename)
        sanitized = filename.gsub(/[^\w.\-]/, "_").last(120)
        "shops/#{shop.id}/#{STAGED_PREFIX}/#{SecureRandom.uuid}/#{sanitized}"
      end

      def upload_path = "/admin/uploads/staged"

      def base_origin
        host = ENV.fetch("CHILLLOVE_BASE_HOST", "lvh.me")
        scheme = ENV["DISABLE_FORCE_SSL"] == "1" ? "http" : "https"
        "#{scheme}://#{host}"
      end

      def sign(key, expires_at, content_length_max)
        data = [ key, expires_at, content_length_max ].join("|")
        OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, data)
      end
    end
  end
end
