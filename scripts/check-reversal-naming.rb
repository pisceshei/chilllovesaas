#!/usr/bin/env ruby
# frozen_string_literal: true

# 撤銷款項 vs 實體退貨的命名檢查——把 docs/specs/86 的契約從「紀律」變成「機制」。
#
# 背景（86 §0）：`returns`（實體退貨）與 `sales_reversals`（撤銷款項聚合）是**兩個概念**，
# 官方 2026-03-05 特地把它們拆開。合併的後果：
#   - 用 returns 當聚合 ⇒ 取消單與訂單編輯的減項被漏掉，總銷售額對不上；
#   - 用 sales_reversals 取代實體退貨 ⇒ 退貨數量/原因/補貨決策無處可放。
#
# 這個腳本檢查兩條命名規則（86 §3.1）：
#   規則 1｜**聚合指標欄不得用 `returns` 系列的舊名**（官方 2026-07 已移除的 11 個舊欄名）
#   規則 2｜**資源表不得用 `sales_reversal` 命名**（它是指標不是資源）
#
# 不檢查什麼（誠實聲明）：無法判斷「某個欄位在語義上是不是聚合」——那要讀規格。
# 本腳本只擋**明確違規的字面形態**，語義正確性仍靠 code review 與 86 號。
#
# 用法：ruby scripts/check-reversal-naming.rb
# 退出碼：0=通過，1=有違規

ROOT = File.expand_path("..", __dir__)

# 🔴 官方已移除的舊指標欄名（86 §2 的左欄）。出現在 schema 或 model 即違規。
DEPRECATED_METRIC_COLUMNS = %w[
  returns
  net_returns
  gross_returns
  total_returns
  discounts_returned
  shipping_returned
  taxes_returned
  quantity_returned
  returned_quantity_rate
  is_return_related
  order_or_return
].freeze

# 資源表不得叫這些（sales_reversals 是指標不是資源，86 §1.1）。
FORBIDDEN_TABLE_NAMES = %w[
  sales_reversals
  reversals
].freeze

violations = []
schema_path = File.join(ROOT, "db", "schema.rb")

if File.exist?(schema_path)
  schema = File.read(schema_path)

  # ── 規則 1：舊指標欄名 ────────────────────────────────────────────────
  # 只看欄位宣告行（t.xxx "name"），避免命中註釋或表名。
  schema.each_line.with_index(1) do |line, lineno|
    next unless (m = line.match(/^\s+t\.\w+\s+"([^"]+)"/))

    column = m[1]
    next unless DEPRECATED_METRIC_COLUMNS.include?(column)

    violations << "db/schema.rb:#{lineno} 欄位 `#{column}` 是官方 2026-07 已移除的舊指標欄名。" \
      "新名見 docs/specs/86 §2；若這其實是**實體退貨資源**的欄位，請改用 `return_*` 前綴。"
  end

  # ── 規則 2：資源表命名 ────────────────────────────────────────────────
  schema.each_line.with_index(1) do |line, lineno|
    next unless (m = line.match(/create_table "([^"]+)"/))

    table = m[1]
    next unless FORBIDDEN_TABLE_NAMES.include?(table)

    violations << "db/schema.rb:#{lineno} 表 `#{table}` 用了聚合指標的名字。" \
      "`sales_reversals` 是**指標不是資源**（86 §1.1）——實體退貨的表請叫 `returns`。"
  end
end

if violations.empty?
  puts "OK：撤銷/退貨命名檢查通過"
  puts "  - 無官方已移除的舊指標欄名（#{DEPRECATED_METRIC_COLUMNS.size} 個）"
  puts "  - 無以聚合指標命名的資源表"
  exit 0
end

warn "::error::撤銷/退貨命名檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
exit 1
