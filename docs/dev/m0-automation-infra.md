# M0 — P-8 自動化基建（判詞格式驗證・四條件評估器・熔斷修復・倒計時腳本・CI 淺 clone 修洞）

> 出處：合併版總方案 §八 P-8（`docs/plans/2026-08-18-總方案.md`，隨 PR #58 落庫、尚未進 main）。
> 條文依據＝鐵律 17/18（CLAUDE.md，同在 PR #58 立法、尚未進 main；本篇按已批准條文語義實作，
> 條文措辭以該 PR 收官版為準）。本篇＝終態層：必須等於 HEAD 行為。

## 1. 這是什麼

鐵律 17（等待自動化）與 18（自動合併）的**機制面**首批交付，共五件：

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
  - **C1 Codex 完成且零未清**：最新 Codex review 內文含當前 head 前 9 位 SHA（錨定）
    且不含建議聲明句（`review suggestions`）。
  - **C2 bot 通過**：＝進入本分支的條件（恆 1，寫出來是讓留言可讀）。
  - **C3 機械 CI 全綠**：head 的 check-runs 全部 `success`，**排除本 review job 自身**
    （名稱 `review`——它此刻必然 in_progress）；空集合＝0（沒跑≠綠）。
  - **C4 判詞格式**：§2.1 的結果（格式失敗根本走不到這裡）。
- **行為分岔**：`AUTO_MERGE != "true"`（現況）⇒ 只貼評估留言存證、止於評估；
  `"true"` ⇒ 四條件缺一即拒絕合併並留言，齊了才 `gh pr merge --squash`。
- 🔴 **C1 的已知限制（誠實聲明）**：Codex inline thread 的 resolved 狀態拿不到
  （API 權限），「零未清」用**代理判準**；Codex 無建議輪可能只按 👍 不發 review ⇒
  錨定不到 ⇒ C1=0 ⇒ 不合併。方向是 fail-closed：代價是多等一輪人工，不是誤合併。
  這正是 18.4 要求信任邊界的原因之一，啟用裁定時必須重看這條。

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
  每輪查①判詞數是否**比起跑時增加**（判詞累積制，比絕對數會誤認上一輪）
  ②Codex review 是否錨定 head（前 9 位）。雙到 exit 0；等滿升級 exit 4；
  API 連敗 3 次 exit 2。
- 🔴 兩條實作紀律寫在檔頭：JSON 一律**落檔後 python UTF-8 顯式解析**（Windows
  cp950 管道直讀 CJK JSON 靜默解錯，同日兩次實測）；未認證 API **60 次/小時/IP
  跨工具共用** ⇒ INTERVAL 下限 300 秒（腳本硬擋）。
- 不匹配閘門 selector（`^(check|test|lint)-`）：它是操作工具不是驗收閘門，刻意的。

### 2.5 doc-claims 淺 clone 雙重洞修復
- **洞**（PR #58 期考掘、2026-08-18，詳錄於該 PR 的 91 §3.4 增補——尚未進 main）：
  quality job 淺 clone＋base 淺 fetch ⇒ `base...HEAD` 三點 diff 無 merge-base ⇒
  腳本印「R4/R5 本次未執行」warning 後 exit 0，**連續多輪 quality 綠而 R4/R5 實質沒跑**。
  `--depth=1` 是為單點 ref 比對（baseline 步驟）設計的修法，誤套到三點 diff 消費者。
- **修法三件一組**（缺一即回洞）：ci.yml ①`--unshallow` 補全歷史 ②base fetch 去
  depth、**去 `|| true`**（拿不到當場紅）；③checker 新旗標 `--require-base`：
  diff 算不出來 ⇒ exit 3（檢查根本沒有生效），CI 帶上它。
- **回歸測試**：`test-doc-claims-rules.rb` 新增 git-G3 情境（`--require-base`＋
  不存在的 base ⇒ 必須 exit 3 且訊息講明）。**突變已驗**：把 exit 3 分支改註釋 ⇒
  整支轉紅（git-G3 段），還原後綠。
- 本機日常**不帶** `--require-base`（fixture 目錄與離線環境合法地算不出 diff）；
  帶不帶的行為差異即是 CI canary 的全部內容。

## 3. 驗證紀錄（2026-08-18）

- 全閘門一鍵（selector 全集）FAIL=0；`test-doc-claims-rules.rb` 報「9 條 fixture case
  ＋ 3 條 git 情境」全綠。
- 兩支 workflow：ruby YAML parse OK；全部 `run:` 區塊抽出後 `bash -n` OK。
- `await-verdict.sh`：`bash -n` OK；參數驗證與 INTERVAL 下限實跑驗過。
- G3 突變：壞 → harness exit 1（失敗訊息含 git-G3）；還原 → exit 0。
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
