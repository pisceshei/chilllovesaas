# frozen_string_literal: true

module Products
  # `products(query:)` 的伺服器端搜尋（排程第 1 包；契約＝docs/research/28 §1）。
  #
  # ①這是什麼：把 Shopify search syntax 的 **v1 白名單子集**編譯成 tenant scope 上的
  #   SQL 條件。白名單外的語法一律**當字面文字對 title 搜尋**，不猜、不半支援。
  # ②值域（v1 支援）：
  #   - 裸詞與引號片語（單雙引號皆可）⇒ title CONTAINS，多詞 AND（本尊「未指定連接詞＝AND」）
  #   - `status:<v>` ⇒ 等值；合法值＝Product::STATUSES（大小寫不敏感），非法值 ⇒ **整查詢空集**
  #     （回錯資料比回空集糟；products query 沒有 userErrors 通道）
  #   - `vendor:<v>`／`product_type:<v>` ⇒ 等值（utf8mb4_0900_ai_ci ⇒ `=` 天然大小寫不敏感）
  #   同欄位出現兩次＝AND（本尊語義：`orders_count:>16 orders_count:<=30`）⇒ `status:active status:draft` 恆空。
  # ③怎麼做：token 化（片語→field:value→裸詞）後逐條 AND 進 Arel。
  #   🔴 LIKE 的 `%`／`_` 必須經 `sanitize_sql_like` 跳脫——商品標題本身就可能含 `%`
  #   （「100% cotton」），不跳脫則使用者輸入 `0%` 會萬用匹配整表。
  #   🔴 不用字串內插組 SQL（Brakeman fail-closed；ML-3b 的 keyset 前例）。
  # ④跨功能影響：與 `Products::KeysetConnection` 組合——filter 先於 cursor 套用，
  #   同一 query 字串跨頁傳遞時 keyset 語義不變。products 的 `sortKey` 仍未上（D48 已補 `files` 的排序，products 的值域窮舉另計）——原文寫「刻意不在本包」
  #   （排程第 21 包做排序鍵一般化時一起上，這裡先做會把該包拆散）。
  #   v1 未支援而**登記 V** 的：`tag:`（等值集合運算需 product_tags 正規化表＝排程第 9 包，
  #   在那之前做 JSON LIKE 就是 13 §F4.3 禁止的子字串比對）、`created_at:>`、`-`/`NOT` 否定、
  #   `OR`、括號分組、`*` 萬用字元——全文見 docs/dev/m1-products-search.md §3。
  class SearchScope
    # field:value 的白名單。unknown prefix（如 `tag:red`）不在此列 ⇒ 整個 token 當字面文字。
    FIELD_FILTERS = %w[status vendor product_type].freeze

    # token 化：優先吃 `field:"quoted value"`，再吃 `field:value`、`"phrase"`、裸詞。
    TOKEN = /
      (?:(?<field>[a-z_]+):)?
      (?:
        "(?<dq>[^"]*)" |
        '(?<sq>[^']*)' |
        (?<bare>[^\s"']+)
      )
    /x

    def self.apply(scope:, query:)
      return scope if query.blank?

      arel = scope.model.arel_table
      query.scan(TOKEN) do
        field, dq, sq, bare = Regexp.last_match.values_at(:field, :dq, :sq, :bare)
        value = dq || sq || bare
        next if value.blank? && field.blank?

        if field.present? && FIELD_FILTERS.include?(field)
          scope = apply_field(scope, arel, field, value.to_s)
        else
          # 未知 prefix ⇒ 還原成字面文字（含冒號）；純片語／裸詞 ⇒ 原值。
          literal = field.present? ? "#{field}:#{value}" : value.to_s
          escaped = ActiveRecord::Base.sanitize_sql_like(literal)
          scope = scope.where(arel[:title].matches("%#{escaped}%"))
        end
      end
      scope
    end

    def self.apply_field(scope, arel, field, value)
      case field
      when "status"
        normalized = value.downcase
        return scope.none unless Product::STATUSES.include?(normalized)

        scope.where(arel[:status].eq(normalized))
      when "vendor"
        scope.where(arel[:vendor].eq(value))
      when "product_type"
        scope.where(arel[:product_type].eq(value))
      end
    end
    private_class_method :apply_field
  end
end
