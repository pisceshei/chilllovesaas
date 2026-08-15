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
  ⇒ 順帶也擋住 `off/no/true/false`（含 `On`/`YES` 這類**大小寫變體**）、`~/null`（→ nil）、
  `2026-08-15`（→ Date）等同類鍵，不是只擋 `on`（已實測三種：Date / NilClass / FalseClass 均判出）。
- **偵測到 ERB 一律 fail**（fail-closed）：loader 走
  `ActiveSupport::ConfigurationFile.parse`，它**先 render ERB 再解析 YAML**，
  本腳本讀的是原始檔 ⇒ 不擋就會出現「CI 綠燈但 runtime KeyError」。
  已實測 `<%= "on" %>: v` 在原始檔的 AST 裡是合法 String 鍵，但真正的 loader 產出 `[true]`。
- **`TARGETS` 是清單常數**：目前只有 `config/limits.yml`（鐵律 6 的唯一上限值來源）。
  要納管其他 config YAML 只加路徑，不必改邏輯。

**自測**：
- 正向：對修好的檔跑 → exit 0。
- 反向：把 `git show HEAD:config/limits.yml`（修前版）放進鏡像目錄跑 →
  **exit 1，抓到全部 6 筆**，行號 1986–1991 與原檔逐行對得上。
- 邊界（驗收後補）：`y: 1 / n: 2` → **exit 0**（是 String，正確放行）；
  `foo: { Off: 3 }` → **exit 1**（大小寫變體確實會轉，正確攔下）。
- ERB（驗收後補）：`<%= "on" %>: value` → **exit 1**；
  同一份檔給真正的 loader（`ActiveSupport::ConfigurationFile.parse`）產出 `[true]`，
  證實不擋就是 CI 綠燈而 runtime KeyError。
- `bundle exec rubocop scripts/check-limits-keys.rb` → no offenses。
- 既有兩支 check 腳本重跑仍全綠；GitHub Actions 上 `Check limits.yml key types` 步驟實跑 **success**。

### 3. 驗收後修正（PR #33 第 1 輪，兩個驗收方獨立指出同一條 🔴）

**🔴 `y`/`n` 的斷言是錯的**——初稿把 `y`/`n` 寫進 `YAML11_COERCED_WORDS` 與五處敘述，
宣稱它們會被轉布林。複驗（**Ruby 3.4.10 / Psych 5.2.2**，本專案鎖定版本）：

```
YAML.load("y: 1\nn: 2\nY: 3\nN: 4").keys  →  ["y", "n", "Y", "N"]   # 全是 String
```

YAML 1.1 **規格**的 bool 全集確實含 `y`/`n`，但 **Psych 5 的實作不轉**。
判定邏輯無恙（它比對型別、不比對字面，所以 `y`/`n` 鍵本來就正確地放行），
壞的是**錯誤訊息與文檔**：鍵解析成 TrueClass 時字面只可能是 `on`/`yes`/`true` 的大小寫變體，
訊息裡的 `y` 永遠是假訊息。

🔴 **這正是本 PR 要修的那一類錯誤**（註釋↔行為矛盾），出現在修它的 PR 自己身上。
⇒ 字表移除 `y`/`n`，五處敘述改為「on/off/yes/no/true/false（含大小寫變體）」，
並在字表上方寫明**為什麼刻意不含**、以及**不要反過來加一條「禁止裸字 y/n」的字面規則**
（那會擋掉 Psych 能安全 symbolize 的合法鍵，比假訊息更糟）。

順帶補到的：初稿也漏了**大小寫變體**（`Off`→FalseClass、`TRUE`→TrueClass），已一併寫入。

**ERB fail-closed**（同輪另一條）：見上一節第三點。

### 4. 第 3 輪：合併 main ＋ 補回歸測試

**觸發點**：第 2 輪推送後**完全沒有觸發任何 CI run**（不是失敗，是沒跑）。
查因＝main 合入 PR #29 後與本分支衝突，PR 變 `mergeable_state: dirty` ⇒
GitHub 建不出 merge ref ⇒ `pull_request` 事件不產生 run。
🔴 **監看腳本第一版只依 branch 過濾，把上一輪已完成的 run 當成本輪結果回報**——
已改為依 `head_sha` 過濾並要求 ≥2 個 run。
教訓與本 PR 主題同形：**綠燈來自一個沒真正驗到目標的檢查**。

**衝突只有一處**：`ci.yml` 的 quality job，雙方都在尾端追加步驟 ⇒ 兩邊都保留。
`config/limits.yml` 自動合併且語義正確（main 動 money_boundary／idempotency，
本分支動 jurisdictions.hk.accounting，位置不重疊），合併後重跑仍 exit 0。

**三件連帶改動**：

1. 🔴 **`Limits.fetch` 現在真的存在**（`app/models/limits.rb`，隨 PR #29 進 main）。
   第 2 輪把註釋裡的 `Limits.fetch` 改成 `Rails.configuration.x.limits`——
   那在當時是對的（main 沒有這個類別），現在要改回去。已全部改回 `Limits.fetch`。
   ⚠️ 順帶記一件事：`Limits` 缺鍵一律 raise，這是好事，但它的訊息是
   「缺少 limits.….M27.on 設定」——讀起來像**設定沒寫**，而檔案裡明明寫著 `on:`。
   根因仍然看不出來，本腳本補的正是這段落差。
2. **補回歸測試**：`scripts/test-limits-key-rules.rb` ＋ 三份 fixture
   （`spec/fixtures/ci_violations/limits_{bool_key,erb,clean}`），已掛 CI。
   `check-limits-keys.rb` 加一個**選用的 ROOT 參數**讓 fixture 可被指到（形態比照
   `check-money-boundary.rb`）。
   🔴 `limits_clean` 這份反向 fixture 刻意放了 `y:` / `n:` 鍵——它同時守住
   「不得反過來加一條禁止裸字 y/n 的字面規則」，真有人加了這裡會紅。
3. **meta 驗證**：把判定改壞（`unless resolved.is_a?(String)` → `if false`）後，
   `check-limits-keys.rb` 對乾淨倉庫**仍然 exit 0**（CI 全綠、什麼都不擋了），
   而 `test-limits-key-rules.rb` **exit 1 抓到**。改壞的版本已還原。

### 5. 掛進 CI（`.github/workflows/ci.yml`）

`quality` job 加兩步：`Check limits.yml key types` 與 `Regression-test limits key rules`，
排在 main 的 money 兩步之後，附註釋說明為什麼這一類必須由機制擋
（鍵名剛好是那幾個字時才出現，review 肉眼看不出來）。
已實測 `ci.yml` 仍可解析，且步驟落在 `quality` job 內（與其他 check 同 job，該 job 已有 ruby）。

---

## 修改的檔案與核心邏輯 (Changes)

| 檔案 | 改動 |
|---|---|
| `config/limits.yml` | M27–M32 六行 `on:` → `"on":`；區塊上方加註釋（YAML 1.1 成因、實測鍵值、誤修警告、指向本次的 CI 腳本） |
| `scripts/check-limits-keys.rb` | **新增**。Psych AST 遞迴走訪，對每個 mapping key 以 `to_ruby` 取實際型別，非 String 即違規並報 `檔:行` 與修法；`ERB_TAG` 偵測到 `<%` 即 fail-closed；選用 ROOT 參數供 fixture 測試 |
| `scripts/test-limits-key-rules.rb` | **新增**。上一支的回歸測試（fixture 驅動，含反向斷言），形態比照 `test-money-rules.rb` |
| `spec/fixtures/ci_violations/limits_{bool_key,erb,clean}/config/limits.yml` | **新增**。故意違反 ×2 ＋ 乾淨 ×1（後者刻意含 `y`/`n` 鍵，守住「不得加禁止 y/n 的字面規則」） |
| `.github/workflows/ci.yml` | `quality` job 新增 `Check limits.yml key types` 與 `Regression-test limits key rules` 兩步 |
| `docs/dev/m0-rails-skeleton.md` | 依 `AGENTS.md` 註釋與文檔節第 3 條（修 bug PR 更新受影響既有篇章）更新三處：「關鍵取捨與假設」#6 補鍵契約、「自動驗證」補本腳本、「變更記錄」補本輪 |
| `docs/worklog/2026-08-15-limits-yaml布林鍵陷阱.md` | 本檔 |

---

## 尚未完成或需注意的風險 (Pending / TODO)

1. 🔴 **只修了「鍵」，沒有動「值」**。值寫成裸 `on/off/yes/no` 而意圖是字串，會出同一種錯，
   但機械判定會大量誤報（`no_fund_pooling: true` 本來就該是布林）⇒ 值的型別正確性
   仍靠 code review 與各 spec。這一點已寫進腳本檔頭的誠實聲明，**不得**把腳本宣傳成「限制檔型別全檢」。

2. ⚠️ **`M27..M32` 的 `on` 這個鍵名本身沒有被檢討**。本次只保證它「是字串 `"on"`」，
   沒有問「entry point 的觸發事件欄位該不該叫 `on`」。若日後改名為 `trigger`/`event`，
   YAML 1.1 陷阱自然消失，但**那是規格決定，不是這次該做的**——我沒有代為改名。

3. ✅ **回歸測試已補**（原本列為未完成，第 3 輪合併 main 後改判——見「已完成」第 5 節）。
   `scripts/test-limits-key-rules.rb` ＋ 三份 fixture，已掛 CI。
   🔴 原本不補的理由是「既有兩支 `check-*.rb` 都沒有，比照辦理」——
   那個理由在 main 合入 PR #29 之後**不成立**了（`scripts/test-money-rules.rb` 立了慣例，
   65 §K.7 更逐字寫「只有前者綠不算交付」）。**理由會過期，過期就要重判。**

4. ⚠️ **其他 config YAML 未納管**（`config/brand.yml` 等）。`config_for` 同樣會 symbolize，
   同一個陷阱在那些檔上一樣成立，只是目前沒有踩到。加進 `TARGETS` 即可，但**我沒有擅自擴大範圍**——
   本輪的授權範圍是 limits.yml。

5. ⚠️ **ERB 是「擋下來」不是「檢查過了」**。`limits.yml` 目前零個 ERB tag，
   本腳本偵測到 `<%` 直接 fail。日後真要用 ERB，必須先擴充腳本
   （render 後解析＋行號映射），**不要把閘門拿掉**——拿掉就回到「CI 綠燈但 runtime KeyError」。

6. ⚠️ **`y`/`n` 的結論綁在 Psych 版本上**（Ruby 3.4.10 / Psych 5.2.2，2026-08-15 取證）。
   YAML 1.1 規格含 y/n、Psych 5 不轉——這是**實作行為**不是規格保證。
   升級 Psych 時若行為變回去，字表與五處敘述要一起重驗。
   （比照專案「規則性斷言標註取證日期」慣例登記。）

7. ✅ **全檔掃描已做，沒有其他同類鍵**。修後遍歷 `config/limits.yml` 全部鍵，
   非 String 鍵為 0（不只是那 6 個被修好，是整檔確認乾淨），登記以免下一個人重掃。
