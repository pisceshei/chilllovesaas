# 2026-08-15 — 修 limits.yml 的 YAML 1.1 布林鍵陷阱（並機制化）

> 發現來源：PR #29 驗收後的「註釋↔行為矛盾掃描」。**與 PR #29 的 `decimal_string` 位數閘門無關**，
> 是掃描過程中順帶查出的獨立缺陷，獨立處理。

---

## 已完成的工作 (Done)

### 1. 修好那 6 個鍵（`config/limits.yml`）

`jurisdictions.hk.accounting.gift_card_entry_points.M27..M32` 原文：

```yaml
M27: { on: gift_card_issued_by_admin, direction: liability_increase, revenue: 0 }
```

Psych 走 **YAML 1.1**，裸字 `on` 解析成布林 `true`ᅠ⇒ 這六筆的鍵是 `true`（TrueClass），
**不是**字串 `"on"`。全部改為 `"on":`（加引號），並在區塊上方補一段註釋說明成因與誤修方向。

**修前實測**（`ruby -ryaml` 遍歷全檔）：非 String 鍵 **6 個**，路徑正是 M27–M32 的 `on`，型別皆 `TrueClass`。
**修後實測**：非 String 鍵 **0 個**。

**端到端實測**（走 `config/application.rb` 真正用的那條路徑，
`ActiveSupport::ConfigurationFile.parse(...).deep_symbolize_keys`）：

| | M27 的鍵 | `.fetch(:on)` |
|---|---|---|
| 修前 | `[true, :direction, :revenue]` | `KeyError: key not found: :on` |
| 修後 | `[:on, :direction, :revenue]` | `"gift_card_issued_by_admin"` |

🔴 **為什麼 `deep_symbolize_keys` 沒有救回來**：它對非字串鍵**原樣保留**（`true` 不能 `to_sym`），
所以錯誤不會在載入時炸，而是延到取值端才變成 KeyError——**而 KeyError 的訊息看不出根因**。
這正是它值得修的理由：實作禮品卡會計（M27–M32）的人撞到時，
最可能的反應是「那就改用 `true` 當鍵」，**那會把 bug 固化成契約**（鍵名從此不是檔案裡看起來的樣子）。

### 2. 機制化：新增 `scripts/check-limits-keys.rb`（CI 跑）

斷言 `config/limits.yml` 每一層 mapping 的鍵都解析成 String。
比照既有 `check-tenant-isolation.rb` / `check-reversal-naming.rb` 的形態：
檔頭寫背景與**誠實聲明**（不檢查什麼）、退出碼 0/1、失敗訊息走 `::error::`。

三個實作決定：

- **走 Psych AST 而不是走 load 出來的 Hash**：AST 的 scalar node 帶 `start_line`，
  能把違規指到**確切行號**；load 出來的 Hash 只剩值，報不出位置。
- **判定用 `key_node.to_ruby` 的實際型別，不是自己重寫一份 YAML 1.1 字表**。
  檔內那張 `YAML11_COERCED_WORDS` **只用於產生提示文字**——表漏字不會讓違規逃掉。
  ⇒ 順帶也擋住 `off/no/y/n`、`~/null`（→ nil）、`2026-08-15`（→ Date）等同類鍵，
  不是只擋 `on`（已實測三種：Date / NilClass / FalseClass 均判出）。
- **`TARGETS` 是清單常數**：目前只有 `config/limits.yml`（鐵律 6 的唯一上限值來源）。
  要納管其他 config YAML 只加路徑，不必改邏輯。

**自測**：
- 正向：對修好的檔跑 → exit 0。
- 反向：把 `git show HEAD:config/limits.yml`（修前版）放進鏡像目錄跑 →
  **exit 1，抓到全部 6 筆**，行號 1986–1991 與原檔逐行對得上。
- `bundle exec rubocop scripts/check-limits-keys.rb` → no offenses。
- 既有兩支 check 腳本重跑仍全綠。

### 3. 掛進 CI（`.github/workflows/ci.yml`）

在 `quality` job 的 `Check reversal naming` 之後加 `Check limits.yml key types`，
附註釋說明為什麼這一類必須由機制擋（鍵名剛好是那幾個字時才出現，review 肉眼看不出來）。
已實測 `ci.yml` 仍可解析，且步驟落在 `quality` job 內（與其他 check 同 job，該 job 已有 ruby）。

---

## 修改的檔案與核心邏輯 (Changes)

| 檔案 | 改動 |
|---|---|
| `config/limits.yml` | M27–M32 六行 `on:` → `"on":`；區塊上方加註釋（YAML 1.1 成因、實測鍵值、誤修警告、指向本次的 CI 腳本） |
| `scripts/check-limits-keys.rb` | **新增**。Psych AST 遞迴走訪，對每個 mapping key 以 `to_ruby` 取實際型別，非 String 即違規並報 `檔:行` 與修法 |
| `.github/workflows/ci.yml` | `quality` job 新增 `Check limits.yml key types` 步驟 |
| `docs/worklog/2026-08-15-limits-yaml布林鍵陷阱.md` | 本檔 |

---

## 尚未完成或需注意的風險 (Pending / TODO)

1. 🔴 **只修了「鍵」，沒有動「值」**。值寫成裸 `on/off/yes/no` 而意圖是字串，會出同一種錯，
   但機械判定會大量誤報（`no_fund_pooling: true` 本來就該是布林）⇒ 值的型別正確性
   仍靠 code review 與各 spec。這一點已寫進腳本檔頭的誠實聲明，**不得**把腳本宣傳成「限制檔型別全檢」。

2. ⚠️ **`M27..M32` 的 `on` 這個鍵名本身沒有被檢討**。本次只保證它「是字串 `"on"`」，
   沒有問「entry point 的觸發事件欄位該不該叫 `on`」。若日後改名為 `trigger`/`event`，
   YAML 1.1 陷阱自然消失，但**那是規格決定，不是這次該做的**——我沒有代為改名。

3. ⚠️ **本腳本沒有自己的回歸測試**。`lint-prototype.py` 有 `test-lint-rules.py` 配對，
   但既有兩支 `check-*.rb` 都沒有，本支比照辦理。本輪的反向測試是**手動**跑的
   （鏡像目錄 ＋ `git show HEAD:config/limits.yml`），沒有固化成 CI 會重跑的東西。
   ⇒ 日後若有人改壞判定邏輯（例如把 `is_a?(String)` 寫反），CI 會靜默放行。
   要補的話，做法與 `test-lint-rules.py` 同形：準備一份「已知有違規」的 fixture YAML 斷言 exit 1。

4. ⚠️ **其他 config YAML 未納管**（`config/brand.yml` 等）。`config_for` 同樣會 symbolize，
   同一個陷阱在那些檔上一樣成立，只是目前沒有踩到。加進 `TARGETS` 即可，但**我沒有擅自擴大範圍**——
   本輪的授權範圍是 limits.yml。

5. ✅ **全檔掃描已做，沒有其他同類鍵**。修後遍歷 `config/limits.yml` 全部鍵，
   非 String 鍵為 0（不只是那 6 個被修好，是整檔確認乾淨），登記以免下一個人重掃。
