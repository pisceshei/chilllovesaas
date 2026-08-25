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
      },
      # ── D48「所有的都跟 Shopify」：檔案庫排序（本尊 Files 頁可依
      #    Date added／File name／Size 排序）──
      # 🔴 字串鍵的 load **必須自己驗型別**：`Integer(raw)` 遇到 "abc" 會 raise
      #    ⇒ position/byte_size 天然 fail-closed；字串沒有這個保護，
      #    `JSON.parse('[123, 5]')` 會給你一個 Integer 當 filename，
      #    後面 `WHERE filename > 123` 在 MySQL 是**隱式轉型**不是錯誤
      #    ——那是一整頁錯資料而不是一個錯誤訊息。
      filename: {
        dump: ->(v) { String(v) },
        load: lambda { |raw|
          raise ArgumentError, "filename cursor must be a string" unless raw.is_a?(String)

          raw
        }
      },
      byte_size: {
        dump: ->(v) { Integer(v) },
        # 🔴 `Integer(raw)` 不夠：JSON 的整數沒有上界，`Integer(10**20)` 原封放行，
        #    然後在 bind 參數時炸 `ActiveModel::RangeError` ⇒ **HTTP 500**，
        #    而契約要求無效 cursor 一律 `BAD_USER_INPUT`（鐵律 4）。
        #    在這裡就夾在 signed bigint 範圍內，讓它走既有的 rescue。
        load: lambda { |raw|
          value = Integer(raw)
          raise ArgumentError, "byte_size cursor out of range" unless value.between?(-2**63, 2**63 - 1)

          value
        }
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
        # 🔴 payload **帶排序鍵**（三元組）。只有 `[value, id]` 的話，
        #    cursor 沒有任何東西說得出它是用哪個鍵編的，而 `decode` 只信呼叫端傳的
        #    `key` ⇒ 拿 CREATED_AT 的 cursor 去當 `sortKey: FILENAME` 的 after，
        #    ISO8601 字串通過 `is_a?(String)` 守衛、SQL 變成
        #    `WHERE filename > '2026-08-25T…'`，**靜默回一整頁錯資料**
        #    （數字開頭的檔名整批被吞掉，或使用者看過的列再回一次）。
        #    對抗審查以真實端點復現，見 `docs/specs/91` §3.13。
        payload = [ key.to_s, codec[:dump].call(record.public_send(key)), record.id ]
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
        raw, id = extract(JSON.parse(Base64.urlsafe_decode64(padded(cursor.to_s))), key)
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

      # payload → `[raw, id]`，並確認它是用**同一個鍵**編出來的。
      #
      # 🔴 **兩種長度都要收**：三元組是本次（D48）之後的新形；二元組是本次之前
      #   線上已經發出去的 cursor（admin SPA 正在翻頁的那些）。若只收三元組，
      #   部署當下所有進行中的分頁會一起變成 BAD_USER_INPUT。
      # 🔴 二元組的相容範圍**只到本次之前存在的兩個鍵**（`created_at`／`position`），
      #   而那兩個鍵的 codec 本來就互斥（`Time.iso8601(3)` 丟 TypeError、
      #   `Integer("2026-08-…")` 丟 ArgumentError）⇒ 舊形沒有跨鍵誤用的空間。
      #   新鍵（filename／byte_size）一律只認三元組。
      LEGACY_KEYS = %i[created_at position].freeze
      private_constant :LEGACY_KEYS

      def extract(payload, key)
        raise ArgumentError, "cursor payload must be an array" unless payload.is_a?(Array)

        case payload.length
        when 3
          cursor_key, raw, id = payload
          raise ArgumentError, "cursor key mismatch" unless cursor_key == key.to_s

          [ raw, id ]
        when 2
          raise ArgumentError, "legacy cursor not valid for #{key}" unless LEGACY_KEYS.include?(key)

          payload
        else
          raise ArgumentError, "cursor payload has unexpected shape"
        end
      end

      def padded(cursor)
        cursor + ("=" * ((4 - cursor.length % 4) % 4))
      end
    end
  end
end
