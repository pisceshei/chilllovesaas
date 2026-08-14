#!/usr/bin/env ruby
# frozen_string_literal: true

# 撤銷款項 vs 實體退貨的命名檢查——把 docs/specs/86 的契約從「紀律」變成「機制」。
#
# 背景（86 §0）：`returns`（實體退貨）與 `sales_reversals`（撤銷款項聚合）是**兩個概念**，
# 官方 2026-03-05 特地把它們拆開。合併的後果：
#   - 用 returns 當聚合 ⇒ 取消單與訂單編輯的減項被漏掉，總銷售額對不上；
#   - 用 sales_reversals 取代實體退貨 ⇒ 退貨數量/原因/補貨決策無處可放。
#
# 這個腳本檢查三條命名規則（86 §3.1）：
#   規則 1｜**schema 的聚合指標欄不得用 `returns` 系列的舊名**（官方 2026-07 移除的 11 個）
#   規則 2｜**資源表不得用 `sales_reversal` 命名**（它是指標不是資源）
#   規則 3｜**舊指標名不得出現在 app 代碼**（GraphQL 欄位／model 方法／rollup key／報表 UI）
#
# 🔴 規則 3 是 2026-08-14 補的（來源：PR #22 的 Codex review 第 3 條）。
#    原本本腳本**只讀 `db/schema.rb`**，但 86 §3.1 的規則適用範圍是
#    「rollup 表、分析 API、報表 UI」**三處**——舊名以 GraphQL 欄位、model 方法、
#    序列化 key 或前端報表欄位的形態出現時，CI 一律綠燈通過。三處只守住一處。
#
# 不檢查什麼（🔴 誠實聲明，這段就是本腳本對外宣稱的契約，不得誇大）：
#   1. 無法判斷「某個欄位在語義上是不是聚合」——那要讀規格，語義正確性仍靠 code review 與 86 號。
#   2. 🔴 **規則 3 不掃裸 `returns`**，只掃 10 個不會誤判的複合名。理由：`returns` 在 app 代碼裡
#      **多半是合法的**——86 §3.1 要求實體退貨資源就叫 `returns`（`has_many :returns`、
#      `Return` model、`/returns` 路由），而英文散文與 YARD `@return` 也大量出現這個字。
#      裸 `returns` 只在**規則 1 的 schema 欄位位置**判得準（rollup 表上的欄位叫 returns
#      就是聚合），所以只在那裡擋。
#
# 用法：ruby scripts/check-reversal-naming.rb
# 退出碼：0=通過，1=有違規

ROOT = File.expand_path("..", __dir__)

# 🔴 官方已移除的舊指標欄名（86 §2 的左欄）。
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

# 規則 3 掃的子集：**去掉裸 `returns`** 後的 10 個複合名。
# 這些不會出現在英文散文或 `@return` 裡，掃全檔也不會誤判。
DEPRECATED_IN_CODE = (DEPRECATED_METRIC_COLUMNS - %w[returns]).freeze

# 規則 3 的掃描範圍＝86 §3.1 表格右欄的「分析 API」與「報表 UI」。
CODE_GLOBS = [
  "app/models/**/*.rb",
  "app/graphql/**/*.rb",
  "app/controllers/**/*.rb",
  "app/jobs/**/*.rb",
  "app/frontend/admin/**/*.ts",
  "app/frontend/admin/**/*.tsx"
].freeze

# 資源表不得叫這些（sales_reversals 是指標不是資源，86 §1.1）。
FORBIDDEN_TABLE_NAMES = %w[
  sales_reversals
  reversals
].freeze

# `reversals`（不帶 sales_ 前綴）**不在官方 11 組對照表內**，是我方的預防性加嚴：
# 它同樣是聚合語義的字，拿來當資源表名會犯 86 §1.1 的同一個錯。
# 🔴 不要把它讀成「官方清單項」——日後對照官方文檔時，這一個是我們自己加的。
PREVENTIVE_TABLE_NAMES = %w[reversals].freeze

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

    note = PREVENTIVE_TABLE_NAMES.include?(table) ? "（本名為我方預防性加嚴，非官方清單項）" : ""
    violations << "db/schema.rb:#{lineno} 表 `#{table}` 用了聚合指標的名字#{note}。" \
      "`sales_reversals` 是**指標不是資源**（86 §1.1）——實體退貨的表請叫 `returns`。"
  end
end

# ── 規則 3：app 代碼裡的舊指標名 ──────────────────────────────────────────
# 掃 GraphQL 欄位／model 方法／rollup key／前端報表欄位——86 §3.1 的另外兩處適用範圍。
CODE_GLOBS.each do |glob|
  Dir.glob(File.join(ROOT, glob)).each do |path|
    rel = path.sub("#{ROOT}/", "").tr("\\", "/")
    next if rel.include?("node_modules/")

    File.readlines(path).each_with_index do |line, idx|
      DEPRECATED_IN_CODE.each do |name|
        # \b 邊界確保 `returned_quantity`（86 §3.3 的合法新欄名）不會被
        # `returned_quantity_rate` 的規則命中，反之亦然——`_` 是 word 字元。
        next unless line.match?(/\b#{Regexp.escape(name)}\b/)

        violations << "#{rel}:#{idx + 1} 出現官方 2026-07 已移除的舊指標名 `#{name}`。" \
          "新名見 docs/specs/86 §2；若這其實是**實體退貨**的東西，請改用 `return_*` 前綴。"
      end
    end
  end
end

if violations.empty?
  puts "OK：撤銷/退貨命名檢查通過"
  puts "  - schema 無官方已移除的舊指標欄名（#{DEPRECATED_METRIC_COLUMNS.size} 個）"
  puts "  - 無以聚合指標命名的資源表"
  puts "  - app 代碼（model/graphql/controller/job/admin 前端）無舊指標名" \
       "（#{DEPRECATED_IN_CODE.size} 個複合名；裸 `returns` 不掃，理由見檔頭誠實聲明）"
  exit 0
end

warn "::error::撤銷/退貨命名檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
exit 1
