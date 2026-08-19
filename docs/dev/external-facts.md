# 已查證的外部事實（GitHub API／git／bash／MSYS2／CommonMark／限流）

> **這份檔案是給誰看的**：Codex、Claude bot、以及任何接手的工作階段。
> 三方對**外部服務語義**的認知原本只能來自各自的訓練資料，而那正是本專案錯誤最集中的地方
> （立法理由與事故紀錄見 `AGENTS.md` §8）。這裡收錄**已經查證、附官方原文與取證日期**的事實，
> 推論到這些主題前**先讀它**。
>
> 🔴 **使用規則（三條，缺一這份檔案就會變成新的錯誤來源）**：
> 1. **它會過期**。與你查到的官方原文不符時，**以官方原文為準**，並指出本檔哪一條已過期。
>    過期是它的已知性質，不是缺陷——但發現了不更正就是。
> 2. **只收「查得到原文」的事實**。推論、經驗法則、我們自己的裁定**不進這裡**
>    （那些屬 `CLAUDE.md` 鐵律或 `docs/specs/91-pit-register.md`）。
> 3. **原文一律留英文逐字**，中文只做說明。翻譯會流失語義——本檔多條事實的要害
>    正好在 pertains to／must match、push／reviewable push 這種措辭差異上。
>
> 建立：2026-08-19（使用者裁定「把已查證的外部事實寫進倉庫」）。
> 全部條目經**獨立第二輪複核**（重查 URL、比對逐字原文），複核發現 1 條原斷言為 WRONG、
> 6 條有過度宣稱，均已更正——詳見各條的「⚠️ 精度」。

---

## A. GitHub：核准（approve）沒有前置條件，合併（merge）有

### A1. `POST /pulls/{n}/reviews` 的 `commit_id` **不是**樂觀鎖

> `commit_id string` — "The SHA of the commit that needs a review. Not using the latest commit SHA
> may render your review comment outdated if a subsequent commit modifies the line you specify as
> the position. **Defaults to the most recent commit in the pull request when you do not specify a value.**"
>
> 狀態碼表逐字：`200 OK` ／ `403 Forbidden` ／ `422 Validation failed, or the endpoint has been spammed.`

來源：<https://docs.github.com/en/rest/pulls/reviews?apiVersion=2022-11-28>（取證 2026-08-19）

🔴 **要害**：措辭全部圍繞「comment outdated／position」，**沒有任何前置條件語義**；
未指定時是**預設帶入最新 commit**而非拒絕；**狀態碼表裡沒有 409**。
⇒ **傳 `commit_id` 不會讓 API 在 head 已前進時拒絕核准。它不能當 head 綁定機制。**

📌 **本專案事故**：2026-08-19，驗收方查了 `gh pr review --help`（觀察正確：該 CLI 確實沒有
head 前置條件旗標），據此**推論**改用 REST 的 `commit_id` 就能綁定，作者照做並寫進註釋
「不再需要賭時間窗」——查證後證明該推論錯誤，假修復已進 main，補審才抓出。

### A2. GitHub REST 對 POST 等 unsafe method **不支援條件式請求**

> "Conditional requests for unsafe methods, such as POST, PUT, PATCH, and DELETE **are not supported**
> unless otherwise noted in the documentation for a specific endpoint."

來源：<https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api?apiVersion=2022-11-28>（取證 2026-08-19）

⚠️ **精度**：該頁的條件式請求段落**只講 GET**（`etag`+`if-none-match`、`last-modified`+`if-modified-since`），
且**全頁不存在 `If-Match` 這個字**。原文留了「除非個別端點另有註明」的例外
⇒ 要主張某端點支援，**必須在該端點頁面找到明文**，不得援引通則。

### A3. `PUT /pulls/{n}/merge` 的 `sha` **是**樂觀鎖，且有專屬 409

> `sha string` — "**SHA that pull request head must match to allow merge.**"
> 狀態碼逐字包含：`409 Conflict if sha was provided and pull request head did not match`

來源：<https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28>（取證 2026-08-19）

### A4. GraphQL 同構：merge 有、review 沒有

> `MergePullRequestInput.expectedHeadOid` — "OID that the pull request head ref **must match to allow merge**;
> **if omitted, no check is performed.**"
> `AddPullRequestReviewInput.commitOID` — "The commit OID the review **pertains to**."

來源：GitHub 官方公開 GraphQL schema <https://docs.github.com/public/fpt/schema.docs.graphql>（取證 2026-08-19）

🔴 **A1／A3／A4 合起來的結論**：head 前置條件原語**只掛在合併，一個都沒掛在核准**。
**任何「用 approve 端點做 head 綁定」的設計，都是在原文沒有承諾的地方假設保證。**

### A5. `dismiss_stale_reviews`：API 層與概念層措辭**不一致**，且觸發不只推送

> **API 層**（事件式）— "Set to true if you want to automatically dismiss approving reviews
> **when someone pushes a new commit**."
> **概念層**（狀態式）— "GitHub **records the state of the diff at the point when a pull request is
> approved**… If the diff changes from this state (for example, because a contributor pushes new
> changes to the pull request branch **or clicks Update branch**, or because **a related pull request
> is merged into the target branch**), the approving review is dismissed as stale…"

來源：<https://docs.github.com/en/rest/branches/branch-protection> 與
<https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches>（取證 2026-08-19）

🔴 **實作影響**：照 API 描述建模的人會以為「沒人 push 就不會 stale」，
但概念層的條件寫的是 **"If the diff changes from this state"**——push 只是括號內
**"for example"** 三個例子之一（另兩個是 **"clicks Update branch"** 與 **"a related pull
request is merged into the target branch"**）⇒ **不碰本 PR 也可能失效**。
⚠️ **不得反過來讀成「任何人合併到 base 都足以讓核准失效」**：原文的條件是 **diff 改變**，
合併只是**可能造成**該改變的例子，限定詞還是 **related**；不改變本 PR diff 的無關合併，
**現有原文並不支持**核准一定被 dismiss。
本輪重新檢查 GitHub 官方 rulesets 文件（取證 2026-08-19），逐字仍只寫
**"If the merge base changes, the pull request cannot be merged until someone approves the work again."**；
這能證成合併前置條件，不能證成內部狀態在何時求值，也不能升格成「官方從未公布」的全稱結論。
來源：<https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>。
求值時機的未決推論與受控驗證方案見 `docs/specs/91-pit-register.md` §3.4；本檔只保留上述官方原文能支持的證據邊界。
rulesets 的 API 措辭同樣是事件式（"New, reviewable commits pushed will dismiss…"），
而其概念頁與 about-protected-branches 用同一段狀態式文字。

📌 **「related」為什麼是承重詞（官方 changelog，取證 2026-08-19）**：
> "The branch protection for dismissing stale reviews now dismisses approvals **whenever a merge
> base changes** after a review." ／ "The merge base of a pull request is the **closest common
> ancestor** of both the target and source branches for that pull request." ／ "Merge bases changing
> under a pull request will **preserve approvals in most situations where no new changes are introduced**."

來源：<https://github.blog/changelog/2023-06-06-security-enhancements-to-required-approvals-on-pull-requests/>（取證 2026-08-19）

⇒ 觸發被綁在 **merge base 改變**上；無關 PR 合入 target 只讓 target 前移，**不動**本 PR 的最近共同祖先。
⚠️ **精度**：changelog 的 "whenever a merge base changes" 與概念頁的「條件＝diff 改變」**措辭仍不一致**，
且 "in most situations" 留了餘地 ⇒ **正反兩個方向都不得寫成保證**，本條只否掉「任何 base merge 必然 dismiss」。

### A6. `require_last_push_approval`：措辭是狀態謂詞，但**官方自承比 dismiss stale 鬆**

> **Rulesets API** — "Whether the **most recent reviewable push** must be approved by someone other
> than the person who pushed it."
> **Branch protection API** — "Whether the **most recent push** must be approved by someone other
> than the person who pushed it. Default: false."
> **概念層** — "…at least one other authorized reviewer has approved any changes."

來源：<https://docs.github.com/en/rest/repos/rules>、<https://docs.github.com/en/rest/branches/branch-protection>、about-protected-branches（取證 2026-08-19）

⚠️ **精度**：兩處 API 措辭**不同**——branch protection 寫 "the most recent **push**"，
rulesets 與概念層寫 "the most recent **reviewable** push"。`reviewable` 是實質限定詞。

🔴 **官方對兩者取捨的原話（直接關係到「怕核准被劫持該用哪個」）**：
> "with this option, **\"stale\" reviews are not dismissed**, and the pull request remains approved
> as long as someone other than the person who made the most recent changes approves it…
> **If you are concerned about pull requests being \"hijacked\"** (where unapproved content is added
> to approved pull requests), **it is safer to dismiss stale reviews.**"

⇒ 官方明說：怕 hijack 就用 **dismiss stale**，不要只靠 last-push-approval。

### A7. GitHub 官方的 Dependabot 自動核准範例，**零 head 複驗**

> `run: gh pr review --approve "$PR_URL"`（該 workflow 全文無任何 head SHA 比對）

來源：<https://docs.github.com/en/code-security/dependabot/working-with-dependabot/automating-dependabot-with-github-actions>（取證 2026-08-19）

⇒ **本頁不只是「一份沒做 head 複驗的範例」——它同一頁就明文把閘門開在合併**：
> "**If you use status checks to test pull requests, you should enable Require status checks to pass
> before merging for the target branch for Dependabot pull requests.**"
> 同頁對 auto-merge 的定義 — "This enables the pull request to be merged **when any tests and approvals
> required by the branch protection rules are successfully met**."

同日另取三份獨立來源，措辭一律以**合併**為界（**不是**我方外推）：
> GitHub 分支保護 — "After enabling required status checks, **all required status checks must pass before
> collaborators can merge changes into the protected branch.**"
> <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches>（取證 2026-08-19）
> OpenSSF Scorecard 的 Branch-Protection 分級 — "Require at least 1 reviewer for approval **before merging**"／
> "Require branch to be up to date **before merging**"／"Require branch to pass at least 1 status check **before merging**"
> <https://github.com/ossf/scorecard/blob/main/docs/checks.md>（取證 2026-08-19）
> Renovate — "By default, Renovate **will not automerge until it sees passing status checks / check runs**
> for the branch." <https://docs.renovatebot.com/key-concepts/automerge/>（取證 2026-08-19）

⚠️ **精度（本條只能說到這裡）**：以上支持的是「**官方指引與通行安全基準把閘門定在合併**」，
**不支持**「業界普遍如此」——後者要抽樣調查，我方沒做 ⇒ 原句的「業界做法」是單例外推，已刪。
「核准那一步守不住」不是新斷言，是 A1／A4 的直接後果（核准端沒有 head 前置條件原語）。
「合併時**重新**求值」的強形式（真的重跑）只在 strict 模式與 merge queue 成立：
> "The merge queue will ensure the pull request's changes pass all required status checks
> **when applied to the latest version of the target branch** and any pull requests already in the queue."
> <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue>（取證 2026-08-19）

required check 對新 head 的效果另有官方明文：
> "**Required checks must pass on the latest commit SHA. Checks from earlier commits don't satisfy the requirement.**"
> <https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks>（取證 2026-08-19）

⚠️ **精度**：這句支持的是「先前 commit SHA 的檢查結果不能滿足 latest commit SHA」，**不是重新執行**。
同頁另區分 test merge commit 有／無 status 的兩種判準：有 status 時看 test merge commit，沒有才看
head commit；因此原句一概稱「合併當下的 head」也過寬，已刪。

### A8. auto-merge 的停用條件——⚠️ 本條原斷言被複核判為 **WRONG**，已更正

> "Auto-merge is disabled if someone without write permissions pushes new changes to the head branch
> **or switches the base branch**."
> "**People with write permissions to a repository and pull request authors can disable auto-merge**
> for a pull request."

來源：<https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request>（取證 2026-08-19）

🔴 **原斷言「只會因無寫入權限者推送而停用」是錯的**：官方那句列了**兩個**觸發（還有切換 base），
另有**手動停用**路徑。
⚠️ **原文有文法歧義**：「if someone without write permissions pushes new changes to the head branch
or switches the base branch」可讀成「無寫入權限者推送」OR「任何人切換 base」，
也可讀成無寫入權限者「推送或切換 base」——**官方未釐清，不得把任一讀法寫成確定事實**。
🔴 但無論哪種讀法，**有寫入權限者推送新 commit 依本頁原文不會停用 auto-merge**
⇒ **auto-merge 本身不是 head 變動的防護**。
📌 本頁**未提及**「PR 產生衝突／變成不可合併」是否停用——屬未涵蓋，不是已否定。

---

## B. 工具鏈：退出碼、路徑轉換、Markdown、限流

### B1. `grep -c` 無匹配時 stdout 印 `0` 而退出碼是 `1`

> POSIX EXIT STATUS — "0 One or more lines were selected… **1 No lines were selected.** >1 An error occurred."
> POSIX `-c` — "Write only a count of selected lines to standard output."

來源：<https://pubs.opengroup.org/onlinepubs/9799919799/utilities/grep.html>、
<https://www.gnu.org/software/grep/manual/grep.html>（取證 2026-08-19）

⚠️ **精度（複核指出的過度宣稱）**：**沒有任何一份官方文件用一句話寫出「`-c` 無匹配時印 0 且退出碼 1」**
——這是兩條規則相加的結果（退出碼只看「有沒有行被選中」，完全不看輸出；`-c` 的輸出格式無條件是計數）。
引用時不得寫成「官方明文規定」。

🔴 **本專案的用途**：這解釋了為什麼 `<某命令> | grep -c X` 是 fail-open——
前段失敗時空 stdin 進 `grep -c`，stdout 一樣印 `0`，而 `0` 恰好等於「識別字已移除」的期望讀數。

### B2. git 的 `die()` 退出碼是 `128`

> "`die` is for fatal application errors. It prints a message to the user and **exits with status 128**."
> "`usage` is for errors in command line usage… it exits with status 129."

來源：<https://github.com/git/git/blob/master/Documentation/technical/api-error-handling.adoc>（取證 2026-08-19）

⇒ `git show <不存在的 ref>:<path>` 走 die()／128，訊息只到 stderr。

### B3. bash `pipefail` 取的是「最右邊那個**失敗**的指令」

> "The exit status of a pipeline is the exit status of the last command in the pipeline, unless the
> pipefail option is enabled… If pipefail is enabled, the pipeline's return status is the value of
> **the last (rightmost) command to exit with a non-zero status**, or zero if all commands exit successfully."

來源：<https://www.gnu.org/software/bash/manual/html_node/Pipelines.html>（取證 2026-08-19）

⚠️ **精度**：「非零」這個限定詞**不可省略**——是「最右邊的**失敗**指令」，不是「最右邊的指令」。

🔴 **推論（標為推論，非官方明文）**：因此 `git show <badref>:<f> | grep -c X` 在 pipefail 下，
git 的 128 會被 grep 的 1 **蓋掉**（grep 較右且非零）⇒ 與「識別字真的不在」同形，
**pipefail 對這個情境零鑑別力**。本專案已實測驗證此推論。

### B4. MSYS2 會轉換「看起來像 Unix 路徑」的參數，且**加引號無效**

> "When calling native executables from the context of Cygwin, then all the arguments that look like
> Unix paths will get auto converted to Windows."
> 逃生口：`MSYS2_ARG_CONV_EXCL`（分號分隔的前綴白名單，`*` 代表全部排除）；
> Git for Windows 另有 `MSYS_NO_PATHCONV`。

來源：<https://www.msys2.org/docs/filesystem-paths/>、
<https://github.com/git-for-windows/msys2-runtime/blob/HEAD/winsup/cygwin/msys2_path_conv.cc>（取證 2026-08-19）

⚠️ **精度（複核指出）**：**官方文件沒有精確枚舉「什麼形式會被轉換」**，只有一句
"arguments that look like Unix paths"。真正的判定規則只存在於 `msys2_path_conv.cc` 的原始碼裡
⇒ 任何列出精確形式的說法都應標為「讀原始碼推得」而非官方明文。

🔴 **原始碼裡的明文豁免**（可引用）：`/* Prevent Git's :file.txt and :/message syntax from beeing modified. */`
——**以冒號開頭的參數不轉換**。
🔴 **加引號無效**：轉換發生在 runtime 組 win32 argv 時，shell 引號早已被消化。

### B5. code span 內不做任何 inline 解析，反斜線轉義也失效

> "Code span backticks have **higher precedence than any other inline constructs** except HTML tags and autolinks."
> "Note that **backslash escapes do not work in code spans**. All backslashes are treated literally."

來源：CommonMark 0.31.2 §6.1 <https://spec.commonmark.org/0.31.2/>；
GFM 規範同文 <https://github.github.com/gfm/>（取證 2026-08-19，已與 cmark-gfm 上游規範檔
<https://github.com/github/cmark-gfm/blob/master/test/spec.txt> 逐字比對——**該路徑屬外部倉庫，
不在本倉庫樹上**，故不寫成 code span，避免 `check-doc-claims.rb` R1 誤判為本倉庫路徑）

🔴 **實務後果**：寫在反引號裡的 `**2**` 會**原樣顯示**（GitHub `/markdown` API 實測確認）。
⇒ 文件裡的「預期輸出」若含 `**`，會與終端機實際輸出**字面不符**；
要強調就把粗體包在 code span **外**，不要塞進去。

### B6. 限流：primary 明列 reset 時點；secondary 另明列有限次重試

> primary — "If you exceed your primary rate limit, you will receive a 403 or 429 response, and the
> `x-ratelimit-remaining` header will be 0. **You should not retry your request until after the time
> specified by the `x-ratelimit-reset` header.**"
> secondary — "…wait for an exponentially increasing amount of time between retries, and
> **throw an error after a specific number of retries**."

來源：<https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api>、
<https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api>（取證 2026-08-19）

🔴 **證據邊界**：primary 的上列逐字只支持「reset 時點之前不要重試」，**不支持**把客戶端的
總重試次數或總時間寫成「不存在」；有限頁面的檢索也不能證明不存在。secondary 的上列逐字則
明載 exponential wait 與 specific number of retries，但沒有替本專案指定那個數值。
⇒ 長時間輪詢是否另設 deadline／次數界線是**本專案的設計決定**，不是可由這兩段官方原文推出的
GitHub 契約；未決證據邊界登記於 `docs/specs/91-pit-register.md` §3.4。

另有一句該當警語引用：
> "**Continuing to make requests while you are rate limited may result in the banning of your integration.**"

### B7. 官方建議「Avoid polling」——但**是建議、附降級路徑，不是禁止**

> 章節標題 "Avoid polling"；"You should subscribe to webhook events instead of polling the API for data."
> 緊接著："**If you cannot use webhooks and you must poll the API**, poll as efficiently as possible…"

來源：同 B6 的 best-practices 頁（取證 2026-08-19）

⚠️ **精度**：官方自己給了「不能用 webhook 就盡量有效率地輪詢」的降級路徑
⇒ 引用時不得寫成「官方禁止輪詢」。

### B8. gRPC：deadline 是**跨所有 attempt 的硬上限**，retry policy 延長不了它

> "gRPC's call deadline **applies across all attempts for a given RPC**. For example, if the specified
> deadline for an RPC is July 23 9:00:00pm PDT the operation will fail after that time **regardless of
> how many attempts were configured or attempted**."

來源：<https://github.com/grpc/proposal/blob/master/A6-client-retries.md>（取證 2026-08-19）

🔴 **可借的設計形狀**：A6 把三件事拆開——`retryThrottling`（准不准重試）／`maxAttempts`（最多幾次）／
**deadline（整件事何時必須結束）**。「暫時性錯誤不算失敗」屬前兩者，**「有界」只能由 deadline 表達**。
⇒ 想用「次數上限」表達「時間有界」是**維度用錯**：一次等待可長可短，同一個次數在真實時間上可差數個量級。
