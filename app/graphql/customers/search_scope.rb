# frozen_string_literal: true

module Customers
  # `customers(query:)` 的伺服器端搜尋（G6-7 v1）。
  #
  # ①這是什麼：把搜尋字串編譯成 tenant scope 上的 SQL 條件。
  # ②值域（v1）：裸詞與引號片語 ⇒ **姓名／email／電話 任一 CONTAINS**，
  #   多詞 AND（每個詞都要命中至少一欄）。74 §1 的 ShopifyQL 查詢視圖
  #   （18 欄 SHOW／field filter／分群 DSL）屬顧客模組全量包——本包刻意只做
  #   自由文字，**不半支援 field:value**（出現冒號語法一律當字面文字，與
  #   Products::SearchScope 的 fail-closed 姿勢一致）。
  # ③🔴 LIKE 的 `%`／`_` 經 `sanitize_sql_like` 跳脫（商品線同教訓：
  #   使用者輸入 `0%` 不得萬用匹配整表）；不用字串內插組 SQL。
  # ④跨功能影響：與 Products::KeysetConnection 組合——filter 先於 cursor 套用。
  class SearchScope
    TOKEN = /
      (?:
        "(?<dq>[^"]*)" |
        '(?<sq>[^']*)' |
        (?<bare>[^\s"']+)
      )
    /x

    # @param scope [ActiveRecord::Relation] 已 tenant-scoped 的 Customer relation
    # @param query [String, nil]
    # @return [ActiveRecord::Relation]
    def self.apply(scope:, query:)
      return scope if query.blank?

      query.scan(TOKEN).each do |dq, sq, bare|
        term = dq || sq || bare
        next if term.blank?

        like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        scope = scope.where(
          "first_name LIKE :t OR last_name LIKE :t OR email LIKE :t OR phone LIKE :t",
          t: like
        )
      end
      scope
    end
  end
end
