# 工作記錄：死控件 lint 規則 —— PR #28 第二輪 review 修正（2026-08-14）

> 同一功能的第一份工作記錄＝`docs/worklog/2026-08-14-死控件lint規則.md`。
> 本份是**第二個可獨立驗收單位**：Claude 對 `4efb0fa` 的四條建議之處置。
> 第一輪 review（六條漏看）的處置記在 commit `4efb0fa` 與 PR #28 留言，
> 判準與六種漏看形態的正典＝`docs/specs/89` §7。

## 已完成的工作 (Done)

Claude 對 `4efb0fa` 給【驗收結論】通過，附四條 🟡 建議。**逐條查證後全部屬實**
（三條實症、一條潛在），全部修掉：

| # | 建議 | 查證結果 | 處置 |
|---|---|---|---|
| ① | `89 §7.6` 排在 `§7.5` 之前 | 屬實（341 vs 358 行） | 合併成單一 §7.5 |
| ② | 「六種漏看」表第 4 列有未跳脫的字面換行 | 屬實（`cat -A` 確認 `\| 4 \| \`[^>` 後直接斷行） | 改 `[^>\n]` |
| ③ | `_attr_ok` 掃整串選擇器 ⇒ 逗號複合選擇器誤報 | 邏輯屬實；**目前三份原型 0 個實例** ⇒ 潛在未發作 | `_split_selectors()` 拆段 ＋ fixture ×2 |
| ④ | 基準線調高只靠 review 肉眼判斷方向 | 屬實，且是本 PR 自陳的紀律缺口 | 新增 `scripts/check-baseline-raise.py`，掛 CI |

### ① §7.5／§7.6 不只是換順序

Claude 同時指出「§7.5 的手動四項測試已被 §7.6 的 19 條 fixture 完整涵蓋，
可考慮合併以免兩份測試紀錄各說各話」。**採納合併而不是只調順序**——
兩份紀錄並存時，過期的那份會變成新的誤導來源，而這正是 ⑥ 號建議
（PR 描述數字過期）的同一種病。

### ③ 方向與前六種相反：這是**誤報**

前六種漏看全部是**少報**（規則看不到壞東西）。第 ③ 條是**誤報**（規則冤枉好東西）：

```js
querySelectorAll('.mkt-country, .tgl[role="switch"]')
```

`_attr_ok` 對整串掃 `[attr=value]`，於是靠 `.mkt-country` 當把手的控件
**被要求也得有 `role="switch"`**，一個實際上被讀取的控件被判成死控件。

🔴 **誤報比少報更危險**：少報只是規則沒發揮價值，誤報會讓人把規則關掉——
這正是 §7.1 一開始就避開「必須有 onclick」天真判準的同一個理由。

修法 `_split_selectors()`：依**頂層逗號**拆段，逐段比對。逗號可以合法出現在
`[data-x="a,b"]` 與 `:not(...)`／`:is(...)` 裡，所以只在**引號外且括號深度 0**
時才切。fixture 補**雙向**兩條：另一段的條件不得加到我頭上／我這一段的條件仍要驗
（後者防「拆段拆過頭、把該驗的也丟了」）。

### ④ 這條建議打在本 PR 的自我矛盾上

`DEAD_CONTROL_BASELINE` 的註釋寫著「調高必須同時有量表本身的修正，
否則就是把新增的死控件就地合法」——**但那條規則自己只靠 review 肉眼看 diff 方向**。
而 89 §7 這一節的標題就叫「把死控件從紀律變成機制」。

`scripts/check-baseline-raise.py` 的判準**刻意保守**：

- 任一檔調高 **＋** 掃描邏輯零 diff ⇒ **fail**
- 調降 ⇒ **永遠放行**（清存量是好事，本來就該順手調降）
- 量表變準造成的調高 ⇒ 必然連帶改到掃描邏輯 ⇒ 自然通過

指紋用 **AST 取三個掃描函式**（`_strip_comments`／`_iter_control_tags`／`r_dead_control`）
而不是整檔比對——整檔比對會讓「改了別的規則」也算「量表變了」，等於沒擋。

三條路徑各實測一次：

| 情境 | 期望 | 實測 |
|---|---|---|
| A 只調高數字（43→60），掃描邏輯不動 | fail | `::error::` ＋ exit 1 ✅ |
| B 同樣調高，但 `LIMIT` 改一個字 | pass | exit 0，訊息列出「有對應修正」✅ |
| C 調降（43→30） | pass | exit 0，訊息列出調降值 ✅ |

## 修改的檔案與核心邏輯 (Changes)

- `scripts/lint-prototype.py`：新增 `_split_selectors()`（引號／括號感知的頂層逗號切分）；
  `_blob_hit()` 改為**逐段**尋找 token 並對**該段**呼叫 `_attr_ok`
- `scripts/test-lint-rules.py`：19 → **21** 條 fixture（逗號複合選擇器雙向各一）
- `scripts/check-baseline-raise.py`（新增）：`_baseline()` 用 `ast.literal_eval` 取字面值
  （不 import，避免執行舊版程式）、`_scanner_src()` 用 AST 取三個函式當指紋；
  取不到 base ref 一律略過並回 0
- `.github/workflows/ci.yml`：新增 `Guard dead-control baseline` 步驟。
  🔴 先 `git fetch --depth=1 origin "$BASE"` 再比 `FETCH_HEAD`——
  `actions/checkout` 預設淺 clone，`origin/main` 這個 ref 根本不存在，
  直接比會每次都走「略過」，機制形同沒掛
- `docs/specs/89-prototype-defect-reverify.md`：修表格斷行；§7.5／§7.6 合併為單一 §7.5；
  §7.4 增補「調高基準線的合法性：已從紀律變成機制」小節

## 尚未完成或需注意的風險 (Pending / TODO)

- 🔴 **`check-baseline-raise.py` 擋不住「改了掃描邏輯又順手多調幾個」**——
  那仍要 review 判斷。腳本 docstring 已明寫這件事，以免它被讀成保證。
  機制的目的是把**不需要判斷的那一半**變成硬失敗。
- 🔴 **`SCANNER_FNS` 是硬編的函式名清單**。往後把掃描邏輯搬到新函式而忘了加進清單，
  機制會**靜默失效**（方向是少擋，不會誤擋，所以不會有人發現）。
  沒有為這件事再加一層檢查——再加就變成無限遞迴的自我保護。
- **`_split_selectors` 不處理 `:not(.a, .b)` 內部的語義**：括號內的逗號不切是對的，
  但 `:not()` 的語義（排除）本來就沒被 `_attr_ok` 模型化，維持既有啟發式限度。
- **123 條存量死控件仍未清**（admin 43／platform-admin 25／storefront 55）。
  storefront 那 55 條所在的檔案至今沒有人工複核過。**歸屬**：storefront 屬 M2、
  platform-admin 屬 M8，本輪刻意不動。
- 本輪只有 CI 步驟是**未經 GitHub Actions 實跑驗證**的部分——本機三路徑都測了，
  但 `github.base_ref` 在真實 PR 事件下的值要等這次 CI 跑完才算證實。
