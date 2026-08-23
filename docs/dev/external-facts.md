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

### A9. resolved thread 不是獨立核准，review body 也不是 inline thread

<!-- 🔴 2026-08-22 反向指標（合併 PR #64 時加）：PR #64 在其分支期間也用 `A9` 這個編號，內容完全不同；
     合併時已改編為 **`A16`**（見本檔該節）。歷史 worklog 若以 `A9` 指涉 `gh api`／`git log` 那一族內容，指的是 `A16` 而不是本節。 -->

GitHub 官方對 conversation 權限逐字寫（節錄）：

> "if you opened the pull request or if you have write access"
>
> "The entire conversation will collapse and be marked as resolved."

來源：<https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/commenting-on-a-pull-request>（取證 2026-08-21）

GraphQL schema 對 `PullRequestReviewThread` 的欄位逐字只定義狀態：

> `isResolved` — "Whether this thread has been resolved."
>
> `isOutdated` — "Indicates whether this thread was outdated by newer changes."
>
> `resolvedBy` — "The user who resolved this thread."

來源：<https://docs.github.com/en/graphql/reference/pulls>（取證 2026-08-21）

官方 webhook 文件另外把 review 定義為：

> "A pull request review is a group of pull request review comments in addition to a body comment and a state."

來源：<https://docs.github.com/en/webhooks/webhook-events-and-payloads>（取證 2026-08-21）

🔴 **證據邊界**：官方只說 thread 是否被 resolved，且 PR 作者本身就有 resolve 權；因此
`isResolved=true` 不能單獨證明獨立 reviewer 已接受修法。review body 又是 review comments 之外的
獨立構成，故只讀 inline／thread 也不能證明沒有 body-only finding。

📌 **本專案設計決定（不是 GitHub 保證）**：C1 同時保留未解 thread 為零，並要求全量讀每則
review body，再取得建立於當前 head 最後 finding 之後的 reviewer-controlled 乾淨 completion；
未知 body 或缺少較晚 completion 一律 fail-closed。這是為補上作者可 resolve 與 body 分流兩個缺口。

### A10. Codex 的 reaction 不取代 GitHub review

<!-- 🔴 2026-08-22 反向指標（合併 PR #64 時加）：PR #64 在其分支期間也用 `A10` 這個編號，內容完全不同；
     合併時已改編為 **`A17`**（見本檔該節）。歷史 worklog 若以 `A10` 指涉 `gh api`／`git log` 那一族內容，指的是 `A17` 而不是本節。 -->

OpenAI 官方 Codex GitHub 指南在「Request a Codex review」步驟逐字寫：

> "Wait for Codex to react (👀) and post a review."
>
> "Codex posts a review on the pull request, just like a teammate would."

來源：<https://learn.chatgpt.com/docs/third-party/github>（取證 2026-08-21）

🔴 **證據邊界**：官方把 reaction 與 review 並列，沒有說 reaction 本身是綁 commit 的乾淨審核，
也沒有保證對**同一 SHA**重複請求必定產生一則更晚 review。因此本專案只把 reaction 當觸發／
排隊輔助訊號，不得把 👀、👍 或其他 reaction 解讀成獨立核准。官方沒有定義 GitHub 載體或
head-binding 欄位；本倉庫觀察到的 clean issue
comment 契約另記於 `docs/dev/m0-review-convergence.md`，不得冒充官方保證。沒有可由受控載體綁
exact head 的結果時 C1 fail-closed。若有 finding 但處置不改 tree，只送一次 same-head 請求；
有界 deadline 內沒有
更晚 completion（包含 connector 去重）時 C1 保持 0，轉獨立人工審核／人工合併，不造新 head。

### A11. `gh pr checks` 的 watch 沒有文件化 deadline，bucket 可區分等待、失敗與合併就緒

GitHub CLI 官方手冊逐字寫：

> "Show CI status for a single pull request."
>
> `--watch` — "Watch checks until they finish"
>
> `--fail-fast` — "Exit watch mode on first check failure"

同頁並明列 JSON `bucket` 可能值為 `pass`、`fail`、`pending`、`skipping`、`cancel`，且另列：

> "Additional exit codes: 8: Checks pending"

來源：<https://cli.github.com/manual/gh_pr_checks>（取證 2026-08-21）

🔴 **證據邊界**：官方列出的 watch 相關旗標只有 interval 與 fail-fast，沒有 deadline／timeout；
`--fail-fast` 只承諾第一個 failure 時退出，不能保證 pending 永遠不結束時有界終止。

📌 **本專案使用邊界**：`gh pr checks` 的查詢對象是 PR，不是固定 SHA；自動化以
`--json name,bucket,link` 作有界間隔輪詢時，每輪查詢**前後**與凍結 ledger 前都要重取 PR
`headRefOid` 並與候選 SHA 精確相等，否則丟棄該輪結果、以 head drift 非零終止。不直接用 `--watch`。
零個 check 的集合在 deadline 內仍視為尚未開始並繼續等，deadline 到期才記證據未取得／C3=0；
不能對空集合做 vacuous all-pass，也不能把 CLI 的 no-check 訊息當作可立即終止的 API 故障。
`pending` 是等待；此時 `gh pr checks` 的退出碼 8 是文件化狀態，不是 API failure。消費者須先解析
已取得的 JSON bucket，再決定等待／finding／完成；不得讓 shell 的一般非零退出處理在讀 JSON 前
終止。只有 JSON 未取得／不可解析或傳輸失敗才走 API failure。終態 `fail` 是已取得的 CI finding，
可凍結進 ledger 後修復；API／deadline 才是證據未取得。`skipping`／`cancel` 同 head rerun 一次後仍
轉人工。合併判定另要求**非空集合**所有 bucket 均 `pass`，並重取 PR `headRefOid` 與候選 SHA 精確相等。

### A12. review 與 issue comment 的時間欄位不同；跨端點 ID 不作先後順序

GitHub REST reviews 官方頁逐字寫：

> "The list of reviews returns in chronological order."
>
> `"submitted_at": "2019-11-17T17:43:43Z"`

同頁另明載 PENDING review 尚未 submit，因此 response 不含 `submitted_at`。來源：
<https://docs.github.com/en/rest/pulls/reviews>（取證 2026-08-21）。

GitHub REST issue comments 官方 response example 使用：

> `"created_at": "2011-04-14T16:00:49Z"`

來源：<https://docs.github.com/en/rest/issues/comments>（取證 2026-08-21）。

🔴 **本專案使用邊界**：0e 把已提交 review 的 `submitted_at` 與 issue comment 的 `created_at`
解析成 UTC event time，clean completion 必須**嚴格晚於**最後 current-head finding。跨端點的數字 ID
沒有官方全域排序契約，只作各自載體的身分、去重與 endpoint-local 水位，不拿來比較 review 與
issue comment 的先後；時間欄缺失、無法解析或相等時一律 fail-closed。PENDING review 不構成 completion。

### A13. workflow run／job／check-run 提供可綁 head 與排除 evaluator 自身的精確身分

GitHub Actions variables 官方頁逐字寫：

> `GITHUB_RUN_ID` — "A unique number for each workflow run within a repository."
>
> `GITHUB_RUN_ATTEMPT` — "A unique number for each attempt of a particular workflow run in a repository."
>
> `GITHUB_SHA` — "The commit SHA that triggered the workflow."

同頁說 `GITHUB_RUN_ID` 在 re-run 時不變，而 `GITHUB_RUN_ATTEMPT` 每次 re-run 遞增；`GITHUB_SHA`
的實際 commit 依觸發事件而異，所以本專案不把它不加判別地等同 PR head。來源：
<https://docs.github.com/en/actions/reference/workflows-and-actions/variables>（取證 2026-08-21）。

GitHub 的 `pull_request` 事件頁另逐字區分 merge SHA 與 head SHA：

> "`GITHUB_SHA` is the SHA of the merge commit on the merge branch"
>
> "To test only the head branch commits without simulating a merge, check out the head branch using
> `github.event.pull_request.head.sha` in your workflow."

來源：<https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows>
（取證 2026-08-21）。所以 0f 的 candidate 必須明取 `github.event.pull_request.head.sha`，不得從
`GITHUB_SHA` 猜。

Workflow runs REST 的 `head_sha` 查詢參數逐字是：

> "Only returns workflow runs that are associated with the specified `head_sha`."

來源：<https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28>（取證 2026-08-21）。

Workflow jobs REST 的官方 response 同時提供 `id`、`run_id`、`head_sha` 與 `check_run_url`；check-runs
REST response 則提供 `id`、`head_sha`、`status` 與 `conclusion`。來源：
<https://docs.github.com/en/rest/actions/workflow-jobs>、
<https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28>（取證 2026-08-21）。

⚠️ **官方缺口與本倉庫實證分開寫**：上面的 workflow-runs 文件只定義 `head_sha` 查詢參數，沒有
逐字定義 `pull_request` run response 的 `head_sha` 一定等於 PR head；不得從欄位名自行外推。
本倉庫 PR #66 的 run `32463413197`（2026-08-21）原始 REST 回應實得
`event=pull_request`、`head_sha=ae41a51a6b69e45a2aa5e225e748fc9a9fe5fd24`，其
`pull_requests[0].number=66` 與 `.head.sha` 也是同一值；job `96714869405` 及其
`check_run_url` 指向的 check-run 回應也各自回同一 `head_sha`。同一時點 PR API 的 `.head.sha`
相同，而 `.merge_commit_sha=8e8e3f95d8895b275f725c47e3bc5e4c2749aec6`，兩者可區分。複驗：

```bash
gh api repos/pisceshei/chilllovesaas/actions/runs/32463413197
gh api --paginate repos/pisceshei/chilllovesaas/actions/runs/32463413197/jobs
gh api repos/pisceshei/chilllovesaas/check-runs/96714869405
gh api repos/pisceshei/chilllovesaas/pulls/66
```

這是**具名倉庫／run 快照，不是 GitHub 永久語義保證**；未來回應不再同形時必須 C2=0，不得改成
猜測或時間窗 fallback。

🔴 **本專案使用邊界**：0f 以受信任 workflow 產生 `run_id`／`run_attempt`／candidate
（精確取 `github.event.pull_request.head.sha`）／`verdict_comment_id`／`verdict_body_sha256` 的
run-specific evidence；comment ID 與 body hash 必須同時存在，不是二選一。0e 依 run id 取原始
回應，要求 `event=pull_request`、`run_attempt` 與 evidence 精確相等、`pull_requests[]` 中恰有目標
PR 且其 `head.sha == candidate`，並以 run／job／check-run 的 `head_sha == candidate` 作本倉庫
canary；**job 只能取自 attempt-specific 端點、check-run 只能沿該 job 的 `check_run_url`**（端點
差異與 attempt 語義見 A15）；
任一缺失、多義或不等即 C2=0，`head_sha` 單欄與時間窗都不能獨立證明綁定。body 不可變綁定
另見 A14。C3 只排除 workflow
jobs `check_run_url` 指出的 evaluator 精確 check-run ID；不得只按 `name=review` 排除。排除後
eligible 集合仍須非空且全部 success；self ID 缺失／多重、只剩 self、其他 pending 或 head 不符
都 C3=0。

### A14. PR issue comment 可原地更新；分頁只保證逐頁取全（跨端點快照語義＝未取得）

GitHub issue-comments REST 官方逐字寫：

> "You can use the REST API to update comments on issues and pull requests."

同頁的 update endpoint 是 `PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}`，response schema
同時含 `body` 與 `updated_at`。來源：
<https://docs.github.com/en/rest/issues/comments?apiVersion=2022-11-28>（取證 2026-08-21）。

GitHub pagination 官方頁逐字寫：

> "When a response is paginated, the response headers will include a `link` header."

並說明 paginate 會逐頁請求直到最後一頁；每頁上限通常為 100。來源：
<https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api>
（取證 2026-08-21）。Review comments 官方頁另明載它們不同於 PR 的 issue comments，且各自有
獨立 list endpoint：<https://docs.github.com/en/rest/pulls/comments?apiVersion=2022-11-28>
（取證 2026-08-21）。

🔴 **證據缺口，不是可引用的事實（鐵律 19.3「未取得」）**：本輪在上述官方頁**沒有查到**
issues comments、reviews、inline comments 與 GraphQL threads 之間的跨端點交易 snapshot 契約，
也沒有查到任何跨端點一致性視窗的數值或 SLA（取證 2026-08-21；再查方法＝重讀本節兩個官方頁
與 GraphQL 文件，或取得 GitHub 第一方對跨端點一致性的明文）。**「沒查到」只能記為未取得**：
既不得反向斷言「平台保證沒有 snapshot」，也**不得作為實作輸入、判準或驗收依據**。
本專案據此採取的兩次穩定掃描、fail-closed 與 `SETTLE_INTERVAL_S` 校準，是**專案安全裁定**、
不是平台語義——理由、射程與交付責任全文見 `docs/DECISIONS.md` D38，本檔只保留上面三項可查
原文的事實（comment 可更新、update endpoint 與 schema、分頁 `link` header 與各集合獨立端點）。

🔴 **本專案的 C2 邊界**：0f 完成最終判詞貼文／更新後，按 `verdict_comment_id` 從 GitHub 回讀
`.body`，對不作換行或 Unicode 正規化的 UTF-8 bytes 計算 `verdict_body_sha256`；0e 依同一 ID
重取 body 並重算。相同 ID 但 hash 不等、hash 缺失／格式錯、或 body 後續被改，一律 C2=0；
`updated_at` 只作診斷，不替代內容 hash。0e 必須有 same-ID body-edit fixture 與移除 hash guard 的
mutation。

### A15. jobs 有 attempt-specific 端點；run／job／check-run 只能沿同一 attempt 配對

GitHub workflow-jobs REST 官方頁對兩個端點分別逐字寫：

> "Lists jobs for a specific workflow run attempt. You can use parameters to narrow the list of results."
>
> "Lists jobs for a workflow run. You can use parameters to narrow the list of results."

前者的路徑是 `GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}/jobs`，
後者是 `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`。來源：
<https://docs.github.com/en/rest/actions/workflow-jobs?apiVersion=2022-11-28>（取證 2026-08-21）。
⇒ **官方本身把「某次 attempt 的 jobs」與「這個 run 的 jobs」定義成兩個不同端點**；後者的敘述
沒有限定 attempt，因此不能用來證明取回的 job 屬於 evidence 記錄的那一次 attempt。

同一 run 重跑時 `GITHUB_RUN_ID` 不變、`GITHUB_RUN_ATTEMPT` 遞增（官方逐字與來源見 A13）
⇒ 只比對 `run_id` 無法區分 attempt-1 與 attempt-2 的執行證據。

**本倉庫具名 canary（不是平台永久保證）**：PR #66 的 run `32480285711` 原始 REST 回應實得
`event=pull_request`、`run_attempt=1`、`head_sha=073fadc6ea20e28904565767c7a32afb86472250`，
其 `pull_requests[0].number=66` 且 `.head.sha` 同值；attempt-specific 端點
`/actions/runs/32480285711/attempts/1/jobs` 回 job `96764927745`（`name=review`）且 `head_sha`
同值，該 job 的 `check_run_url` 指向 check-run `96764927745`，其 `head_sha` 亦同值。複驗：

```bash
gh api repos/pisceshei/chilllovesaas/actions/runs/32480285711
gh api repos/pisceshei/chilllovesaas/actions/runs/32480285711/attempts/1/jobs
gh api repos/pisceshei/chilllovesaas/check-runs/96764927745
```

🔴 **本專案使用邊界**：C2 必須把 evidence 的 `run_attempt` 與 run 回應的 `run_attempt` **精確
比對**；job 只能從 attempt-specific 端點取得，check-run 只能沿該 job 回應的 `check_run_url` 取得。
一般 run jobs 集合、另一 attempt 的 job／check-run，或只比 `run_id` 都不得配對成功，一律 C2=0。
0e fixture 必須含 attempt mismatch（evidence attempt ≠ run 回應 attempt）與 cross-attempt
job／check-run 兩格，且移除 attempt 守衛的 mutation 必須轉紅。專案驗收選擇的理由與射程見
`docs/DECISIONS.md` D38。

### A16. `gh api --paginate` 以單一 `$endCursor` 前進；不完整 `pageInfo` 交錯邊界未取得

<!-- 🔴 2026-08-22 改編號（合併 PR #66 進 main 之後）：本條在 PR #64 期間編為 `A9`。
     PR #66 先行合併，其 `A9` 是**完全不同的內容**（逐字標題：「resolved thread 不是獨立核准，review body 也不是 inline thread」）
     ⇒ 同號不同義，本條改編為 `A16`（main 已用到 A15／B12，取下一個未占用號）。
     🔴 **歷史 worklog 裡對 `A9` 的引用指的是本條**——那些 worklog 屬歷史層、不就地改寫，
     以本註作為對照。體例先例＝main 的 B9 自註原編為 `A16`。 -->

> "all pages of results will sequentially be requested"
>
> "the original query accepts an `$endCursor: String` variable"
>
> "`pageInfo{ hasNextPage, endCursor }`"

來源：<https://cli.github.com/manual/gh_api>（取證 2026-08-21）

以上三段逐字分別支持完整取頁、GraphQL 游標變數及 `pageInfo` 欄位契約。
GitHub CLI 官方原始碼在 pinned commit `fadd4efb7daddd8afd8a5517a0cb5f5f39af6ada` 的
`findEndCursor` 使用函式層級的 `foundEndCursor`／`foundNextPage`，遇到另一旗標已成立時即：

> `if foundNextPage { break loop }`
> `if foundEndCursor { break loop }`

來源：<https://github.com/cli/cli/blob/fadd4efb7daddd8afd8a5517a0cb5f5f39af6ada/pkg/cmd/api/pagination.go#L30-L88>
（取證 2026-08-21）。同版 `api.go` 下一頁只設定單一 `params["endCursor"] = endCursor`：
<https://github.com/cli/cli/blob/fadd4efb7daddd8afd8a5517a0cb5f5f39af6ada/pkg/cmd/api/api.go>
（取證 2026-08-21）。

⚠️ **證據邊界**：上述旗標沒有綁定到某一個 `pageInfo` 物件；若同一 JSON token stream 出現
多個、不完整或交錯的 `pageInfo`，不同物件的 token 可能令兩旗標先後成立。官方手冊沒有承諾
這種輸入的選擇／停止規則，因此「首組完整游標對」及特定 mixed-token 結果均為**未取得**，
不得發布或依賴。官方同 commit 的 `pagination_test.go` 有正常完整 block 與
`more pageInfo blocks` 案例，但沒有把不完整交錯升格成公開契約：
<https://github.com/cli/cli/blob/fadd4efb7daddd8afd8a5517a0cb5f5f39af6ada/pkg/cmd/api/pagination_test.go>
（取證 2026-08-21）。

🔴 **可發布邊界**：下一頁只回填單一 `$endCursor`，不會替每個巢狀 connection 維護獨立游標。
因此 PR #62 把 `$endCursor`／`pageInfo` 放在外層 `reviewThreads` 時，只能把該外層重取稱為完整，
不得外推巢狀 `comments(first:100)` 也逐頁取完。正文全集仍走三個 `--paginate` REST 集合；
GraphQL threads 只取 `isResolved`／`isOutdated` 與首則 inline ID 對應。

### A17. PR commits 端點最多 250；fallback 是 repository List commits＋`sha` 起點

<!-- 🔴 2026-08-22 改編號（合併 PR #66 進 main 之後）：本條在 PR #64 期間編為 `A10`。
     PR #66 先行合併，其 `A10` 是**完全不同的內容**（Codex 的 reaction 不取代 GitHub review）
     ⇒ 同號不同義，本條改編為 `A17`（main 已用到 A15／B12，取下一個未占用號）。
     🔴 **歷史 worklog 裡對 `A10` 的引用指的是本條**——那些 worklog 屬歷史層、不就地改寫，
     以本註作為對照。體例先例＝main 的 B9 自註原編為 `A16`。 -->

> "Lists a maximum of 250 commits for a pull request. To receive a complete commit list for pull requests with more than 250 commits, use the List commits endpoint."
>
> "SHA or branch to start listing commits from."

來源：GitHub REST 官方的
<https://docs.github.com/en/rest/pulls/pulls#list-commits-on-a-pull-request> 與
<https://docs.github.com/en/rest/commits/commits#list-commits>（取證 2026-08-21）。第一句是 PR
commits 的超限指引；第二句是 repository List commits 的 `sha` query parameter 定義。

🔴 **三件事必須分開，不得併成一句**（來源＝PR #64 Codex inline `3836905826`）：
① **官方明文的上限**：受 250 上限的端點是 `GET /repos/{owner}/{repo}/pulls/{pull_number}/commits`，
   官方要求改用 **List commits** 端點；
② **官方明文的參數語義**：List commits 的 `sha` 逐字為 “SHA or branch to start listing commits from.”
   （另一頁文檔，見本節上方引文）；
③ **本專案把 ①② 組合出來的查詢**：`GET /repos/{owner}/{repo}/commits?sha={pull_head_sha}`——
   🔴 **這是我方的組合，不是 GitHub 的逐字指示**，不得當成官方原文引用。2026-08-21 對 PR #64 exact head
`26fc683e40bb8ad6466d082c6887876345f84646` 實跑後，repository endpoint 第一筆 SHA 與該 head
逐字相同。因此不得把單次 PR commits 回應外推成任意大型 PR 的全集。

⚠️ **證據邊界**：repository List commits 只明定「從 SHA／branch 開始列 commits」；上述兩頁
沒有提供「只取 PR delta」的停止參數，也沒有把 merge-base／base exclusion 的客戶端算法定為
契約。因此 fallback endpoint 與起點已取得，但如何從它的 ancestor stream 精確裁出 PR-only
集合仍為**未取得**，不得把 `?sha={pull_head_sha}` 的全部回應直接稱為 PR commits 全集。

📌 **倉庫快照，不是全域保證**：2026-08-21 實跑
`gh api --paginate repos/pisceshei/chilllovesaas/pulls/61/commits`，在 PR #61 已 squash merge
（merge commit `1800b20aa006ee67f6f8c88cd24e50322db99a4c`）後仍取回 pre-squash
`2ed2403d06eb50bba0f82e74fcacf44643a81bd8`。這證明該精確 PR 的 API 取回路徑可用；官方頁面
沒有承諾所有已合併 PR 永久保留所有 pre-squash 物件，故不得升格為永久可達保證。

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

### B9. 指令碼檔內的 PowerShell 函式必須先定義才能呼叫

<!-- 🔴 2026-08-22 反向指標（合併 PR #64 時加）：PR #64 在其分支期間也用 `B9` 這個編號，內容完全不同；
     合併時已改編為 **`B13`**（見本檔該節）。歷史 worklog 若以 `B9` 指涉 `gh api`／`git log` 那一族內容，指的是 `B13` 而不是本節。 -->

<!-- 🔴 2026-08-22 更正（來源＝Codex inline `3834080765`）：本條原編為 `A16`，但它**物理上位於
     `## B. 工具鏈` 之後**，而 A 區全部屬 GitHub 語義、PowerShell 屬工具鏈 ⇒ 編號歸錯區，
     且讓 A 區出現一個不在 A 區的號、B 區的序號斷在 B8。改編為 `B9`，全部引用同批更新。 -->

Microsoft Learn 的 `about_Functions` 在 **7.6 與 5.1 兩個版本頁面**都以 Important 區塊逐字寫：

> "Within script files and script-based modules, functions must be defined before they can be called."

來源：<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions>
（7.6，取證 2026-08-22）與
<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions?view=powershell-5.1>
（5.1，取證 2026-08-22）。⚠️ **兩個版本都查了**，因為本倉庫的 worklog block 實際跑在
Windows PowerShell 5.1 上，拿 7.x 的頁面替 5.1 背書不成立。

🔴 **本專案使用邊界**：本條只支持「**指令碼檔內**呼叫點必須排在定義之後」。它**不**支持
「PowerShell 完全不做前置解析」這類更強的說法——官方這句限定在 script files 與 script-based
modules，互動式 session 與 dot-source 後的可見性不在本條射程。`docs/worklog/` 內以此為由的
函式移位，引用範圍以本條為限。

### B10. GFM 表格：行首／行尾分隔直線是「建議」不是必要；直線靠反斜線跳脫

<!-- 🔴 2026-08-22 反向指標（合併 PR #64 時加）：PR #64 在其分支期間也用 `B10` 這個編號，內容完全不同；
     合併時已改編為 **`B14`**（見本檔該節）。歷史 worklog 若以 `B10` 指涉 `gh api`／`git log` 那一族內容，指的是 `B14` 而不是本節。 -->

<!-- 🔴 2026-08-22 移位（來源＝Claude issue comment `5376772877` 🟡-2）：本條新增時被插在
     `B9` **之前**，使全檔唯一一處編號逆序落在 B 區——而上一輪 Codex `3834080765` 點掉、
     並由本 PR 修掉的，正是同一檔同一區的「編號與物理位置不一致」。⚠️ 本檔沒有明文排序
     規則，但下一個要加 `B11` 的人需要一個明確的插入位置，因此就地補上：**本檔以編號遞增
     的物理順序排列，新條目一律追加在該區末尾。** -->

GitHub Flavored Markdown Spec 的 Tables (extension) 節逐字：

> "A leading and trailing pipe is also recommended for clarity of reading, and if there's otherwise parsing ambiguity."

> "Include a pipe in a cell's content by escaping it, including inside other inline spans"

來源：<https://github.github.com/gfm/>（取證 2026-08-22）。

🔴 **第一句支持的是「尾巴沒有分隔直線的列仍然是合法的一列」**——原文用 recommended（建議）
而不是 required，給的兩個理由是「便於閱讀」與「有解析歧義時」，兩者都不是有效性條件。

跳脫的判定另需 Backslash escapes 節逐字：

> "Any ASCII punctuation character may be backslash-escaped."

> "Backslashes before other characters are treated as literal backslashes."

來源：<https://github.github.com/gfm/#backslash-escapes>（取證 2026-08-22）。
而 spec 的 ASCII punctuation character 定義逐字列舉中含反斜線（`U+005B–0060` 段）與直線
（`U+007B–007E` 段）：來源 <https://github.github.com/gfm/#ascii-punctuation-character>
（取證 2026-08-22）。

🔴 **奇偶規則是我方推導，不是官方逐字**（依 AGENTS §8.2 明示標記）：官方逐字只給三件事
——①任何 ASCII 標點都可被反斜線跳脫 ②反斜線自己就是 ASCII 標點 ③表格內要放直線得靠跳脫。
把三者合起來才得到：`\\` 是**一個已被跳脫、已被消耗的反斜線**，它後面那個直線前面並沒有
可用來跳脫的反斜線 ⇒ 那是**分隔符**。故判準是**緊鄰該直線之前的連續反斜線串長度的奇偶**
（奇＝被跳脫、偶＝分隔符），**不是**「前一個字元是不是反斜線」。⚠️ 這一段若日後被引用，
要引的是「我方由三條逐字推導」，不得寫成「GFM 規定奇偶」。

🔴 **本專案使用邊界**：本條只支持 `docs/worklog/2026-08-21-驗收收斂制度V2.md` 的乙堆表
切格與邊界剝除如何判定分隔直線。它**不**支持任何關於表格對齊列、行內元素解析、或最終渲染
結果的說法；表頭欄數與超出格的處置是另一條（`the excess is ignored`，見該 worklog 內引用）。

### B11. PowerShell：變數名不分大小寫（官方逐字）；`&` 呼叫 scriptblock 的**父作用域是誰**＝未取得

**① 變數名不分大小寫——官方逐字：**

> "Variable names aren't case-sensitive, and can include spaces and special characters."

來源 `about_Variables`，**5.1 與當前版兩個頁面逐字相同**：
<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_variables?view=powershell-5.1>
與 <https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_variables>
（皆取證 2026-08-22）。⚠️ **兩個版本都查了**，理由同 `B9`：本倉庫的 worklog block 跑在
Windows PowerShell 5.1 上。

🔴 **逐字與推導的分界**：官方**沒有**逐字寫「`$Body` 與 `$body` 是同一個變數」，那是上面那句的
直接蘊涵。引用本條時要說「由『不分大小寫』推得」，不得寫成「官方寫了」。

**② `&` 執行 scriptblock 的作用域——官方逐字說的是 child scope：**

> "The call operator executes in a child scope."

（`about_Operators`；<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_operators?view=powershell-5.1>
與當前版逐字相同，取證 2026-08-22）

> "Scriptblocks create a new scope for variables."

> "The call operator is another way to execute scriptblocks stored in a variable. Like `Invoke-Command`, the call operator executes the scriptblock in a child scope."

（`about_Script_Blocks`；<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_script_blocks?view=powershell-5.1>
與當前版逐字相同，取證 2026-08-22）

🔴 **本條同批更正一句我方寫錯的話**（來源＝Codex inline `3834527588`）：worklog 曾寫
「`& $Body` 是**在該函式的作用域裡**執行 scriptblock」——**與官方逐字相反**，官方說的是
**child scope**（新的子作用域）。該句已就地更正。

**③ 真正承重的那一環＝未取得：**

「該 child scope 的**父**是**呼叫點**的作用域，而不是 scriptblock **定義處**的作用域」
——這一句**在官方參考文檔裡查不到**。查得到的只有下列各句，它們**每一句都同樣相容於
語彙作用域（lexical scoping）**，接不到「呼叫點才是父」這一環：

> "You can create a new child scope by calling a script or function. The calling scope is the parent scope. The called script or function is the child scope."

> "When code running in a runspace references an item, PowerShell searches the scope hierarchy, starting with the current scope and proceeding through each parent scope."

（`about_Scopes`，5.1／當前版逐字相同，取證 2026-08-22）

> "Within a child scope, a name defined there hides any items defined with the same name in parent scopes."

（Windows PowerShell Language Specification 3.0 §3.5.1；該頁帶 Microsoft 自己的
「does not reflect the current state of PowerShell⋯historical reference」告示，取證 2026-08-22）

**查過而沒有這句的五處**（複驗＝逐頁搜尋「invok」「parent scope」「dynamic」）：
`about_Operators`、`about_Script_Blocks`、`about_Scopes`、語言規格 §3.5.1、語言規格 §3.5.5
（後者列出 `& { ... }` 屬「建立新作用域」那一側，但仍未說**父是誰**）。**明確演示
「呼叫點的區域變數會贏」的只有一處**：learn.microsoft.com 上一篇**已封存的 MSDN 部落格**
（`ms.topic: Archived`、`ROBOTS: NOINDEX,NOFOLLOW`）——**部落格不是規格，不得當官方語義
引用**。⇒ 依 AGENTS §8.2 記為 **未取得**。

🔴 **本專案使用邊界**：`docs/worklog/` 內那處「突變文字要在 scriptblock 外組好」的修法，
其前提只是**本機實測到的觀察**——scriptblock 內的 `$body` 拿到的不是 PR 描述，錯誤逐字
`Method invocation failed because [System.Management.Automation.ScriptBlock] does not contain
a method named 'op_Addition'.`。**該修法對「機制是哪一條」並不敏感**，因此不受 ③ 的未取得
狀態影響；反過來，**任何人不得用 ③ 去論證別處的作用域行為**。

### B12. 大小寫語義：PowerShell 比較運算子預設**不分**大小寫；.NET 靜態 `Regex` 預設**分**大小寫

**① PowerShell 比較運算子（含 `-match`／`-notmatch`）預設不分大小寫——官方逐字：**

> "String comparisons are case-insensitive unless you use the explicit case-sensitive operator. To make a comparison operator case-sensitive, add a `c` after the `-`."

來源 `about_Comparison_Operators`，**5.1 moniker 頁**（與本倉庫 worklog block 的執行環境一致）：
<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comparison_operators?view=powershell-5.1>
（取證 2026-08-22）

**② .NET 無 `options` 參數的靜態 `Regex` 方法預設分大小寫——官方逐字：**

> "By default, the comparison of an input string with any literal characters in a regular expression pattern is case-sensitive"

> （`RegexOptions.None` 條目）"Comparisons are case-sensitive."

> "A constructor or static pattern-matching method without an `options` parameter is called instead."

來源 <https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expression-options>
（取證 2026-08-22）

🔴 **兩者相加就是一個安靜的漏洞**：同一段程式碼裡用 `[regex]::Matches($x, $p)` **掃**、
再用 `$v -notmatch $p` **驗**，兩邊對同一個 pattern 的大小寫語義**相反**。掃得到但驗不出來的
輸入（例如大寫 hex）會被判為合文法而放行，隨後抽取階段又因分大小寫而抽不到 ⇒
**「掃過了」與「驗過了」之間出現一個誰都不管的縫**。本倉庫 `docs/worklog/` 的
`Assert-DeferredWhite` 就踩過這個縫（2026-08-22，來源＝Claude issue comment `5377528418` 🔴-2）。

🔴 **本專案使用邊界**：本條只支持「同一 pattern 在 PowerShell 運算子與 .NET 靜態方法上
預設語義相反」這一件事，以及由它推出的**修法方向**（把驗證側改成 `-cnotmatch` 或
`[regex]::IsMatch`，讓兩側同語義）。它**不**支持任何關於 `-like`／`Compare-Object`／
`Sort-Object -Unique` 等其他比較路徑的大小寫斷言——那些各有各的文件，要用要各自取證。

### B13. `gh api` 的字面 `@path` shorthand 屬 `-F`；stdin／整體 body 另有入口

<!-- 🔴 2026-08-22 改編號（合併 PR #66 進 main 之後）：本條在 PR #64 期間編為 `B9`。
     PR #66 先行合併，其 `B9` 是**完全不同的內容**（指令碼檔內的 PowerShell 函式必須先定義才能呼叫）
     ⇒ 同號不同義，本條改編為 `B13`（main 已用到 A15／B12，取下一個未占用號）。
     🔴 **歷史 worklog 裡對 `B9` 的引用指的是本條**——那些 worklog 屬歷史層、不就地改寫，
     以本註作為對照。體例先例＝main 的 B9 自註原編為 `A16`。 -->

> "Pass one or more `-f/--raw-field` values in `key=value` format to add static string parameters"
>
> "if the value starts with `@`, the rest of the value is interpreted as a filename to read the value from. Pass `-` to read from standard input."
>
> "To pass pre-constructed JSON or payloads in other formats, a request body may be read from file specified by `--input`. Use `-` to read from standard input."

來源：GitHub CLI 官方 <https://cli.github.com/manual/gh_api>（取證 2026-08-21）。
🔴 **上方三句逐句分屬三個不同旗標，不得互相代替**（2026-08-22 改寫；來源＝Claude issue
comment `5364180385` 🟡-1）：
- **第一句**屬 `-f/--raw-field`——靜態字串參數。
- **第二句**屬 `-F/--field` 的 magic type conversion（`@filename`／`@-`）。
  🔴 **不得外推到 `-f`**：`-f text=@path` 送出的是字面 `@path`，本節下方即為該事故的實測。
- **第三句**屬 `--input`——它是**整體 request body** 的入口，與 `-F` 的**單一欄位值**入口不同層。
<!-- 🔴 2026-08-22 更正（同來源）：本段原文為「前句屬 `-f/--raw-field`，後句屬 `-F/--field`
     的 magic type conversion；不得把後句外推到 `-f`」——那是為**兩句**版本寫的。上一輪在
     blockquote 補進第三句（`--input`）時沒有同批改這裡，於是「後句」的自然讀法（最後一句）
     指向 `--input`，第二句的歸屬被頂掉、第三句沒有歸屬。
     🔴 而「不得把後句外推到 `-f`」是本節**唯一的規範性防線**，擋的正是已發生過的事故。 -->

官方同頁另明列：`-F key=@-` 可從 stdin 讀取**欄位值**；`--input file` 可讀取預先組好的
**整體 request body**，且 `--input -` 從 stdin 讀。2026-08-21 實跑 `-F text=@-` 與
`--input -` 兩路，GitHub Markdown API 分別回傳帶 `field stdin canary`／`stdin body canary` 的
`<h1>`，兩種替代入口均已取得。

🔴 **本專案的用途**：`gh api ... -f text=@path` 送出的是字面 `@path`；若要使用 CLI 的
`@path` shorthand 把該檔內容放進 `text` 欄位，須用 `-F text=@path`，但這不是所有 file/stdin
供給形態的絕對要求。PR #64 exact response 曾把字面路徑渲染成
`<p dir="auto">@docs/worklog/2026-08-21-PR64第十一輪雙驗收修復.md</p>`，證明 HTTP exit 0
不等於 request body 正確。任何 Markdown render 複驗都要同時釘輸入來源與至少一個承重 HTML
canary，不能把 table／pre 的零計數直接當成功。

### B14. `git log` 預設不輸出 merge diff；`separate` 逐 parent 顯示

<!-- 🔴 2026-08-22 改編號（合併 PR #66 進 main 之後）：本條在 PR #64 期間編為 `B10`。
     PR #66 先行合併，其 `B10` 是**完全不同的內容**（GFM 表格：行首／行尾分隔直線是「建議」不是必要；直線靠反斜線跳脫）
     ⇒ 同號不同義，本條改編為 `B14`（main 已用到 A15／B12，取下一個未占用號）。
     🔴 **歷史 worklog 裡對 `B10` 的引用指的是本條**——那些 worklog 屬歷史層、不就地改寫，
     以本註作為對照。體例先例＝main 的 B9 自註原編為 `A16`。 -->

> "merge commits will not show a diff"
>
> "Show full diff with respect to each of parents."

> "Disable output of diffs for merge commits. Useful to override implied value."

> "Default is `off` unless --first-parent is in use, in which case first-parent is the default."

來源：Git 官方 <https://git-scm.com/docs/git-log> 的 DIFF FORMATTING／
`--diff-merges=separate`（取證 2026-08-21）。
🔴 **上面兩句是本輪補的條件逐字**（2026-08-22；來源＝Codex inline `3826627165`）：原文只用
中文寫「官方另明列 `--diff-merges` 預設為 `off`（未使用 `--first-parent` 時）」，而**那正是
本條承重的那一句**——沒有它，「預設不輸出 merge diff」這個結論沒有出處。
⚠️ **取證路徑要說清楚**：`git-scm.com/docs/git-log` 的渲染頁在本次抓取時被截斷，取不到
DIFF FORMATTING 全段；因此改取 git 一手來源
<https://raw.githubusercontent.com/git/git/master/Documentation/diff-options.adoc>
（取證 2026-08-22）。該檔的條件句寫作 `"Default is {diff-merges-default} unless --first-parent
is in use, in which case first-parent is the default."`，其中 `{diff-merges-default}` 是
asciidoc 屬性；<https://raw.githubusercontent.com/git/git/master/Documentation/git-log.adoc>
（取證 2026-08-22）逐字設 `:diff-merges-default: ``off``` ⇒ 在 git-log 文檔的渲染結果即為
`off`。**上面第二句引的是展開後的形態，展開依據就是這一行屬性定義**，不是我方推斷。
所以 `--name-status` 與 `--diff-filter` 本身不能證明 merge-resolution 刪除／改名已被掃到。

`git diff-tree` 的 `-r` 官方逐字是 "Recurse into sub-trees."，來源：Git 官方
<https://git-scm.com/docs/git-diff-tree>（取證 2026-08-21）。因此巢狀路徑的 merge-only witness
必須明示 `-r`，不能把只回報頂層 tree 的輸出當成目標檔案紀錄。

🔴 **倉庫 fixture**：immutable merge `59cfaf44bd2d71cef6d54d8e1b63aa8b8b602890` 相對 first parent
`76751e4162a79bbb28860b545e673ee1d9ee1bea`，目標
`scripts/__pycache__/lint-prototype.cpython-311.pyc`（該檔已刪除，只存在於上述 immutable merge
歷史）在未開 merge diff 的 range log 出現 1 次，
加 `--diff-merges=separate` 後出現 2 次；
`git diff-tree -m -r --format= --name-status 59cfaf44bd2d71cef6d54d8e1b63aa8b8b602890 -- scripts/__pycache__/lint-prototype.cpython-311.pyc`
單看 merge 本身得到 1 筆目標 `D` 紀錄。拿掉 `-r` 時只得到頂層 `M scripts`，不能重現該計數。
PR #64 validator 以該 multiset 差異承重，移除 merge-diff 選項就必須非零。

### B15. 〔**官方逐字＝未取得**；版本限定實測〕`gh pr view --json mergedAt --jq .mergedAt` 對**未合併** PR 回**空值**，不是字面 `null`

🔴 **本條的證據等級**（來源＝PR #64 Codex inline `3837307764`）：官方文檔未記載此行為 ⇒ 依 19.3 標「未取得」；
下方實測只建立 **`gh` 2.97.0 這一版**的觀察，不得外推為跨版本語義。D39 依它成立的部分**不受影響**——
D39 是 fail-closed：空值走「非 ISO8601」分支被擋，**不依賴**「空值 vs 字面 null」哪個為真。

- **來源**：**本機實測**（本檔規則 2 要求「查得到原文」——`gh` 官方文檔未記載 `--jq` 對 JSON `null` 的輸出形態，
  查無可引的原文 ⇒ 本條以**可重跑的實測**替代逐字原文，並明標此例外）。
  環境：`gh version 2.97.0 (2026-07-31)`，取證日期＝2026-08-23。
- **實測命令與逐字輸出**：

  ```
  $ set -o pipefail
  $ gh pr view 64 --repo pisceshei/chilllovesaas --json mergedAt --jq .mergedAt | od -c
  0000000  \n
  0000001
  $ echo $?
  0
  ```

  🔴 **本區塊的證據前後錯了兩次，兩次根因不同，都記在這裡**：
  ① 初稿寫成 `0000000  0a`——那是 `od -An -tx1` 的形態，不是 `od -c` 的。**重打的**。
  ② 第二版改成「重跑後逐字貼上」，貼出來卻只有單獨一行 `0000000`——那是**零位元組**的
     od 簽章，與本段結論「只有一個換行」互斥（來源＝PR #64 Claude `5382422505` 🔴-1）。
     🔴 **成因已逐步查清**：我用 Python `subprocess` 呼叫 `bash -c` 抓輸出，
     而**該子行程的 PATH 上沒有 `gh`**（實測 stderr 逐字 `bash: line 1: gh: command not found`）
     ⇒ 管線左端無輸出，`od` 對空輸入印出零位元組簽章。
     ⇒ 又一次「量了 X（子行程環境）當成關於 Y（文件裡那條指令）的事實發布」。
  🔴 **`gh` 失敗時這條管線預設不會報錯**：管線退出碼取最後一個命令（`od` 的 0）。
     來源＝PR #64 Codex inline `3836905817`，引 GNU Bash 手冊 Pipelines 節逐字
     “The return status of a pipeline is the status of the last command”（取證 2026-08-22）。
     ⇒ 上面的重跑**加了 `set -o pipefail` 並貼出退出碼**；沒有這一步，
     這個證據塊無法區分「未合併 PR 回空值」與「`gh` 呼叫失敗」。
     ⚠️ 但 `pipefail` **擋不住本次的成因**——`gh` 不在 PATH 時是 shell 回 127，
     而我上一輪根本沒看退出碼。真正的防線是**貼出退出碼**，不是只加 `pipefail`。

  ⇒ stdout **只有一個換行**；經 `$( )` 命令替換後是**空字串**（長度 0），
  **不是**四個字元的 `null`。

- **為什麼要登記**：`--json` 那一層拿到的 JSON 值確實是 JSON `null`，
  但 `--jq` 對 JSON `null` 的輸出是**空行**而不是字面字串 `null`。
  兩者在 shell 裡的行為完全不同——`[ -z "$v" ]` 對前者為真、對後者為假；
  而任何寫成 `[ "$v" = "null" ]` 的防呆對前者**完全無效**。

- **落點**：`docs/DECISIONS.md` D39 的 fail-closed 判準以此為據
  （空字串走「非 ISO8601」那條分支被擋成 rc 2）。

- 🔴 **登記的緣由是一次真實的誤述**：PR #64 第 19 輪的 D39 更正註逐字寫過
  「#66 尚未合併（`--jq .mergedAt` 得**字面 `null`**）」，該句來自驗收方措辭的轉述，
  **沒有任何一方實測過**。第 20 輪驗收方自行以 `od -c` 實測後撤回自己的措辭。
  ⇒ **外部行為的轉述不算證據**；本檔的存在就是為了讓這類句子有一個必須帶實測的落點。
