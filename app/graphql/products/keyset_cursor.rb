require "base64"
require "json"
require "time"

# Product GraphQL query service 的 namespace。
module Products
  # 編碼並驗證不透明的 keyset cursor（排序鍵＋id tiebreaker）。
  #
  # 第 21 包泛化（整合規格 §4-21）：排序鍵由呼叫端指定、**白名單制**——
  # `ORDER_KEYS` 登記每個合法鍵的編解碼器，白名單外一律拒絕（fail-closed）。
  # 🔴 向後相容：預設鍵 `:created_at` 的 payload 形與舊版逐位元組同構
  # `[iso8601(6), id]` ⇒ 線上既有 cursor（admin SPA 分頁）繼續可解。
  # cursor 只暴露 URL-safe Base64，不把 pagination 實作細節列為 API contract。
  # 見 docs/research/28 §0.3。
  class KeysetCursor
    # 合法排序鍵 → {dump:, load:}。新增鍵必須在此登記（變體連線用 :position）。
    ORDER_KEYS = {
      created_at: {
        dump: ->(v) { v.utc.iso8601(6) },
        load: ->(raw) { Time.iso8601(raw) }
      },
      position: {
        dump: ->(v) { Integer(v) },
        load: ->(raw) { Integer(raw) }
      }
    }.freeze

    class << self
      # 將穩定排序鍵與 tiebreaker 編碼成 opaque cursor。
      #
      # @param record [ApplicationRecord] 已持久化且有排序鍵欄與 id 的紀錄
      # @param key [Symbol] ORDER_KEYS 白名單內的排序鍵
      # @return [String] URL-safe Base64 cursor
      # @see docs/research/28-api-contract.md §0.3
      def encode(record, key: :created_at)
        codec = ORDER_KEYS.fetch(key)
        payload = [ codec[:dump].call(record.public_send(key)), record.id ]
        Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      end

      # 解碼並驗證 opaque cursor。
      #
      # @param cursor [String] URL-safe Base64 cursor
      # @param key [Symbol] 編碼時使用的排序鍵
      # @return [Array(Object, Integer)] 排序鍵值與正整數 record id
      # @raise [GraphQL::ExecutionError] cursor 格式錯誤時拋出
      def decode(cursor, key: :created_at)
        codec = ORDER_KEYS.fetch(key)
        raw, id = JSON.parse(Base64.urlsafe_decode64(padded(cursor.to_s)))
        parsed_key = codec[:load].call(raw)
        parsed_id = Integer(id)
        raise ArgumentError unless parsed_id.positive?

        [ parsed_key, parsed_id ]
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
