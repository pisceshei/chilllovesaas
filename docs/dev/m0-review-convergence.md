# M0 — 驗收閉環的收斂機制

> **現行入口是文末「2026-08-21 Convergence Protocol v2」**。下方早期四／五機制編號保留作
> 沿革，不再代表目前流程；`MAX_FIX_ROUNDS` 不恢復，新的 C1 evaluator 與 workflow 接線仍待
> 各自的 18.3 工作包落地。

> 對應規格：`AGENTS.md` §工作記錄與交接文件的寫法、`CLAUDE.md` §工作方式。
> 建立日期：2026-08-15（使用者裁定）。

## 概述

把「自動驗收永遠找得到新問題、因此永遠不通過」這個結構性問題修掉。
🔴 **歷史機制清單**（下列編號 1–5 保留以免既有交叉引用失效；現行流程見文末 v2）：

1. `scripts/check-doc-claims.rb` — 文檔引用保真的**確定性檢查器**
2. `AGENTS.md` 新增文檔**分層規範**（歷史層／終態層／契約層）
3. `claude-review.yml` — 文檔類判定權交給腳本、同一項目不重提、`CLAUDE.md` 進驗收依據
4. ~~`MAX_FIX_ROUNDS` 由「換一句留言」升級成**真閘門**~~ **已廢止（2026-08-19 使用者裁定「取消熔断机制，所有的必须循环到双清为止。不限次数」）**——機制已隨 **PR #59 於 2026-08-19 合併移除**。當時留下的缺口於 2026-08-21 改由 v2 的原子攝取、根因批次與模式切換承接，不恢復輪數熔斷。
5. **鐵律 15 提交前復核**（交付完整性層）：現行已改為雙方完成→凍結 ledger→targeted 內迴圈→凍結 tree 全套→commit→逐項核對→最終全量重拉→push。

## 為什麼要做（問題的形狀）

兩個 PR（`m1/ci-parity`、`m1/limits-fixture-coverage`）連續九輪被判「需修改」。
逐輪拆解 15 條 🔴：

| 類別 | 條數 |
|---|---|
| 代碼缺陷 | 3（全在前兩輪） |
| **文檔敘述與事實不符** | **12** |

而兩邊的檢查器與回歸測試**從第 3 輪起一直是綠的**。

三層根因，每一層都有實證：

### ① 機制層：閉環在結構上沒有終點

- 驗收方每輪跑 `gh pr diff`＝**全量累計 diff**，且 prompt 裡沒有任何跨輪狀態
  （`上一輪`／`已修`／`增量` 的命中數皆為 0）。
- 判定規則是二元的：**任一條 🔴 即需修改**，沒有嚴重度門檻。
  <!-- 2026-08-16 起判定規則已再改制（PR #51）：任一 🔴 或**未清 🟡** 皆需修改，
       另設 ⚪（範圍外觀察，不擋）。本節其餘描述的是 2026-08-15 事故當時的機制，屬歷史敘述。 -->
- 🔴 的產生集合**不封閉**：「修復／重構 PR 未更新受影響的既有文檔」沒有邊界，
  任何一句與終態不符的散文都落在裡面。
- `MAX_FIX_ROUNDS` 當時不是閘門，超過門檻只換一句提示文字就 `exit 0`。

🔴 **決定性證據**：第 5 輪那條 🔴（handoff §① 陳舊）是該 PR **第一個 commit** 帶進來的，
而第 2／3／4 輪都聲稱「docs 全讀」卻沒有標它。
⇒ **缺陷不是被修出來的，是每輪抽樣抽到不同切片。**

### ② 歷史：產物層曾由逐輪記錄放大挑剔面（2026-08-15）

> 本節描述事故當時已被 D38 廢止的舊解讀，不是 HEAD 現行 worklog 契約。現值是一個可獨立合併
> PR／原子工作包維護一份 tracked worklog；no-tree disposition 不改 worklog、不產生新 head。

累積新增行數逐輪：**313 → 508 → 686 → 829 → 1000**，其中 **66% 是 docs**；
單一份 worklog 從 98 行長到 487 行，刪除率只有 6%。
實際交付的腳本與 fixture 只有 337 行——**散文是代碼的兩倍，而且是被逐字審的那一半**。

當時的 `CLAUDE.md` 把「一個部分」解讀到**一次修復**且每個部分要寫 worklog，於是每一輪驗收
回應都被當成新「部分」，規則強制產生新的散文；D38 已撤銷這個解讀。

### ③ 行為層：修正 commit 自己在生產新缺陷

九輪之後用機械檢查掃同一批檔案，30 分鐘內找到 3 條全新的同型缺陷，**全部出自修正 commit**：

| 寫的 | 實際 |
|---|---|
| 「已合併的檢查器共 7 支」（commit message 還寫著「實跑確認」） | 6 支 |
| 「15 條全綠」 | 17（寫下當刻是 16） |
| 「worklog 有四張突變表」——**這句就是「修掉過期數字」那次加的** | 6 張 |

### 🔴 還有一個制度矛盾

- `AGENTS.md` 是驗收依據第 1 條，但它對 `worklog`／`handoff` 命中 **0** 次
- 定義它們的 `CLAUDE.md` **不在**驗收依據清單裡
- 而既有裁定說 worklog 是歷史紀錄、**刻意不改**

⇒ 12 條 🔴 打的是「驗收方沒被授權讀的文件所要求產生的產物」，且與另一條裁定衝突。
**沒有寫下來的標準，就沒有「達標」這個狀態。**

## 架構

### `scripts/check-doc-claims.rb`

| 規則 | 檢查 | 範圍 |
|---|---|---|
| R1 | 反引號內的具體路徑（**含裸腳本名**）必須存在於樹上 | 全樹（納管目錄內） |
| R2 | R1／R3 命中但鄰近 ±2 行有錨定詞 ⇒ 放行 | — |
| R3 | `路徑:行號` 的行號不得超出該檔行數 | 全樹（納管目錄內） |
| R4 | 易腐數字必須附複驗指令或標為快照 | 只掃**相對 base 有改動**的 worklog／handoff |
| R5 | 全稱句要列舉或附查法 | 同上，**🟡 警告不擋** |
| canary | 掃到 0 個檔 ⇒ 不是通過，是沒生效 | — |

退出碼照 `check-limits-keys.rb` 已立的三分表：`0` 通過／`1` 有違規／`2` 跑不了／`3` 沒生效。
🔴 canary 用 3 而非 2，是為了與 fail-closed 的 2 **結構上可分辨**。

**納管範圍**＝對本倉庫**現況**做斷言的地方：`docs/worklog/`、`docs/handoff/`、`docs/dev/`、
`docs/plans/`（2026-08-18 PR #58 擴入——方案檔同性質；注意僅 R1／R3，R4／R5 範圍見上表不變）、
`AGENTS.md`、`CLAUDE.md`、`HANDOFF.md`、`scripts/`。

**R4／R5 只掃改動過的檔**，這是分層規範的直接後果：歷史層不回頭改，
所以不對既有散文開火；新寫的散文要守規矩。

已知限制（2026-08-18 補）：⚠️ R4／R5 在 **CI 生產調用**疑似結構上未執行（淺 clone
取不到 merge-base ⇒ 腳本走「未執行」warning 分支 exit 0；#58 第 7 輪判詞 ⚪1 的
機械跡象＋本地 post-commit 實測互證）——修法屬 P-8（fetch 深度＋skip 升 canary 碼）；
✅ **該限制已於 P-8 落地修復**（`ci.yml` 加 `--unshallow`＋完整 base fetch，checker 加 `--require-base`：取不到 merge-base 即 exit 3，隨 PR #59 合併進 main）⇒ 本表對 R4 的「生效中」描述**現已對 CI 成立**。🔴 **仍然成立的限制**：R4／R5 用 `git diff <base>` 只掃**已提交**的新增行 ⇒ **commit 之後必須再跑一次**，commit 前跑掃不到剛寫的散文。
**另一條**：R1 的 `TOP_DIRS`／`PATH_SHAPE` 只認**真實頂層目錄**開頭的
路徑與裸腳本名——去掉 `docs/` 前綴的短式（`specs/110-…`、`research/105-…`）對 R1
**隱形**；引用待建檔時用全式 `docs/…` 才有機械保真（#58 第 6 輪判詞 ⚪2）。

### 為什麼範圍這麼窄（這是規則能不能存活的關鍵）

初版掃全樹，對 `main` 一次噴 **552 條**；收窄成「帶副檔名」後仍有 **183 條**，幾乎全是誤報：

- `docs/research/**` 大量描述**Shopify 本尊與第三方 gem 的檔案結構**——那些路徑本來就不該在我方樹上
- `docs/design/**`／`docs/specs/**` 是**計畫與規格**，寫的是還沒做的東西
- 本倉庫慣用**編號簡稱**（`docs/research/22` 指 `22-*.md`），那是既有且刻意的慣例

⇒ 一個噪音比訊號多的檢查器會在一週內被關掉。收窄後對 `main` 是 **0 條**。

## 關鍵取捨（誠實聲明）

1. 🔴 **把文檔類判定權交給腳本＝真的鬆綁。**
   腳本抓不到的**歷史層**語義錯誤（例如「假逐字引用」——引用的檔存在、行號也對，但那句話
   不在裡面）會被降級成 ⚪ 而放行（2026-08-16 改制前是 🟡；終態層語義錯誤不降級、仍是 🔴，
   由驗收方人工把關——PR #51 的 Codex review 把這條界線收窄補上）。這不是純贏。
   **緩解**：R5 的全稱句警告仍會印出來讓人看見；Codex 是第二個獨立驗收方。
   **不採用的替代**：把文檔類整體降級為 🟡 而不加腳本——那等於直接放棄這條文化，
   而本倉庫有實例證明文檔錯誤會造成錯誤行為（`config/ci.rb` 一句錯註釋會誘導出
   一個「結構上不可能失敗」的 CI 步驟）。**換執法者，不是換標準。**

2. **R1 不管編號簡稱**。簡稱指到不存在的編號抓不到。
   可接受：九輪裡的路徑錯誤**全部**是帶副檔名的具體路徑。

3. **R1／R3 不管 research／design／specs**。要納管必須先解決
   「如何區分本尊路徑與我方路徑」，本輪沒解。

4. **「同一項目不重提」是在賭模型配合**（讀上一則留言）。
   賭輸的後果是**放行**而非誤擋；`AUTO_MERGE` 維持 `false`，所以 workflow 本身不會合併。
   🔴 **2026-08-20 D31／D32 終態補充**：18.3 PR 與未取得具名代行授權的 PR 仍保留使用者
   人工安全網；但具名授權的互動式 Codex 可對非 18.3 PR 在四條件齊時代行 CLI 合併。
   因此 `AUTO_MERGE=false` 不得再被解讀成所有 PR 都必須由使用者逐次操作。

5. **`MAX_FIX_ROUNDS` 變閘門＝承認自動驗收有判不了的區間**，把「什麼時候夠好」交回人手上。
   這正是它該做的事——一個永遠不會說「夠了」的驗收方，與沒有驗收方一樣沒用。
   <!-- 🔴 2026-08-19 使用者裁定推翻本條：「取消熔断机制，所有的必须循环到双清为止。
        不限次数」。推翻的**不是這條的分析**（它對閘門代價的描述仍然成立），而是**這個
        代價值不值得付**——使用者的判斷是：收斂要靠真的修完，不靠把問題退回人手。
        ⇒ 「什麼時候夠好」的答案自此固定為**雙清**（兩個驗收方都零未清意見），
        沒有其他答案，也沒有輪數上限。缺口與替代責任見文末「廢止後的收斂責任」段。 -->

## 測試

`scripts/test-doc-claims-rules.rb`——fixture 在 `spec/fixtures/ci_violations/doc_*`。

| fixture | 期望 | 守什麼 |
|---|---|---|
| `doc_missing_path` | 1 | R1 帶前綴的路徑 |
| `doc_bare_script` | 1 | 🔴 R1 **裸檔名**分支（本專案最常見的寫法；開發時實測漏掉過） |
| `doc_anchored_ok` | 0 | 反向：有錨定必須放行 |
| `doc_stale_lineno` | 1 | R3 行號失效 |
| `doc_volatile_num` | 1 | R4 易腐數字 |
| `doc_volatile_ok` | 0 | 反向：附複驗指令必須放行 |
| `doc_volatile_cjk` | 1 | 🔴 R4 **中文數字**分支（「八條」這類——初版 \d+ pattern 對最常見寫法全盲） |
| `doc_plans_scope` | 1 | 🔴 掃描範圍 canary：`docs/plans/` 已納 IN_SCOPE（2026-08-18 PR #58）——拿掉範圍時本 CASE 期望 1 實得 3（零檔 canary）＝回歸測試轉紅 |
| `doc_no_files` | **3** | canary |
| `doc_clean` | 0 | 總反向斷言 |
（表列以 `ls spec/fixtures/ci_violations/ | grep ^doc_` 為準——列數勿手寫。）

**開發時的決定性驗證**：把 `check-doc-claims.rb` 拿去跑四個**歷史 commit**，
確認它抓得到當時驗收方標的**同一行**——`worklog:57`、`handoff:44`、`:13`、`:14` 全部命中。

**突變測試全抓**（逐項）：R1 停用／裸檔名分支拿掉／R3 停用／R4 停用／錨定變全放行／canary 拿掉／docs/plans 範圍拿掉（2026-08-18 補，test 轉紅）。

## 已知限制

1. R4 的 pattern 是中文散文比對，**列舉式**（只認實際燒過的五種形態），會漏。
2. R5 只警告不擋，全稱句的**真假**仍然沒有機器判準。
3. `MIN_CASES` 是手動維護的下限，加 case 時要記得往上調。
4. 「同一項目不重提」依賴驗收方正確讀取上一則留言，**沒有機制驗證它有沒有照做**。
5. `check-doc-claims.rb` 本身沒有納管 `docs/specs/`／`docs/research/`——那兩處的引用錯誤仍靠人。

## 歷史編號第五機制：鐵律 15 提交前復核（2026-08-17，PR #53）

> 🔴 編號沿用建立時的「第五」；本節只保存 2026-08-17 的歷史編號，不再計算或描述現行機制；
> 現行流程以文末 Convergence Protocol v2 為準。

2026-08-17 原流程＝修復 → 閘門 → commit → **逐項核對已提交差異**（回應輪對**上輪 push 的 HEAD** 兩點 diff、SHA 與輕量基準 ref 由 push 時自記**並推送遠端**（合併後刪）；對 PR base 的累計 diff 僅作初始盤點——同 CLAUDE 15.1）（宣稱已修復者有
hunk；清法②（僅 🟡）與 ⚪ 核對登記存在、③ 核對證據存在）→ **重拉兩種留言**（bot 判詞＋
Codex inline；首推豁免）→ push。與其餘機制的關係（原文寫「前四機制」，現行為三項——原第 4 項已廢止）：它們管「判定怎麼下」，
本機制管「回應輪的交付完整性」。2026-08-21 起此段只作沿革，現行固定順序見文末 v2。
當時已知限制：它是**紀律條款**，機制化（腳本比對
判詞清單 vs diff hunk）為待辦。
<!-- 2026-08-17 第 5 輪自註釋移出；第 7 輪自歷史清單中段移至文末獨立段 -->

## 變更記錄

- 2026-08-17（PR #53）：新增第五機制「鐵律 15 提交前復核」段＋概述同步五項；核對命令基準修訂（origin/main→回應輪對上輪已審 HEAD）。
- 2026-08-17（PR #53 續）：基準再修——回應輪＝對上輪 push 的 HEAD 取**兩點** diff（三點在 rebase 後退回 merge-base；SHA 由作者 push 時自記，不依賴判詞）；初始盤點與修復證據分離；push 末步增記 HEAD。
- 2026-08-17（PR #53 續 2）：清法②限定僅 🟡（🔴 放行唯有改鐵律本文）；push 末步增建輕量基準 ref（僅 SHA 字串在重寫歷史／換 clone 後不保 object 可達）。
- 2026-08-17（PR #53 續 3）：基準 ref 增**推送遠端**（本地 tag 換 clone 後同樣不可達；`pull/{N}/head` 只指現任 head 取不回上一輪）；合併後刪遠端 tag。
- 2026-08-20（PR #61）：依使用者裁定完成 F1–F12 全型態稽核；把有跨 PR 復發證據且已有固定
  處理與反向複驗的交付根因升格為鐵律 20。未授權新增 checker，本輪只立紀律與證據帳。
- 2026-08-20（PR #61）：依 D35／鐵律 21 把 handoff 觸發點從整次工作結束收緊為每個具名
  步驟與決策節點；命令留在所屬步驟內，避免遞迴建檔，worklog 與終態回寫照舊並存。
- 2026-08-20（D36）：使用者指出上一項把「沿用以前形式」錯誤擴張成每個小步驟都 commit
  handoff。現行規則恢復為每個工作單位／驗收修復輪結束一份，並改在 Git 倉庫外本地保存；
  上一項保留為錯誤制度沿革，不再執行。
- 2026-08-21（D37／D38）：先廢止以 commit 刷新驗收的循環，再由 D38 把同一 PR 的 worklog／
  handoff 收斂為各一份；D36 的本地載體保留，驗收修復輪另拆檔與一對多 worklog 改為歷史。

## 歷史：工作單位 handoff 契約（2026-08-20，D36）

> 本節保存 D36 當時形態；2026-08-21 起檔案頻率已由 D38／鐵律 21 覆寫，現行契約讀文末
> 「產物頻率的終態」。D36 的「只存 Git 倉庫外本地工作區」仍有效。

既有制度分別在「可獨立驗收單位完成」產生 worklog、在「工作結束前」產生一份 handoff。
D35 把後者錯誤收緊成每個具名步驟與決策節點都要另檔、另 commit，造成 handoff 本身反覆改
PR head。D36 依使用者澄清恢復原有時間邊界，並把 handoff 移出 Git 倉庫。

D36 當時固定處理如下：

- 一個工作包／PR 初始交付、一次驗收修復輪、正式阻塞／rollback 或整次工作結束，各寫一份
  handoff；研究、實作、測試、commit、push、等待、驗收與遠端結果收在同一份，不逐小步拆檔。
- §①綁工作單位輸入與證據並列重要動作、產物、驗證及配對 worklog；§②記決策與被推翻假設；
  §③非空記未解／阻塞／風險；§④給精確下一步入口、前置、紅線與不得外推範圍。
- handoff 只存 Git 倉庫外本地工作區；不新增／修改 `docs/handoff/`，不做 handoff-only commit，
  不 push，也不留 remote handoff。遠端終態取得後補進同一份本地 handoff，避免改 head。
- worklog 三段、倉庫終態回寫與鐵律 19 不被取代；附錄 A 只追蹤實際入庫的 worklog 與既有
  歷史 handoff，不為本地 handoff 新增路徑。

## 歷史：廢止後的收斂責任（2026-08-19）

> 本節記錄 2026-08-19 到 D37 前的判斷；2026-08-21 已由文末 v2 取代「只靠確定性 checker」
> 的單一路徑，保留本節是為了說明沿革，不作現行操作指令。

熔斷是本文原本論述的第 4 項機制，也是唯一一個**保證有限步終止**的機制。它被使用者裁定取消後，
「輪數會不會收斂」不再有任何機制保障 ⇒ **收斂責任整個移到第 1 項那類確定性檢查器上**。

這不是勸阻，是把配套寫清楚。本文開頭記的問題形狀是：兩個 PR 連續九輪被判需修改，
而其中 15 條 🔴 有 12 條是文檔敘述類、**不是被修出來的**——是每輪抽樣抽到不同切片。
對這一類，再審一輪不會讓它變少，只有**確定性腳本一次掃全樹**才會。

⇒ 操作準則：**每當同一類意見第二次出現，先問「這一類能不能寫成腳本」**，
🔴 **能寫也不要直接寫**（2026-08-19 使用者裁定「把機制改成紀律」並否決兩個機制化提案後更新）：先把**候選與代價**寫進 `docs/specs/91-pit-register.md` 並取得使用者裁定，**裁定後才實作**（進 `scripts/`＋掛 `config/ci.rb` 兩側）。不能寫的同樣登記，說明為什麼不能。
讓意見數單調下降的是這件事，不是輪數上限。

## 重犯根因收斂稽核（2026-08-20，鐵律 20 的證據帳）

### 稽核邊界與升格門檻

本節回答的是「哪些**處理方法已經定型**，送驗前就該一次做完」，不是宣稱所有既有坑都已修完。
稽核範圍固定為三層：

1. `docs/specs/91-pit-register.md` 的 F1–F12 正典形態表與 §3 暫存；
2. 當前樹可追蹤的 `docs/worklog/`、`docs/handoff/` 及本檔所載沿革；
3. GitHub PR #58、#60、#61 的三個 REST 集合與 review threads。取證日為 2026-08-20；
   每次使用本節判當前 PR 時仍須重拉現值，不得把本次快照外推。

可重跑的取證入口：

```bash
N=61 # 例：本 PR；處理其他 PR 時替換
git -c core.quotepath=false ls-files docs/worklog docs/handoff
git log -p -- CLAUDE.md AGENTS.md docs/dev/m0-review-convergence.md docs/specs/91-pit-register.md
gh pr view "$N" --repo pisceshei/chilllovesaas --json headRefOid
gh api "repos/pisceshei/chilllovesaas/issues/$N/comments" --paginate
gh api "repos/pisceshei/chilllovesaas/pulls/$N/reviews" --paginate
gh api "repos/pisceshei/chilllovesaas/pulls/$N/comments" --paginate
gh api graphql --paginate -F owner=pisceshei -F name=chilllovesaas -F number="$N" -f query='
query($owner:String!, $name:String!, $number:Int!, $endCursor:String) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      reviewThreads(first:100, after:$endCursor) {
        nodes { id isResolved comments(first:1) { nodes { databaseId } } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}'
```

升格鐵律須同時滿足：同一系統性根因有兩個獨立可追事故，或在宣稱修復後復發；處理法已由
實跑、現行規則或反向 fixture 定型；不含尚待產品／費用／架構裁定。未滿足者只進 `91`，
避免把一次性事故硬編成永久負擔。

### F1–F12 全型態判定

| 91 形態 | 是否進鐵律 20 | 判定 | 現行主要防線 |
|---|---|---|---|
| F1 死控件 | 不重複立法 | 屬產品實作缺陷；近期驗收循環沒有形成新的通用交付修法 | `lint-prototype.py`、按鈕表與 E2E |
| F2 假數字 | 不重複立法 | 已有鐵律 7 的同源 rollup 約束；文檔裸計數另歸 F11 | 鐵律 7、資料同源測試 |
| F3 假成功 | 不重複立法 | 要按每個 mutation／outbox／UI 流程做真實效果驗證，沒有一條可取代領域規格的通法 | 鐵律 5、API／E2E 驗證 |
| F4 假憑證 | 升格 | 跨 PR 復發，且已定型為逐聲明證據、當前 head 與完整驗收攝取 | 鐵律 14、15、19、20.2① |
| F5 副本漂移 | 升格 | 終態檔、執行 prompt、參數契約與入口多次漏同步 | 分層規範、影響面閉合、20.2② |
| F6 引用失真 | 升格 | 外部來源、內容錨、歷史更正位置均曾重犯 | 鐵律 16、19、20.2②③ |
| F7 值域缺陷 | 不重複立法 | enum／上下限需由各領域正典與 `config/limits.yml` 決定，不能以一條審查流程代替 | 鐵律 6、領域規格、邊界測試 |
| F8 狀態機缺陷 | 部分升格 | 產品狀態機仍按領域規格；交付流程的漏分支已有跨 PR 固定修法 | 狀態表與 20.2④ |
| F9 租戶隔離缺陷 | 不重複立法 | 已是鐵律 2 與專用 checker 的技術紅線 | 鐵律 2、tenant checker／DB 約束 |
| F10 回歸 | 升格 | 修法帶入新錯、只驗 happy path 與生產 wiring 漏接均有重犯 | mutation、反向 fixture、20.2②⑤ |
| F11 計數腐化 | 升格 | 裸數字、行號與全稱句在修復輪本身反覆腐化 | AGENTS §2–§5、doc-claims、20.2③ |
| F12 閘門失效 | 升格 | fail-open、零掃描、workflow 平台 skip 與自我指涉均有實案 | canary、反向測試、18.3、20.2⑤⑥⑦ |

「不重複立法」不是放行，而是現有技術鐵律已比本節更精確；把同義規則再抄一次只會製造 F5。

### 已升格根因與固定處理

#### A. 證據不完整、舊 head 或缺席被當現況（F4／F6）

- **復發證據**：PR #58 的 [inline 3802403719](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802403719)
  點名外部規則無來源，[inline 3802581074](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802581074)
  點名 Codex 完成證據未綁當前 head；PR #60 的
  [inline 3809330908](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3809330908)
  再次抓到用未證實 API 語義選修法；PR #61 的
  [inline 3818337787](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818337787)
  與 [inline 3818520936](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818520936)
  再抓到逐字證據不足；後者證明立下鐵律 19／20 後，既有方案種子若未按同一矩陣回掃，仍會把
  中文摘要與外部 UI 分類外推成 enum／狀態機。
- **根因**：把「驗收方說了」「舊 review 存在」「沒有看到留言」誤當存在型證據；取證對象、
  commit 與聲明沒有逐項綁定。
- **固定處理**：外部語義走鐵律 16／19；GitHub 先讀 `headRefOid`，再讀三個 REST 集合、每則
  review body 與 GraphQL threads，最後以 review／comment／run id 加 commit 對帳。任何端點、
  權限或判詞未取得都明載「未取得」，不推導零意見。
- **反向複驗**：故意把 current-head review 拿掉或把 `commit_id` 換成舊 SHA，四條件判定必須
  fail-closed；處置清單的每個 ID 都能由上面的 `gh api` 入口重新找到。

#### B. 驗收資料只拉一部分（F4／F5）

- **復發證據**：`docs/worklog/2026-08-19-PR58-R29驗收修復.md` 記錄只讀 inline 漏掉 review body，
  使「三條全部轉交」實為漏項；`docs/worklog/2026-08-20-PR61-第四輪驗收修復.md` 又曾把
  review body 模板誤述成零 inline，Claude 留言
  [5350972681](https://github.com/pisceshei/chilllovesaas/pull/61#issuecomment-5350972681)
  要求在原處更正；鐵律 20 入庫後，PR #61 的
  [inline 3818520933](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818520933)
  又抓到執行方案只把 GraphQL threads 寫進規範、沒有同步到每輪實際重拉流程。
- **根因**：把 GitHub 的 conversation、review 容器、review body、inline comment 與 thread
  當成同一資料源；未分頁時再把截斷結果當全集。
- **固定處理**：三個 REST 集合全部 `--paginate`；逐則讀 review `.body`；GraphQL threads 用來
  判 unresolved，不用 review 外殼取代意見明細。結論只能在集合對帳後發布。
- **反向複驗**：在 scratch 清單各放一則 conversation、review body 與 inline ID，任一集合
  未拉或少分頁時，集合差異必須非空並禁止「全收」。

#### C. 生產者修了，消費者、終態或歷史更正漏同步（F5／F6／F10）

- **復發證據**：PR #58 的
  [inline 3802403727](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802403727) 與
  [inline 3802942084](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802942084)；
  PR #60 的 [inline 3809330909](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3809330909)
  與 [inline 3809830153](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3809830153)；
  PR #61 的 [inline 3818337781](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818337781)
  與 [inline 3818337799](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818337799)；
  [inline 3818520940](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818520940)
  則證明 `AGENTS.md` 已定義 commit 後 doc-claims，執行方案 consumer 卻仍漏掉該時序。
- **根因**：以「我改的那個檔」當影響面，沒有追同識別字的執行消費者與終態入口；歷史層又被
  靜默覆寫或只在遠處加一個新段落。
- **固定處理**：改前 `rg` 識別字、讀 `git log -p` 沿革，列 producer → consumers → terminal
  docs → history correction 影響圖；同 commit 閉合倉庫內容。worklog `Changes` 與受影響 `docs/dev`
  是倉庫終態；本地 handoff §①在工作單位結束前同步最終 head／遠端狀態，不進 commit。
  worklog 歷史錯句原處加日期更正；D36 已凍結的既有 `docs/handoff/` 不改，改在新 worklog
  （使用者裁定另進 `docs/DECISIONS.md`，未點名同型坑另進 `91` §3）引用其精確路徑與穩定
  內容錨後更正，不能留下無法追到原說法的新篇聲明。
- **反向複驗**：對被改識別字跑全樹搜尋；每個仍活的舊契約要嘛同步、要嘛在處置清單附不受影響
  的證據。終態三處與 HEAD diff 的檔案集合雙向相等。

#### D. 易腐數字、行號、全稱句與完成性聲明（F11）

- **復發證據**：PR #58 的
  [inline 3802403730](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802403730) 與
  [inline 3802942078](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802942078)；
  PR #60 的 [inline 3811512313](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3811512313)
  與 [inline 3811512317](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3811512317)。
  本檔前文另記錄修數字的 commit 再造錯數字，故不是單次筆誤。
- **根因**：把可計算狀態抄成散文常數，或把會漂移的位置當主鍵；「全部／唯一」沒有定義全集。
- **固定處理**：不需要就刪數字；需要就寫日期、ref、命令與實跑輸出。引用改用章節／內容錨；
  全稱句列舉集合或附雙向集合比對。`check-doc-claims.rb` 只作第二道網，不能代替人工核對。
- **反向複驗**：在新提交增刪一個集合成員，原命令輸出會改變而散文不需改；若散文中的數字或
  行號因此必須手修，表示仍未解除易腐副本。

#### E. 狀態空間漏分、head 鎖被誤當 base 鎖（F8／F10）

- **復發證據**：PR #61 的
  [inline 3818337791](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818337791) 指出首次推送
  尚無 PR／tag 卻套後續修復流程；[inline 3818337801](https://github.com/pisceshei/chilllovesaas/pull/61#discussion_r3818337801)
  指出合併前未處理 base 漂移；Claude 留言
  [5350285952](https://github.com/pisceshei/chilllovesaas/pull/61#issuecomment-5350285952)
  抓到代行授權狀態空間漏掉「非 18.3 但未具名授權」。PR #60 的 timeout 修復亦多次漏掉
  fetch、retry 或 sleep 路徑，見同包 worklog 沿革。
- **根因**：用 happy-path 敘事代替狀態機；把 head、base、首次／後續與完成／缺席混成同一格。
- **固定處理**：先列狀態表，再寫流程。首次交付與後續修復分支；每個新 head 重新驗收；合併前
  fetch 最新 base、整合並重跑；證據未取得與平台 skip 是獨立失敗狀態。head 鎖不替代 base 更新。
- **反向複驗**：逐格走首次 push、舊 review、新 head、base 前進、skip、人工合併與失敗／逾時；
  任一格若要引用尚不存在的物件或沿用舊證據，流程不得發布。

#### F. fail-open、只測 happy path 與閘門自我證明（F10／F12）

- **復發證據**：PR #58 的
  [inline 3802744737](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802744737) 要求新增納管範圍的
  regression canary；PR #60 的
  [inline 3809560024](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3809560024)、
  [inline 3809830150](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3809830150)、
  [inline 3810723077](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3810723077) 與
  [inline 3810723082](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3810723082)
  分別抓到缺時間戳放行、數值解析邊界、算術溢位與吞掉 `sleep` 失敗。
- **根因**：只證明合法輸入能綠，沒有證明違規與工具失敗會紅；管道、fallback 或自改 checker
  又能把「沒執行」偽裝成成功。
- **固定處理**：每條新判準至少覆蓋正常、違規、輸入缺失／依賴失敗與零掃描；以 mutation／fixture
  讓判準真的轉紅；核對 `config/ci.rb` 與 workflow 的生產 wiring。不得吞錯，不得用被改判準
  自己的綠作唯一證據。
- **反向複驗**：逐一停用判準、刪目標、破壞輸入、令依賴命令失敗；每個 mutation 都必須取得
  非零且可分辨的退出碼，移除 production wiring 也必須由 parity／canary 擋下。

#### G. workflow 本機假綠與 YAML 字面塊（F12）

- **復發證據**：`docs/worklog/2026-08-14-CI全紅修復.md`、
  `docs/worklog/2026-08-14-驗收maxturns事故.md` 與
  `docs/worklog/2026-08-15-workflow語法閘門.md` 記錄 YAML／shell 交錯事故；PR #58 的
  [inline 3802403739](https://github.com/pisceshei/chilllovesaas/pull/58#discussion_r3802403739) 更正 workflow
  validation-skip 語義；PR #60 的
  [inline 3810262495](https://github.com/pisceshei/chilllovesaas/pull/60#discussion_r3810262495) 抓到
  `claude_args` 字面塊中的假註釋。`docs/worklog/2026-08-19-P8補審-approve綁定斷言更正.md`
  另有長 prompt 內嵌 expression 導致 GitHub 不啟動的實測沿革。
- **根因**：把 YAML parse、`bash -n` 或本機 action validator 的綠外推成 GitHub Actions 實跑；
  忽略 literal scalar 內所有文字都是值的一部分，及修改 workflow 的 PR 可能沒有有效 Claude 判詞。
- **固定處理**：保留本機多層語法檢查，但推後必查實際 run 的 step output／log。長 prompt 變數只走
  step `env`；`claude_args` 內不放 `#` 說明行。skip／run 消失／零判詞只記未取得，且一律走 18.3。
- **反向複驗**：解析 YAML 後直接檢查 prompt 與 args 的值；推送後以 run id 讀 log，確認不是
  validation skip。只有 GitHub 上對該 head 真執行的結果能支持平台狀態聲明。

#### H. Markdown 與 Windows 工具鏈製造假結果（F6／F12）

- **復發證據**：`docs/worklog/2026-08-19-PR58-第九次新head驗收修復.md` 記錄表格／code span
  的真實渲染複驗；`docs/worklog/2026-08-19-P8補審-approve綁定斷言更正.md` 記錄 cp950 把
  lint 輸出錯誤偽裝成檢查失敗；`91` 附錄集合比對與本專案接手紀律則記錄 quotepath 對中文檔名
  造成「全部缺失」的假差異。MSYS 路徑轉換的外部證據已落 `docs/dev/external-facts.md` B4。
- **根因**：把工具輸出層、編碼層、shell 轉參層與被驗內容混為一談；只看退出畫面，不驗實際
  輸入集合或渲染樹。
- **固定處理**：表格字面直線跳脫，預期輸出不加 Markdown 強調符；用實際 Markdown render
  核對結構，並以穩定內容錨定位目標列，斷言最後 `<td>` 保留末欄 sentinel 全文。Windows 顯式
  UTF-8、中文集合關閉 quotepath；可能被 MSYS 改寫的 `ref:path`
  改成 ref 與 path 分開的 argv，並確認實際使用的 bash／python。
- **反向複驗**：渲染後除計數 table 結構節點，另刪掉末欄 sentinel 或插入一個裸 `|`，內容級
  斷言必須轉紅；UTF-8 重跑 lint；集合兩端都用相同 quotepath 設定；令 ref 不存在時命令必須
  顯性非零，而不是得到與「零命中」相同的輸出。

### 送驗前固定順序

1. 用本輪改檔圈出上面適用類型；未適用的列記「不適用＋理由」，不能留白。
2. 編輯期先跑每類反向複驗與 targeted gate；候選 tree 凍結後才跑一次全套。結果寫入現行規則
   要求的 worklog，不用「已確認」代替輸出。
3. push 候選後先等 Claude、Codex 與 CI 都對 exact head 完成；未齊以前不改檔。完成後全量拉
   conversation、review body、inline 與 GraphQL threads；每次完整掃描前後都 guard head，並對
   四個排序後的完整集合算版本化 canonical SHA-256 digest。只有兩次連續掃描在非零 settle
   interval 前後得到相同 digest vector，才去重成倉庫外凍結 ledger；單次掃描或兩掃間插入／
   編輯／thread 變化都 fail-closed（external-facts A14）。D38 起現有
   `await-verdict.sh` 只屬歷史／排隊訊號，不作任何通過證據；0e／0f 尚未合併時直接以 CLI 在同一
   明列 interval／max-polls／deadline 的有界預算輪詢三方載體，之後只用 0e evaluator。CI 以
   `gh pr checks --json name,bucket,link` 間隔輪詢；每輪查詢前後與凍結 ledger 前都重取
   `headRefOid`，任一次不等於候選 SHA 就丟棄結果並非零終止。零 check 集合與 `pending` 在
   deadline 內繼續等；`gh pr checks` 的 pending 退出碼 8 要先按已取得的 JSON bucket 分流，不能
   被 shell 非零處理誤判為 API failure；終態 `fail` 進 ledger；`skipping`／`cancel` 先對
   同一 head 重跑 owning check 一次，仍非乾淨才保存兩次證據轉人工；空集合到 deadline、
   JSON 未取得／不可解析、API 失敗或 head drift 才是未取得；只有非空集合全 `pass` 且 head 不變才可合併
   （external-facts A11）。
4. 一次按根因批次處置；同一元件的完整狀態矩陣與反向 fixture 同批封閉，無關元件只登記
   `91` §3。若 exact-head 終態只新增 ⚪，以 PR body 的 exact `DEFERRED_WHITE` machine line
   延後到下一個 tree-changing PR 首候選批量入籍，不為登記造 head。commit 後核對兩點 diff 並
   最終重拉，再推一個整合修復 head。
5. 第二個 finding-bearing head 仍有同根因時，停止小修小推；在本地重建影響圖、狀態矩陣與
   mutation，必要時拆包。需擴 checker 時依 18.3 另包，不在當輪順手改 `scripts/` 或 CI。

## 2026-08-21 Convergence Protocol v2

### 為什麼問題會愈修愈多

2026-08-21 依 GitHub 三個 paginated REST 集合、review body、GraphQL threads、PR metadata 與
git 歷史重建 PR #61–#65。可重跑入口如下；數量只視為該日快照，不寫進流程判準：

```bash
for n in 61 62 63 64 65; do
  gh api --paginate "repos/pisceshei/chilllovesaas/issues/$n/comments"
  gh api --paginate "repos/pisceshei/chilllovesaas/pulls/$n/reviews"
  gh api --paginate "repos/pisceshei/chilllovesaas/pulls/$n/comments"
  gh api --paginate "repos/pisceshei/chilllovesaas/pulls/$n/commits"
done
```

| 根因 | 舊流程如何放大 | v2 固定處理 |
|---|---|---|
| 非同步先到先修 | Claude 先回就改 head；Codex 晚到時舊審作廢，下一 head 又各自重跑 | 三方 exact-head 全完成才凍結 ledger，未齊不改檔 |
| C1 把歷史當未清 | 同 head 所有 REST inline 永久相加，resolve／證偽後仍 `has:N` | review `.commit_id` 綁 head、inline 以 review ID 關聯；最後 finding 後須有 fixture 鎖定 completion，未解 thread 為零 |
| 驗證粒度錯置 | 每個本地微改全套重跑，但真正候選仍可能在最後又改 | 編輯期 targeted；tree 凍結後與 base 變動時才跑全套 |
| 同一失敗方法無限重複 | 點修只改被指行，下一輪抽到同根因另一狀態；沒有模式切換 | 首輪整合修封閉同元件狀態矩陣；同根因再現就重建模型或拆包 |
| 產物按驗收輪增殖 | 每輪另建 worklog／handoff，為記錄遠端結果再改 head，新增散文又成為下一輪 finding | 一個可獨立合併 PR 維護一份 worklog；一個工作包維護一份本地 handoff；no-tree 狀態不進 Git |

### 不被廢止的安全邊界

- 每個**實際 Git tree 變更**仍須 exact-head Claude＋Codex 最終審查；舊 head 不可沿用。
- GitHub CI 對每次 push 仍全跑；本地只是把開發內迴圈改成 targeted，沒有略過候選驗證。
- 三個 REST 集合、review body 與 GraphQL threads 仍全量分頁攝取；還要連續兩次取得相同
  canonical digest vector，缺席、單掃或不穩定都不是通過。
- 18.3 自我指涉、workflow、規範、不可逆 schema 與費用 PR 仍由使用者人工合併。
- 外部語義仍先走鐵律 16／19 官方取證；無關元件仍受 17.2 射程限制。

### C1 的唯一現行語義

```text
C1 = all_current_head_review_surfaces_ingested
     AND two_consecutive_canonical_digest_vectors_equal
     AND reviewer_clean_completion_after_last_current_head_finding
     AND unresolved_review_threads == 0
```

`all_current_head_review_surfaces_ingested` 包含三個 paginated REST 集合、每則 review `.body` 與
paginated GraphQL threads。finding review 以 REST review `.user.login` 精確等於
`chatgpt-codex-connector[bot]` 且 `.commit_id == headRefOid` 綁 head，inline／thread 只以
`.pull_request_review_id` 歸戶；一般 comment `.commit_id` 不作 head 證據。connector 也可能在
issues comments 發 finding；只有其獨立 `Reviewed commit:` 欄能依下述受控 parser 綁 exact head，
其他散文 SHA 不解析。證偽、裁定不修或 resolve 不抹除 finding 的 event time／endpoint-local ID。
四端點沒有被當成交易快照：0e 用版本化 serializer 對每個完整集合的排序後判定投影計算
SHA-256，投影必須含 endpoint-local identity、所有 C1 判定欄、body／body digest 與可用版本欄位；
每輪掃描前後都 guard `headRefOid`。兩次完整掃描須在明列非零 settle interval 前後得到相同四
digest vector；reviews 讀完後才插入 finding、同 ID body 被編輯、thread resolve 狀態變化、缺頁
或兩掃不等都 C1=0。fixture 與 guard-removal mutation 必須鎖住這些格（external-facts A14）。

乾淨 completion 的本倉庫實測載體是 connector issue comment，而非 clean REST review。已觀測兩種
受控形態：A 型（PR #61 comment `5351471350`、PR #64 comments `5358332294`／`5363805191`）首行
以精確前綴 `Codex Review: Didn't find any major issues.` 開頭，句點後同一行的 `:rocket:`／自由
尾句不參與 envelope 分類；B 型（PR #61 comment `5352954268`）前兩個非空行精確為
`## 驗收結論` 與 `**未發現需要新增 inline 意見的重大問題。**`。兩型都有獨立
`Reviewed commit:`；其餘 body 保存供稽核，依下述結構化 verdict marker 分類，不做 prose NLP。
重跑入口：

```bash
gh api --paginate repos/pisceshei/chilllovesaas/issues/64/comments
gh api --paginate repos/pisceshei/chilllovesaas/pulls/64/reviews
gh api --paginate repos/pisceshei/chilllovesaas/issues/61/comments
gh api --paginate repos/pisceshei/chilllovesaas/pulls/61/reviews
```

0e 因此只接受 bot 身分精確相等、A／B 任一 envelope 符合 fixture，且 `Reviewed commit:` 恰有一個
10–40 位十六進位 ref、該 ref 為當前 40 位 head 前綴的 issue comment。PR #61 的 B 型 comment
`5352954268`（`2026-08-20T07:45:46Z`）之後又有同 head finding review `4980284182`
（`2026-08-20T07:47:33Z`），所以先到 clean 不是終態；較晚 finding 必須令 C1 回到 0。跨載體先後只把已提交 review
的 `submitted_at` 與 issue comment 的 `created_at` 解析為 UTC event time；clean 必須嚴格晚於最後
finding，欄位缺失、解析失敗或時間相等都 fail-closed。數字 ID 只作 endpoint-local 身分／去重，
不跨端點排序（官方欄位證據見 `docs/dev/external-facts.md` A12）。未知作者、缺／多／錯 ref、未知 envelope 一律 fail-closed。未來若 connector 產生 clean
REST review，也必須先以實物加入 fixture 並有權威 exact-head 欄位，不能靠一般 body SHA 猜測。

Issue comment 不做自然語言「可處置」分類。第一個非空行若**以 A 型精確前綴開頭**，或**精確等於
B 型首行**，就依完整 envelope＋ref grammar 分類為一個 clean completion event；A 型其後的固定 About-Codex `<details>`、
B 型其後的確認敘述與 checks 都是同一 completion 的說明，不因「還有文字」改判 finding。第一個
非空行精確為 `## 驗收結論：需修改` 則是 finding event；其他首行是 unknown。任何 comment 出現
第二個頂層 verdict marker（A 型前綴或以 `## 驗收結論` 開頭的行）都屬互斥／ambiguous，C1=0。
0e fixture 必須用 PR #61 comments `5352963934`／`5353241564`／`5353555384` 鎖定 finding 型，並覆蓋
A 型＋固定 boilerplate、B 型＋長敘述、clean＋第二 verdict marker、未知首行四格；不得用 prose NLP。

若 current-head finding 集合為空，時間下界定義為負無限：任一合法 exact-head clean completion
即滿足「晚於最後 finding」；空 finding 但沒有 completion 仍為 C1=0。0e 必須有「零 finding＋clean
→ 1」與「零 finding＋無 completion → 0」正反 fixture，不能把不存在的最後 finding 誤作欄位缺失。

OpenAI 官方要求 Codex reaction 後仍發布 review 結果（逐字與 URL 見 `docs/dev/external-facts.md` A10）；
reaction 只作觸發／排隊輔助訊號。reaction-only／沒有可綁 exact-head 的受控載體時 C1 fail-closed 並轉人工，
不得把 👀、👍 或其他 reaction 當 reviewer-controlled completion。

`isResolved` 只是必要的工作流狀態，不是獨立核准：GitHub 官方允許 PR 作者或具 write 權限者
resolve conversation，而且 review body 是 inline comments 之外的 review 構成；逐字與 URL 見
`docs/dev/external-facts.md` A9。證偽與裁定不修須先有合規證據／裁定落點；作者 resolve 不能取代
更晚的 reviewer-controlled completion。處置未改 tree 時只送一次同 head review 請求並作有界等待；
官方未保證同 SHA 的重複請求必產生新 review，若 deadline 前沒有更晚 completion，C1 保持 0 並
轉獨立人工審核／人工合併，不再請求或造 head。作者自貼 envelope、review `.commit_id` 不等於
head、A 型前綴／尾句、B 型兩個非空首行、clean issue comment 缺／多／錯 ref、跨載體時間缺失／
相等／解析失敗、先 clean 後較晚 finding、issue-comment finding、reaction-only、same-head 請求
被去重／逾時仍把 C1 設 1，都是 0e 必測反例。
resolve、PR body、check artifact 與本地 handoff 不改 Git tree，所以不產生新 head。舊 evaluator
仍以 REST inline 歷史總數計 C1，`await-verdict.sh` 也看不到 clean issue comment；兩者自 D38 起
只作歷史／排隊訊號，不得證明 C1、C3 或雙清。在獨立 evaluator 與 workflow-only 接線各自合併前，舊 `1111`
不得授權互動式 Codex 代行合併，過渡期全部 PR 走使用者人工合併。

### C2／C3／C4 的 exact-head、自我排除與格式契約

- **C2** 不再使用「留言 id 水位＋job 起跑時間窗」猜判詞歸屬。0f 必須由受信任 workflow 產生
  run-specific evidence，且 `run_id`、`run_attempt`、candidate＝
  `github.event.pull_request.head.sha`、`verdict_comment_id`、`verdict_body_sha256` 五者都存在。
  0f 完成最終貼文／更新後按 ID 回讀 `.body`，對原樣 UTF-8 bytes 算 SHA-256；0e 按 ID 重取、
  重算且要求相等，comment ID 不能替代 hash。再依 run id 要求 `event=pull_request`、
  `pull_requests[]` 中恰有目標 PR 且其 `head.sha == candidate`，並比對 run／job／check-run 的
  `head_sha` 作本倉庫 canary。缺／錯 hash、same-ID body edit、任一關聯缺失／多義／不等、跨 run、
  只有時間落窗或多個無法配對的判詞一律 C2=0。fixture 必測 same-ID edit、缺 hash、錯 hash；
  hash guard mutation 必須轉紅。官方邊界與 PR #66 run `32463413197` 的具名實證見
  external-facts A13／A14。
- **C3** 的 eligible 集合是 candidate head 的 check runs，扣掉 0f 提供的 evaluator 自身**精確
  check-run ID**。0f 由 workflow jobs REST 的 `check_run_url` 取得該 ID；找不到、找到多個或 ID
  不屬同 run/head 就 C3=0。自己的 pending 可排除，任何其他 pending／非 success 都保留；排除後
  只剩自己等於空集合，仍 C3=0。fixtures 必須覆蓋 self pending＋其他全綠、self pending＋他項
  pending、only-self、錯 self ID／多 self ID 四格。
- **C4** 不得只沿用 workflow 內一段未被獨立測試的 grep。0e fixture／mutation 至少覆蓋合法
  「通過」、合法「需修改：非空理由」、判詞缺失、標記不在首行、重複標記、通過／需修改互斥、
  空白理由（ASCII／全形空白／CR）與未知結構；first-line、唯一標記、互斥與非空理由任一守衛
  被刪，regression 必須轉紅。
- Codex 晚到只重跑／再調用 evaluator，不整體 rerun Claude workflow。whole-run rerun 只保留
  「Claude 判詞格式畸形」同 head 最多一次的 transport 例外；不得因 C1 timing 另造 Claude 判詞。

### 產物頻率的終態

- 一個可獨立合併的 PR／原子工作包維護一份 tracked worklog；tree 真改時在同一整合 commit
  更新，no-tree disposition／遠端狀態不改 worklog。
- exact-head 終態只有新增 ⚪ 時，PR body 的 `DEFERRED_WHITE head=<40hex> comment=<decimal>
  item=<decimal>` 是唯一 no-tree 登記形態；下一個本來會改 tree 的 PR 在首候選前掃 merged PR
  bodies，將尚未存在於 `91` 的 pair 批量入籍。任意散文、錯 head、重複或無來源 pair 都不算。
- 一個工作包／PR 從研究到 merge／rollback／正式阻塞維護一份倉庫外本地 handoff，不按驗收輪
  拆檔。只有正式轉交、rollback 後另起恢復包或真正拆 PR 才另建。
- 這一終態由 D38 覆寫 D36／D37 的過渡粒度；`docs/worklog/README.md`、CLAUDE 與 AGENTS 已同批同步。

### 1–2 次的精確承諾

目標是通常只發布初始候選與一次整合修復，不承諾 reviewer 一定在兩次內發現所有缺陷。若第二個
finding-bearing head 仍有同根因，任務不停止，但禁止第三次沿用點修；本地先完成根因模型、mutation
與拆包判斷。這讓第三個 head（若確有必要）來自更強的修法或更小的語義單元，而不是重複碰運氣。
