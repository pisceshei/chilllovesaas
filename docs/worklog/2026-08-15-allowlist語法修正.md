# 2026-08-15 — 驗收方實跑權限：`:*` 與 ` *` 的差別（allowlist 語法修正）

> 承接 `2026-08-15-驗收恢復後的兩項修正.md` §3。那一輪加的四條 allowlist **完全沒有生效**，
> 由四個 PR 的驗收各自實測抓到。

---

## 已完成的工作 (Done)

### 1. 現象：四份驗收都寫「零實跑證據」

`#39`／`#40`／`#41`／`#42` 同一批跑完，四份留言各自登記：

> 本輪 **零實跑證據**。以下呼叫全部被擋，原文一律是 `This command requires approval`：
> `ruby scripts/test-limits-key-rules.rb`／`ruby scripts/check-limits-keys.rb`／
> `python3 scripts/lint-prototype.py`／`bash scripts/check-exec-bits.sh`
> 而 `git ls-files -s`／`ls scripts`／`gh pr diff` 全部通 ⇒ **allowlist 有生效，是那三條沒有匹配到**。

🔴 **這是一個「加了設定卻沒有生效」的形態**，而且**四份驗收獨立測到同一件事**——
比任何單一來源的推測都可靠。它讓本專案自己的判準
（「PR 自稱全過不算證據，你自己跑一次才算」）在**每一輪驗收上**失效。

### 2. 根因：`:*` 等同「**空格 ＋ `*`**」，而空格會強制 word boundary

官方文件（`code.claude.com/docs/en/permissions`）逐字：

> The `:*` suffix is an equivalent way to write a trailing wildcard,
> so `Bash(ls:*)` matches the same commands as `Bash(ls *)`.

> When `*` appears at the end **with a space before it** (like `Bash(ls *)`),
> it enforces a **word boundary**, requiring the prefix to be followed by a space or end-of-string.
> For example, `Bash(ls *)` matches `ls -la` but not `lsof`.
> **In contrast, `Bash(ls*)` without a space matches both `ls -la` and `lsof`**
> because there's no word boundary constraint.

⇒ 我寫的 `Bash(ruby scripts/:*)` **等同** `Bash(ruby scripts/ *)`，
要求 `ruby scripts/` 後面接**一個空格** ⇒ `ruby scripts/check-limits-keys.rb` **永遠不匹配**。

✅ **而 `Bash(gh pr view:*)`／`Bash(git diff:*)` 為什麼有效**：
`view`／`diff` 後面本來就有空格，word boundary 自然成立。
🔴 **只有以 `/` 結尾（停在 token 中間）的前綴會踩到這個坑**——而我加的四條全是這種。

### 3. 修法：改成**不留空格**的 `Bash(ruby scripts/*)`

| 舊（無效） | 新 |
|---|---|
| `Bash(bash scripts/:*)` | `Bash(bash scripts/*)` |
| `Bash(ruby scripts/:*)` | `Bash(ruby scripts/*)` |
| `Bash(python scripts/:*)` | `Bash(python scripts/*)` |
| `Bash(python3 scripts/:*)` | `Bash(python3 scripts/*)` |

⚠️ **不改成 `Bash(ruby:*)`**（那是當初考慮過的「放到直譯器層」）：
那會連 `ruby -e '任意代碼'` 一起放行，而本 job 握有 `contents: write` 與 OAuth token、
執行的又是被審 PR 帶進來的代碼。新語法讓我拿到**原本就想要的那個緊範圍**，不必放寬。

---

## 修改的檔案與核心邏輯 (Changes)

| 檔案 | 改動 |
|---|---|
| `.github/workflows/claude-review.yml` | 四條 `scripts/` allowlist 由 `:*` 改成 `*`；上方補一段「為什麼」註釋（四份驗收的實測 ＋ 官方兩段逐字 ＋ 為什麼 `gh pr view:*` 有效而這四條不行 ＋ 為什麼不放寬到直譯器層） |

**自測**：`YAML.safe_load` 通過｜`claude_args` 解析後逐項列印，確認四條已是 `Bash(… scripts/*)`
且 `scripts/:*` 殘留數為 **0**。

### 4. 🔴 依 PR #44 的 Codex review：收緊 job 權限（我的安全推理原本是錯的）

Codex 逐字：

> Restricting the prefix to `scripts/` **does not establish trust** because the checked-out
> script itself comes from the reviewed PR… the process inherits `GH_TOKEN` while this job
> grants `contents: write`, `pull-requests: write`, and `issues: write`.

**它是對的，而且打中我最得意的那一句。** 我原本寫「只授權 `scripts/` 底下，所以拿到了緊範圍、
不必放寬安全邊界」——**範圍限制不等於信任**：`scripts/` 底下的東西**正是被審 PR 帶進來的**。
🔴 而且因為舊語法根本沒生效，**修正語法的這個 PR 才是真正把洞打開的那一個**。

#### 配套：逐項稽核後把 `contents: write` 降成 `read`

| 權限 | 誰在用 | 處置 |
|---|---|---|
| `contents: write` | **只有 `gh pr merge --squash`**，而 `AUTO_MERGE` 是 `"false"` | 🔴 **目前完全用不到、攻擊面卻最大 ⇒ 降成 `read`** |
| `pull-requests: write` | `gh pr comment`／`gh pr review --approve` | 核心功能，保留 |
| `issues: write` | 通過後關階段 issue／在下一階段登記 | 風險遠低於 contents（改不了代碼），保留 |
| `id-token: write` | action 換 app token 的 OIDC | 保留 |
| `actions: read` | 本檔沒直接用 | 保留（唯讀無害） |

🔴 **陷阱已寫進註釋**：要把 `AUTO_MERGE` 改回 `"true"` 的人會發現 `gh pr merge` 失敗——
那時**不要只改 AUTO_MERGE**，得同時面對「讓一個執行過 PR 代碼的 job 重新拿到 `contents: write`」
這個決定。

⚠️ **這只是降低爆炸半徑，不是消除風險**：被注入的驗收方仍能貼留言、approve、動 issue。

---

---

## 尚未完成或需注意的風險 (Pending / TODO)

1. 🔴 **本次修正一樣無法在本 PR 上驗證**（反竄改），而且**它是否真的匹配得上，仍未實測**。
   ⏳ **判準寫在這裡，下一輪照著看**：合併後任一 PR 的驗收留言若仍寫
   「零實跑證據 ＋ `This command requires approval`」，代表**無空格形式也不對**，
   那時才考慮退到 `Bash(bash:*)`／`Bash(ruby:*)` 並重新評估安全取捨。
   ⚠️ **不要在沒看到那句話之前就先放寬**——這一輪的教訓正是「沒實測就當它會動」。
2. 🔴 **這條路只是「降低爆炸半徑」，不是安全的最終解。**
   更徹底的兩條（已考慮、本輪未採，是使用者裁定「合但限縮權限」）：
   ①只執行 base commit 的可信版本——但那樣**修改檢查腳本的 PR 就無法用實跑驗證**，
   而那正是最需要實跑的場合（#39／#41／#42 全部是這種）；②拆成獨立的唯讀 job。
   🔴 **日後若開放外部貢獻者或轉 public，必須改成 ① 或 ②**，不得只靠降權。
3. ⚠️ **路徑穿越沒有被擋**：`Bash(ruby scripts/*)` 的 `*` 可以跨越任意字元，
   所以 `ruby scripts/../evil.rb` 也會匹配。
   實務上影響有限（被審 PR 本來就能把代碼放進 `scripts/`），但**這不是零風險**，
   登記在此，別當成「只能跑 scripts/ 底下的東西」。
3. ⚠️ **複合指令仍然要每一段各自匹配**（官方：「A rule must match each subcommand
   independently.」，分隔符 `&&`／`||`／`;`／`|`／`|&`／`&`／換行）。
   prompt 已經寫了這一條，但**沒有實測過**驗收方會不會照做。
5. ⚠️ **新增 `scripts/` 底下的檢查腳本不需要改 allowlist**（前綴涵蓋），
   但**改用別的直譯器**（例如 `node scripts/x.js`）就會再次靜默失效。
   🔴 那時的症狀與這次一模一樣：留言寫「零實跑證據」。**看到那句話就先查這裡。**
