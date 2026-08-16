#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-doc-claims.rb` 的回歸測試（fixture 驅動）。
#
# 判準出處：`docs/specs/65-money-unit-boundary.md` §K 第 7 條——**檢查本身也要被測試**，
# 一條永遠不會紅的 CI 規則等於沒有。
#
# 🔴 這一支尤其不能省，因為它守的東西**本身就是「防止文檔說謊」**：
#    一個壞掉的引用保真檢查器，會讓所有人以為引用已經被守著。
#
# ## 這張表怎麼來的
#
# 不是想出來的，是**拿真實事故當 fixture**：2026-08-15 的 PR #39／#40 九輪驗收裡，
# 12 條文檔類 🔴 的每一種形態，這裡各有一份對應的 fixture。
# 開發時把 `check-doc-claims.rb` 拿去跑那幾個歷史 commit 實測，
# 確認它抓得到當時驗收方標的**同一行**（`worklog:57`／`handoff:44`／`:13`／`:14`）。
#
# 用法：ruby scripts/test-doc-claims-rules.rb
# 退出碼：0=全過，1=有失敗

ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(ROOT, "scripts/check-doc-claims.rb")
FIXTURES = File.join(ROOT, "spec/fixtures/ci_violations")

# (fixture 目錄, 期望 exit code, 輸出須包含的字串, 這條在防什麼)
#
# 🔴 一律加 `--all`：R4／R5 預設只掃「相對 base 有改動」的 worklog／handoff，
#    而 fixture 目錄不是 git 工作樹，算不出差異 ⇒ 不加的話那兩條規則永遠不會被測到。
CASES = [
  [ "doc_missing_path", 1, "不存在於樹上",
    "R1：帶目錄前綴的具體路徑指到不存在的檔。" \
    "九輪驗收裡 PR #40 第 2 輪那條 🔴 就是這個形態（worklog:57／handoff:44 引用當時未合併的 check-ci-parity.rb）" ],
  [ "doc_bare_script", 1, "不存在於樹上",
    "🔴 R1 的**裸檔名**分支：`check-exec-bits.sh` 這種不帶 `scripts/` 前綴的寫法。" \
    "PR #39 第 3 輪那條 🔴 正是它，而且**這是本專案最常見的引用寫法**——" \
    "只認帶前綴的路徑會讓整類掃不到（開發時實測漏掉過，補 BARE_SCRIPT 才抓到）" ],
  [ "doc_anchored_ok", 0, "OK：文檔引用保真檢查通過",
    "🔴 反向斷言：引用不存在的檔但**有錨定**（`PR #99 引入，尚未進 main`）必須放行。" \
    "跨 PR 交叉指引本身有價值，錯的只是把「別的分支上有」寫成「現在就有」。" \
    "缺這條，規則會逼人刪掉有用的交叉指引" ],
  [ "doc_stale_lineno", 1, "行號已失效",
    "R3：`config/short.yml:99` 但該檔只有 3 行。PR #40 第 5 輪的 `config/ci.rb:48-49` 即此形態" ],
  [ "doc_volatile_num", 1, "可由代碼算出的數字",
    "🔴 R4：「共 7 支」這種手抄的易腐數字，鄰近沒有任何複驗方式。" \
    "PR #40 第 4／5 輪各踩一次，而且**兩次都是「修掉過期數字」的修正本身寫錯的**" ],
  [ "doc_volatile_ok", 0, "OK：文檔引用保真檢查通過",
    "🔴 反向斷言：同樣寫數字但**附了複驗指令** ⇒ 放行。" \
    "缺這條，R4 會退化成「一律禁止寫數字」，那會逼人把有用的量化敘述都刪掉" ],
  [ "doc_no_files", 3, "掃到 **0 個檔案**",
    "🔴 canary：掃到 0 個檔必須 exit 3，不是印「通過」。"     "IN_SCOPE 寫壞、glob 打錯、或 git ls-files 回空時，這支會報通過而它一個字都沒讀過。"     "fixture＝一個只有 `NOTE.txt`、沒有任何 .md 的目錄。"     "🔴 碼用 3 不是 2：與 fail-closed 的 2 結構上可分辨（check-limits-keys.rb 第 3 輪的教訓）" ],
  [ "doc_clean", 0, "OK：文檔引用保真檢查通過",
    "🔴 總反向斷言：乾淨 fixture 必須通過。缺這條，一個永遠 fail 的檢查器會讓上面每一條都「通過」" ]
].freeze

# 🔴 canary：本測試自己也會「沒有失敗」與「沒有檢查」長得一模一樣。
#    把 CASES 清空，這支會印「OK（0 條）」並 exit 0。
#    數字只准往上調；要調低必須在 PR 描述說明刪了哪一條、為什麼不再需要。
MIN_CASES = 8
if CASES.size < MIN_CASES
  warn "::error::CASES 只剩 #{CASES.size} 條（下限 #{MIN_CASES}）——這不是通過，是檢查被砍掉了。"
  exit 1
end

indent = ->(t) { t.to_s.lines.map { |l| "        #{l.rstrip}" }.join("\n") }
failures = []

CASES.each do |dir, want_status, want_output, why|
  path = File.join(FIXTURES, dir)
  unless Dir.exist?(path)
    failures << "#{dir}：fixture 目錄不存在（#{why}）"
    next
  end

  output = `ruby "#{CHECKER}" "#{path}" --all 2>&1`
  status = $?.exitstatus

  if status != want_status
    failures << "#{dir}：期望 exit #{want_status}，實得 #{status}（#{why}）\n      完整輸出：\n#{indent.call(output)}"
    next
  end
  next if output.include?(want_output)

  failures << "#{dir}：exit code 對，但輸出不含 `#{want_output}`（#{why}）\n      完整輸出：\n#{indent.call(output)}"
end

if failures.empty?
  puts "OK：文檔引用保真檢查器的回歸測試通過（#{CASES.size} 條 / #{CASES.map(&:first).uniq.size} 個 fixture）"
  CASES.each { |dir, st, needle, why| puts "  - #{dir} → exit #{st}，含 `#{needle}`：#{why}" }
  exit 0
end

warn "::error::文檔引用保真檢查器的回歸測試失敗（#{failures.size}/#{CASES.size}）："
failures.each { |f| warn "  - #{f}" }
warn "  🔴 這代表 scripts/check-doc-claims.rb 的判定邏輯壞了，或 fixture 被改動。"
exit 1
