# 2026-08-20 — Claude Fable 5 額度復發，依既定處置回退 Opus 5

## 已完成的工作 (Done)

PR #62 的 Claude Review run `32378427336` 在精確 HEAD
`5209087f58a908ef0b300f8c7a05a189b2b279da` 連續兩次沒有產生判詞：

- attempt 1 實際審查 34 回合、`total_cost_usd=4.555815000000001`、
  `duration_ms=364356` 後，錯誤原文為
  `You've reached your Fable 5 limit. Switch to another model to continue.`
  （PR 留言 `5357115702`）。
- 依診斷規則完整重跑後，attempt 2 在第一個請求即以 `num_turns=1`、
  `total_cost_usd=0`、`duration_ms=689` 回傳逐字同一句
  （PR 留言 `5357146961`）。

這不是 workflow validation-skip，也不是 `API Error: 529 Overloaded`：workflow 兩次都進入
Claude 步驟，且服務端錯誤原文明確點名 Fable 5 limit。`git log -p -G
"claude-fable-5|claude-opus-5" -- .github/workflows/claude-review.yml` 另確認沿革⑥已走過
同一條路，而沿革⑦已明載此錯誤復發時「照④／⑥先例換回 `claude-opus-5`，不必再問」。

因此本輪只執行既定處置：把 live `--model` 改回完整名 `claude-opus-5`，並新增沿革⑧保留
本次 run、兩次 attempt、費用／回合指紋與逐字錯誤；`--effort max`、`--max-turns 200`、
allowed tools、判詞解析與其餘 workflow 行為全部不動。

## 修改的檔案與核心邏輯 (Changes)

| 檔案 | 改動 |
|---|---|
| `.github/workflows/claude-review.yml` | live 模型由 `claude-fable-5` 切回 `claude-opus-5`；現值註解改指沿革⑧；新增 PR #62 兩次 attempt 的原始證據與「不是推翻能力判斷」邊界 |
| `docs/worklog/2026-08-20-Claude-Fable5額度回退Opus5.md` | 本工作單位的查證、修法、測試與風險記錄 |
| `docs/specs/91-pit-register.md` | 附錄 A.1 同 commit 補列本 worklog，維持倉庫檔案集合與清單雙向相等 |

驗證採 fail-closed：第一次直接跑 `ruby bin/ci` 的完整退出碼為 1，失敗集中在 Windows 無法直接
執行 extensionless `bin/*` 與環境沒有 `python3` 命令；該輪沒有被宣稱為全綠。依倉庫同日既有
Windows 等價口徑，把 setup 拆成四步、`bin/*` 改由 Ruby 執行、Python 改用 Codex bundled
Python，並在同一 process 把 Git for Windows Bash 放到 PATH 前端後，從 setup 起完整重跑：

- `GATES_TOTAL=29`、`GATES_PASSED=29`、`GATES_FAILED=0`；
- Rails `284 examples, 0 failures`；Vitest `5 passed`；RuboCop 162 檔、0 offenses；
  Brakeman 0 errors／0 warnings；Ruby 與前端 audit 無已知漏洞；
- prototype 三份合計 `ERROR 0 / WARN 136`；workflow 2 份 YAML、33 個 `run:` 區塊與
  11 條 syntax regression 全綠；
- `claude_args` 的實際 YAML 解析前三行為 `--model claude-opus-5`、`--effort max`、
  `--max-turns 200`，且純量內沒有 `#` 註解行；
- worklog 納入 index 後的 doc-claims 掃描 277 檔、warning 0；附錄 A 雙向集合為
  tracked 242、listed 242、兩側差集皆空，MD5 同為 `83036c0c72467a32d37d454248803a1d`。

Node 實跑為 v24.19.0，超出專案宣告的 `>=22.12 <23`；前端 gate 綠只證明本次環境實跑，
不代表新增 Node 24 支援。上述結果回填改變受驗文檔後，提交前仍須從 setup 起重跑完整 29 項；
commit 後另跑 doc-claims，不能沿用回填前結果。

## 尚未完成或需注意的風險 (Pending / TODO)

1. 本 PR 修改 `.github/workflows/claude-review.yml`，依已實測的反竄改機制無法取得自己的
   Claude 判詞；必須保留 validation-skip 證據，並以 current-head Codex＋CI 驗收後由使用者
   人工合併。workflow job 顯示 success 本身不算 Claude 通過。
2. Opus 5 的實效只能由本 PR 合併後第一個未修改該 workflow 的 PR 做 canary。第一個目標是
   更新 PR #62 至含本變更的最新 `main`，再對其新 HEAD 重跑 CI、Codex 與 Claude。
3. 本輪只處置已被錯誤原文與既有沿革點名的模型額度問題；未改推理強度、工具權限、回合上限、
   自動合併開關或驗收判準。Fable 5 的能力理由未被推翻，未來額度恢復後是否切回仍屬另一次裁定。
4. 首輪 `bin/ci` 的 Windows 入口失敗已由 29 項等價 runner 從頭全綠取代；它仍是本機環境限制，
   不得刪掉失敗紀錄或反向宣稱原始 extensionless 入口已在 Windows 可用。
