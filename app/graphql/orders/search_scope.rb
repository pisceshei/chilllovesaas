# frozen_string_literal: true

module Orders
  # `orders(query:)` 的伺服器端搜尋（G6-6a v1）。
  #
  # ①這是什麼：搜尋字串 → tenant scope 上的 SQL 條件。
  # ②值域（v1）：
  #   - 裸詞／引號片語 ⇒ **單號或 email** CONTAINS，多詞 AND（單號比對前
  #     剝別名前綴 `#`——買家貼「#1001」是常態）。
  #   - `status:<v>` ⇒ 等值；合法值＝Order::STATUSES，非法值 ⇒ 整查詢空集。
  #   - `financial_status:<v>` ⇒ 等值；合法值＝Order::FINANCIAL_STATUSES。
  #   - `fulfillment_status:<v>` ⇒ 等值；合法值＝Order::FULFILLMENT_STATUSES。
  #   同欄位兩次＝AND（products 線同語義）⇒ 恆空。88 §2 的 24 個列表篩選維度
  #   屬列表功能包逐步擴白名單；未支援 prefix 一律當字面文字（fail-closed）。
  # ③🔴 LIKE 跳脫與禁字串內插——products/customers 線同紀律。
  # ④跨功能影響：與 Products::KeysetConnection 組合；admin 訂單列表（步 4）的
  #   篩選 chips 組 query 字串直接吃本白名單。
  class SearchScope
    FIELD_FILTERS = {
      "status" => { column: :status, values: -> { Order::STATUSES } },
      "financial_status" => { column: :financial_status, values: -> { Order::FINANCIAL_STATUSES } },
      "fulfillment_status" => { column: :fulfillment_status, values: -> { Order::FULFILLMENT_STATUSES } }
    }.freeze

    TOKEN = /
      (?:(?<field>[a-z_]+):)?
      (?:
        "(?<dq>[^"]*)" |
        '(?<sq>[^']*)' |
        (?<bare>[^\s"']+)
      )
    /x

    # @param scope [ActiveRecord::Relation] 已 tenant-scoped 的 Order relation
    # @param query [String, nil]
    # @return [ActiveRecord::Relation]
    def self.apply(scope:, query:)
      return scope if query.blank?

      query.scan(TOKEN).each do |field, dq, sq, bare|
        term = dq || sq || bare
        next if term.blank?

        filter = field && FIELD_FILTERS[field]
        if filter
          value = term.downcase
          # 非法 enum 值 ⇒ 空集（回錯資料比回空集糟；query 無 userErrors 通道）
          scope = filter[:values].call.include?(value) ?
                    scope.where(filter[:column] => value) : scope.none
        else
          text = field ? "#{field}:#{term}" : term # 未知 prefix＝字面文字
          like = "%#{ActiveRecord::Base.sanitize_sql_like(text.delete_prefix('#'))}%"
          scope = scope.where("name LIKE :t OR email LIKE :t", t: like)
        end
      end
      scope
    end
  end
end
