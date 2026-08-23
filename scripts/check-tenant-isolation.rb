#!/usr/bin/env ruby
# frozen_string_literal: true

# 租戶隔離檢查——把裁定 D8／§A G24 的配套條款從「紀律」變成「機制」。
#
# 背景（docs/specs/85）：身分表（staff_members／roles／role_permissions／sessions）
# 已升為組織層、不再帶 shop_id，因此**資料庫層不再擋跨店引用**。豁免的邊界是：
#
#   🔴 豁免的是「表有沒有 shop_id 欄」，**不是「查詢可不可以不帶 shop_id」**。
#
# 這個腳本檢查兩件事：
#
#   規則 1｜**白名單以外的表一律要有 shop_id**
#     防止有人日後新建業務資料表時忘記帶 shop_id，或把新的身分表偷偷加進豁免。
#     白名單是**逐表列舉的常數**，改它就會在 diff 裡看見（G24 配套條款③）。
#
#   規則 2｜**身分表的 model 不得再宣告 acts_as_tenant**
#     它們已無 shop_id，宣告了會在 runtime 才炸；早點抓到。
#
# 不檢查什麼（誠實聲明）：本腳本是**靜態結構檢查**，無法保證「每一句查詢都帶了
# shop_id 條件」——那需要 runtime 或 AST 分析。業務資料表的 query 隔離仍由
# `acts_as_tenant` 的 fail-closed 承擔（那些表沒有被豁免，acts_as_tenant 照舊生效）。
#
# 用法：ruby scripts/check-tenant-isolation.rb
# 退出碼：0=通過，1=有違規

require "yaml"

ROOT = File.expand_path("..", __dir__)
SCHEMA = File.join(ROOT, "db", "schema.rb")

# 🔴 組織層豁免白名單。**本清單必須逐字等於** CLAUDE.md 鐵律 2 註釋與 docs/specs/71 §A G24
# 的「已建」那一列；要新增必須同步改那兩處並在 PR 描述標明（G24 配套條款③）。
#
# <!-- 2026-08-14 修正：原本 `shops` 也放在這個常數裡（下面第二個迴圈還特地 `next if table == "shops"`
#      把它排除掉）——它不是「組織層身分表」，它是**租戶根**，是 shop_id 指向的那張表。
#      混在一起的後果不是跑錯，是**清單失去可稽核性**：規則說白名單是身分表，
#      常數裡卻有一張不是身分表的，於是「常數＝規則」這句話變成假的，
#      對不上時沒人知道是誰錯。拆成兩個常數後，下面這一份可以逐字對照規則。 -->
ORG_LEVEL_TABLES = %w[
  staff_members
  roles
  role_permissions
  sessions
].freeze

# 租戶根：`shops` 本身當然沒有 shop_id，它是被指向的那一端。這不是豁免。
TENANT_ROOT_TABLES = %w[shops].freeze

# 🔴 明確**不得**進白名單的表：它們必須帶 shop_id。
# `user_store_assignments` 是 user × shop 的關聯本體——曾被誤列進鐵律 2 的豁免清單，
# 那是反的（2026-08-14 修正）。這裡做成自檢，避免同一個錯再犯一次。
MUST_HAVE_SHOP_ID = %w[user_store_assignments].freeze

overlap = ORG_LEVEL_TABLES & MUST_HAVE_SHOP_ID
unless overlap.empty?
  warn "::error::白名單自檢失敗：#{overlap.join(', ')} 必須帶 shop_id，不得列入 ORG_LEVEL_TABLES。"
  exit 1
end

# 非租戶資料：平台級或系統表，本來就不該有 shop_id。
# 🔴 `platform_locales`＝**平台字典表**（2026-08-23 ML-0，docs/plans/2026-08-23-多語言方案.md §3.1）：
#    跨租戶共用、隨版本部署、無任何租戶資料——它不是身分表（不進 ORG_LEVEL_TABLES），
#    也不是業務資料；分類依 CLAUDE.md 鐵律 2 註釋「平台字典表」段，71 §A G24 同步登記。
NON_TENANT_TABLES = %w[
  schema_migrations
  ar_internal_metadata
  solid_queue_jobs
  solid_cache_entries
  platform_locales
].freeze

# 身分表的 model 不得再宣告 acts_as_tenant。
IDENTITY_MODELS = {
  "staff_member" => "StaffMember",
  "role" => "Role",
  "role_permission" => "RolePermission",
  "session" => "Session"
}.freeze

def tables_with_shop_id(schema_source)
  result = {}
  current = nil
  schema_source.each_line do |line|
    if (m = line.match(/create_table "([^"]+)"/))
      current = m[1]
      result[current] = false
    elsif current && line.match?(/^\s+end\s*$/)
      current = nil
    elsif current && line.match?(/t\.bigint "shop_id"/)
      result[current] = true
    end
  end
  result
end

violations = []

schema = File.read(SCHEMA)
tables = tables_with_shop_id(schema)

# ── 規則 1 ────────────────────────────────────────────────────────────────
tables.each do |table, has_shop_id|
  next if ORG_LEVEL_TABLES.include?(table)
  next if TENANT_ROOT_TABLES.include?(table)
  next if NON_TENANT_TABLES.include?(table)
  next if has_shop_id

  violations << "表 `#{table}` 缺少 shop_id，且不在組織層豁免白名單中。" \
    "業務資料表一律要帶 shop_id（鐵律 2）；若它真的該是組織層，" \
    "必須同時改 CLAUDE.md 鐵律 2、docs/specs/71 §A G24 與本腳本的 ORG_LEVEL_TABLES。"
end

# 反向：白名單裡的表不該還留著 shop_id（改到一半的狀態）
ORG_LEVEL_TABLES.each do |table|
  next unless tables[table]

  violations << "表 `#{table}` 在組織層白名單中卻仍有 shop_id——" \
    "migration 可能只做了一半（docs/specs/85 §5）。"
end

# 正向：明列必須帶 shop_id 的表，真的帶了嗎（規則 1 已涵蓋，這裡給出更明確的訊息）
MUST_HAVE_SHOP_ID.each do |table|
  next unless tables.key?(table)
  next if tables[table]

  violations << "表 `#{table}` 缺少 shop_id，但它是 user × shop 的關聯本體，" \
    "**必須**帶 shop_id（CLAUDE.md 鐵律 2 註釋、docs/specs/85 §3）。"
end

# ── 規則 2 ────────────────────────────────────────────────────────────────
IDENTITY_MODELS.each do |file, klass|
  path = File.join(ROOT, "app", "models", "#{file}.rb")
  next unless File.exist?(path)

  source = File.read(path)
  # 只看實際程式碼行，註釋裡提到 acts_as_tenant 是說明歷史，不算違規
  code = source.lines.reject { |l| l.strip.start_with?("#") }.join
  next unless code.match?(/^\s*acts_as_tenant\b/)

  violations << "`#{klass}` 仍宣告 acts_as_tenant，但該表已無 shop_id（裁定 D8）。"
end

# ── 規則 3｜金額欄不得為 unsigned（§A G25） ──────────────────────────────
# 🔴 **總銷售額可以是負數**（撤銷 > 銷售的日子，官方明列，docs/research/80 §3）。
# 金額欄若被宣告成 unsigned，那些日子的資料**寫不進去**——而且在只有正常銷售的
# 測試資料上完全測不出來。這條擋的是「未來有人為了省空間或防呆而加 unsigned」。
if File.exist?(SCHEMA)
  File.read(SCHEMA).each_line.with_index(1) do |line, lineno|
    next unless line.match?(/t\.\w+\s+"[a-z_]*cents"/)
    next unless line.include?("unsigned")

    # 三段字串用 `\` 續行拼接。原本寫成同一行三個相鄰字面值中間夾巨量空白，
    # 語法正確（omakase 未開行長限制）但讀起來像被壓壞的續行，
    # 之後有人插逗號就會誤讀成方法呼叫（PR #24 的 Claude 驗收 🟡 建議）。
    violations << "db/schema.rb:#{lineno} 金額欄被宣告為 unsigned。" \
      "🔴 總銷售額可以是負數（撤銷 > 銷售的日子）——unsigned 會讓那些日子寫不進去，" \
      "且在正常銷售的測試資料上測不出來。見 §A G25／docs/research/80 §3。"
  end
end

if violations.empty?
  puts "OK：租戶隔離檢查通過"
  puts "  - 業務資料表皆帶 shop_id（組織層白名單 #{ORG_LEVEL_TABLES.size} 張 ＋ 租戶根 " \
       "#{TENANT_ROOT_TABLES.size} 張除外）"
  puts "  - 白名單：#{ORG_LEVEL_TABLES.join(' / ')}（須逐字等於 CLAUDE.md 鐵律 2 的「已建」列）"
  puts "  - #{MUST_HAVE_SHOP_ID.join(' / ')} 確實帶 shop_id"
  puts "  - 身分表的 model 皆未宣告 acts_as_tenant"
  puts "  - 金額欄皆未宣告 unsigned（總銷售額可為負，G25）"
  exit 0
end

warn "::error::租戶隔離檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
exit 1
