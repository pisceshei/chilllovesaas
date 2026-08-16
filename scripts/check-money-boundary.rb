#!/usr/bin/env ruby
# frozen_string_literal: true

# 金額單位邊界的**機器編譯期**——`docs/specs/65` §C.3 的 CI 靜態檢查。
#
# ## 為什麼需要它（L4 這一層擋的東西別的層擋不到）
#
# 65 §C.1 的四層防呆裡：
#   L1（值物件無隱式轉換）、L2（唯一建構路徑）、L3（adapter 型別閘門）
#   ——這三層只約束**已經用了值物件的路徑**；
#   **L4（命名 ＋ 本腳本）約束的是「還沒寫出來的路徑」。**
#
# 🔴 三個月後有人在 `app/services/psp/<某家>/charge.rb` 新寫一行、
# 不經 adapter 直接組 HTTP body 時，**擋得住他的只有這個腳本**——
# 他不會先去讀 `app/models/money.rb` 的註釋（65 §C.4 第 2 點）。
#
# 🔴 而且這個 bug **在 HKD／USD 下測試全綠**（65 §0.2）：exponent=2 時 divisor 是 1，
# 錯誤實作與正確實作的輸出**完全相同**。註釋唯一能起作用的時機是「有人心裡有疑問而去查」，
# 但這個 bug **不會讓任何人產生疑問**。
#
# ## 不檢查什麼（🔴 誠實聲明——這段是本腳本對外宣稱的契約，不得誇大）
#
# 1. **它是純文字掃描，不解析 AST**。`_cents` 出現在**字串常數或行尾註釋**裡也會命中
#    （寧可誤擋）。⚠️ **整行註釋不會命中**——`each_line` 會跳過它們，
#    理由見該方法：不跳的話「唯一正確實作 C4 的檔案會被 C4 判違規」。
#    原文寫「註釋裡也會命中」沒有區分這兩種，把涵蓋範圍講得比實際大。
# 2. **它不驗證語義**：一個叫 `amount_minor` 但其實裝著 cents 的變數，本腳本看不出來。
#    那要靠 L1–L3 的型別層。**四層是互補的，任何一層都不宣稱單獨足夠。**
# 3. **C2 只掃「明顯的 kwarg 呼叫」**：`Psp::X.new(...).charge(amount_minor: ...)` 這種。
#    動態 send、hash splat（`**payload`）它看不到。
#
# 用法：ruby scripts/check-money-boundary.rb [root]
# 退出碼：0=通過，1=有違規
require "yaml"

ROOT = ARGV[0] || File.expand_path("..", __dir__)

# 🔴 `app/models/money.rb` 是**唯一**允許出現 `__build` 的檔案。
#
# Ruby 表達不了「friend class」——`Money::Storage` 與 `Money::PspMinor` 是兩個不同的
# 類別，private class method 呼叫不到 ⇒ `__build` 只能是 public。
# 這是 65 §C 四層防線裡**唯一一處「型別擋不住、只能靠 CI 擋」**的地方。
BUILD_ALLOWED = [ "app/models/money.rb" ].freeze

# 「金額路徑的測試檔」的定義（65 §H.1 的 CI 規則以它為判準，但規格沒有定義它）。
# 🔴 用具名常數而不是即興 glob：改動它一定會出現在 diff 裡。
MONEY_TEST_GLOBS = [
  "spec/models/money_spec.rb",
  "spec/models/psp_amount_matrix_spec.rb",
  "spec/models/psp/*_spec.rb"
].freeze

def read(path) = File.read(path, encoding: "UTF-8")
def rel(path) = path.delete_prefix("#{ROOT}/").tr("\\", "/")
def files(glob) = Dir.glob(File.join(ROOT, glob)).select { |f| File.file?(f) }

violations = []

# 每一行的 (行號, 內容)。
#
# 🔴 **只跳過整行註釋，不跳過行尾註釋**（2026-08-15 的取捨，寫下來以免被當成疏忽）：
#   - 跳過整行註釋是**必要的**——`base_adapter.rb` 的文檔註釋必須說明「R4 一律拒收」，
#     而它得叫出 `Money::Decimal` 這個名字才講得清楚。不跳的話，
#     **唯一一個正確實作了 C4 的檔案會被 C4 判成違規**。
#   - **不跳行尾註釋**是刻意的：要精確剝掉行尾 `#` 就得處理字串內的 `#` 與 `#{}`，
#     而那正是 `scripts/lint-prototype.py` 踩過六次「漏看」的那類解析。
#     這裡的取捨方向是**寧可誤擋**——誤擋會有人來改，漏看不會有人發現。
def each_line(path)
  read(path).each_line.with_index(1) do |line, no|
    next if line.lstrip.start_with?("#")

    yield(line, no)
  end
end

# ── C1：`app/services/psp/**` 不得出現 `_cents` ────────────────────────────────
#
# PSP 目錄裡本來就不該有 storage 尺度的東西。
#
# ⚠️ 65 §C.3 的 C1 原文寫「白名單：`Money::Storage` 的型別註記與 `#to_psp_amount`
# 的實作兩處」——**那兩處在 `app/models/money.rb`，本來就不在掃描範圍內** ⇒
# 該白名單是**空的**。此處不實作白名單，並把這個發現寫下來，
# 免得下一個人以為漏做了（2026-08-15 查證）。
files("app/services/psp/**/*.rb").each do |path|
  each_line(path) do |line, no|
    next unless line.include?("_cents")

    violations << "[C1] #{rel(path)}:#{no} PSP 目錄裡出現 `_cents`——" \
      "storage 尺度不該進 PSP 路徑（65 §C.3 C1）"
  end
end

# ── C4：`app/services/psp/**` 不得出現 R4 ─────────────────────────────────────
#
# 🔴 R4（`Money::Decimal`，物流商／JSON-LD 用的那個）與 R6 的 **wire form 完全相同**
# ⇒ **在 PSP 目錄裡看到 R4，唯一的可能就是有人拿 feed／物流商的值來送款**。
files("app/services/psp/**/*.rb").each do |path|
  each_line(path) do |line, no|
    if line.include?("Money::Decimal")
      violations << "[C4] #{rel(path)}:#{no} PSP 目錄裡出現 `Money::Decimal`（R4）——" \
        "它與 R6 的字串內容可能一模一樣，但不帶 psp、不跑 65 §D 的斷言（65 §C.3 C4）"
    end
    # `_psp_decimal`（R6 的後綴）是合法的；裸 `_decimal`（R4 的後綴）不是。
    stripped = line.gsub("_psp_decimal", "")
    next unless stripped.include?("_decimal")

    violations << "[C4] #{rel(path)}:#{no} PSP 目錄裡出現 `_decimal`（R4 的後綴）——" \
      "R6 的後綴是 `_psp_decimal`，刻意不同（65 §C.2）"
  end
end

# ── C2：對 `Psp::*` 的呼叫，金額 kwarg 名須以 `_minor` 或 `_psp_decimal` 結尾 ────
#
# 擋住「不經 adapter、直接組 HTTP body」的繞過。
AMOUNT_KWARG = /\b(?<name>\w*(?:amount|price|total|fee|charge|refund)\w*):\s/i
files("app/**/*.rb").each do |path|
  each_line(path) do |line, no|
    next unless line.match?(/\bPsp::\w+/)

    line.scan(AMOUNT_KWARG) do
      name = Regexp.last_match[:name]
      next if name.end_with?("_minor", "_psp_decimal")
      # 值物件本身當參數傳是合法的（adapter 會驗型別）。
      next if line.match?(/#{Regexp.escape(name)}:\s*(amount|\w*_(minor|psp_decimal))\b/)

      violations << "[C2] #{rel(path)}:#{no} 對 Psp::* 的呼叫用了金額 kwarg `#{name}:`——" \
        "須以 `_minor` 或 `_psp_decimal` 結尾（65 §C.3 C2）"
    end
  end
end

# ── C3：新增的金額欄位須 `bigint` ＋ `_cents`，禁 `decimal`／`float` ────────────
files("db/migrate/*.rb").each do |path|
  each_line(path) do |line, no|
    if line.match?(/t\.(decimal|float)\b/)
      violations << "[C3] #{rel(path)}:#{no} migration 出現 `t.decimal`／`t.float`——" \
        "金額欄位一律 `bigint` ＋ `_cents`（鐵律 3／65 §C.2）"
    end
    # 🔴 **正面檢查：`_cents` 欄位的宣告型別必須是 `bigint`**（2026-08-15 補）。
    #
    # 原本這裡只擋 `t.integer :xxx_cents` 一種寫法 ⇒ `t.string :price_cents`、
    # `t.bigint` 以外的**任何**型別都會靜默通過，而下方的成功訊息卻宣告
    # 「`_cents` 皆為 bigint」——**訊息宣稱了一個沒有發生的檢查**。
    # ⚠️ 這與本輪修掉的三條是同一種病：讓人對一道不存在的防線產生信心。
    # ⇒ 改成白名單式：抓所有 `t.<型別> :xxx_cents`，型別不是 bigint 就是違規。
    #   這樣新增一種錯誤寫法時**預設是被擋的**，不需要有人想到要加規則。
    next unless (m = line.match(/t\.(\w+)\s+:(\w*_cents)\b/))
    next if m[1] == "bigint"

    violations << "[C3] #{rel(path)}:#{no} `#{m[2]}` 宣告為 `t.#{m[1]}`——" \
      "須 `bigint`（`limits.money_boundary.storage_column_sql_type`；" \
      "integer 會在大額或高單價幣別上溢位，而溢位是靜默的）"
  end
end

# ── C5：`__build` 只准出現在 `app/models/money.rb` ─────────────────────────────
#
# 見檔頭 `BUILD_ALLOWED` 的說明：這是四層防線裡唯一一處型別擋不住的地方。
files("app/**/*.rb").each do |path|
  next if BUILD_ALLOWED.include?(rel(path))

  each_line(path) do |line, no|
    next unless line.include?("__build")

    violations << "[C5] #{rel(path)}:#{no} 出現 `__build`——" \
      "R5／R6 的唯一建構路徑是 `Money::Storage#to_psp_amount`（65 §C L2）；" \
      "`__build` 只准 app/models/money.rb 呼叫"
  end
end

# ── 矩陣覆蓋度（65 §H.1 的兩條機械化保證）────────────────────────────────────
#
# 🔴 65 §H.1 逐字：「這兩條是本節唯二的機械化保證——其餘都是清單，清單會被忘記。」
limits = YAML.safe_load_file(File.join(ROOT, "config/limits.yml"), aliases: true)
boundary = limits.fetch("money_boundary")
test_source = MONEY_TEST_GLOBS.flat_map { |glob| files(glob) }.map { |f| read(f) }.join("\n")

boundary.fetch("test_matrix_zero_decimal_required").each do |currency|
  next if test_source.include?(currency)

  violations << "[矩陣] 金額路徑的測試檔沒有出現 zero-decimal 幣別 `#{currency}`——" \
    "視為未涵蓋（65 §H.1 `test_matrix_missing_zero_decimal_action: ci_fail`）。" \
    "掃描範圍＝#{MONEY_TEST_GLOBS.join(', ')}"
end

pack_source = files("spec/fixtures/psp_packs/*.yml").map { |f| read(f) }.join("\n")
boundary.fetch("test_matrix_amount_formats_required").each do |format|
  next if pack_source.include?("amount_format: #{format}")

  violations << "[矩陣] 沒有任何 `amount_format: #{format}` 的 fixture pack——" \
    "只測 minor_units 的矩陣，在 Airwallex 型 PSP 上等於零覆蓋（65 §H.1）"
end

if violations.empty?
  puts "OK：金額單位邊界檢查通過"
  puts "  - C1 PSP 目錄無 `_cents`"
  puts "  - C2 對 Psp::* 的金額 kwarg 皆為 `_minor`／`_psp_decimal`"
  puts "  - C3 migration 無 `t.decimal`／`t.float`，`_cents` 皆為 bigint"
  puts "  - C4 PSP 目錄無 `Money::Decimal` 與裸 `_decimal`"
  puts "  - C5 `__build` 只出現在 #{BUILD_ALLOWED.join(', ')}"
  puts "  - 矩陣：zero-decimal 幣別 #{boundary.fetch('test_matrix_zero_decimal_required').join('／')} 皆有涵蓋；" \
       "兩種 amount_format 皆有 fixture pack"
  exit 0
end

warn "::error::金額單位邊界檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
exit 1
