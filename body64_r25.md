## 對應方案

- 階段一'執行方案 §1 收口與 §2 序 0b：P-8 evidence-source／合併後文件債收斂。
- 累積處置 PR #62 exact-head Codex 意見，以及 PR #64 後續 Claude／Codex 驗收；每輪輸入、查證、failure-first、20.3／20.4 與射程保存在同一 head 的 worklog。

## 累積變更（current exact head 逐檔全集）

以下 30 個路徑由 `git -c core.quotepath=false diff --name-only bbf5f3b73971b35d23c253a68bb2554d14eff1bc..1acb87de50f13f66d09b6323fb0e71ddeb71bf82` 重取：

- `AGENTS.md`
- `docs/DECISIONS.md`
- `CLAUDE.md`
- `docs/plans/2026-08-18-總方案.md`
- `docs/plans/2026-08-20-階段一執行方案.md`
- `docs/worklog/README.md`
- `docs/dev/external-facts.md`
- `docs/dev/m0-review-convergence.md`
- `docs/specs/91-pit-register.md`
- `docs/worklog/2026-08-20-P8證據來源與合併後文件債收斂.md`
- `docs/worklog/2026-08-20-PR62首輪驗收修復.md`
- `docs/worklog/2026-08-20-handoff工作單位節奏與本地保存更正.md`
- `docs/worklog/2026-08-21-PR64第七輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第三輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第九輪Codex驗收修復.md`
- `docs/worklog/2026-08-21-PR64第二輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第五輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第八輪Claude晚到驗收修復.md`
- `docs/worklog/2026-08-21-PR64第八輪Codex驗收修復.md`
- `docs/worklog/2026-08-21-PR64第六輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第十一輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第十三輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第十二輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第十五輪Claude驗收修復.md`
- `docs/worklog/2026-08-22-PR64第十六輪雙驗收修復.md`
- `docs/worklog/2026-08-22-PR64第十七輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第十四輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64第十輪Claude驗收修復.md`
- `docs/worklog/2026-08-21-PR64第四輪雙驗收修復.md`
- `docs/worklog/2026-08-21-PR64首輪Claude驗收修復.md`

- 累積 diff：30 files changed, 3687 insertions(+), 2 deletions(-)，綁 immutable range `bbf5f3b73971b35d23c253a68bb2554d14eff1bc..1acb87de50f13f66d09b6323fb0e71ddeb71bf82`。
- 第十五輪相對上一已發布 head `874eade9e58df099323013c9693e3f19e21debe4`：4 files／109 insertions／11 deletions。
- 第十七輪相對上一已發布 head `53d346bb86c7c4049440ffc3aab578f20f8ff317`：4 files／228 insertions／7 deletions。

## 當前 exact head 與實跑證據

- head：`1acb87de50f13f66d09b6323fb0e71ddeb71bf82`；push 後複驗 `gh pr view 64 --json headRefOid` 同值（實得相同）。
- 🔴 **以下全部取自本輪 commit 之後、`git status --porcelain` 為空時那一次實跑**
  （不是任何舊 head 的快照）：

```
bin/ci                     原生 26 步：19 綠／7 紅
  7 紅全為 Windows 環境缺口（bin/* shebang → Errno::ENOEXEC；本機無 python3），逐步展開：
  ruby bin/rails db:prepare / ruby bin/rubocop / ruby bin/bundler-audit /
  ruby bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error /
  PYTHONIOENCODING=utf-8 python scripts/{lint-prototype,test-lint-rules,check-baseline-raise}.py
                                                    ⇒ 七者皆 exit 0

check-doc-claims.rb（commit 後、`git status --porcelain` 為空）
  預設／--base bbf5f3b7／--base dafa360／--base 6f1848c（後三者 --require-base）
                                   四元組逐 base：rc=0、**警告=0**（警告非 0 時必須逐條列出）
  🔴 發布單位是 `(base, rc, 警告數, 警告逐條)` 四元組——`rc` 恆為 0（R5 只警告不擋），
     只看 `rc` 等於沒看。上一版描述在前一 head 上發布「警告皆 0」而實得 1，
     成因＝我看了 `rc` 沒看警告數（Claude `5382918375` 🔴-1，同根因第 3 次）。
  🔴 **base 集合每輪重取，不累積**：上一版列了五個（含三個舊 head），而同輪留言寫「三個 base」——
     同 head 同輪兩份發布互斥（Claude `5382825871` 🔴-4，與描述自留更正註記的第 20 輪 🔴-1② 原樣復發）。
     ⇒ 兩處統一為「預設 ＋ 不變的 base ＋ 上一已發布 head」這**三個**，舊 head 不再累積列入。
  🔴 上一輪只對預設 base 看過警告數、對其他 base 只看 rc，而 R5 不影響退出碼
     ⇒ 兩條全稱句的警告被漏掉（Codex inline `3836905821` 點名）。本輪逐 base 都數警告。

其餘閘門（逐支親眼看退出碼）
  lint-prototype.py                ERROR 0 / WARN 136（＝既有基線）
  workflow-syntax / tenant-isolation / money-boundary / limits-keys /
  reversal-naming / ci-parity / baseline-raise / exec-bits          rc 皆 0
  五支規則回歸                                                       rc 皆 0
  git diff --check                 無輸出

A.1 完整性（91 既有的 canonical 全量 md5，兩式相等）
  bb4ec2d51d84d026dce74e14c588af7c  *-
  bb4ec2d51d84d026dce74e14c588af7c  *-

本輪自帶的斷言（🔴 只登記**違規數**；射程一律＝**本輪 commit 動到的檔**，既有違規另計於 `91` §3）
  表列完整性（原始碼裡每一行像表列的都必須渲染成 <tr>；欄數＝header；末欄非空）  違規 0
    canary：把一列搬到段落中間 ⇒ 該式必須轉紅（已雙向實跑）
  HTML 註釋（渲染判準：該隱藏的不可見、該可見的可見）                           違規 0
  Changes 覆蓋（非 worklog 類逐檔；worklog 類逐檔判「自己的 Changes 或本檔條列段」） 違規 0
  禁區 pathspec（.github scripts script config bin spec package.json
                 Rakefile Gemfile .rubocop.yml）                              輸出為空
    canary：同一式套 abafcc2^..abafcc2 ⇒ 輸出 .github/workflows/claude-review.yml
  🔴 上一版此清單仍列「末欄 sentinel（⋯十格）」——那支**本輪已整個換掉**
     （它對「整列被擠出表格」結構性盲目），而新立的「表列完整性」在描述裡零命中；
     「十格」還是命中數，違反同段自己寫的「只登記違規數」。

D39 判準輸入矩陣（🔴 不寫格數——該矩陣已擴充過三次；改用**對帳規則**）
  對帳規則：`docs/DECISIONS.md` D39 矩陣的**每一個一般輸入列**，
            在 worklog 的實跑段必須有**同名的一行輸出**；每一個 **canary 列**
            必須在 canary 段有對應輸出（「只刪其中一個」展開為兩個子形態）。
  本 head 實得：一般輸入列與輸出行**逐列同名對映、無缺無多**；
                canary 列 2 個 ↔ canary 輸出 3 行（兩個都刪／只刪 ISO／只刪日曆）。
  🔴 上一版描述寫「正常兩格 rc 0 …共八格 rc 2」＝2＋8＝10，而矩陣實為 3 格 rc 0
     （含閏年真日期 ⇒ APPLIES）＋8＝11 ⇒ **描述與矩陣、worklog 三者互不相符**。
     根因與 🔴-2 同：手寫分類計數。⇒ 改成對帳規則，不寫任何格數。
```

<!-- 🔴 2026-08-23 更正（來源＝PR #64 Claude issue comment `5381492053` 🔴-1，同根因第 4 次）：
     上一版本區塊的 `Changes 覆蓋` 那格逐字寫「🔴 首跑抓到 1 筆漏記：
     docs/plans/2026-08-20-階段一執行方案.md（該列原本只寫「兩份執行方案」，grep 不到檔名）
     ⇒ 已改為逐檔列名，重跑 9／9 命中。」
     🔴 **「已改為逐檔列名」在 `f8d72fa` 上沒有發生**——那筆修正當時還在工作樹裡沒進 commit，
     該式在該 head 實得 **8／9**。我在同一輪的處置留言裡寫了「該修正尚未進樹」，
     卻在描述裡用完成式寫成已完成 ⇒ 同一個 head 上兩份發布互斥，而被拿去當合併輸入的
     是假的那一份。
     🔴 根因與前三次相同：**量了工作樹，然後把它當成關於已推 head 的事實發布**。
     這一次的加重情節是 failure-first 語氣——「抓到了也修好了」讀起來比一般宣稱更可信，
     讀者不會再查。
     🔴 固定處理的哪一步被漏掉：我把「跑檢查」與「檢查跑在哪棵樹上」當成同一件事。
     ⇒ 本輪起，凡是要寫進發布物的檢查，一律用 `git show <HEAD>:<path>` 取內容，
     不讀工作樹；本區塊四項斷言都是這樣跑的。
     可重跑反向複驗：本區塊出現的每一個 SHA 必須等於
     `gh pr view 64 --json headRefOid --jq .headRefOid`，或是明文標註輪次的舊 head。 -->

<!-- 🔴 2026-08-23 更正（來源＝PR #64 Claude issue comment `5381302078` 🔴-1，同根因第 3 次）：
     上一版本段逐字寫「以下全部取自本輪 commit 之後、`git status --porcelain` 為空時那一次實跑
     （不是任何舊 head 的快照）」，而三項可證不成立：
     ① A.1 canonical md5 欄寫 `09e617f6…`，那是 `c9090d4` 那一棵樹的值；本 head 實跑是
        `bb4ec2d5…`（與 commit `3f535aa` 的 message 一致）。
     ② base 數：描述寫「四種 base（預設／`0fbe520`／`53d346b`／`660fc89`）」，
        同輪留言 `5381177960` 卻寫「三種 base（預設／`bbf5f3b7`／`df506749`）」——同 head 同輪兩份發布互斥。
     ③「Changes 覆蓋」綁 `53d346b`＋W16，是第十六輪的檢查；本輪實動 9 檔卻零覆蓋檢查。
     🔴 **根因不是抄錯，是「量了 X 然後把它當成關於 Y 的事實發布」**：這些數字都真的跑過，
     只是跑在別的 head 上，而發布時被掛在本 head 名下。
     🔴 固定處理的哪一步被漏掉：push 後的固定步驟裡「改綁描述」只改了 head 欄與 range，
     **沒有連帶重跑證據區塊**——於是 head 欄是新的、證據是舊的，看起來反而更可信。
     ⇒ 本輪把整塊換成本 head、乾淨工作區的實跑輸出，並在 Changes 覆蓋那格改成逐檔反查
     （該式首跑就抓到一筆真的漏記，見上）。
     可重跑反向複驗：本區塊出現的每一個 SHA 都必須等於 `gh pr view 64 --json headRefOid --jq .headRefOid`
     或是明文標註輪次的舊 head；出現第三種即為未改綁。 -->

- 🔴 **本 head 已改 `AGENTS.md` 與 `CLAUDE.md` ⇒ 命中鐵律 18.3**：必須由**使用者人工合併**，
  D31／D32 的代行授權**不適用**。
  <!-- 🔴 2026-08-22 更正（來源＝PR #64 Claude issue comment `5381104120` 🔴-3）：
       本行原寫「本輪只改 `docs/` 路徑，不命中鐵律 18.3」。**在本 head 上為假**——
       本輪為落地 D39 改了 `AGENTS.md` 與 `CLAUDE.md`（鐵律本文），依 18.3 必須人工合併。
       🔴 這條錯的方向是**放寬**：照原文讀會授權代行 squash merge，繞過人工把關。
       複驗：`git -c core.quotepath=false diff --name-only origin/main..HEAD \
              | grep -E '^(CLAUDE|AGENTS)\.md$|^\.github/|^scripts/|^config/'`
       非空即命中 18.3。 -->
- Node v24.19.0 超出專案 Node 22 engine；本機前端綠不構成 Node 24 支援聲明，
  GitHub CI 仍以倉庫指定 Node 22 為準。

<!-- 🔴 2026-08-22 改綁（來源＝PR #64 Claude issue comment `5379763381` 🔴-3 與 🟡-1）：
     本段先前**整段停在第十五輪**——標題寫著「當前 exact head 與實跑證據」，內容卻是
     `GATES_ALL_GREEN=29`、`--base 874eade9e5…`、`於受驗樹 82e2fa8 實測`、第五輪 validator。
     上一輪只改了 head 欄與 range，**證據段沒有動**，而 worklog 卻宣稱「實跑證據段同批改綁」。
     🔴 把舊 head 的閘門結果掛在新 head 名下正是 19.2 禁止的外推。
     逐字保留的原段落：
       ## 當前 exact head 與實跑證據
       - head：`660fc89de68a7cf5bdce0246b3243704ef777ef7`；push 後會以 `git ls-remote` 複驗遠端 branch 與 `pr64-last-push` tag。
       - 最後 repo edit 後 Windows production-equivalent runner 從 gate 1 完整跑至 gate 29，輸出 `GATES_ALL_GREEN=29`。Rails `284 examples, 0 failures`、Frontend 5/5、RuboCop 162 files／0 offenses、Brakeman 0 warnings／0 errors。
       - post-commit `ruby scripts/check-doc-claims.rb --base 874eade9e58df099323013c9693e3f19e21debe4 --require-base` 掃描 302 檔、2 份變更 worklog、71 個新增行、warning 0。
       - GitHub `/markdown` 實跑 4 個變更 Markdown：於受驗樹 `82e2fa8` 實測（計數式＝`<tr\b`／`<th\b`／`<td\b`；`<th` 前綴會一併命中 `<thead>`，不得使用）：W14 `table=2,tr=13,th=5,td=29`；W15 `2,13,6,33`；91 `3,25,11,72`；external-facts `blockquote=29,table=0`。每個表格群組的未跳脫直線寬度一致。
       - 第五輪現行 validator 在乾淨 HEAD 輸出 normal paths＝16；duplicate、drop、missing-section、off-date、zero-scan、delete、rename 七個反向分支各自命中預期拒絕。
       - `git diff --check` 通過、工作樹乾淨；本輪只改 4 個 `docs/` 路徑，不命中鐵律 18.3。（🔴 該句屬更早一輪的逐字保留；**現行 head 已命中 18.3**，見上方更正註）
       - Node v24.19.0 超出專案 Node 22 engine；本機前端綠不構成 Node 24 支援聲明，GitHub CI 仍以倉庫指定 Node 22 為準。
     ⇒ 本輪把整段換成 commit 後、乾淨工作區的實跑輸出。 -->

## 第十五輪處置

- Claude comment `5363892357`／wrapper `5363893749` 審 `874eade…`，含 🔴1、🟡2、⚪3；Codex issue comment `5363805191` 對同 head 為零意見。
- 上一輪 comment `5363665327` 的三條 ⚪ 原本在 91 §3 為零。本輪把 ⚪1／2 各立條目、⚪3 併入既有 destructive guard 射程條目；本輪三條 ⚪ 也各自落籍。§3 對兩個 comment id 的輸出各為 3。
- W14 的 20.3 第三欄恢復固定名稱「反向複驗輸出」，七列換成實跑 stdout／集合計數，並在相鄰位置留下 dated correction；沒有再做無沿革的歷史覆寫。
- A10 補 GitHub REST 完整逐字 “Lists a maximum of 250 commits for a pull request. To receive a complete commit list for pull requests with more than 250 commits, use the List commits endpoint.”
- B9 補 GitHub CLI 逐字：“if the value starts with `@`, the rest of the value is interpreted as a filename to read the value from. Pass `-` to read from standard input.” 與 “To pass pre-constructed JSON or payloads in other formats, a request body may be read from file specified by `--input`. Use `-` to read from standard input.”
- 修法前先以 `git log -p` 追內部沿革，外部語義再獨立重取官方頁；Claude 修法方向只作線索，沒有直接照抄。

## Failure-first 與反向證明

- failure-first：`5363665327` 在 91 §3 為 0；修後只截 §3 輸出 `old_white=3,new_white=3`。
- W14 修正前只有「反向複驗」且七列為宣稱；修後 good header＝1、bad header＝0，七列可對回 CLI／API／render stdout。
- repository List commits 以 `sha=26fc683e40bb8ad6466d082c6887876345f84646&per_page=1` 實跑，第一筆 SHA 相同；PR #64 commits 端點實取 17 筆。
- `-F text=@-` 與 `--input -` 各回預期 `<h1>`；錯誤的 raw `-f text=@path` 仍回字面 `@path`，證明只看 HTTP exit 0 會假綠。

## push 前鐵律 15 攝取（本 head `5bfb1da6bd0716550c8f5c54e5c1036c75dab886`；2026-08-23 重取）

- 15.1：相對上一已發布 head `dafa3604f71c92afa030dd898832cc64e908d84e` ⇒ **2 files**（兩個 commit：第 25 輪主修＋R5 補遺）；
  `git diff --shortstat` 逐字 `2 files changed, 89 insertions(+), 4 deletions(-)`；
  荒謬檢查：同 range `git log --oneline | wc -l` ⇒ **2**（非 0，合理）；
  `git diff --check` 無輸出、`git status --porcelain` 為空。
- 15.2 三端點 `--paginate` 的 **id 上界**（逐項由指令當場取得）：
  issue comments `5382686198`／inline `3836968552`／reviews `5001012882`。
- 本輪輸入：Claude `5382825871`；**Codex 對本 head 發了 finding review** `5001114795`（`21:43:22Z`），
  inline `3837086325` 已逐條處置（見同輪留言）。
  🔴 **上一版此欄逐字寫「Codex 對本 head 以 👍 reaction 表示零意見」，該句三重錯誤**
  （Claude `5382825871` 🔴-2）：①`CLAUDE.md` 逐字禁止把 reaction 當 completion；
  ②該 reaction 在 `21:08:12Z`，本 head 的上一個 head 才是 `21:02:53Z`——它早於本 head 28 分 49 秒；
  ③Codex 對本 head 實際發的是 finding review。
  ⇒ **Codex 狀態一律只看受控載體**（review 的 `.commit_id`／issue comment 的受控前綴），reaction 不看；
     完全沒有受控載體時記「**未取得**」，不是「零意見」。
- 既有 threads 只有新 exact head 雙零後才可按 approved GraphQL thread ID 收口，舊 head 不外推。

## 外部語義證據與邊界

- GitHub REST 官方 <https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28>（取證 2026-08-21）：逐字為 “Lists a maximum of 250 commits for a pull request. To receive a complete commit list for pull requests with more than 250 commits, use the List commits endpoint.”
- GitHub REST 官方 <https://docs.github.com/en/rest/commits/commits#list-commits>（取證 2026-08-21）：`sha` 逐字為 “SHA or branch to start listing commits from.”
- GitHub CLI 官方 <https://cli.github.com/manual/gh_api>（取證 2026-08-21）：逐字明列 `-F` 的 file／stdin field 與 `--input` 的 file／stdin whole-body 入口。
- 內部事實由 `git log -p`、exact-head 三端點、GraphQL threads 與可重跑 canary 取得；推論與未取得邊界已明標，沒有未標示假設。

## 合併限制

🔴 **#64 現行 head 已改鐵律本文（`AGENTS.md`／`CLAUDE.md`）⇒ 命中鐵律 18.3：必須由使用者人工合併。**
本 PR **永不適用**代行合併——18.3 的判準是「改了什麼」，不是「條件湊齊了沒有」，
所以下列條件全部滿足也**不**產生代行授權：

- 本 exact head 的 CI 全綠、Codex 零未清、Claude 判詞通過、review threads resolved、mergeable。
- 這些是**人工合併的前提**，不是代行的觸發條件。

複驗 18.3 是否命中：

```bash
git -c core.quotepath=false diff --name-only origin/main..HEAD \
  | grep -E '^(CLAUDE|AGENTS)\.md$|^\.github/|^scripts/|^config/'
```

非空即命中。本 head 實跑非空（`AGENTS.md`、`CLAUDE.md`）。

<!-- 🔴 2026-08-23 更正（來源＝PR #64 Claude issue comment `5381302078` 🔴-6；
     上一輪 🔴-3 只清了一半）：
     本節原文在同一段裡並存兩個互斥結論，逐字為
     「⋯必須使用者人工合併；下列雙零條件仍須滿足，但滿足後**不得代行**。只有**本 exact head**
      的 CI、Codex、Claude 雙零、review threads resolved、mergeable 與 evaluator `1111`
      同時成立，互動式 Codex 才依 D31／D32 代行 squash merge；舊 head 結果不得外推。」
     🔴 前半句說不得代行、後半句說條件湊齊就代行——**描述是合併決策的直接輸入**，
     照後半句讀會繞過 18.3 的人工把關。
     另有兩處獨立理由使後半句無效：①`CLAUDE.md:298` 的 D38 過渡期覆寫規定 0e／0f／0g 前
     所有 PR 一律人工合併；②`docs/DECISIONS.md:663-665` 已撤銷舊 `1111` evaluator
     作為代行證據的資格。
     🔴 上一輪只在段首加了「不得代行」，沒有刪掉後半句——**加一句否定不會蓋掉一句肯定**，
     兩句並存時讀者取哪一句是隨機的。⇒ 本輪把後半句整個刪掉，並把理由寫成「18.3 看的是
     改了什麼，不是條件湊齊了沒有」，讓它不可能被讀成條件式。 -->










