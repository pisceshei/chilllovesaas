# M0 — P-8 自動化基建（判詞格式驗證・四條件評估器・熔斷修復・倒計時腳本・CI 淺 clone 修洞）

> 出處：合併版總方案 §八 P-8（`docs/plans/2026-08-18-總方案.md`，隨 PR #58 落庫、
> 2026-08-18 尚未進 main）。條文依據＝鐵律 17/18（CLAUDE.md，同在 PR #58 立法、
> 2026-08-18 尚未進 main；本篇按已批准條文語義實作，條文措辭以該 PR 收官版為準）。
> 本篇＝終態層：必須等於 HEAD 行為。

## 1. 這是什麼

鐵律 17（等待自動化）與 18（自動合併）的**機制面**首批交付，逐件見下表（數量以表列為準）：

| # | 交付物 | 檔案 |
|---|---|---|
| 1 | 判詞格式機械驗證（18.1④） | `.github/workflows/claude-review.yml` 判詞處理步驟內 |
| 2 | 18.1 四條件評估器（fail-closed） | 同上，「通過」分支內 |
| 3 | 熔斷 label 修復（17.4 的閘門真正生效） | 同上，超輪分支內 |
| 4 | 倒計時判詞輪詢腳本（17.1） | `scripts/await-verdict.sh` |
| 5 | doc-claims CI 淺 clone 雙重洞修復 | `.github/workflows/ci.yml`＋`scripts/check-doc-claims.rb` `--require-base`＋`scripts/test-doc-claims-rules.rb` git-G3 |

**AUTO_MERGE 維持 `"false"`**（18.4：機制在真實 PR 實測全鏈路＋另立信任邊界之前不啟用；
啟用是使用者裁定，不是本包能自決的）。

## 2. 各件具體行為

### 2.1 判詞格式機械驗證
- **驗什麼**：`LATEST`（本輪判詞）第一行必須恰為「標記＋通過」或「標記＋需修改：理由」
  兩形之一，且結論標記**全文只出現一次**（供給端 prompt 的原文契約，先前無人驗收端）。
- **失敗＝job 紅（exit 1）＋留言**，不是綠燈留言——先前亂寫的第一行會落到檔尾
  「無法判讀」分支後 job 照綠，18.1④ 等於永真。該檔尾分支現在**結構上不可達**，
  保留為縱深防線並同樣改為 exit 1。
- 為何插在「需修改／通過」分支之前：格式是兩個分支共同的前置契約，通過分支的
  評估器（C4）直接消費它的結果。

### 2.2 四條件評估器（18.1）
- 位置：「通過」分支、approve 之後。四條件全部**存在型判定、fail-closed**（取不到＝0）：
  - **C1 Codex 零建議的正向證據**（r1 加嚴：光「內文沒有某句話」不算證據——同一
    connector 有多種措辭形；r2 再加嚴：身分與 commit 都走**權威欄位**）：存在一則
    review，其 `user.login` **精確等於** `chatgpt-codex-connector[bot]` ∧ 其 `commit_id`
    **精確等於本輪 event head** ∧ 該 review 名下 inline 意見數＝0（以
    `pull_request_review_id` 歸戶實查）。⚠️ 不再用「login 含 codex」與「內文含 9 位
    SHA」——前者任何含該字串的帳號都命中，後者會被引述舊 SHA 的散文騙過。
  - **C2 bot 通過**：＝進入本分支的條件（恆 1，寫出來是讓留言可讀）。
  - **C3 機械 CI 全綠**（🔴 job 需 `checks: read` 權限——顯式 permissions 區塊會關閉未列出的
    權限，缺它時 check-runs API 回權限錯誤 ⇒ C3 恆 0 ⇒ 四條件結構上永遠湊不齊，Codex r3）：
    head 的 check-runs 全部 `success`，**排除本 review job 自身**
    （名稱 `review`——它此刻必然 in_progress）；空集合＝0（沒跑≠綠）。
    **有界等待**（r1）：pending 時每 30 秒重查、至多 20 次，仍未落定＝0。
    **全頁聚合**（r2）：`--paginate`＋`jq -s`——單頁上限 100，破百時後面幾頁的
    pending／failed 會整批看不到而誤報 allgreen。
  - **C4 判詞格式**：§2.1 的結果（格式失敗根本走不到這裡）。
- **行為分岔**：`AUTO_MERGE != "true"`（現況）⇒ 只貼評估留言存證、止於評估——
  **留言文案依四條件分兩種**（r2）：齊了才說「可人工合併」，未齊則列出待補項並明說
  「先不要合併」（舊版一律說「請人工合併」，與同一句的「缺任一即不得合併」互斥）；
  `"true"` ⇒ 四條件缺一即拒絕合併並留言，齊了才合併，且合併本身帶
  **`--match-head-commit "$HEAD_SHA"`**——由 GitHub 服務端在合併前比對 head，不相等直接
  拒絕（r2 的「查完再 merge」是 check-then-act，競態窗只變小沒消失；r3 改為原子。
  前置的 `gh pr view` 查詢保留，只為產生可讀的診斷留言）。
- **全程用 workflow event 的 head**（r2）：不用即時 `gh pr view`——判詞貼出後、
  評估前若發生 synchronize，即時查詢會拿到新 head，而判詞描述的是舊 head，
  併發取消抵達前可能合併一個沒有自己判詞的 commit。
- 🔴 **C1/C3 的已知限制（誠實聲明）**：①Codex inline thread 的 **resolved 狀態**仍拿不到
  （API 權限）——C1 判的是「這輪 review 沒掛任何 inline 意見」，不是「掛過的意見已
  逐條解決」；有意見的輪要等 Codex 對修復後的 head 再發零意見 review 才能 C1=1，而
  Codex 無建議時可能只按 👍 不發 review ⇒ 錨定不到 ⇒ C1=0。②C3 的有界等待只覆蓋
  job 存活期，job 結束後才完成的 check 不會回頭重評（18.4 啟用時由自動合併 workflow
  的 `workflow_run` 再評路徑收口）。兩條方向都是 fail-closed：代價是多等人工，
  不是誤合併——18.4 啟用裁定時必須重看。

### 2.3 熔斷 label 修復
- **事故**：舊註釋稱「label 不存在時 `--add-label` 會自動建立它」——**實測為假**
  （2026-08-18）。label 從未存在於 repo，add-label 每輪失敗又被 `|| true` 吞掉 ⇒
  PR #58 連續多輪 ⛔ 升級留言與照常驗收**並存**，熔斷從未真正生效；label 最終由
  人工補建（2026-08-18，`review:需人工裁定`，色 B60205）。
- **修法**：①先 `gh label create … || true`（冪等；已存在時的失敗是唯一可吞的）
  ②`gh pr edit --add-label` **不再吞錯**，失敗即留言講明「閘門此刻沒有生效」。
- 契約註釋同步更正（錯誤斷言不留原文）。

### 2.4 `scripts/await-verdict.sh`
- `bash scripts/await-verdict.sh <PR> <HEAD_SHA> [INTERVAL=900] [MAX_POLLS=8]`：
  每輪查**兩側是否都已對同一個 head 完成**（r2 重寫；原本兩側都只是 PR 全域條件）：
  ①**判詞就緒**＝該 head 的 `review` check-run 已 `completed`——check-run 掛在 commit 上，
  天然綁 head，且 `completed` 才出現 ⇒ 同時解掉「判詞留言是邊跑邊編輯、API 會回半截
  內容」的坑（2026-08-18 實測：8532 字元的判詞讀到 2933 字元、🟡 段整段不在裡面）；
  ②**Codex 已審該 head**＝有一則 review 其 `user.login` 精確等於 connector 身分
  ∧ `commit_id` 精確等於該 head。雙到 exit 0；等滿升級 exit 4；API 連敗 3 次 exit 2。
- **參數驗證全走 exit 2**（Codex #59 r1）：PR 十進位、HEAD_SHA 十六進位 9–40 位、
  INTERVAL/MAX_POLLS 正整數、INTERVAL≥300——爛參數不得滑進循環變成假逾時或燒限額。
- **額度路徑雙軌**（第 6 輪）：偵測到**已認證的 `gh`** 就走它（5000/小時），否則回退匿名
  urllib（60/小時）。回退分支必須留著——本腳本是本機工具，不保證每台機器都裝了 gh。
- **SHA 一律正規化成完整 40 位小寫**（Codex r3／r4）：API 回的 `commit_id` 是完整小寫，
  傳大寫或短前綴在精確比對下**永遠比不中**，症狀是白等整個輪詢窗後 exit 4（看起來像
  「審查方沒回應」）。短前綴以 API／`git rev-parse` 解析，解不出即 exit 2 不進輪詢。
- **判詞就緒＝job 成功 ∧ 該輪真有合法判詞**（Codex r3 起、r5 補完）：`completed` 涵蓋
  failure／cancelled／timed_out；而 `conclusion == success` **仍不夠**——workflow 在
  「Claude 沒貼結論」「作者不在允許清單」等路徑是**貼診斷留言後 exit 0**（該檔註釋自己
  寫著「失敗被下游 exit 0 吞掉」）⇒ job success 卻零判詞。現行判準追加：存在一則作者在
  允許清單 ∧ 首行整行匹配合法結論形 ∧ `created_at >= 該 check-run 的 started_at` 的留言
  （留言無 commit 關聯，check-run 起跑時刻是唯一可靠的「該輪」關聯鍵）。
  **正反實測**：有真判詞的 head 報 1；反竄改自跳（success 但無判詞）的 head 報 0。
- **非 Windows 可用性**（Codex r5，P1）：gh 偵測用 `${PROGRAMFILES:-}`——`set -u` 下
  Linux／macOS 沒有該變數，直接展開會在**偵測階段就 unbound variable 退出**，兩條路都跑不到。
- **參數前導零**（Codex r5）：`00` 會通過非零檢查卻讓迴圈一次不跑（假逾時）、`08` 會被
  bash 當八進位而算術報錯 ⇒ 兩者一律 exit 2（實測皆 2）。
- **認證路徑被限流不得靜默回退**（Codex r5）：gh 被限流時偵測 stderr 並查 `rate_limit`
  取 reset 後上報等待，不再退回只有 60 額度的匿名路徑（那會把「等一下就好」變成連續失敗）。
- **起跑即齊備就立刻退出**（Codex r3）：主循環第一件事是 sleep，舊版會讓「掛上去時兩側
  早已完成」白等一個 INTERVAL。
- **起跑也有重試預算**（Codex r4）：單次暫時性故障不再直接 exit 2（契約說 exit 2 是
  「持續不可用」），與輪詢路徑的容忍度一致。
- **限流是可恢復狀態、不是故障**（第 4 輪自報實測）：撞 60/hr 未認證上限時，讀
  `X-RateLimit-Reset` 等到重置再續，**不計入失敗也不消耗輪次**（上限 `RATE_WAIT_MAX`
  兜底）。舊版把它當解析失敗直接 exit 2——同日診斷查詢把額度用光後，poller 起跑即
  假性失敗。判別法＝HTTP 403/429 且 `X-RateLimit-Remaining: 0`。
- **分頁**（Codex #59 r1）：留言破百的 PR 只看第一頁會永遠等不到新判詞——逐頁抓到
  不足 100 則為止（上限見腳本 `PAGES_MAX`）。
- 🔴 實作紀律寫在檔頭：JSON 由 **python 直接抓取＋UTF-8 顯式解析、輸出只回 ASCII
  計數**（Windows cp950 管道解 CJK JSON 靜默出錯，同日兩次實測）；未認證 API
  **60 次/小時/IP 跨工具共用** ⇒ INTERVAL 下限 300 秒（腳本硬擋）。
- 不匹配閘門 selector（`^(check|test|lint)-`）：它是操作工具不是驗收閘門，刻意的。

### 2.5 doc-claims 淺 clone 雙重洞修復
- **洞**（PR #58 期考掘、詳錄於該 PR 的 91 §3.4 增補——2026-08-18 尚未進 main）：
  quality job 淺 clone＋base 淺 fetch ⇒ `base...HEAD` 三點 diff 無 merge-base ⇒
  腳本印「R4/R5 本次未執行」warning 後 exit 0，**連續多輪 quality 綠而 R4/R5 實質沒跑**。
  `--depth=1` 是為單點 ref 比對（baseline 步驟）設計的修法，誤套到三點 diff 消費者。
- **修法三件一組**（缺一即回洞）：ci.yml ①`--unshallow` 補全歷史 ②base fetch 去
  depth、**去 `|| true`**（拿不到當場紅）；③checker 新旗標 `--require-base`：
  diff 算不出來 ⇒ exit 3（檢查根本沒有生效），CI 帶上它。
- **回歸測試**：`test-doc-claims-rules.rb` 新增 git-G3 情境（`--require-base`＋
  不存在的 base ⇒ 必須 exit 3 且訊息講明）。**突變已驗**：把 exit 3 分支改註釋 ⇒
  整支轉紅（git-G3 段），還原後綠。**W1 供給斷言**（Codex #59 r1：G3 只測消費端
  分支——把 ci.yml 的旗標拿掉 G3 照綠）：harness 直接斷言 ci.yml 的 doc-claims
  調用行帶 `--require-base`，拿掉即紅。
- 本機日常**不帶** `--require-base`（fixture 目錄與離線環境合法地算不出 diff）；
  帶不帶的行為差異即是 CI canary 的全部內容。

## 3. 驗證紀錄（2026-08-18）

- 全閘門一鍵（selector 全集）FAIL=0；`test-doc-claims-rules.rb` 報「9 條 fixture case
  ＋ 3 條 git 情境」全綠（快照，重跑腳本看現值）。
- 兩支 workflow：ruby YAML parse OK；全部 `run:` 區塊抽出後 `bash -n` OK（第 2 輪重驗）。
- `await-verdict.sh`：`bash -n` OK；第 2 輪參數驗證實跑——壞 INTERVAL／短 SHA／零
  MAX_POLLS／非數字 PR 四形全 exit 2；urllib 分頁抓取以 PR #59 實測（起跑基準行輸出正常）。
- G3 突變：壞 → harness exit 1（失敗訊息含 git-G3）；還原 → exit 0。
- W1 突變（第 2 輪）：拿掉 ci.yml 調用行的 `--require-base` → harness exit 1（訊息含
  W1）；還原 → exit 0。
- **待真實 PR 取證**（本 PR 自身因反竄改自跳驗收，取證不到）：①格式驗證與評估器
  留言要在下一個「通過」的常規 PR 上看到 ②熔斷 add-label 生效路徑要在下一次
  超輪事件上看到。兩者列入本包 Pending，不宣稱已驗。

## 4. 跨功能／跨流程影響（預先對接）

- **所有後續 PR 的 quality job**：base 拿不到會**當場紅**（先前靜默綠）——分支
  剛開、遠端 base 改名等情況會顯性失敗，這是刻意的；修法是把 base 餵對，不是拿掉旗標。
- **判詞格式走樣＝review job 紅**（先前綠）：驗收方產出走樣會第一時間可見。
- **熔斷真正生效**：`MAX_FIX_ROUNDS`（現值 "3"）超輪後 label 掛上，**下一次 push
  不再觸發驗收**——先前歷輪其實都沒生效。要恢復：移除 label 再 push（workflow
  尾註既有文案）。操作者要開始把「label 在不在」當成狀態的一部分。
- **`gh pr checks` 消費者**（驗收 bot prompt 的 CI-as-evidence 段）：不受影響，
  check 名稱與結論語義未動；評估器另走 check-runs API。
- **18.4 啟用時**（未來裁定）：只翻 `AUTO_MERGE` 是不夠的——workflow 頂部與
  contents 權限註釋列了配套（`contents: write`、approve 設定）；評估器屆時自動
  從「證據留言」升為「合併硬閘」，無需再改代碼。
- **與 PR #58 的檔案交集**：`check-doc-claims.rb`／`test-doc-claims-rules.rb` 兩檔
  #58 分支也改過（IN_SCOPE 擴充與 canary CASE）——改動落在不同 hunk（旗標區 vs
  範圍區；G3 vs fixture CASES 表），git 預期可自動合併；後合併的一方要重跑
  `test-doc-claims-rules.rb` 確認兩組改動疊加後仍綠。
