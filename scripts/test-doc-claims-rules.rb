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
  [ "doc_plans_scope", 1, "不存在於樹上",
    '🔴 掃描範圍 canary：docs/plans/ 於 2026-08-18（PR #58）納入 IN_SCOPE——'     '本 fixture 釘住它真的被掃。把 check-doc-claims.rb 的 %r{\Adocs/plans/} 拿掉，'     '本 fixture 只剩零個可掃檔 ⇒ checker exit 3（零檔 canary）≠ 期望 1 ⇒ 本 CASE 失敗、'     '整支回歸測試轉紅＝範圍退化被抓（#58 第 3 輪判詞 ⚪2 點名的缺口，第 6 輪落地）' ],
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
  [ "doc_volatile_cjk", 1, "八條 fixture",
    "🔴 **中文數字也是易腐數字**（PR #42 第 3 輪驗收指出）：本倉庫文檔的計數幾乎一律" \
    "寫中文（「八條」「四條」），初版 pattern 全以 \\d+ 開頭 ⇒ R4 對最常見寫法全盲——" \
    "「八條」撐過兩輪人工審查＋本閘門首跑，就是這個洞的直接後果" ],
  [ "doc_volatile_num", 1, "可由代碼算出的數字",
    "🔴 R4：「共 7 支」這種手抄的易腐數字，鄰近沒有任何複驗方式。" \
    "PR #40 第 4／5 輪各踩一次，而且**兩次都是「修掉過期數字」的修正本身寫錯的**" ],
  [ "doc_volatile_ok", 0, "OK：文檔引用保真檢查通過",
    "🔴 反向斷言：同樣寫數字但**附了複驗指令** ⇒ 放行。" \
    "缺這條，R4 會退化成「一律禁止寫數字」，那會逼人把有用的量化敘述都刪掉" ],
  [ "doc_claim_count_missing_recheck", 1, "R6 計數宣稱",
    "🔴 R6：`docs/specs/92-*` 的 `type: count` 宣稱缺 `recheck:` 必須轉紅。" \
    "這是 P-2『計數必附複驗指令』的負向 fixture" ],
  [ "doc_claim_count_ok", 0, "OK：文檔引用保真檢查通過",
    "🔴 R6 反向斷言：同一結構補上可執行 `recheck:` 後必須通過，" \
    "避免規則退化成宣稱索引一律失敗" ],
  [ "doc_claim_duplicate_count", 1, "R6 同一 CLAIM-001 含多個 `type: count`",
    "🔴 R6：同一 CLAIM 區塊的第二筆 count 不得借用第一筆 recheck；" \
    "每個計數宣稱必須有自己的 CLAIM 標頭與複驗命令" ],
  [ "doc_claim_duplicate_recheck", 1, "R6 同一 CLAIM-001 含多個 `recheck:`",
    "🔴 R6：同一 count 區塊不得以第一筆合法命令遮住後續過期／錯誤 recheck；" \
    "每個計數宣稱只能有一個無歧義的複驗入口" ],
  [ "doc_claim_no_count", 1, "R6 宣稱索引沒有任何活性 `type: count`",
    "🔴 R6 局部零供給 canary：合法 CLAIM 標頭存在但 count 全被刪除／改型時必須轉紅，" \
    "不能拿 header canary 冒充計數契約有輸入" ],
  [ "doc_claim_bad_type", 1, "R6 不支援 type metadata `counts`",
    "🔴 R6：已有另一個合法 count 時，`type: counts` 仍不得被 exact-match 篩選靜默略過；" \
    "未支援或拼錯的 type 必須在原行 fail-closed" ],
  [ "doc_claim_malformed_header", 1, "R6 宣稱標頭格式錯誤",
    "🔴 R6：已有合法區塊時，後續 `### CLAIM-02` 不得被折入前一區塊，" \
    "否則該錯字區塊的 `type: count` 可借用前一條的 recheck 靜默通過" ],
  [ "doc_claim_bad_recheck", 1, "R6 計數宣稱",
    "🔴 R6：`recheck:` 有值但不是可辨識命令時仍須轉紅；" \
    "本 case 釘住 RECHECK_CMD，避免判準退化成只檢查欄位存在" ],
  [ "doc_claim_no_headers", 1, "R6 宣稱索引沒有任何",
    "🔴 R6：索引檔有 `type: count` 卻沒有任何 CLAIM 標頭時必須轉紅，" \
    "釘住 headers.empty? 的局部零掃描分支" ],
  [ "doc_claim_count_before_header", 1, "R6 計數宣稱出現在第一個 CLAIM 標頭之前",
    "🔴 R6：合法 CLAIM 區塊存在時，標頭前的 `type: count` 也不得落在結構化檢查之外" ],
  [ "doc_claim_indented_header", 1, "R6 計數宣稱 CLAIM-001",
    "🔴 R6：CommonMark 允許標題前 0–3 個空格；縮排標頭仍須進入自己的區塊，" \
    "不能掉進 headers.empty? 分支形成假阻擋" ],
  [ "doc_claim_indented_metadata", 1, "R6 計數宣稱 CLAIM-001",
    "🔴 R6：CommonMark 允許清單標記前 0–3 個空格；縮排的 type: count 仍須受 recheck 契約約束，" \
    "不能因 byte-zero 錨定而靜默繞過" ],
  [ "doc_claim_indented_metadata_ok", 0, "OK：文檔引用保真檢查通過",
    "🔴 R6 反向斷言：縮排的 type: count 與合法 recheck 必須成對辨識並放行，" \
    "避免修法退化成一律拒絕合法縮排" ],
  [ "doc_claim_duplicate_id", 1, "R6 重複 CLAIM-001",
    "🔴 R6：兩個活性區塊不得共用同一 CLAIM ID；即使都不是 count 也必須阻擋" ],
  [ "doc_claim_inactive_headers", 0, "OK：文檔引用保真檢查通過",
    "🔴 R6 反向斷言：fenced code 與 HTML comment 內的範例 CLAIM 不是活性區塊，" \
    "不得切斷正文或製造假重複" ],
  [ "doc_claim_unclosed_fence", 1, "R6 Markdown 圍欄未關閉",
    "🔴 R6 fail-closed：合法 CLAIM 後出現未關閉圍欄時不得把後續索引全部靜默遮掉；" \
    "必須在圍欄起始行阻擋" ],
  [ "doc_claim_unclosed_comment", 1, "R6 HTML comment 未關閉",
    "🔴 R6 fail-closed：合法 CLAIM 後出現未關閉 HTML comment 時不得把後續索引全部靜默遮掉；" \
    "必須在 comment 起始行阻擋" ],
  [ "doc_claim_code_span_comment_ok", 0, "OK：文檔引用保真檢查通過",
    "🔴 R6 反向斷言：合法 recheck code span 內的 `<!--` 是字面命令內容，" \
    "不得誤開 HTML comment 或把合法 count 擋掉" ],
  [ "doc_claim_code_span_comment_scope", 1, "R6 計數宣稱 CLAIM-002",
    "🔴 R6：正文 code span 內的 `<!--` 不得誤開 comment；" \
    "其後缺 recheck 的 CLAIM-002 必須保持活性並轉紅" ],
  [ "doc_claim_comment_close_span", 1, "R6 重複 CLAIM-001",
    "🔴 R6：comment 已開啟後，行內任何 `-->` 都依 HTML block end condition 收尾；" \
    "看似 code span 的 closer 不得被 opener-only 遮罩吃掉" ],
  [ "doc_no_files", 3, "掃到 **0 個檔案**",
    "🔴 canary：掃到 0 個檔必須 exit 3，不是印「通過」。" \
    "IN_SCOPE 寫壞、glob 打錯、或 git ls-files 回空時，這支會報通過而它一個字都沒讀過。" \
    "fixture＝一個只有 `NOTE.txt`、沒有任何 .md 的目錄。" \
    "🔴 碼用 3 不是 2：與 fail-closed 的 2 結構上可分辨（check-limits-keys.rb 第 3 輪的教訓）" ],
  [ "doc_clean", 0, "OK：文檔引用保真檢查通過",
    "🔴 總反向斷言：乾淨 fixture 必須通過。缺這條，一個永遠 fail 的檢查器會讓上面每一條都「通過」" ]
].freeze

# 🔴 canary：本測試自己也會「沒有失敗」與「沒有檢查」長得一模一樣。
#    把 CASES 清空，這支會印「OK（0 條）」並 exit 0。
#    數字只准往上調；要調低必須在 PR 描述說明刪了哪一條、為什麼不再需要。
MIN_CASES = 30
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

  output = `ruby "#{CHECKER}" "#{path}" --all --fixture-mode 2>&1`
  status = $?.exitstatus

  if status != want_status
    failures << "#{dir}：期望 exit #{want_status}，實得 #{status}（#{why}）\n      完整輸出：\n#{indent.call(output)}"
    next
  end
  next if output.include?(want_output)

  failures << "#{dir}：exit code 對，但輸出不含 `#{want_output}`（#{why}）\n      完整輸出：\n#{indent.call(output)}"
end

# ---- git 情境測試：R4「只掃新增行」的範圍語義（PR #42 第 4 輪 🔴：零覆蓋／零 canary）----
#
# 🔴 上面的 fixture 目錄**結構上測不到**這條路徑：CASES 一律帶 `--all`
#    （fixture 不是 git 樹，算不出 diff）⇒ `-U0` hunk 行號集合那段代碼
#    在既有 doc_* fixture 裡一次都沒執行過——改壞它，上面照樣全綠。
#    照 test-exec-bits-rules.sh 的辦法：現場 `git init` 一個臨時倉庫，
#    做出「歷史層有髒數字、新增行才受檢」的真實形態（就是本倉庫 worklog 的日常）。
require "tmpdir"
require "fileutils"
require "open3"

GIT_SCENARIOS = 3
SUPPLY_SCENARIOS = 2
git_run = lambda do |work, *cmd|
  out, st = Open3.capture2e({ "LC_ALL" => "C" }, "git", "-C", work,
                            "-c", "user.email=t@example.com", "-c", "user.name=t", *cmd)
  raise "git 情境建置失敗：git #{cmd.join(' ')}\n#{out}" unless st.success?
  out
end

Dir.mktmpdir("doc-claims-git-") do |work|
  doc_dir = File.join(work, "docs/worklog")
  FileUtils.mkdir_p(doc_dir)
  doc = File.join(doc_dir, "2026-08-15-case.md")
  # 歷史層的髒數字：命中 R4 的「共 N 支」，且鄰近沒有複驗指令也沒有快照字樣。
  hist = "歷史層敘事：初版共 7 支腳本，這行故意沒有附上覆核的方式。\n"
  File.write(doc, hist)
  git_run.call(work, "init", "-q")
  git_run.call(work, "add", "-A")
  git_run.call(work, "commit", "-qm", "base")
  base = git_run.call(work, "rev-parse", "HEAD").strip

  # 情境 G1（反向斷言）：本次只新增乾淨行 ⇒ 歷史髒數字**不得**被打，exit 0。
  # 🔴 這是「只掃新增行」的 canary：把範圍退化回「掃整份有改動的檔」，這條立刻紅。
  File.write(doc, hist + "本次新增：這行沒有任何量化宣稱。\n")
  git_run.call(work, "add", "-A")
  git_run.call(work, "commit", "-qm", "clean-add")
  out = `ruby "#{CHECKER}" "#{work}" --base #{base} --fixture-mode 2>&1`
  if $?.exitstatus != 0 || !out.include?("OK：文檔引用保真檢查通過")
    failures << "git-G1：歷史層髒數字＋乾淨新增行應 exit 0（只掃新增行），實得 #{$?.exitstatus}\n      完整輸出：\n#{indent.call(out)}"
  end

  # 情境 G2：新增行寫**中文數字**易腐宣稱（「八條 fixture」）⇒ 必須抓到**那一行**，
  # 且**不得**連帶打到第 1 行的歷史髒數字。兩個斷言合起來才等於「範圍語義對」。
  # 🔴 中文數字在 diff 模式下的 canary 也在這：NUM 退化回 \d+，這條立刻紅。
  File.write(doc, hist + "本次新增：這行沒有任何量化宣稱。\n本輪補了八條 fixture，這行同樣沒有附覆核方式。\n")
  git_run.call(work, "add", "-A")
  git_run.call(work, "commit", "-qm", "cjk-add")
  out = `ruby "#{CHECKER}" "#{work}" --base #{base} --fixture-mode 2>&1`
  st = $?.exitstatus
  if st != 1
    failures << "git-G2：新增行的中文數字易腐宣稱應 exit 1，實得 #{st}\n      完整輸出：\n#{indent.call(out)}"
  elsif !out.include?("2026-08-15-case.md:3")
    failures << "git-G2：exit 對但沒指到新增的第 3 行（中文數字沒被抓？）\n      完整輸出：\n#{indent.call(out)}"
  elsif out.include?("2026-08-15-case.md:1")
    failures << "git-G2：連歷史層第 1 行也被打了——「只掃新增行」的範圍語義壞了\n      完整輸出：\n#{indent.call(out)}"
  end

  # W1（workflow 供給斷言；Codex #59 r1）：G3 只測 checker 的旗標**分支**——把 ci.yml 的
  # `--require-base` 拿掉，G3 照綠、淺 clone 靜默跳過洞原樣回歸（check-ci-parity 比的是
  # 腳本路徑、不含參數）。契約在供給端就釘在供給端：直接斷言 ci.yml 的 doc-claims
  # 調用行帶著旗標。
  ci_yml_text = File.read(File.join(ROOT, ".github/workflows/ci.yml"), encoding: "UTF-8") rescue ""
  unless ci_yml_text.match?(/check-doc-claims\.rb .*--require-base/)
    failures << "W1：.github/workflows/ci.yml 的 check-doc-claims 調用行沒帶 --require-base——" \
                "G3 守的退出分支在生產端沒被啟用，R4/R5 淺 clone 靜默跳過洞會無聲回歸"
  end
  if ci_yml_text.include?("--fixture-mode")
    failures << "W2：.github/workflows/ci.yml 不得傳 --fixture-mode——" \
                "fixture 豁免若流入生產，明確 ROOT 又會把 R6 零供給 canary 關掉"
  end

  # 情境 G3（P-8）：`--require-base` 下取不到 base 差異 ⇒ 必須 exit 3，不得警告後照綠。
  # 🔴 這條釘的是 CI 淺 clone 雙重洞（PR #58 期考掘，2026-08-18）：quality job 的
  #    三點 diff 因淺 clone 無 merge-base，腳本印「R4/R5 本次未執行」warning 後 exit 0
  #    ——連續多輪沒有任何人發現。把 ci.yml 的 --require-base 拿掉、或把 exit 3 分支
  #    改回 warning，這條立刻紅。base 用一個必然不存在的 ref 模擬「取不到差異」。
  out = `ruby "#{CHECKER}" "#{work}" --base refs/never-exists-p8-canary --require-base --fixture-mode 2>&1`
  st = $?.exitstatus
  if st != 3
    failures << "git-G3：--require-base＋取不到 base 應 exit 3（檢查根本沒有生效），實得 #{st}\n      完整輸出：\n#{indent.call(out)}"
  elsif !out.include?("檢查根本沒有生效")
    failures << "git-G3：exit 對但輸出未講明「檢查根本沒有生效」——訊息是這個碼的一半價值\n      完整輸出：\n#{indent.call(out)}"
  end
rescue StandardError => e
  failures << "git 情境測試自身失敗（#{e.class}）：#{e.message}"
end

# S1／S2（R6 生產供給 canary）：總掃描不為 0，不代表 R6 有輸入。把 checker 放進一棵只有
# docs/dev 的乾淨樹，分別用無 ROOT 與明確 ROOT 的生產形態執行；缺 92 索引都必須 exit 3。
Dir.mktmpdir("doc-claims-r6-supply-") do |work|
  FileUtils.mkdir_p(File.join(work, "scripts"))
  FileUtils.mkdir_p(File.join(work, "docs/dev"))
  FileUtils.cp(CHECKER, File.join(work, "scripts/check-doc-claims.rb"))
  File.write(File.join(work, "docs/dev/README.md"), "# clean\n")
  out, st = Open3.capture2e("ruby", File.join(work, "scripts/check-doc-claims.rb"), "--all")
  if st.exitstatus != 3 || !out.include?("R6 掃到 **0 個")
    failures << "supply-S1：生產樹缺 docs/specs/92-* 應 exit 3 並點名 R6 零供給，" \
                "實得 #{st.exitstatus}\n      完整輸出：\n#{indent.call(out)}"
  end
  out, st = Open3.capture2e("ruby", File.join(work, "scripts/check-doc-claims.rb"), work, "--all")
  if st.exitstatus != 3 || !out.include?("R6 掃到 **0 個")
    failures << "supply-S2：明確 ROOT 的生產樹缺 docs/specs/92-* 仍應 exit 3，" \
                "不得把所有明確 ROOT 當 fixture；實得 #{st.exitstatus}\n      完整輸出：\n#{indent.call(out)}"
  end
rescue StandardError => e
  failures << "R6 supply 情境測試自身失敗（#{e.class}）：#{e.message}"
end

if failures.empty?
  puts "OK：文檔引用保真檢查器的回歸測試通過" \
       "（#{CASES.size} 條 fixture case / #{CASES.map(&:first).uniq.size} 個 fixture ＋ " \
       "#{GIT_SCENARIOS} 條 git 情境＋#{SUPPLY_SCENARIOS} 條供給情境）"
  CASES.each { |dir, st, needle, why| puts "  - #{dir} → exit #{st}，含 `#{needle}`：#{why}" }
  puts "  - git-G1 → exit 0：歷史層髒數字＋乾淨新增行必須放行（「只掃新增行」canary）"
  puts "  - git-G2 → exit 1：新增行的中文數字易腐宣稱要抓到該行、且不連坐歷史行"
  puts "  - git-G3 → exit 3：--require-base 下取不到 base 差異＝檢查沒生效，不得靜默照綠（CI 淺 clone 洞的 canary）"
  puts "  - W1 → ci.yml 的 doc-claims 調用行必帶 --require-base（供給端釘住；G3 只測消費端分支）"
  puts "  - W2 → ci.yml 不得傳 --fixture-mode（fixture 豁免不得流入生產）"
  puts "  - supply-S1 → 生產樹缺 docs/specs/92-* 時 exit 3，不得拿其他受管檔掩蓋 R6 零輸入"
  puts "  - supply-S2 → 明確 ROOT 的生產樹缺 docs/specs/92-* 時同樣 exit 3"
  exit 0
end

warn "::error::文檔引用保真檢查器的回歸測試失敗（#{failures.size}/#{CASES.size}）："
failures.each { |f| warn "  - #{f}" }
warn "  🔴 這代表 scripts/check-doc-claims.rb 的判定邏輯壞了，或 fixture 被改動。"
exit 1
