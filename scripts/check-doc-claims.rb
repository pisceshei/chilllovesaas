#!/usr/bin/env ruby
# frozen_string_literal: true

# 文檔引用保真檢查——把「指出處之前先打開來看一眼」從紀律變成機制。
#
# ## 為什麼有這支腳本（2026-08-15，PR #39／#40 的九輪驗收）
#
# 兩個 PR 連續九輪被判「需修改」，15 條 🔴 裡 **12 條是文檔敘述與事實不符**，
# **沒有一條是代碼缺陷**——兩邊的檢查器與回歸測試從第 3 輪起就一直是綠的。
#
# 🔴 更關鍵的是：**修的動作本身就是新缺陷的主要產地**。
#    事後用機械檢查掃同一批（已經過九輪人工審查的）檔案，30 分鐘內又找到三條，
#    **全部出自「修正 commit」**：
#      ①「已合併的檢查器共 7 支」→ 實際 6 支（第 7 支是該 PR 自己新增的），
#        而那個 commit message 逐字寫著「實跑 git ls-files 確認」；
#      ②「15 條全綠」→ 實際 17（寫下當刻是 16）；
#      ③「worklog 有四張突變表」→ 實際 6 張，而這句就是「修掉過期數字」那次修正加的。
#
# ⇒ 這是**紀律型條款的固有失效率**，與 `config/ci.rb` 那條「兩邊要同步」在寫下的隔天
#   就被違反是同一個形態。本專案對這種東西的既定處置是**讓機器擋**。
#
# ## 檢查什麼
#
#   R1｜**路徑保真**：反引號內看起來像倉庫路徑的字串，必須真的存在於樹上。
#   R2｜**跨 PR 錨定豁免**：R1 命中但鄰近有 `PR #NN`／`尚未合併`／`尚未進 main`／
#       `本輪沒做` 這類錨定 ⇒ 放行（引用未合併分支的檔是合法的，只要講清楚）。
#   R3｜**行號保真**：`路徑:行號` 形式，該檔行數必須 ≥ 行號。
#   R4｜**易腐數字要附複驗指令**：`N 支`／`N 條 case`／`N 個 fixture`／`N 張` 這類
#       **可由代碼算出**的數字，鄰近必須有複驗指令（反引號內含 grep／git／ruby／python／wc／ls），
#       否則就是一顆定時炸彈。
#   R5｜**全稱句要附查法或改成列舉**（🟡 **警告，不擋**）。
#   R6｜**每份宣稱索引須有活性標頭、每個活性 CLAIM 都須有 `type: count`、CLAIM ID 跨索引全域唯一、
#       圍欄／HTML comment 須收尾；
#       `type`／`recheck` 鍵大小寫與冒號前空白不敏感，但 type 值只允許小寫 `count`，
#       `type*` 畸形鍵拒絕；每個 count 區塊只能有一筆計數與一筆「以受支援工具開頭」的複驗命令**
#       （🔴 **阻擋**）。
#
# ## 🔴 R4／R5 只掃「本次改動的」worklog／handoff，這是刻意的
#
# 2026-08-15 使用者裁定的文檔分層：
#   **歷史層**（worklog／handoff 的敘事段）＝寫下當刻的認知，**不回頭改**；
#   **終態層**（worklog 的 Changes 表、handoff §①、`docs/dev/`）＝必須等於 HEAD 事實。
# ⇒ 對既有歷史散文套 R4／R5 會與那條裁定直接衝突（而且會一次噴出上百條）。
#   R4／R5 因此**只對相對 base 有改動的 worklog／handoff 生效**——
#   新寫的散文要守規矩，既有的歷史紀錄不動。這不是妥協，是分層本身的直接後果。
#   ⚠️ R1／R3 **是 tree-wide 的**：路徑與行號是客觀事實，歷史紀錄寫錯了一樣會誤導人，
#     而它們的修法是「加更正註記」，不是改原文——不衝突。
#
# 用法：ruby scripts/check-doc-claims.rb [ROOT] [--base <git-ref>] [--require-base] [--fixture-mode]
#   ROOT 省略＝本倉庫根目錄；明確 ROOT 仍是生產形態。只有「明確 ROOT＋`--fixture-mode`」
#   才允許隔離 fixture 不含 `docs/specs/92-*`，形態比照其他 checker 的 fixture runner。
#   --base 省略＝origin/main。
#   --require-base（P-8 引入）＝base 取不到差異時**升為 exit 3**，不再只警告——
#     給 CI 用：淺 clone 曾使 R4／R5 連續多輪靜默跳過而 quality 綠（PR #58 期考掘出的
#     雙重洞，2026-08-18），warning 形態被證實無人看見。本機日常不加，維持警告即可。
#
# 退出碼（照 `scripts/check-limits-keys.rb` 已立的三分碼表）：
#   0＝通過（可能有 🟡 警告）
#   1＝**檢查跑了，發現違規**
#   2＝**檢查跑不了**（讀檔／解析失敗；或 `--fixture-mode` 沒搭配明確 ROOT）
#   3＝**檢查根本沒有生效**（掃了 0 個檔、非 fixture 模式的 R6 索引為 0；
#      或 --require-base 下取不到 base 差異）
#
# 相關：AGENTS.md §工作記錄與交接文件的寫法、CLAUDE.md §工作方式、
#      docs/dev/m0-review-convergence.md。

require "set"

argv = ARGV.dup
base_ref = "origin/main"
# `--all`：把**所有** worklog／handoff 納入 R4／R5（預設只掃相對 base 有改動的那幾份）。
# 給 fixture 回歸測試與「一次全面稽核」用。
# 🔴 日常 CI **不加**這個旗標：對既有歷史散文全面開火，會與「歷史層不回頭改」的裁定衝突，
#    而且一次噴出的量會讓規則被當噪音關掉（見檔頭分層說明）。
scan_all = !!argv.delete("--all")
# `--fixture-mode`：只供帶明確 ROOT 的隔離 fixture 使用；允許該 fixture 不含生產
# `docs/specs/92-*`。一般的明確 ROOT 仍須通過 R6 零供給 canary，不能因呼叫形式而靜默豁免。
fixture_mode = !!argv.delete("--fixture-mode")
# `--require-base`：R4／R5 的範圍差異算不出來時，從「警告後照跑 R1／R3」升為 exit 3。
# 🔴 為什麼是旗標不是無條件（P-8）：fixture 目錄不是 git 樹、本機也可能沒有 origin/main，
#    無條件 exit 3 會把全部 fixture CASE 與離線使用打死；CI 則必須有這道 canary——
#    「未執行」printf 過 GitHub Actions log 沒有任何人看到，是實測過的失效形態。
require_base = !!argv.delete("--require-base")
if (i = argv.index("--base"))
  base_ref = argv[i + 1].to_s
  argv.delete_at(i)
  argv.delete_at(i)
end
explicit_root = !argv.empty?
ROOT = argv[0] ? File.expand_path(argv[0]) : File.expand_path("..", __dir__)
if fixture_mode && !explicit_root
  warn "::error::`--fixture-mode` 必須搭配明確 ROOT；不得用它豁免生產樹的 R6 供給 canary。"
  exit 2
end

# 反引號內、看起來像倉庫路徑的東西。開頭限定在真實存在的頂層目錄，
# 避免把 `application/json`、`text/html` 這種 MIME 當成路徑。
TOP_DIRS = %w[docs scripts spec config bin app test db lib poc .github].freeze
PATH_IN_BACKTICKS = /`([^`\n]+)`/
PATH_SHAPE = %r{\A(#{TOP_DIRS.map { |d| Regexp.escape(d) }.join('|')})/[^\s]+\z}

# `路徑:行號` 或 `路徑:行號-行號`
LINE_REF = /\A(.+?):(\d+)(?:-(\d+))?\z/

# 🔴 **裸檔名也要查**（2026-08-15：拿歷史 commit 當 fixture 實測時發現 R1 漏掉了 #39 那條）。
#    當時的原文是「`check-limits-keys.rb`、`check-money-boundary.rb`、
#    **`check-exec-bits.sh`、`check-workflow-syntax.rb`** 都有回歸測試」——
#    四個都寫成**不帶目錄前綴**的裸檔名，而後兩支當時在未合併的 PR、根本不在樹上。
#    只認帶目錄前綴的形式的話，這一整類（本專案最常見的引用寫法）完全掃不到。
#    ⇒ 凡是 `check-`／`test-`／`lint-` 開頭、副檔名 .rb/.py/.sh 的裸檔名，
#      一律當成對 `scripts/` 的斷言。前綴刻意窄，避免把散文裡的一般檔名誤判。
BARE_SCRIPT = /\A(?:check|test|lint)-[A-Za-z0-9_.-]+\.(?:rb|py|sh)\z/

# R2：鄰近有這些字樣 ⇒ 該行的 R1／R3 命中一律放行。
# 🔴 逐項列舉、不得口頭擴充；加詞要在 PR 描述說明。
ANCHORS = [
  /PR\s*#\d+/,
  # 「未合併」與「尚未合併」都要認——初版只寫了後者，結果本檔自己的註釋
  # （「後兩支當時在**未合併**的 PR」）被自己判成違規。實測抓到的第一個誤報。
  /未合併/, /尚未進\s*main/, /未進\s*main/, /還沒進\s*main/,
  /本輪沒做/, /本輪未做/, /尚未建立/, /尚未存在/,
  /之後要加/, /日後/, /正解是/,
  /已刪除/, /已移除/, /曾經/,
  # 🔴 **反向主張**也算錨定：文中在論證「**不該**建立某個檔」時必然要指名它。
  #    實測誤報：`docs/worklog/…對等性檢查器補上反向證明.md` 論證
  #    「往 quality job 加一支 `check-schema-drift.rb` 會得到一個結構上不可能失敗的步驟」——
  #    那是**警告別人不要建**，被判成「引用不存在的檔」是反的。
  /不該[補加建寫]/, /不要[補加建]/, /不得[補加]|不得新增/, /假想/, /比沒有.{0,6}更糟/
].freeze

# R4：可由代碼算出、且本專案實際踩過的易腐數字。
# 🔴 刻意窄——只列真的燒過的形態，不做泛用數字偵測（那會誤報整個 docs/）。
# 🔴 數字字元類含**中文數字**（2026-08-16，PR #42 第 3 輪驗收指出）：
#    本倉庫文檔的計數幾乎一律寫中文（「八條」「四條」「三處」），
#    而初版五條 pattern 全以 `\d+` 開頭 ⇒ R4 對本專案最常見的寫法**結構上全盲**——
#    「八條」在兩輪人工審查與本閘門首跑下全數存活，就是這個洞的直接後果。
# ⚠️ **單獨的「一」刻意排除**（實測誤報：「一支 240+ 行的閉環 shell」「有一條路徑」——
#    量詞單數是描述不是計數，不會腐）。「十一」「一百」這類複合數詞仍然涵蓋。
NUM = /(?:[〇零二三四五六七八九十百][〇零一二三四五六七八九十百]*|一[〇零一二三四五六七八九十百]+|\d+)/
VOLATILE_NUM = [
  /#{NUM}\s*支(?:檢查器|腳本)?(?=[，。、）)\s]|\z)/,
  /#{NUM}\s*條\s*(?:case|fixture)/i,
  # （原本這裡還有一支「NUM 條 fixture」的半支——PR #48 首輪指出它與上一支重疊、
  #    正是下面自我警告說的「重複 pattern 遮蔽突變」形態，2026-08-16 收斂掉。
  #    PR #49 首輪補刀：舊半支帶 /i 而上一支沒有 ⇒ 收斂會丟大小寫變體涵蓋，
  #    修法＝把 /i 上移到上一支（case|CASE 因此合併）。）
  /#{NUM}\s*個\s*fixture/i,
  /#{NUM}\s*張\s*(?:突變)?表/,
  /共\s*#{NUM}\s*[支條個張份]/
  # 🔴 不要另加「獨立的中文數字 pattern」——NUM 已涵蓋，重複的 pattern 會讓
  #    「NUM 退化回 \d+」的突變被它接住而測不出來（2026-08-16 突變實測抓到過一次）。
].freeze

# R4 的豁免：鄰近有可複驗的指令，或明示是某時點的快照。
RECHECK_CMD = /`[^`\n]*\b(?:grep|git|ruby|python3?|wc|ls|awk|sed|bundle)\b[^`\n]*`/
# R6 比 R4 的鄰近「像命令」判定更嚴：整個 code span 必須以受支援工具開頭；只在散文中
# 提到工具名不得滿足結構化宣稱的可重跑契約。清單本身已含 `bundle`，因此
# `bundle exec ...` 由同一工具起頭規則涵蓋，不另放語言等價、無法承重的 wrapper pattern。
CLAIM_RECHECK_CMD = /\A`(?:grep|git|ruby|python3?|wc|ls|awk|sed|bundle)\b[^`\n]*`\z/
SNAPSHOT = /快照|實跑輸出|輸出如下|取證/

# R5：全稱句（只警告）。
UNIVERSALS = [ /唯一/, /都各有/, /全部都/, /所有[^\s]{0,6}都/, /從來沒有/, /一律都/ ].freeze
ENUMERATION = /[、，,].*[、，,]|^\s*[-*]\s|\d+\s*組/

# R6：只納管 P-2 新建的結構化宣稱索引，不把整個 specs 歷史集合突然納入。
# 每份索引必須至少有一個活性 `CLAIM-NNN` 標頭，且每個合法活性區塊都要有 `type: count`；
# 所有 `docs/specs/92-*` 索引之間的 CLAIM ID 必須全域唯一。
# Markdown 圍欄與 HTML comment 必須收尾。`type`／`recheck` 鍵大小寫與冒號前空白不敏感；
# type 值只允許小寫 `count`，以 `type` 起頭的畸形鍵 fail-closed。每個 count 區塊只能有一筆
# 計數與一筆語義 `recheck`，後者內容要符合上方 CLAIM_RECHECK_CMD 的整段可執行指令形態。
# 既有 R1–R5 的判定對象與語義因此不變。
CLAIM_INDEX = %r{\Adocs/specs/92-[^/]+\.md\z}
CLAIM_HEADER = /\A {0,3}### CLAIM-(\d{3})\s*\z/
CLAIM_LIKE_HEADER = /\A {0,3}#+\s+CLAIM-/
CLAIM_TYPE = /\A {0,3}-\s+(type[A-Za-z0-9_-]*)\s*:\s*(.*?)\s*\z/i
CLAIM_RECHECK = /\A {0,3}-\s+recheck\s*:\s*(.+)\z/i

violations = []
warnings = []
scanned = []
claim_indexes_scanned = 0

def anchored?(lines, idx)
  lo = [ idx - 2, 0 ].max
  hi = [ idx + 2, lines.size - 1 ].min
  window = lines[lo..hi].join("\n")
  ANCHORS.any? { |a| window.match?(a) }
end

def near?(lines, idx, re)
  lo = [ idx - 2, 0 ].max
  hi = [ idx + 2, lines.size - 1 ].min
  lines[lo..hi].join("\n").match?(re)
end

# 只遮同一行內成對的 code span，保留字元位置與原文供後續 metadata 判定；未成對 backtick
# 仍是字面文字。這個遮罩只拿來找 HTML comment opener，不能拿它取代可見正文。
def mask_inline_code_spans(line)
  masked = line.dup
  cursor = 0

  while (opening = /`+/.match(line, cursor))
    run = opening[0]
    closing = /(?<!`)#{Regexp.escape(run)}(?!`)/.match(line, opening.end(0))
    unless closing
      cursor = opening.end(0)
      next
    end

    length = closing.end(0) - opening.begin(0)
    masked[opening.begin(0), length] = " " * length
    cursor = closing.end(0)
  end

  masked
end

# R6 讀的是 Markdown 的**活性正文**，不是原始字串集合。圍欄與 HTML comment 可合法放
# 範例／歷史註記；若把裡面的假 `### CLAIM-*` 當區塊，會切斷真區塊或製造假重複。
# block fence 先於 inline/comment 掃描；正文同一行的 code span 只在尋找 comment opener 時遮罩。
# comment 已開啟後，任何 `-->` 子字串都依 HTML block end condition 收尾，不解析 inline code span。
# 回傳活性行、未關閉圍欄與未關閉 HTML comment（若有）；活性行為
# `[原始零基行號, 移除 HTML comment 後的可見文字]`，保留原行號供錯誤定位。
def active_markdown_lines(lines)
  active = []
  fence = nil
  comment = nil

  lines.each_with_index do |raw, idx|
    if fence
      close = /\A {0,3}#{Regexp.escape(fence[:char])}{#{fence[:length]},}[ \t]*\z/
      fence = nil if raw.match?(close)
      next
    end

    unless comment
      if (fence_opening = raw.match(/\A {0,3}(`{3,}|~{3,})(.*)\z/))
        run = fence_opening[1]
        info = fence_opening[2]
        # CommonMark：backtick fence 的 info string 不得再含 backtick；不合法者仍是正文。
        unless run.start_with?("`") && info.include?("`")
          fence = { char: run[0], length: run.length, line: idx }
          next
        end
      end
    end

    visible = +""
    rest = raw
    loop do
      if comment
        closing = rest.index("-->")
        break unless closing

        rest = rest[(closing + 3)..].to_s
        comment = nil
      else
        opening = mask_inline_code_spans(rest).index("<!--")
        unless opening
          visible << rest
          break
        end

        visible << rest[0...opening]
        rest = rest[(opening + 4)..].to_s
        comment = { line: idx }
      end
    end

    active << [ idx, visible ]
  end

  [ active, fence, comment ]
end

# ---- 收集要掃的檔 ----------------------------------------------------------

def git(root, *args)
  out = IO.popen({ "LC_ALL" => "C" }, [ "git", "-C", root, "-c", "core.quotePath=false", *args ], err: File::NULL, &:read)
  $?.success? ? out : nil
end

# 🔴 git 回**空**也要退回 glob，不能只判「git 失敗」。
#    fixture 目錄位於本倉庫內 ⇒ `git -C <fixture> ls-files` 會**成功**，
#    但因為 fixture 檔尚未進索引而回空字串 ⇒ 只判 nil 的話 targets 是空的、
#    canary 喊「檢查沒有生效」，而真正的原因只是「這些檔還沒 git add」。
#    2026-08-15 建 fixture 時實際踩到，七份 fixture 全部 exit 3。
def listing(root, pattern, glob)
  files = git(root, "ls-files", "-z", "--", pattern).to_s.split("\0").reject(&:empty?)
  return files unless files.empty?
  Dir.glob(glob, base: root).reject { |p| p.start_with?("node_modules/", "vendor/") }
end

all_md = listing(ROOT, "*.md", "**/*.md")
script_headers = listing(ROOT, "scripts/", "scripts/*")

# 🔴 **只掃「對本倉庫現況做斷言」的檔**，這是規則能不能存活的關鍵。
#    初版掃全樹，對 main 一次噴 552 條、收窄成「帶副檔名」後仍有 183 條，**幾乎全是誤報**，
#    而一個噪音比訊號多的檢查器會在一週內被關掉。三類誤報的來源很清楚：
#      ①`docs/research/**` 大量描述**Shopify 本尊與第三方 gem 的檔案結構**
#        （主題的 settings_schema.json 是本尊的結構、Liquid gem 的 standardfilters.rb 是它自己的源碼）
#        ——那些路徑本來就不該存在於我方樹上；
#      ②`docs/design/**` 是**計畫**，寫的是還沒做的東西（例如某支尚未建立的 crosscheck 腳本）；
#      ③`docs/specs/**` 同理，是規格不是現況。
#    ⇒ 納管範圍＝**對我方倉庫此刻狀態做斷言**的地方：
#      worklog／handoff（工作紀錄）、docs/dev（實作篇章）、AGENTS.md／CLAUDE.md（規約）、
#      scripts/（腳本檔頭）。九輪驗收裡的路徑錯誤**全部落在這個範圍內**。
#      docs/plans/（2026-08-18 PR #58 擴入）：方案檔對倉庫現況與待建檔做大量斷言——
#      未納管時本 PR 最大的新檔（方案正本，行數以 `wc -l` 為準）零機械覆蓋
#      （#58 第 2 輪 🟡5），納入當輪即抓到兩條無錨引用。
#      ⚠️ 實得覆蓋僅 R1／R3：R4／R5 的範圍判斷（下方兩處 start_with?）仍只認
#      worklog／handoff，plans 不在內——刻意維持，勿讀成全規則納管。
#    ⚠️ 代價寫在這裡：research／design／specs 的路徑錯誤本檢查**普遍不管**；
#      唯一窄例外是 P-2 新建的 `docs/specs/92-*` 宣稱索引，供 R6 檢查結構化計數。
#      這不等於 specs 全面納管；全面納管仍須先解決「如何區分本尊路徑與我方路徑」。
IN_SCOPE = [
  %r{\Adocs/worklog/}, %r{\Adocs/handoff/}, %r{\Adocs/dev/}, %r{\Adocs/plans/},
  CLAIM_INDEX,
  %r{\AAGENTS\.md\z}, %r{\ACLAUDE\.md\z}, %r{\AHANDOFF\.md\z},
  %r{\Ascripts/}
].freeze

targets = (all_md + script_headers).uniq.sort.select { |p| IN_SCOPE.any? { |re| p.match?(re) } }

# R4／R5 的範圍：相對 base 有改動的 worklog／handoff。拿不到 base 就不跑，並**明說**。
changed_docs = nil
scope_note = nil
if scan_all
  changed_docs = :all
elsif (diff = git(ROOT, "diff", "--name-only", "-z", "#{base_ref}...HEAD"))
  # 🔴 R4／R5 只掃**本次新增的行**，不是「有改動的整份檔」（2026-08-16，PR #42 第 3 輪）。
  #    掃整份檔的話，歷史層敘事段（「八條 case 是照⋯設計的」）也會被打——
  #    而歷史層依裁定**不得回頭改**，等於逼人違規或讓閘門永遠紅著。
  #    「新寫的散文守規矩、歷史不動」的機械對應就是：只看 diff 的 `+` 行。
  #    行號集合由 `-U0` 的 hunk 頭（`@@ -a,b +c,d @@`）算出。
  changed_docs = {}
  diff.split("\0").reject(&:empty?)
      .select { |p| p.start_with?("docs/worklog/", "docs/handoff/") }
      .each do |rel|
    hunks = git(ROOT, "diff", "-U0", "#{base_ref}...HEAD", "--", rel)
    # 🔴 執行期 canary（PR #42 第 6 輪 🟡）：name-only diff 剛成功、逐檔 diff 才失敗
    #    是環境問題不是「該檔沒有新增行」——原本 `.to_s` 把失敗吞成空集合，
    #    R4/R5 對該檔靜默跳過。fail-closed：exit 2（檢查跑不了，不是通過也不是違規）。
    if hunks.nil?
      warn "::error::git diff -U0 對 #{rel} 失敗（name-only 卻成功）⇒ **檢查跑不了**（exit 2）。"
      exit 2
    end
    added = Set.new
    hunks.scan(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/) do |start, count|
      st = start.to_i
      (count.nil? ? 1 : count.to_i).times { |k| added << (st + k) }
    end
    changed_docs[rel] = added
  end
else
  # 🔴 --require-base（P-8）：這條路在 CI 上曾連續多輪被靜默走到（淺 clone ⇒ 三點
  #    diff 無 merge-base）而 quality 照綠——「檢查沒生效」與「檢查通過」在退出碼上
  #    長得一樣，正是 exit 3 這個碼存在的理由。帶旗標時就升成它。
  if require_base
    warn "::error::--require-base：取不到 base `#{base_ref}` 的差異 ⇒ R4／R5 無法執行" \
         "＝**檢查根本沒有生效**（exit 3）。CI 請確認 checkout／fetch 拿得到 merge-base" \
         "（淺 clone 是已實測過的成因）；本機請改用存在的 --base ref 或去掉 --require-base。"
    exit 3
  end
  scope_note = "⚠️ 取不到 base `#{base_ref}` 的差異 ⇒ **R4／R5 本次未執行**（R1／R3 仍為全樹）。" \
               "在 CI 上請確認有 fetch 到 base；本機請用 --base 指定一個存在的 ref。"
end

# ---- 逐檔掃 ----------------------------------------------------------------

# R6 的 ID namespace 是整個 `docs/specs/92-*`，不能逐檔重置；否則分片索引可各自發布同一 ID。
seen_claim_ids = {}
targets.each do |rel|
  path = File.join(ROOT, rel)
  next unless File.file?(path)

  begin
    text = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  rescue SystemCallError, IOError => e
    warn "::error::#{rel} 讀不到（#{e.class}）⇒ **檢查跑不了**（exit 2，不是 1）。#{e.message}"
    exit 2
  end

  scanned << rel
  lines = text.lines.map(&:chomp)

  # --- R6（宣稱索引，tree-wide）---
  if rel.match?(CLAIM_INDEX)
    claim_indexes_scanned += 1
    active_lines, unclosed_fence, unclosed_comment = active_markdown_lines(lines)
    if unclosed_fence
      violations << "#{rel}:#{unclosed_fence[:line] + 1} R6 Markdown 圍欄未關閉——" \
                    "後續索引不可被靜默排除；請補上同字元且長度不少於起始圍欄的收尾行。"
    end
    if unclosed_comment
      violations << "#{rel}:#{unclosed_comment[:line] + 1} R6 HTML comment 未關閉——" \
                    "後續索引不可被靜默排除；請補上 `-->` 收尾。"
    end
    header_positions = active_lines.each_index.select do |pos|
      active_lines[pos][1].match?(CLAIM_LIKE_HEADER)
    end
    if header_positions.empty?
      violations << "#{rel}:1 R6 宣稱索引沒有任何 `### CLAIM-NNN` 區塊——" \
                    "這不是零宣稱，是結構化檢查沒有生效。"
    end
    if header_positions.any?
      active_lines[0...header_positions.first].each do |idx, line|
        match = line.match(CLAIM_TYPE)
        next unless match

        key = match[1]
        value = match[2].strip
        if !key.casecmp?("type")
          violations << "#{rel}:#{idx + 1} R6 畸形 type metadata 鍵 `#{key}`——" \
                        "鍵只允許 `type`（大小寫／冒號前空白不敏感），`type*` 拼字不得靜默略過。"
        elsif value != "count"
          violations << "#{rel}:#{idx + 1} R6 不支援 type metadata `#{value}`——" \
                        "值只允許精確小寫 `count`，拼字錯誤不得靜默脫離複驗契約。"
        else
          violations << "#{rel}:#{idx + 1} R6 計數宣稱出現在第一個 CLAIM 標頭之前——" \
                        "每個 `type: count` 都必須位於自己的 `### CLAIM-NNN` 區塊內。"
        end
      end
    end
    count_claim_blocks = 0
    header_positions.each_with_index do |start_pos, pos|
      finish_pos = pos + 1 < header_positions.size ? header_positions[pos + 1] : active_lines.size
      start, header_line = active_lines[start_pos]
      header = header_line.match(CLAIM_HEADER)
      unless header
        violations << "#{rel}:#{start + 1} R6 宣稱標頭格式錯誤：`#{header_line}`——" \
                      "必須使用三位數 `### CLAIM-NNN`（例如 `### CLAIM-002`）。"
        next
      end

      claim_id = header[1]
      if seen_claim_ids.key?(claim_id)
        first = seen_claim_ids[claim_id]
        violations << "#{rel}:#{start + 1} R6 重複 CLAIM-#{claim_id}——" \
                      "首次出現在 #{first[:path]}:#{first[:line] + 1}；" \
                      "所有 `docs/specs/92-*` 的 CLAIM ID 必須全域唯一。"
      else
        seen_claim_ids[claim_id] = { path: rel, line: start }
      end

      block = active_lines[start_pos...finish_pos]
      type_entries = block.filter_map do |idx, line|
        match = line.match(CLAIM_TYPE)
        match && [ idx, match[1], match[2].strip ]
      end
      type_entries.reject { |_idx, key, _value| key.casecmp?("type") }.each do |idx, key, _value|
        violations << "#{rel}:#{idx + 1} R6 畸形 type metadata 鍵 `#{key}`——" \
                      "鍵只允許 `type`（大小寫／冒號前空白不敏感），`type*` 拼字不得靜默略過。"
      end
      type_entries.select { |_idx, key, _value| key.casecmp?("type") }
                  .reject { |_idx, _key, value| value == "count" }.each do |idx, _key, value|
        violations << "#{rel}:#{idx + 1} R6 不支援 type metadata `#{value}`——" \
                      "值只允許精確小寫 `count`，拼字錯誤不得靜默脫離複驗契約。"
      end

      if type_entries.empty?
        violations << "#{rel}:#{start + 1} R6 CLAIM-#{claim_id} 缺 `type: count` metadata——" \
                      "每個活性 CLAIM 都必須明示受 R6 計數複驗契約納管；欄位缺字不得靜默略過。"
        next
      end

      count_entries = type_entries.select do |_idx, key, value|
        key.casecmp?("type") && value == "count"
      end
      next if count_entries.empty?

      count_claim_blocks += 1
      count_entries.drop(1).each do |idx, _key, _value|
        violations << "#{rel}:#{idx + 1} R6 同一 CLAIM-#{claim_id} 含多個 `type: count`——" \
                      "每筆計數必須放在自己的 `### CLAIM-NNN` 區塊並附複驗指令。"
      end

      recheck_entries = block.filter_map do |idx, line|
        match = line.match(CLAIM_RECHECK)
        match && [ idx, match[1] ]
      end
      recheck_entries.drop(1).each do |idx, _value|
        violations << "#{rel}:#{idx + 1} R6 同一 CLAIM-#{claim_id} 含多個 `recheck:`——" \
                      "每個計數區塊只能發布一個無歧義的複驗命令。"
      end
      recheck = recheck_entries.first&.last
      next if recheck&.match?(CLAIM_RECHECK_CMD)

      violations << "#{rel}:#{start + 1} R6 計數宣稱 CLAIM-#{claim_id} 必須附複驗指令：" \
                      "整段 code span 必須以 `ruby` 等 CLAIM_RECHECK_CMD 支援工具開頭，不能只是提到工具名。"
    end
    if count_claim_blocks.zero?
      violations << "#{rel}:1 R6 宣稱索引沒有任何活性 `type: count` CLAIM 區塊——" \
                    "這不是零宣稱，是計數契約的輸入被清空。"
    end
  end

  added_line_set =
    if changed_docs == :all
      rel.start_with?("docs/worklog/", "docs/handoff/") ? :all : nil
    elsif changed_docs
      changed_docs[rel]
    end

  lines.each_with_index do |line, idx|
    no = idx + 1

    # --- R1 / R3 ---
    line.scan(PATH_IN_BACKTICKS).flatten.each do |raw|
      cand = raw.strip
      lineno = nil
      if (m = cand.match(LINE_REF))
        cand = m[1]
        lineno = m[2].to_i
      end
      # 裸腳本名 ⇒ 補上 scripts/ 前綴再查（見 BARE_SCRIPT 的註釋）
      cand = "scripts/#{cand}" if cand.match?(BARE_SCRIPT)

      next unless cand.match?(PATH_SHAPE)
      # 路徑裡有 glob／萬用字元的不查（`scripts/check-*.rb`）
      next if cand.match?(/[*?\[\]{}]/)
      # 模板佔位符不查（`docs/worklog/YYYY-MM-DD-<功能>.md` 是規約本身的範例格式）
      next if cand.match?(/[<>]/) || cand.match?(/YYYY|MM-DD|\{N\}|\bN\b/)
      # 編號區間（`docs/specs/11-19`、`docs/research/00–10`，含全形連字號）不查
      next if cand.match?(/\d+\s*[-–—]\s*\d+\z/)
      # 🔴 **只查帶副檔名的具體路徑**。本倉庫大量使用「編號簡稱」——
      #    `docs/research/22` 指的是 `22-admin-button-inventory.md`、
      #    `docs/specs/65` 指 `65-money-unit-boundary.md`、`docs/design/20/23` 是兩份的合稱。
      #    那是既有且刻意的慣例（見 CLAUDE.md §文件地圖），**不是錯誤**。
      #    初版沒排除它，對 main 全樹一次噴出 552 條全是誤報 ⇒ 規則會被當噪音關掉。
      #    ⚠️ 代價：簡稱指到不存在的編號**抓不到**。可接受——九輪驗收裡的路徑錯誤
      #      （四支當時尚未進 main 的 check-* 腳本與一份 worklog）**全部都是帶副檔名的具體路徑**。
      next unless File.extname(cand).match?(/\A\.[A-Za-z0-9]{1,5}\z/)
      next if anchored?(lines, idx)

      target = File.join(ROOT, cand)
      unless File.exist?(target)
        violations << "#{rel}:#{no} 引用的路徑 `#{cand}` **不存在於樹上**。" \
                      "若它在別的分支／PR，請照 AGENTS.md §工作記錄 第 4 條加錨定" \
                      "（`（PR #NN，尚未進 main）`）；若是打錯就修正。"
        next
      end

      next unless lineno && File.file?(target)
      actual = File.foreach(target).count
      next unless actual < lineno
      violations << "#{rel}:#{no} 引用 `#{cand}:#{lineno}`，但該檔只有 #{actual} 行 ⇒ **行號已失效**。" \
                    "行號是最容易腐爛的引用；寫之前請跑 `grep -n`，或改成指章節名。"
    end

    next if added_line_set.nil?
    next unless added_line_set == :all || added_line_set.include?(no)

    # --- R4 ---
    if VOLATILE_NUM.any? { |re| line.match?(re) } &&
       !near?(lines, idx, RECHECK_CMD) && !near?(lines, idx, SNAPSHOT)
      violations << "#{rel}:#{no} 寫了**可由代碼算出的數字**卻沒有複驗方式：#{line.strip[0, 90]}" \
                    "⇒ 三種合法寫法擇一：①不寫數字（「整份 CASES 全綠」）" \
                    "②鄰近附複驗指令（`` `grep -c ...` ``）③貼實跑輸出並標「快照」。" \
                    "（理由：2026-08-15 兩次「修掉過期數字」的修正**本身都寫進了新的錯數字**。）"
    end

    # --- R5（只警告，不擋）---
    next unless UNIVERSALS.any? { |re| line.match?(re) }
    next if near?(lines, idx, RECHECK_CMD) || line.match?(ENUMERATION)
    warnings << "#{rel}:#{no} 全稱句沒有列舉也沒有查法：#{line.strip[0, 90]}" \
                "⇒ 改成列舉（「三組有：A／B／C；三支沒有：D／E／F」）或附複驗指令。"
  end
end

# ---- canary ----------------------------------------------------------------
# 🔴 「沒有違規」與「沒有檢查」在輸出上長得一模一樣。
#    glob 寫壞、或 git ls-files 在某個環境下回空，這支會印「OK：通過」並 exit 0，
#    而它一個字都沒讀過。碼用 3，與上面 fail-closed 的 2 **結構上可分辨**
#    （這是 check-limits-keys.rb 第 3 輪的教訓：同碼會讓 fail-closed 的突變被遮蔽）。
if scanned.empty?
  warn "::error::掃到 **0 個檔案**——這不是通過，是檢查沒有生效。" \
       "請確認 ROOT（#{ROOT}）正確、且 `git ls-files` 在此環境可用。"
  exit 3
end

# 🔴 R6 的局部零掃描 canary：整棵樹有其他受管檔時，總 canary 不會響；若生產樹的
#    `docs/specs/92-*` 全被移除，舊版仍印「R6 ... tree-wide」並 exit 0。只有明確標記
#    `--fixture-mode` 的隔離 fixture 可合法沒有生產索引；一般調用即使傳 ROOT 仍須至少掃到一份。
if !fixture_mode && claim_indexes_scanned.zero?
  warn "::error::R6 掃到 **0 個 `docs/specs/92-*` 宣稱索引**——" \
       "這不是通過，是 R6 在生產樹沒有輸入（exit 3）。"
  exit 3
end

warnings.each { |w| warn "::warning::#{w}" }

if violations.empty?
  puts "OK：文檔引用保真檢查通過"
  puts "  - 掃描檔案：#{scanned.size} 個（*.md ＋ scripts/*）"
  puts "  - R1 路徑保真／R3 行號保真：全樹"
  puts "  - R6 計數宣稱：docs/specs/92-* 結構化索引（tree-wide；#{claim_indexes_scanned} 份）"
  if changed_docs == :all
    puts "  - R4 易腐數字／R5 全稱句：**全部** worklog／handoff（`--all`）"
  elsif changed_docs
    puts "  - R4 易腐數字／R5 全稱句：只掃相對 `#{base_ref}` 有改動的 worklog／handoff" \
         "（本次 #{changed_docs.size} 份、共 #{changed_docs.values.sum(&:size)} 個新增行——"          "**只掃新增的行**）——歷史紀錄不回頭改，見 AGENTS.md §文檔分層"
  else
    puts "  - #{scope_note}"
  end
  puts "  - 🟡 警告 #{warnings.size} 條（不擋）"
  exit 0
end

warn "::error::文檔引用保真檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
warn "  🔴 這些是**機器可判定**的引用錯誤。修好之前不要靠人眼重讀——"
warn "     2026-08-15 的實測是：九輪人工審查後，機械掃描仍在同一批檔案裡找到三條新的。"
exit 1
