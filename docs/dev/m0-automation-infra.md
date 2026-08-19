# M0 — P-8 自動化基建（判詞格式驗證・四條件評估器・倒計時腳本・CI 淺 clone 修洞）

> 🔴 **2026-08-19 使用者裁定「取消熔斷機制，一律循環到雙清為止、不限次數」**：本包原有的
> 第 3 項交付「熔斷 label 修復」**已廢止**，機制（`MAX_FIX_ROUNDS`／label 閘門／超輪分支）
> 已自 `claude-review.yml` 整個移除。下文 §2.3 保留為**事故紀錄**（那個靜默失效形態仍有
> 參考價值），但它描述的機制**不再存在**。複驗現值：
> `grep -n "MAX_FIX_ROUNDS" .github/workflows/claude-review.yml`（應只剩廢止說明註釋）。

> 出處：合併版總方案 §八 P-8（`docs/plans/2026-08-18-總方案.md`，隨 PR #58 落庫、
> 2026-08-18 尚未進 main）。條文依據＝鐵律 17/18（CLAUDE.md，同在 PR #58 立法、
> 2026-08-18 尚未進 main；本篇按已批准條文語義實作，條文措辭以該 PR 收官版為準）。
> 本篇＝終態層：必須等於 HEAD 行為。

## 1. 這是什麼

鐵律 17（等待自動化）與 18（自動合併）的**機制面**首批交付，逐件見下表（數量以表列為準）：

| # | 交付物 | 檔案 |
|---|---|---|
| 1 | 判詞格式機械驗證（18.1④） | `解析結論並驅動閉環` 步驟內的 `FORMAT_OK` 區塊（複驗：`grep -n 'FORMAT_OK' .github/workflows/claude-review.yml`） |
| 2 | 18.1 四條件評估器（fail-closed） | 同上，「通過」分支內 |
| 3 | ~~熔斷 label 修復~~ **已廢止（2026-08-19 裁定取消熔斷）**——機制連同超輪分支整段移除 | — |
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
- 位置：「通過」分支，**在 approve 之前**（r10 起——approve 是分支保護會消費的憑證，
  先 approve 再評估等於閘門報 0 時已留下核准，屬 fail-open）。四條件全部**存在型判定、
  fail-closed**（取不到＝0）：
  - **C1 Codex 零建議的正向證據**（r1 加嚴：光「內文沒有某句話」不算證據——同一
    connector 有多種措辭形；r2 再加嚴：身分與 commit 都走**權威欄位**）：存在一則
    review，其 `user.login` **精確等於** `chatgpt-codex-connector[bot]` ∧ 其 `commit_id`
    **精確等於本輪 event head**。🔴 **意見數是「同 head 全部 review 的加總」不是單一 review**
    （r7 改聚合制、r10 回寫本段）：收齊該 head 全部符合條件的 review id，再以
    `pull_request_review_id` 歸戶加總其名下 inline 意見數，**總和為 0** 才算零建議
    ——只看最後一則會讓「後到的零意見 review 遮蔽前一則未清發現」。
    🔴 **取值失敗與「真的沒有」分開**（r9）：五態＝`apifail`（分頁中途失敗，fail-closed）／
    `nohead`／`noreview`（該 head 真的沒有 Codex review，合法狀態）／`zero`／`has:N`，
    狀態字串會印在評估留言裡。⚠️ 不再用「login 含 codex」與「內文含 9 位
    SHA」——前者任何含該字串的帳號都命中，後者會被引述舊 SHA 的散文騙過。
  - **C2 bot 判詞且綁本輪**（r11 起**不再恆 1**）：進入本分支只代表「有一則通過判詞」，
    不代表那則判詞屬於本輪 ⇒ 追加兩道 fail-closed：①水位之後的合法判詞**必須恰好一則**
    （多於一則＝無法分辨哪則屬本輪，記 0）②該則的 `created_at` 必須 ≥ **本 job 起跑時刻**
    （水位步驟輸出的 `started_ts`）。狀態字串 `C2_STATE` 進評估留言
    （`unique`／`none-in-window`／`ambiguous:N`／`parse-error`）。
    ⚠️ 誠實限制：擋不住「本輪 Claude 沒貼、而某舊 run 恰在本 job 期間貼出唯一一則」，
    根治＝判詞契約帶 head SHA（與 `await-verdict.sh` 同一項待辦）。
  - 🔴 **approve 綁 commit 的真實效力（2026-08-19 補審更正，此前本篇宣稱過頭）**：
    送核准走 `POST /pulls/{n}/reviews` 並帶 `commit_id="$HEAD_SHA"`。
    ⚠️ **它不會讓 head 前進後的核准失效**——官方對該參數的定義是
    「Not using the latest commit SHA may render your review **comment** outdated…」
    （docs.github.com/en/rest/pulls/reviews，取證 2026-08-19），管的是**留言行定位**；
    dismiss-stale 則是**推播事件撤銷全部核准**，與 `commit_id` 無關。
    ⇒ check-then-act 的競態**沒有關掉**，只是窗變小＋留下可稽核紀錄。
    ⚠️ 現況：`main` **未設分支保護**（實測 404 Branch not protected）⇒ 核准不構成閘門，
    本項風險惰性；啟用 required approving review 後才會活過來。
  - 🔴 **approve 在四條件之後才送出**（r10）：舊版先 `gh pr review --approve` 再算
    C1–C4，缺項時只留言「先不要合併」——但 approve 是**分支保護規則會消費的憑證**，
    在啟用 Actions approvals 的倉庫可能滿足「需要一則核准」而讓人工或外部 auto-merge
    在閘門報 0 時照樣合併 ⇒ fail-open，與評估器整體立場矛盾。現值＝四條件齊才 approve。
  - **C3 機械 CI 全綠**（🔴 job 需 `checks: read` 權限——顯式 permissions 區塊會關閉未列出的
    權限，缺它時 check-runs API 回權限錯誤 ⇒ C3 恆 0 ⇒ 四條件結構上永遠湊不齊，Codex r3）：
    head 的 check-runs 全部 `success`，**排除本 review job 自身**
    （名稱 `review`——它此刻必然 in_progress）；空集合＝0（沒跑≠綠）。
    **有界等待**（r1）：pending 時每 30 秒重查，仍未落定＝0。
    **末查不 sleep**（r8）：21 次查詢夾 20 段等待——舊版 query→sleep 收尾，CI 在最後
    一段 sleep 中轉綠會帶著過期的 pending 收場、C3 誤記 0。
    🔴 **另有時間預算截斷**（r13 引入、r14 改 fail-closed）：本 job `timeout-minutes: 30`
    而 Claude 驗收步驟可跑 18–20 分 ⇒ 再等滿 10 分鐘會讓 job **在解析途中被砍**、
    評估留言與核准一則都貼不出。用水位步驟輸出的 `started_ts` 算已用時間，逼近
    `JOB_BUDGET_S`（22 分）即停等。**C3 因此有兩個額外狀態**：
    `pending-timebudget`（預算用盡）與 `pending-nobudgetclock`（**取不到 `started_ts`**——
    r14 起改 fail-closed：取不到就當預算已用盡並停等，舊版是「守衛整個停用、照跑滿」，
    那是 fail-open）。兩者都記 C3=0。
    **全頁聚合**（r2）：`--paginate`＋`jq -s`——單頁上限 100，破百時後面幾頁的
    pending／failed 會整批看不到而誤報 allgreen。
  - **C4 判詞格式**：§2.1 的結果（格式失敗根本走不到這裡）。
- **行為分岔**：`AUTO_MERGE != "true"`（現況）⇒ **四條件齊時仍會送出 approving review**（r10 起：approve 移到閘門之後，齊了才核准），只是**不合併**；缺項則只留言、不核准。🔴 **不要讀成「什麼都不做只留言」**——核准是分支保護規則會消費的憑證，它留在 PR 上。r12 起核准與評估留言都綁被評估的 head，push 造成 head 變動時兩者都不送出——
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

### 2.3 熔斷 label 修復（**交付物已廢止，本節留作事故紀錄**）
> 🔴 2026-08-19 裁定取消熔斷後，本節描述的機制已不存在（label 建立／add-label／超輪分支
> 全部移除）。保留的理由是**那個失效形態**：「宣稱掛上了其實沒掛上、失敗被 `|| true` 吞掉」
> ——任何新的 label／狀態類機制都要照它設防。

- **事故**：舊註釋稱「label 不存在時 `--add-label` 會自動建立它」——**實測為假**
  （2026-08-18）。label 從未存在於 repo，add-label 每輪失敗又被 `|| true` 吞掉 ⇒
  PR #58 連續多輪 ⛔ 升級留言與照常驗收**並存**，熔斷從未真正生效；label 最終由
  人工補建（2026-08-18，`review:需人工裁定`，色 B60205）。
- **修法**：①先 `gh label create … || true`（冪等；已存在時的失敗是唯一可吞的）
  ②`gh pr edit --add-label` **不再吞錯**，失敗即留言講明「閘門此刻沒有生效」。
- 契約註釋同步更正（錯誤斷言不留原文）。

### 2.4 `scripts/await-verdict.sh`
- `bash scripts/await-verdict.sh <PR> <HEAD_SHA> [INTERVAL=900（限 900–1500）] [MAX_POLLS=8]`：
  每輪查**兩側是否都已對同一個 head 完成**（r2 重寫；原本兩側都只是 PR 全域條件）：
  ①**判詞就緒**＝該 head 的 `review` check-run `conclusion == success`
  **∧ 該 run 時間窗內存在一則合法判詞留言**（完整判準見下方同節「現行判準追加」段）——
  check-run 掛在 commit 上，天然綁 head，且完成後才出現 ⇒ 同時解掉「判詞留言是邊跑邊
  編輯、API 會回半截內容」的坑（2026-08-18 實測：8532 字元的判詞讀到 2933 字元、
  🟡 段整段不在裡面）。
  🔴 **只看 `completed` 不夠**（r6 修正；本摘要 r9 才補齊——終態文檔的開頭摘要與後段
  判準不同步，會讓人照摘要把已被否決的行為復原）：no-verdict 診斷路徑同樣是 job success；
  ②**Codex 已審該 head**＝**存在**一則 review 其 `user.login` 精確等於 connector 身分
  ∧ `commit_id` 精確等於該 head。雙到 exit 0；等滿升級 exit 4。
  🔴 **exit 5＝達總時鐘上限**（`DEADLINE_S`，預設 `MAX_POLLS×INTERVAL×2`，第 5 參數可覆寫）
  ——與 exit 4 的差別：4 是「輪次用完」，5 是「**牆鐘用完**」，後者涵蓋限流等待。
  限流仍然**不消耗輪次**（`i=$((i-1))` 不變），但整體由本上限保證有界終止。
  立法理由（研究實據，取證 2026-08-19）：GitHub 官方對 **primary** 限流**沒有**任何放棄
  門檻（只說等到 reset），對 secondary 才說「throw an error after a specific number of
  retries」——**次數而非時間**，且不覆蓋本案主要形態；缺口形狀取自 gRPC A6 的 deadline
  「applies across all attempts」。⚠️ 官方對本形態的首選建議是「Avoid polling」，
  本腳本收不到 webhook ⇒ 屬**已登記的合法偏離**。
  **exit 2 有三個獨立門檻**（r12 起不再是單一數字）：輪詢路徑連敗 **3** 次／起跑路徑連敗 **4** 次（`BASE_FAILS`）／起跑連續撞限額 **6** 次（`RATE_WAITS`）。
  🔴 **本腳本只做存在性判定、不數 inline 意見**（r9 澄清）：它回答「Codex 審完了沒」，
  不是「Codex 有沒有意見」。**意見數的聚合只存在於 `claude-review.yml` 的 C1**——
  兩者職責不同，不要把評估器的保證讀到這支腳本身上。
- **參數驗證全走 exit 2**（Codex #59 r1；#58 exact-head review `4973362395` 收緊）：PR 十進位、
  HEAD_SHA 十六進位 9–40 位、INTERVAL/MAX_POLLS 正整數、INTERVAL＝900–1500 秒——爛參數不得
  滑進循環變成假逾時、燒限額，或違反鐵律 17.1 的 15–25 分鐘窗。
- **額度路徑雙軌**（第 6 輪）：偵測到**已認證的 `gh`** 就走它（5000/小時），否則回退匿名
  urllib（60/小時）。回退分支必須留著——本腳本是本機工具，不保證每台機器都裝了 gh。
- **SHA 一律正規化成完整 40 位小寫**（Codex r3／r4）：API 回的 `commit_id` 是完整小寫，
  傳大寫或短前綴在精確比對下**永遠比不中**，症狀是白等整個輪詢窗後 exit 4（看起來像
  「審查方沒回應」）。短前綴以 API／`git rev-parse` 解析，解不出即 exit 2 不進輪詢。
- **判詞就緒＝job 成功 ∧ 該輪真有合法判詞**（Codex r3 起、r5 補完）：`completed` 涵蓋
  failure／cancelled／timed_out；而 `conclusion == success` **仍不夠**——workflow 在
  「Claude 沒貼結論」「作者不在允許清單」等路徑是**貼診斷留言後 exit 0**（該檔註釋自己
  寫著「失敗被下游 exit 0 吞掉」）⇒ job success 卻零判詞。現行判準追加：存在一則作者在
  允許清單 ∧ 首行整行匹配合法結論形（理由不得全空白）∧ **落在該 check-run 的時間窗內**
  ——`started_at ≤ created_at ≤ completed_at＋5 分鐘餘裕`（r6 修正：只設下界的話，
  舊 commit 的 workflow 事後人工 rerun 貼出的判詞照樣通過；上界擋掉事後 rerun。
  留言無 commit 關聯欄位，run 時間窗是現行唯一可用的關聯鍵；根治＝判詞契約帶 SHA，
  屬 workflow 側待辦）。
  **正反實測**：有真判詞的 head 報 1；反竄改自跳（success 但無判詞）的 head 報 0。
- **非 Windows 可用性**（Codex r5，P1）：gh 偵測用 `${PROGRAMFILES:-}`——`set -u` 下
  Linux／macOS 沒有該變數，直接展開會在**偵測階段就 unbound variable 退出**，兩條路都跑不到。
- **參數前導零**（Codex r5）：`00` 會通過非零檢查卻讓迴圈一次不跑（假逾時）、`08` 會被
  bash 當八進位而算術報錯 ⇒ 兩者一律 exit 2（實測皆 2）。
- **認證路徑被限流不得靜默回退**（Codex r5）：gh 被限流時偵測 stderr 並查 `rate_limit`
  取 reset 後上報等待，不再退回只有 60 額度的匿名路徑（那會把「等一下就好」變成連續失敗）。
- **起跑即齊備就立刻退出**（Codex r3）：主循環第一件事是 sleep，舊版會讓「掛上去時兩側
  早已完成」白等一個 INTERVAL。
- **起跑也有重試預算**（Codex r4；r12 改雙計數）：單次暫時性故障不再直接 exit 2
  （契約說 exit 2 是「持續不可用」）。🔴 **與輪詢路徑的數字不同、刻意的**：起跑路徑用
  **兩個獨立計數**——`BASE_FAILS`（暫時性 API 失敗，上限 4）與 `RATE_WAITS`（限流等待，
  上限 6）；限流**不消耗失敗預算**，但自己有界，否則「等完仍被限流」會無限打轉
  （r12 首版即如此，自檢時抓到）。
- **限流是可恢復狀態、不是故障**（第 4 輪自報實測）：撞 60/hr 未認證上限時，讀
  `X-RateLimit-Reset` 等到重置再續，**不計入失敗也不消耗輪次**（上限 `RATE_WAIT_MAX`
  兜底）。舊版把它當解析失敗直接 exit 2——同日診斷查詢把額度用光後，poller 起跑即
  假性失敗。**判別法兩段式**（r13 起）：先讀被拒回應的 `Retry-After`（秒數形）——它涵蓋
  **secondary** 限流（該情況下 `X-RateLimit-Remaining` 可能仍為正數）；拿不到才退回
  `X-RateLimit-Remaining: 0` ＋ `X-RateLimit-Reset` 的 **primary** 判準。
  **primary 與 secondary 分開**（r8）：secondary（突發／abuse）的冷卻與 core 窗 reset
  無關——拿 `.resources.core.reset` 充數會睡到不相干的整點、或重試耗盡而 secondary 還在生效。
  **冷卻讀被拒回應的 `Retry-After` 標頭**（r9）：**只在失敗路徑**重發一次同一請求並帶
  `--include`（成功路徑絕不加，會汙染 JSON 流），拿不到才退回固定 120 秒。
  ✅ 可行性實測（2026-08-19，gh 2.97.0）：失敗回應同樣把狀態行與標頭印到 stdout、
  錯誤訊息走 stderr、exit 1 ⇒ 標頭拿得到。複驗：
  `gh api --include repos/<owner>/<不存在的名字>` 看 stdout 首行是否為 `HTTP/2.0 404 Not Found`。
- **分頁**（Codex #59 r1）：留言破百的 PR 只看第一頁會永遠等不到新判詞——逐頁抓到
  不足 100 則為止（理智上限見腳本具名常數 `HARD_PAGE_CAP`＝100 頁，兩個 pager 共用；觸頂＝APIERR 大聲失敗，不裝作讀完）。
- 🔴 實作紀律寫在檔頭：JSON 由 **python 直接抓取＋UTF-8 顯式解析、輸出只回 ASCII
  計數**（Windows cp950 管道解 CJK JSON 靜默出錯，同日兩次實測）；未認證 API
  **60 次/小時/IP 跨工具共用** ⇒ 額度估算原先只設 300 秒下限；現由鐵律 17.1 的
  900–1500 秒區間收緊，腳本硬擋區間外值。
- **未登記進 `config/ci.rb` 的 `step` 清單，故不是驗收閘門**——它是操作工具，刻意的。
  複驗：`grep -n await-verdict config/ci.rb .github/workflows/ci.yml`（應無命中）。
  <!-- 🔴 2026-08-19 更正（#59 r12 掃描）：原文寫「不匹配閘門 selector（`^(check|test|lint)-`）」，
       那是錯的——全樹唯一的該正則是 `scripts/check-doc-claims.rb` 的 `BARE_SCRIPT`，用途是
       R1 的「裸檔名一律當成對 scripts/ 的斷言」偵測，**不是任何閘門的 selector**；
       閘門是 `config/ci.rb` 逐條列舉的 `step`。 -->

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
- **待真實 PR 取證**（本 PR 自身因反竄改自跳驗收，取證不到）：格式驗證與評估器
  留言要在下一個「通過」的常規 PR 上看到，列入本包 Pending，不宣稱已驗。
  ⚠️ 原本還有第 ② 項「熔斷 add-label 生效路徑要在下一次超輪事件上看到」，
  **隨 2026-08-19 取消熔斷刪除**——該證據的對象已不存在。

## 4. 跨功能／跨流程影響（預先對接）

- **所有後續 PR 的 quality job**：base 拿不到會**當場紅**（先前靜默綠）——分支
  剛開、遠端 base 改名等情況會顯性失敗，這是刻意的；修法是把 base 餵對，不是拿掉旗標。
- **判詞格式走樣＝review job 紅**（先前綠）：驗收方產出走樣會第一時間可見。
- 🔴 **驗收循環不再有輪數上限**（2026-08-19 裁定取代原「熔斷真正生效」段）：
  `MAX_FIX_ROUNDS`、job 層 label 閘門、超輪分支皆已移除 ⇒ **`review:需人工裁定`
  對機制完全無作用**，殘留在既有 PR 上的直接移除即可，不必再把「label 在不在」
  當成狀態。終止條件只剩一個＝**雙清**（bot 🔴0🟡0 ∧ Codex 對當前 head inline 總和 0）。
  ⚠️ 代價誠實寫明：沒有任何機制保證輪數收斂，配套＝把復發的意見類型固化成確定性腳本。
- **`gh pr checks` 消費者**（驗收 bot prompt 的 CI-as-evidence 段）：不受影響，
  check 名稱與結論語義未動；評估器另走 check-runs API。
- **18.4 啟用時**（未來裁定）：只翻 `AUTO_MERGE` 是不夠的——workflow 頂部與
  contents 權限註釋列了配套（`contents: write`、approve 設定）；評估器屆時自動
  從「證據留言」升為「合併硬閘」，無需再改代碼。
- **與 PR #58 的檔案交集**：`check-doc-claims.rb`／`test-doc-claims-rules.rb` 兩檔
  #58 分支也改過（IN_SCOPE 擴充與 canary CASE）——改動落在不同 hunk（旗標區 vs
  範圍區；G3 vs fixture CASES 表），git 預期可自動合併；後合併的一方要重跑
  `test-doc-claims-rules.rb` 確認兩組改動疊加後仍綠。
