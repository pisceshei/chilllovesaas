require "base64"
require "json"
require "time"

# Product GraphQL query service 的 namespace。
module Products
  # 編碼並驗證不透明的 `(created_at, id)` product cursor。
  #
  # cursor 只暴露 URL-safe Base64，不把 pagination 實作細節列為 API
  # contract。見 docs/research/28 §0.3。
  class KeysetCursor
    class << self
      # 將穩定排序鍵與 tiebreaker 編碼成 opaque cursor。
      #
      # @param product [Product] 已持久化且有 created_at/id 的 product
      # @return [String] URL-safe Base64 cursor
      # @note 副作用：無。
      # @see docs/research/28-api-contract.md §0.3
      def encode(product)
        payload = [ product.created_at.utc.iso8601(6), product.id ]
        Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      end

      # 解碼並驗證 opaque product cursor。
      #
      # @param cursor [String] URL-safe Base64 cursor
      # @return [Array(Time, Integer)] timestamp 與正整數 record id
      # @raise [GraphQL::ExecutionError] cursor 格式錯誤時拋出
      # @note 副作用：無。
      # @see docs/research/28-api-contract.md §0.3
      def decode(cursor)
        timestamp, id = JSON.parse(Base64.urlsafe_decode64(padded(cursor.to_s)))
        parsed_time = Time.iso8601(timestamp)
        parsed_id = Integer(id)
        raise ArgumentError unless parsed_id.positive?

        [ parsed_time, parsed_id ]
      rescue ArgumentError, JSON::ParserError, TypeError
        raise GraphQL::ExecutionError.new(
          "分頁游標無效。",
          extensions: { "code" => "BAD_USER_INPUT" }
        )
      end

      private

      def padded(cursor)
        cursor + ("=" * ((4 - cursor.length % 4) % 4))
      end
    end
  end
end
