# 38 — 平台後台實作手冊 · 信任安全與治理

> 本篇是 `docs/specs/35` 的分冊之一。涵蓋：違規處置／申訴／合規（DSR・電子發票・個資通報・前台巡檢）／審計日誌（append-only 四層防護）／人員與權限（JIT・break-glass・複核）。

## 違規處置（波次 W2）

### 1. 這是什麼、給誰用、解決什麼問題（含法源）

**是什麼**：平台對租戶違規行為的**執法台**——把「發現 → 立案 → 證據 → 積分 → 處置 → 通知 → 申訴 → 恢復」做成一條有留痕的閉環，取代 Slack 上喊一聲就把店關掉。

**給誰用**：信任安全（Trust & Safety）審核員為主要操作者；`support` 可讀＋可建案不可執行處置；`admin` 可執行到「限制交易」為止；`查封帳戶`／`強制退款` 需 `platform_owner` ＋四眼（見模組五 §4 dual control）。

**解決什麼問題**：
1. **尺度不一致**——同樣「保健食品療效宣稱」，A 審核員下架商品、B 審核員直接鎖店。積分制把裁量收斂成規則。
2. **無法對外舉證**——商家申訴或主管機關詢問時，拿不出「當時看到什麼、依哪條規則、誰批准的」。
3. **恢復條件說不清**——處置之後永遠沒人敢解除。33 §2.7 給了明確恢復條件：**糾正全部違規＋處理措施執行完畢且期限屆滿**。

**制度出處與法源**：

| 面向 | 出處 | 內容 |
|---|---|---|
| 處置階梯 | 33 §2.7（有贊《商家管理規範》） | 市場管控 5 項＋違規處理 11 項 |
| 精簡階梯 | 33 §2.7（Shopify 執法階梯） | 內容下架 → 停用付款 → 限制 admin → 鎖店 → 終止帳號 |
| 積分制 | 33 §2.7 | A 類（一般）／B 類（嚴重）**雙軌獨立累計、分別執行**；自然年累計；未達 B 類 48 分者年底清零 |
| 恢復條件 | 33 §2.7 | 糾正全部違規＋處理措施執行完畢且期限屆滿 |
| 自動開案觸發 | 33 §2.5＋原型 `ratemonitor` | 爭議率越 VAMP／ECM／HECM／EFM 門檻 → 自動開違規案件＋限制提現 |
| 平台實質責任 | 33 §2.13 | 平台業者須訂定個資保護守則並**要求租戶遵守** → 租戶違反守則本身即為可立案事由 |
| 違禁品掃描類別 | 原型 `violcases` 掃描按鈕 | 保健食品療效宣稱／醫療器材／藥事法／酒類廣告警語（原型 `VIOL` 另有「疑似仿冒品」「廣告法違禁詞」） |

> **待定，需使用者確認**：上述四類違禁品各自對應的**法條條號、主管機關、罰則級距**，33 號與原型皆未載明。實作時 `prohibited_rules.legal_basis` 欄位先留空字串並在 UI 顯示「法源待補」，不得由工程端自行填入條號。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `pointsrule`（頁首說明帶） | 說明 A／B 雙軌積分規則 | 靜態文案，但**數值由 `violation_point_policies` 生成**不得硬編碼：雙軌獨立累計、自然年清零、B 類 48 分為分水嶺（33 §2.7） | 政策版本變更時本帶顯示「政策 v{n}，{生效日}起適用」；舊案沿用立案時的政策版本 |
| `violcases`（案件表） | 案件／商店／類型／積分／已執行處置／狀態 | 欄位對照原型 `VIOL`：`id / n / cat / type(A|B) / pt / act / st`。積分 badge：A 類 `attention`、B 類 `critical`（原型 `renderAll`）。cursor 分頁 ≤250（28 §0.3） | 空結果附「清除篩選」；列點擊進案件詳情；`已結案` 列不可再執行處置 |
| 「違禁品掃描 12」按鈕（`violcases` 內） | 進違禁品掃描待審佇列，badge＝`pending` 命中數 | badge 數字與佇列頁 count **同源**（單一 rollup 查詢，CLAUDE.md §7 數字同源） | 0 時 badge 隱藏不顯示「0」；>99 顯示 `99+` |
| 「建立案件」（page-actions 主鈕） | 人工立案 | 必填：`shop_id`、`category`（違規類型字典）、`track(A/B)`、`points`、至少 1 筆證據。points 預設值由 `violation_categories.default_points` 帶入，可覆寫但覆寫需填理由 | 覆寫 points 且偏離預設 >50% → 二次確認＋要求 `platform_owner` 核准 |
| 「處置動作清單」→ `ovLadder` modal | 展示 16 項動作階梯 | 市場管控 5 項：警告｜商品下架｜限制參加營銷活動｜單品監管｜店鋪監管。違規處理 11 項：警告｜刪除商品｜刪除店鋪主頁｜刪除頁面｜限制社區功能｜**強制退款**｜限制參加平台活動｜限制交易｜**限制提現與轉帳**｜**公示警告**｜**查封帳戶**（原型 `ovLadder`；33 §2.7 第四項寫「刪除微頁面」，原型寫「刪除頁面」，見 §12 規格衝突） | modal 為唯讀展示；每一階旁標「原因碼／證據／通知／可申訴」四要件皆為必要條件 |
| 案件列「處置」按鈕 | 開處置抽屜，勾選動作組合 | 勾選後即時試算：本次追加積分、A／B 兩軌新總分、是否跨越 12／24／48 節點、是否觸發連動的 `shop_restrictions` 旗標（33 §2.2 六旗標） | 勾到 `查封帳戶` → 紅主鈕＋輸入商店名確認（比照 32 §3-3 危險區慣例）；未勾任何動作 → 主鈕 disabled |
| 案件詳情：證據頁籤 | 截圖／URL／商品快照／原始 HTML 摘要 | 證據**不可刪除**，只能追加與標記 `superseded`；每筆證據存 `captured_at` 與擷取者 | 證據 0 筆時禁止執行任何處置（`userErrors: EVIDENCE_REQUIRED`） |
| 案件詳情：積分頁籤 | 本案積分流水與該店年度雙軌總分 | 讀 `violation_points_ledger`；顯示「距 B 類 48 分還有 n 分」 | B 軌 ≥48 → 卡片轉 critical 並顯示「年底不清零、結轉次年」 |
| 案件詳情：通知頁籤 | 已寄出的商家通知與已讀狀態 | 每執行一階處置必發通知（33 §2.7 四要件）；通知模板帶申訴入口與期限 | 通知寄送失敗 → 處置**不回滾**但案件標 `notification_failed` 並進工單 |
| 案件詳情：申訴頁籤 | 關聯申訴案 | 有 `appeals.state IN (new, info_required)` 時，本案 `status` 顯示為「申訴中」（原型 `VIOL` V-3065） | 申訴進行中預設**不暫停處置**（除非審核員明示 `suspend_pending_appeal`） |

---

### 3. 資料模型

全部為**租戶域表**：帶 `shop_id`，複合索引以 `shop_id` 開頭（CLAUDE.md 鐵律 2）。金額 integer cents。

```ruby
# db/migrate/20260901000010_create_violation_cases.rb
# 對應 docs/design/33-platform-admin-benchmark.md §6「violation_cases／violation_points_ledger／appeals」
create_table :violation_cases do |t|
  t.references :shop, null: false, foreign_key: true          # 多租戶鐵律
  t.string  :code,        null: false                          # 顯示用 V-3081（原型 VIOL.id）
  t.string  :category_key, null: false                         # 對 violation_categories.key
  t.string  :track,       null: false                          # 'A'|'B'（33 §2.7 雙軌）
  t.integer :points,      null: false, default: 0              # 本案積分
  t.string  :status,      null: false, default: "open"
  # open / acting / awaiting_appeal_window / appealing / remediating / resolved / withdrawn
  t.string  :source,      null: false                          # manual / prohibited_scan / dispute_threshold / compliance_scan / report
  t.string  :source_ref                                        # 觸發來源的 GID
  t.bigint  :policy_version, null: false                       # 立案時的積分政策版本（政策改版不追溯）
  t.datetime :appeal_deadline_at                               # 申訴期限
  t.datetime :remediation_due_at
  t.datetime :recovered_at                                     # 恢復條件全部成立的時點（33 §2.7）
  t.bigint  :opened_by_staff_id
  t.bigint  :closed_by_staff_id
  t.timestamps
end
add_index :violation_cases, [:shop_id, :status, :created_at], name: "idx_vcase_shop_status"
add_index :violation_cases, [:shop_id, :track, :created_at],  name: "idx_vcase_shop_track"
add_index :violation_cases, :code, unique: true
```

其餘表（欄位摘要）：

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `violation_categories` | `key`, `label`, `default_track`, `default_points`, `legal_basis`（可空，待定）, `evidence_hint`, `active` | 違規類型字典。原型類型：酒類廣告未加警語／保健食品療效宣稱／疑似仿冒品／廣告法違禁詞／爭議率越線 |
| `violation_points_ledger` | `shop_id`, `case_id`, `track`, `delta`, `balance_after`, `year`, `effective_on`, `kind`(accrue / expire / adjust / carry_over), `reason`, `actor_staff_id` | **append-only 語意**：修正用反向 `adjust` 列，不 UPDATE。索引 `[shop_id, track, year, effective_on]` |
| `violation_actions` | `shop_id`, `case_id`, `action_key`, `family`(market_control / violation_handling), `params JSON`, `amount_cents`（強制退款用）, `effective_at`, `expires_at`, `state`(pending / applied / reverted / failed), `restriction_id`, `applied_by`, `reverted_by`, `revert_reason`, `idempotency_key` | 一階處置一列。`expires_at` 到期由 job 自動 revert |
| `violation_evidences` | `shop_id`, `case_id`, `kind`(screenshot / url / product_snapshot / html_excerpt / third_party_notice), `blob_ref`, `sha256`, `captured_at`, `captured_by`, `superseded_by_id` | 不可刪、不可改，只能 supersede |
| `violation_notices` | `shop_id`, `case_id`, `action_id`, `channel`(email / admin_banner / webhook), `template_key`, `sent_at`, `read_at`, `delivery_state` | 33 §2.7 通知要件的留痕 |
| `violation_point_policies` | `version`, `effective_at`, `year_end_rule JSON`, `thresholds JSON`, `published_by` | **平台域表**（無 shop_id，見白名單）。`thresholds` 形如 `{"B":[{"points":12,...},{"points":24,...},{"points":48,...}]}` |
| `prohibited_rules` | `key`, `category_key`, `terms JSON`, `regex`, `scope`(title / body_html / tags / all), `confidence_base`, `legal_basis`（待定）, `version`, `active` | **平台域表**。字典＋regex，版本化 |
| `prohibited_scan_hits` | `shop_id`, `product_id`, `rule_key`, `rule_version`, `matched_terms JSON`, `excerpt`, `confidence`, `content_digest`, `state`(pending / confirmed / dismissed / suppressed), `case_id`, `triaged_by`, `triaged_at` | 索引 `[shop_id, state, created_at]`；`[shop_id, product_id, rule_key, content_digest]` 唯一（去重） |
| `prohibited_suppressions` | `shop_id`, `rule_key`, `term`, `reason`, `expires_at`, `approved_by` | 誤判白名單，**必須有到期日**（預設 180 天，待定：期限需使用者確認） |

**平台域表白名單（本模組）**：`violation_point_policies`、`prohibited_rules`。此二表為全平台共用字典／政策，無 `shop_id` 是刻意設計；查詢一律在 `Platform::` 命名空間內，不經 `ActsAsTenant` 作用域（32 §0 跨租戶查詢紅線）。

---

### 4. API 契約（Platform:: GraphQL）

端點 `/platform/api/2026-08/graphql.json`（32 §6）。GID：`gid://chilllove/ViolationCase/{id}`、`gid://chilllove/ProhibitedScanHit/{id}`。

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformViolationCases` | query | `query, shopId, track, status, source, first≤250, after` | `ViolationCaseConnection` | — | 全部（含 `read_only`） |
| `platformViolationCase` | query | `id!` | `ViolationCase`（含 evidences／actions／points／notices／appeal） | `NOT_FOUND` | 全部 |
| `platformViolationPoints` | query | `shopId!, year` | `{ aPoints, bPoints, entries, nextThreshold, willCarryOver }` | `NOT_FOUND` | 全部 |
| `platformProhibitedScanHits` | query | `state, ruleKey, shopId, first, after` | `ProhibitedScanHitConnection` | — | 全部 |
| `platformViolationCaseCreate` | mutation | `input{ shopId!, categoryKey!, track, points, summary!, evidences[]!, source, sourceRef, idempotencyKey! }` | `{ violationCase, userErrors }` | `VALIDATION_FAILED` `EVIDENCE_REQUIRED` `SHOP_NOT_FOUND` `IDEMPOTENCY_CONFLICT` | `support`＋ |
| `platformViolationCaseActionApply` | mutation | `input{ caseId!, actions[{ actionKey!, params, amountCents, effectiveAt, expiresAt }]!, reasonCode!, note, notifyMerchant=true, confirmShopName, idempotencyKey! }` | `{ violationCase, appliedActions, restrictions, userErrors }` | `FORBIDDEN` `EVIDENCE_REQUIRED` `DUAL_APPROVAL_REQUIRED` `CONFIRM_NAME_MISMATCH` `INVALID_STATE` `ACTION_NOT_IN_LADDER` | `admin`＋；`forced_refund`／`account_ban` 需 `platform_owner`＋JIT 提權 |
| `platformViolationActionRevert` | mutation | `id!, reason!, idempotencyKey!` | `{ action, userErrors }` | `FORBIDDEN` `ALREADY_REVERTED` | `admin`＋ |
| `platformViolationCaseClose` | mutation | `id!, resolution!(REMEDIATED\|WITHDRAWN\|UPHELD), note, idempotencyKey!` | `{ violationCase, userErrors }` | `RECOVERY_CONDITIONS_UNMET` `APPEAL_IN_PROGRESS` | `admin`＋ |
| `platformViolationPointsAdjust` | mutation | `caseId!, track!, delta!, reason!, idempotencyKey!` | `{ ledgerEntry, userErrors }` | `FORBIDDEN` `DUAL_APPROVAL_REQUIRED` | `platform_owner`＋四眼 |
| `platformProhibitedScanHitTriage` | mutation | `id!, decision!(CONFIRM\|DISMISS\|SUPPRESS), caseInput, suppressUntil, reason!, idempotencyKey!` | `{ hit, violationCase, userErrors }` | `ALREADY_TRIAGED` `SUPPRESSION_REQUIRES_EXPIRY` | `support`＋ |
| `platformProhibitedScanRun` | mutation | `shopId, full=false, idempotencyKey!` | `{ jobId, userErrors }` | `RATE_LIMITED` | `admin`＋ |

**慣例遵循**：業務錯誤一律 `userErrors{field,message,code}` ＋ HTTP 200（28 §0.3）；`platformViolationCaseActionApply` 為寫入型，`idempotencyKey` 必填（28 §0.6、11 §2）；金額欄位序列化為 `MoneyV2`，內部 integer cents。

---

### 5. 服務物件與背景任務

**服務物件**（全在 `app/services/platform/violations/`）：

| 類別 | 職責 | 交易邊界 |
|---|---|---|
| `Platform::Violations::OpenCase` | 建案＋首筆積分＋證據落地 | 單一 transaction；通知丟 job（11 §2「transaction 內禁外部 IO」） |
| `Platform::Violations::ApplyActions` | 驗證階梯合法性 → 寫 `violation_actions` → 呼叫 `Platform::Restrictions::Apply`（W1 模組介面）→ 記積分 → 排通知 job | 單一 transaction；provider／email／webhook 全在 transaction 外 |
| `Platform::Violations::PointsLedger` | 雙軌加減、跨節點判定、年度結轉 | 條件式 UPDATE 更新 `balance_after`（11 §3 三板斧第一招） |
| `Platform::Violations::LadderAdvisor` | 依 category＋歷史積分推薦下一階動作（**只推薦不執行**） | 純函式，無寫入 |
| `Platform::Violations::RecoveryChecker` | 判定 33 §2.7 三條恢復條件 | 唯讀 |
| `Platform::Violations::ProhibitedScanner` | 對單一商品跑 `prohibited_rules` | 唯讀＋批次 INSERT hits |

**背景任務**（Solid Queue，佇列名見原型 `QUEUES`）：

| Job | 排程 | 說明 |
|---|---|---|
| `Platform::Violations::ProhibitedScanJob(shop_id, product_ids)` | 商品 create/update 事件觸發（增量）＋每日 03:00 全量 | 進場 `ActsAsTenant.with_tenant`（11 §8 坑 1）；以 `content_digest` 去重 |
| `Platform::Violations::ActionExpiryJob` | 每 10 分鐘 | 掃 `violation_actions.expires_at <= now AND state='applied'` → revert，並寫審計 |
| `Platform::Violations::PointsYearEndJob` | 每年 12/31 23:50（**依 shop 時區換算**，11 §8 坑 5） | 執行 33 §2.7 清零規則 |
| `Platform::Violations::RecoveryScanJob` | 每小時 | 恢復條件成立 → 案件轉 `resolved` 並通知商家 |
| `Platform::Violations::NoticeJob(notice_id)` | 事件觸發 | 寄送＋回寫 `delivery_state`；失敗指數退避，3 次後開工單 |
| `Platform::Violations::DisputeThresholdWatcher` | 每日（由 W2 爭議模組觸發） | 越線自動 `OpenCase(source: 'dispute_threshold')`＋限制提現（33 §2.5、原型 `ratemonitor`） |

---

### 6. 關鍵流程與演算法

#### 6-1 A／B 雙軌積分累計與年度清零

```ruby
# app/services/platform/violations/points_ledger.rb
module Platform
  module Violations
    # 違規積分帳本（A／B 雙軌）。
    #
    # 為什麼要雙軌：33 §2.7 明訂「A 類（一般）／B 類（嚴重）雙軌獨立累計、分別執行」。
    # 一般實作會把兩類加權成單一分數——那會讓「20 個 A 類小違規」等同「一個 B 類嚴重違規」，
    # 執法邏輯就錯了。兩軌必須是兩個獨立餘額，各自有自己的門檻表。
    class PointsLedger
      TRACKS = %w[A B].freeze

      # @param shop [Shop]
      # @param year [Integer] 自然年（33 §2.7「自然年累計」）
      def initialize(shop, year: Time.current.in_time_zone(shop.timezone).year)
        @shop = shop
        @year = year
      end

      # 記一筆積分並回傳新餘額。
      # @param track [String] "A" | "B"
      # @param delta [Integer] 正數＝累計，負數＝調整（人工修正一律用反向列，不改舊列）
      # @return [ViolationPointsLedger]
      def accrue!(track:, delta:, case_id:, kind: "accrue", reason: nil, actor_staff_id: nil)
        raise ArgumentError, "bad track" unless TRACKS.include?(track)

        # 為什麼用悲觀鎖而不是條件式 UPDATE：這裡需要「讀當前餘額 → 算新餘額 → 寫入」的複合操作，
        # 且新餘額要回寫進帳列（balance_after）供稽核重建。鎖順序固定為 shop 級資源優先（11 §3）。
        ViolationPointsLedger.transaction do
          current = balance(track, lock: true)
          entry = ViolationPointsLedger.create!(
            shop_id: @shop.id, case_id:, track:, delta:, kind:, reason:,
            actor_staff_id:, year: @year, effective_on: Date.current,
            balance_after: current + delta
          )
          @crossed = crossed_thresholds(track, from: current, to: current + delta)
          entry
        end
      end

      # 跨越的門檻節點（供 LadderAdvisor 用）。
      # 為什麼門檻放 DB 不放常數：33 §9 明載「有贊 A/B 類積分的節點分數對應措施表官方頁未展開，
      # 僅確認 B 類 48 分為分水嶺」——12／24／48 各觸發什麼是【待定】，必須可由營運端改而不重新部署。
      def crossed_thresholds(track, from:, to:)
        policy.thresholds.fetch(track, []).select { |t| from < t["points"] && to >= t["points"] }
      end

      def balance(track, lock: false)
        scope = ViolationPointsLedger.where(shop_id: @shop.id, track:, year: @year)
        scope = scope.lock("FOR UPDATE") if lock
        scope.sum(:delta)
      end

      # 年度清零。
      # 33 §2.7：「自然年累計，未達 B 類 48 分者年底清零」。
      # 【待定，需使用者確認】原文未言明「B 類滿 48 分時 A 軌是否一併結轉」。本實作採
      # 「以 B 軌是否達 48 分決定兩軌一起清零或一起結轉」，因為 33 §2.7 把 48 分描述為
      # 商家整體的「分水嶺」而非單軌規則。若使用者確認應分軌判定，改動點只有這一個方法。
      def year_end_settle!
        b = balance("B")
        carry = b >= policy.carry_over_threshold   # 預設 48（33 §2.7）
        return :carried_over if carry

        TRACKS.each do |track|
          bal = balance(track)
          next if bal.zero?
          ViolationPointsLedger.create!(
            shop_id: @shop.id, track:, delta: -bal, kind: "expire", year: @year,
            effective_on: Date.new(@year, 12, 31), balance_after: 0,
            reason: "自然年清零（33 §2.7；B 軌 #{b} 分 < #{policy.carry_over_threshold}）"
          )
        end
        :cleared
      end

      def policy = @policy ||= ViolationPointPolicy.effective_at(Time.current)
    end
  end
end
```

#### 6-2 處置階梯執行（含 `shop_restrictions` 連動）

```ruby
# app/services/platform/violations/apply_actions.rb
module Platform
  module Violations
    # 執行一組處置動作。
    #
    # 四要件（33 §2.7）：每一階處置都必須有「原因碼＋證據＋通知＋可申訴」，缺一即拒絕執行。
    # 這不是 UI 檢核，是服務層硬約束——UI 會被繞過，服務層不會。
    class ApplyActions
      # 動作 → shop_restrictions 旗標的映射（33 §2.2 六旗標）。
      # 為什麼要映射而不是各自寫 DB：分級凍結是 W1 的單一入口（32 §2「禁止散落 update_column」），
      # 違規模組只能透過 Platform::Restrictions::Apply 下指令，才能保證旗標狀態與生命週期狀態機一致。
      RESTRICTION_MAP = {
        "trade_restrict"            => :trade,
        "payout_transfer_restrict"  => :payout,
        "payment_suspend"           => :payin,    # Shopify 精簡階梯「停用付款」（33 §2.7）
        "admin_readonly"            => :readonly, # Shopify 精簡階梯「限制 admin」
        "account_ban"               => :banned
      }.freeze

      DUAL_CONTROL_ACTIONS = %w[forced_refund account_ban public_warning].freeze

      def initialize(kase:, actor:, actions:, reason_code:, note: nil,
                     notify_merchant: true, idempotency_key:)
        @kase = kase; @actor = actor; @actions = actions
        @reason_code = reason_code; @note = note
        @notify = notify_merchant; @key = idempotency_key
      end

      def call
        return failure(:EVIDENCE_REQUIRED, "本案尚無證據，不得執行處置（33 §2.7 四要件）") if @kase.violation_evidences.empty?
        return failure(:INVALID_STATE, "已結案的案件不可再處置") if @kase.status == "resolved"

        unauthorized = @actions.reject { |a| Platform::Authz.allow?(@actor, action_permission(a[:action_key])) }
        return failure(:FORBIDDEN, "角色不足：#{unauthorized.map { _1[:action_key] }.join(',')}") if unauthorized.any?

        needs_dual = @actions.map { _1[:action_key] } & DUAL_CONTROL_ACTIONS
        if needs_dual.any? && !Platform::Jit.active_elevation?(@actor, "violation.severe_action")
          return failure(:DUAL_APPROVAL_REQUIRED, "#{needs_dual.join('、')} 需 JIT 提權＋四眼核准（模組五 §6-3）")
        end

        applied = []
        # 交易邊界：DB 寫入全部在內、外部 IO（email／webhook／provider）全部在外（11 §2、CLAUDE.md 鐵律 5）
        ActiveRecord::Base.transaction do
          Platform::Idempotency.claim!(@key, scope: "violation_action", shop_id: @kase.shop_id)

          @actions.each do |a|
            act = @kase.violation_actions.create!(
              shop_id: @kase.shop_id, action_key: a[:action_key], family: family_of(a[:action_key]),
              params: a[:params] || {}, amount_cents: a[:amount_cents],
              effective_at: a[:effective_at] || Time.current, expires_at: a[:expires_at],
              state: "applied", applied_by: @actor.id, idempotency_key: "#{@key}:#{a[:action_key]}"
            )
            if (flag = RESTRICTION_MAP[a[:action_key]])
              r = Platform::Restrictions::Apply.new(
                shop: @kase.shop, flags: { flag => true }, reason: @reason_code,
                expires_at: a[:expires_at], source: "violation_case", source_id: @kase.id, actor: @actor
              ).call
              act.update_column(:restriction_id, r.id) # 同 transaction 內回填 FK，非狀態變更
            end
            applied << act
          end

          Platform::Violations::PointsLedger.new(@kase.shop).accrue!(
            track: @kase.track, delta: @kase.points, case_id: @kase.id,
            reason: @reason_code, actor_staff_id: @actor.id
          )

          @kase.update!(status: "acting",
                        appeal_deadline_at: appeal_deadline,
                        remediation_due_at: applied.filter_map(&:expires_at).max)

          Platform::Audit.record!(                     # 模組四：與業務寫入同 transaction，保證原子性
            action: "violation.action_apply", actor: @actor, shop_id: @kase.shop_id,
            target_type: "ViolationCase", target_id: @kase.id,
            previous: { status: @kase.status_previously_was, actions: [] },
            next_state: { status: "acting", actions: applied.map(&:action_key) },
            reason: @reason_code, source: "UI"
          )
        end

        # transaction 外：通知與事件（11 §2）
        Platform::Violations::NoticeJob.perform_later(@kase.id, applied.map(&:id)) if @notify
        Platform::Outbox.emit("violation_case.action_applied", shop_id: @kase.shop_id, case_id: @kase.id)

        success(applied)
      end

      # 申訴期限。33 §2.7 只給了「知識產權 3–7 工作天」的審理 SLA，
      # 【待定，需使用者確認】商家「可提出申訴的期限」本身（例如處置後 N 日內）33 未載，
      # 這裡讀 config/limits.yml 的 violation.appeal_window_days（不得硬編碼，CLAUDE.md 鐵律 6）。
      def appeal_deadline
        Platform::BusinessCalendar.tw.advance(Time.current, Limits.get("violation.appeal_window_days"))
      end
    end
  end
end
```

#### 6-3 違禁品掃描去重與信心分

```ruby
# app/services/platform/violations/prohibited_scanner.rb
# 為什麼要 content_digest：同一商品每天被掃一次，若不去重，一個違規商品 30 天會產生 30 筆待審件，
# 審核佇列會被自己淹死。digest = SHA256(rule_key + rule_version + normalize(scanned_text))，
# 只有「商品文案改了」或「規則改版了」才會產生新命中。
def scan(product)
  text = normalize([product.title, product.body_html, product.tags.join(" ")].join("\n"))
  Platform::ProhibitedRule.active.flat_map do |rule|
    hits = rule.match(text)                       # 回傳 [{term:, offset:}, ...]
    next [] if hits.empty?
    digest = Digest::SHA256.hexdigest([rule.key, rule.version, text].join("|"))
    next [] if suppressed?(product.shop_id, rule.key, hits)
    [{ shop_id: product.shop_id, product_id: product.id, rule_key: rule.key,
       rule_version: rule.version, matched_terms: hits.map { _1[:term] },
       excerpt: excerpt_around(text, hits.first[:offset], 120),
       confidence: rule.confidence_base + 0.1 * [hits.size - 1, 3].min,  # 命中越多詞信心越高，上限 +0.3
       content_digest: digest, state: "pending" }]
  end
end
# upsert：唯一索引 [shop_id, product_id, rule_key, content_digest] 兜底（11 §2 唯一索引兜底）
```

---

### 7. 需要的工具、gem 與外部依賴

- **既有棧內**：`acts_as_tenant`（租戶隔離；平台查詢用 `without_tenant`）、Solid Queue（背景任務）、Solid Cache、`pundit`（授權，12 §F3）、`strong_migrations`（DDL 安全，11 §2）、`annotaterb`。
- **新增 gem（皆為輕量、需在 PR 說明）**：
  - `aasm` 或原生 enum＋service：案件狀態機。**建議不引入 gem**，用 service 單一入口即可（比照 32 §2「所有轉移走 state machine 單一入口」），避免 AGENTS.md「不引入未討論的重型依賴」。
  - `diff-lcs`（已為 rspec 依賴）：處置前後 diff 呈現。
- **文字比對**：違禁詞比對用 MySQL 端 `REGEXP` 不可行（無法帶版本與 offset），一律 Ruby 端跑；大量商品用 `find_each(batch_size: 500)`。
- **外部依賴**：無。**不接**第三方內容審核 API（會把租戶商品資料送出境，與 33 §2.13 個資規範衝突）——若日後要接，須先做跨境傳輸評估，**待定**。
- **不做**：圖片 OCR 違禁品辨識（原型無此控件，33 未載）——標記為 out of scope。

---

### 8. 實作步驟（順序化 todo）

1. `db/migrate` 建 8 張表＋索引；`violation_categories`、`prohibited_rules`、`violation_point_policies` 三張種子表寫 `db/seeds/violations.rb`（含原型 5 種類型與 4 類違禁品）。
2. `config/limits.yml` 新增 `violation.appeal_window_days`、`violation.suppression_default_days`、`violation.scan_batch_size`。
3. `Platform::Violations::PointsLedger`＋單元測試（雙軌獨立、節點跨越、年度清零三情境）。
4. `Platform::Restrictions::Apply` 的**介面約定**與 W1 負責人對齊（`source`／`source_id`／`expires_at` 三個參數必須存在）；未就緒時先寫 adapter＋契約測試（`instance_double(verify_partial_doubles: true)`）。
5. `Platform::Violations::OpenCase` / `ApplyActions` / `RecoveryChecker`。
6. GraphQL type／connection／mutation＋`userErrors` enum；接 `Platform::Authz`。
7. `ProhibitedScanner`＋增量／全量 job；接商品 outbox 事件。
8. `ActionExpiryJob`、`PointsYearEndJob`、`RecoveryScanJob`、`NoticeJob`。
9. 通知模板（email＋商家後台橫幅）＋申訴入口連結（銜接模組二）。
10. React 頁面：違規列表、案件詳情四頁籤、處置抽屜、違禁品佇列。
11. `docs/dev/m8-violations.md`（AGENTS.md 強制）。

---

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/violations/points_ledger_spec.rb` | ① A 軌加 6 分不影響 B 軌餘額 ② B 軌 44→50 分回傳跨越 48 節點 ③ 年末 B=47 → 兩軌清零 ④ 年末 B=48 → 兩軌結轉 ⑤ 併發兩筆 accrue（`Thread` × 2）餘額正確且無 lost update ⑥ 調整用反向列，原列 `updated_at` 不變 |
| `spec/services/platform/violations/apply_actions_spec.rb` | ① 無證據 → `EVIDENCE_REQUIRED` ② `account_ban` 無 JIT 提權 → `DUAL_APPROVAL_REQUIRED` ③ `trade_restrict` 正確寫入 `shop_restrictions.trade` 且 `source='violation_case'` ④ 相同 `idempotencyKey` 重放 → 不重複建 action、不重複加分、不重複發事件 ⑤ transaction 內未發生任何 HTTP（用 `WebMock.disable_net_connect!` ＋ `expect(NoticeJob).to have_been_enqueued`） ⑥ 已結案案件 → `INVALID_STATE` |
| `spec/services/platform/violations/prohibited_scanner_spec.rb` | ① 同商品同規則同文案掃兩次只產一筆 hit ② 商品改文案 → 產新 hit ③ 規則改版 → 產新 hit ④ 有效 suppression 內不產 hit ⑤ suppression 過期後恢復產出 |
| `spec/jobs/platform/violations/action_expiry_job_spec.rb` | 到期動作自動 revert 並解除對應 restriction；已手動 revert 的不重複處理 |
| `spec/requests/platform/violations_graphql_spec.rb` | ① `read_only` 執行 `ActionApply` → HTTP 200＋`userErrors code:FORBIDDEN`（不得回 403，28 §0.3） ② 分頁 `first:300` → `MAX_COST_EXCEEDED` ③ GID 格式 `gid://chilllove/ViolationCase/{id}` ④ 金額回傳 `MoneyV2` |
| `spec/models/violation_points_ledger_spec.rb` | 帳列不可 update／destroy（模型層 `readonly?`），修正只能新增反向列 |
| `spec/system/platform/violation_case_spec.rb` | 快樂路徑：建案 → 上傳證據 → 勾選 2 項處置 → 確認 → 商家收到通知 → 申訴入口可點 |

---

### 10. 驗收清單

1. 16 項動作階梯在 `ovLadder` 與 DB enum **完全一致**（靜態測試比對常數與原型清單）。
2. A／B 雙軌獨立累計、分別執行；門檻值讀 DB 不硬編碼（`grep -rn "48" app/` 無積分相關硬編碼）。
3. 年度清零規則兩分支各有測試；shop 時區換算正確（11 §8 坑 5）。
4. 每一階處置皆具「原因碼＋證據＋通知＋可申訴」四要件，缺一被服務層擋下（33 §2.7）。
5. 處置動作與 `shop_restrictions` 六旗標的映射正確且**唯一入口**（靜態掃描：`violation` 目錄下不得出現 `shop_restrictions` 直接寫入）。
6. 全部寫入 mutation 帶 `idempotencyKey`，重放測試通過（11 §2）。
7. 違禁品掃描去重生效：1,000 件商品連掃 3 天，待審件數不成長。
8. 恢復條件三項全成立才可 `resolved`；任一未成立回 `RECOVERY_CONDITIONS_UNMET`。
9. 每個處置在 `platform_audit_logs` 有 before/after（模組四抽測 100%，32 §9-4）。
10. 權限矩陣逐格測試（原型 `RM`）：未授權回 `userErrors code:FORBIDDEN`。
11. UI 對照原型 `pointsrule`／`violcases`／`ovLadder` 逐控件打勾；tokens 全部取自 23 §1。

---

### 11. 前端（React/TS）

**元件樹**

```
<ViolationsPage>                       // 路由 /violations
  ├─ <PolicyBanner policy={...}/>      // data-doc=pointsrule；note note-info
  ├─ <PageActions>
  │    ├─ <Button variant="sec" onClick={openLadder}>處置動作清單</Button>
  │    └─ <Button variant="pri" onClick={openCreate}>建立案件</Button>
  ├─ <Card>
  │    ├─ <CardHead>案件 <ProhibitedQueueButton count={n}/></CardHead>
  │    └─ <IndexTable columns={7} rows={cases} onRowClick={openCase}/>   // data-doc=violcases
  ├─ <ActionLadderModal/>              // 唯讀，wide
  ├─ <CaseDrawer>                      // 四頁籤：證據／積分／通知／申訴
  │    └─ <ApplyActionsSheet/>         // 勾選 → 即時試算 → 二次確認
  └─ <ProhibitedTriageDrawer/>
```

**狀態管理**：TanStack Query（`platformViolationCases` 查詢 key `['viol', filters, cursor]`）；mutation 成功後 `invalidateQueries(['viol'])` ＋ `['violPoints', shopId]`。處置抽屜的即時試算用**本地純函式**（不打 API），資料來自已載入的 `policy.thresholds`——避免每勾一個 checkbox 就發請求。

**GraphQL 片段**

```graphql
fragment ViolationCaseRow on ViolationCase {
  id  code  track  points  status
  shop { id name }
  category { key label }
  appliedActions { actionKey label expiresAt }
  appeal { id state slaRemainingBusinessDays }
}
query PlatformViolationCases($status:[ViolationCaseStatus!], $first:Int!, $after:String){
  platformViolationCases(status:$status, first:$first, after:$after){
    nodes { ...ViolationCaseRow }
    pageInfo { hasNextPage endCursor }
  }
}
```

**三態**
- **Loading**：表格骨架 6 列（列高 40，23 §1 佈局常數）；不用 spinner。
- **Empty**：有篩選 → 「沒有符合條件的案件」＋「清除篩選」次要鈕；無篩選 → 「目前沒有違規案件」＋插圖位留白（32 §3-2 慣例）。
- **Error**：卡片內 `note note-crit`＋「重試」鈕；`FORBIDDEN` 特別處理為「你的角色無法檢視此區」並隱藏重試。

**響應式**（斷點取自原型 `<style>`）
- **≤1279**：`.idx{min-width:max-content}` 表格橫捲（CJK min-content 極小，寧可橫捲不擠字）；`page-actions` 維持橫列。
- **≤1023**：處置抽屜由右側 420px 改為全寬 overlay；案件詳情兩欄轉單欄；`usage-row` 轉 `110px 1fr 140px`。
- **≤767**：`html{font-size:14px}`；案件表加 `card-table` class 轉堆疊卡片（`td::before{content:attr(data-label)}`，每個 `<td>` 必須寫 `data-label`）；處置抽屜轉貼底 sheet（`max-height:92dvh`＋sticky footer＋`env(safe-area-inset-bottom)`）；輸入框 `font-size:16px` 防 iOS 聚焦放大。
- **≤429**：`page-actions .btn{flex:1}` 兩鈕平分整行；積分卡 `dl` 轉單欄。
- **pointer:coarse**：所有 `btn-xs`（處置／diff）用偽元素把命中區撐到 ≥44px（WCAG 2.5.5）。
- **prefers-reduced-motion**：抽屜與 sheet 動畫降為 0.01ms（原型已有全域規則）。

---

## 申訴（波次 W2）

### 1. 這是什麼、給誰用、解決什麼問題（含法源）

**是什麼**：租戶對平台處分提出異議的**受理與審理台**——四欄看板（待審理／要求補證／維持原判／撤銷處分）＋工作天 SLA 計時＋審理留痕。

**給誰用**：申訴審理員（`support` 受理與補證、`admin` 決議）；`platform_owner` 為升級對象。原申訴標的的處置執行人**不得**擔任該案審理人（迴避原則，見 §6-2）。

**解決什麼問題**：
1. **沒有申訴管道＝執法無效**——33 §2.7 把「可申訴」列為每一階處置的四要件之一；沒有申訴台，前一個模組的每一次處置在法律上都是可被質疑的。
2. **SLA 無人管**——原型 `TICKETS` 已出現「#5079 違規申訴・逾 SLA 3h・負責人 —」：未指派的申訴案是最容易爛掉的一類。
3. **審理過程不可重建**——撤銷處分時要能回答「為什麼撤銷、誰批的、看了什麼證據」。

**法源與制度出處**：

| 面向 | 出處 | 內容 |
|---|---|---|
| 申訴為處置必要條件 | 33 §2.7 | 每一階處置須「原因碼＋證據＋通知＋**可申訴**」 |
| 審理 SLA | 33 §2.7 | 知識產權 **3–7 工作天**；狀態四態 `待審／補件／維持原判／撤銷處分`；**須留審理人與證據** |
| 看板四欄與件數 | 原型 `appealboard` | 待審理 2／要求補證 1／維持原判 1／撤銷處分 1；頁首「5 件・SLA 3–7 工作天」 |
| 申訴來源類型 | 原型 `APPEALS`＋`TICKETS` | 違規案（V-3065／V-3081／V-3072）、KYC 駁回、限流誤判 |
| 受限狀態下仍可申訴 | 33 §2.1 | `restricted` 狀態商家**可看帳單、可提申訴、可換銀行帳號**——申訴入口不得因處置而關閉 |

> **待定，需使用者確認**：①「3–7 工作天」在 33 §2.7 是**知識產權專屬**的 SLA，原型卻套用到全部申訴（見 §12 規格衝突）；非 IP 類別（KYC 駁回、限流誤判、爭議率處置）的 SLA 數值待定。②申訴**次數上限**與「同一處分可否二次申訴」33 未載，本手冊實作為「每個處置 1 次申訴＋1 次升級複審」，數值放 `config/limits.yml` 待確認。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `appealboard`（四欄看板） | 待審理／要求補證／維持原判／撤銷處分 | 四欄對映 `appeals.state ∈ {under_review, info_required, upheld, overturned}`（33 §2.7 四態）。欄標題件數與 `platformAppeals` count **同源** | 每欄 >20 件時欄內虛擬捲動，欄標題顯示 `20 / 37`；四欄皆空時整塊顯示「目前沒有申訴案」 |
| 看板卡片（`kitem`） | 商家名／關聯案號與事由／SLA 剩餘 | 卡片副標＝關聯標的（`V-3065 疑似仿冒`）；`kmeta` badge＝SLA 文案（原型：`2 天前・SLA 剩 1 天`／`要求補證`／`維持原判・已通知`／`撤銷處分・已恢復`） | badge 色階：剩 >2 工作天 `attention`、≤2 `warning`、逾期 `critical`（比對原型 `ac()` 的 cls 參數） |
| 頁首「5 件・SLA 3–7 工作天」 | 總量與 SLA 提示 | 件數＝`state IN (under_review, info_required)` 的 open 件數（**不含**已決議欄），與側欄 badge 同源 | 逾期件 >0 時頁首追加紅字「n 件逾 SLA」 |
| 申訴詳情：時間軸 | 受理／指派／補證要求／商家回覆／決議 | 每個節點寫入 `appeal_events`；審理人、時間、內容全留痕（33 §2.7「須留審理人與證據」） | 時間軸不可編輯、不可刪除；補正只能追加 `correction` 事件 |
| 申訴詳情：「要求補證」 | 發補證要求並暫停 SLA 計時 | **SLA 時鐘在 `info_required` 期間暫停**（見 §6-1）；補證期限預設 3 工作天，逾期自動回 `under_review` 並恢復計時 | 補證要求次數上限 2 次（待定，需使用者確認）；超過後只能決議 |
| 申訴詳情：「維持原判」 | 決議 `upheld` | 必填 `rationale`（≥30 字）；自動寄結果通知（33 §2.7「結果 email 通知」，原型 `appealboard`） | 決議後案件不可再改；只能由 `platform_owner` 開「複審」新案 |
| 申訴詳情：「撤銷處分」 | 決議 `overturned`＋回滾處置 | 勾選要回滾的 `violation_actions`（可部分撤銷）；回滾走 `platformViolationActionRevert`；同時決定**積分是否回沖**（預設回沖，反向 ledger 列） | 若處置已產生不可逆副作用（已強制退款、已公示警告）→ 顯示「此動作不可自動回滾」並要求填補救說明 |
| 申訴詳情：「升級」 | 轉 `platform_owner` 複審 | 升級不重置 SLA 時鐘（避免用升級洗掉逾期紀錄） | 已升級案不可再升級 |
| 迴避提示條 | 當前使用者＝原處置執行人時顯示 | 決議鈕 disabled＋提示「你是本案原處置執行人，不得審理」（§6-2） | `platform_owner` 亦不豁免；系統自動處置（`source='dispute_threshold'`）無執行人，不觸發迴避 |

---

### 3. 資料模型

租戶域表（`shop_id` 前導索引）：

```ruby
# db/migrate/20260901000030_create_appeals.rb
# 對應 33 §6「violation_cases／violation_points_ledger／appeals」
create_table :appeals do |t|
  t.references :shop, null: false, foreign_key: true
  t.string  :code,     null: false                      # AP-1042
  t.string  :kind,     null: false                      # violation / kyc_rejection / rate_limit /
                                                        # compliance_scan / dispute_action / restriction
  t.string  :subject_type, null: false                  # ViolationCase / KycSubmission / ComplianceFinding ...
  t.bigint  :subject_id,   null: false
  t.string  :state,    null: false, default: "under_review"
  # under_review / info_required / upheld / overturned / partially_overturned / withdrawn / expired
  t.text    :claim,           null: false               # 商家陳述
  t.bigint  :assignee_staff_id
  t.bigint  :decided_by_staff_id
  t.text    :rationale                                  # 決議理由（維持原判必填）
  t.datetime :received_at,    null: false
  t.integer :sla_business_days, null: false             # 立案時凍結的 SLA 天數（政策改版不追溯）
  t.datetime :sla_due_at,     null: false               # 工作天換算後的絕對時點
  t.integer :sla_paused_seconds, null: false, default: 0 # info_required 期間累計暫停秒數
  t.datetime :paused_at
  t.datetime :decided_at
  t.datetime :escalated_at
  t.bigint  :escalated_to_staff_id
  t.timestamps
end
add_index :appeals, [:shop_id, :state, :sla_due_at], name: "idx_appeal_shop_state_due"
add_index :appeals, [:subject_type, :subject_id]
add_index :appeals, :code, unique: true
```

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `appeal_events` | `shop_id`, `appeal_id`, `kind`(received / assigned / info_requested / merchant_replied / evidence_added / escalated / decided / notified / correction), `actor_type`(platform_staff / merchant / system), `actor_id`, `body`, `payload JSON`, `occurred_at` | **append-only**（同模組四規則：模型 `readonly?`＋DB 不授權 UPDATE／DELETE） |
| `appeal_evidences` | `shop_id`, `appeal_id`, `kind`, `blob_ref`, `sha256`, `uploaded_by_type`, `uploaded_by_id`, `uploaded_at` | 商家與平台雙方皆可上傳；不可刪 |
| `appeal_decisions` | `shop_id`, `appeal_id`, `decision`(UPHOLD / OVERTURN / PARTIAL), `reverted_action_ids JSON`, `points_reversed`, `rationale`, `decided_by`, `decided_at`, `idempotency_key` | 一案一列（唯一索引 `[appeal_id]`）；複審另開新 appeal |
| `appeal_sla_policies` | `kind`, `first_response_business_days`, `decision_business_days`, `info_request_limit`, `version`, `effective_at` | **平台域表**（白名單）。IP 類 seed 為 3–7 工作天（33 §2.7），其餘 kind 的值標 `null` 並在 UI 顯示「SLA 待定」 |
| `business_calendar_days` | `date`, `country`, `kind`(workday / holiday / makeup_workday), `source_ref` | **平台域表**（白名單）。台灣行政機關辦公日曆表匯入。**待定，需使用者確認**：資料來源與每年更新方式 33 未載 |

**平台域表白名單（本模組）**：`appeal_sla_policies`、`business_calendar_days`。

---

### 4. API 契約（Platform:: GraphQL）

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformAppeals` | query | `state, kind, assigneeId, overdueOnly, first≤250, after` | `AppealConnection`（含 `slaRemainingBusinessDays`, `isOverdue`） | — | 全部 |
| `platformAppeal` | query | `id!` | `Appeal`（events／evidences／subject／decision） | `NOT_FOUND` | 全部 |
| `platformAppealBoard` | query | `kind` | `{ underReview{count,nodes(first:20)}, infoRequired{...}, upheld{...}, overturned{...} }` | — | 全部 |
| `platformAppealAssign` | mutation | `id!, assigneeStaffId!, idempotencyKey!` | `{ appeal, userErrors }` | `NOT_FOUND` `ALREADY_DECIDED` `RECUSAL_REQUIRED` | `support`＋ |
| `platformAppealRequestEvidence` | mutation | `id!, message!, dueBusinessDays=3, idempotencyKey!` | `{ appeal, userErrors }` | `INFO_REQUEST_LIMIT_REACHED` `ALREADY_DECIDED` | `support`＋ |
| `platformAppealDecide` | mutation | `input{ id!, decision!(UPHOLD\|OVERTURN\|PARTIAL), rationale!, revertActionIds[], reversePoints=true, idempotencyKey! }` | `{ appeal, decision, revertedActions, userErrors }` | `FORBIDDEN` `RECUSAL_REQUIRED` `ALREADY_DECIDED` `RATIONALE_TOO_SHORT` `IRREVERSIBLE_ACTION` | `admin`＋ |
| `platformAppealEscalate` | mutation | `id!, toStaffId!, reason!, idempotencyKey!` | `{ appeal, userErrors }` | `ALREADY_ESCALATED` `ALREADY_DECIDED` | `support`＋ |
| `platformAppealWithdraw` | mutation | `id!, reason!, idempotencyKey!` | `{ appeal, userErrors }` | `ALREADY_DECIDED` | 商家端 API／`admin`＋代辦 |

**商家端對應**（`/admin/api/2026-08/graphql.json`，供租戶提申訴）：`appealCreate(subjectGid!, claim!, evidences[])`、`appeal(id)`、`appeals(first, after)`、`appealEvidenceAdd`。**`restricted` 狀態下這四支必須仍可呼叫**（33 §2.1「受限期間可提申訴」）——授權層要對申訴 scope 開白名單，否則凍結中介層會把它一起擋掉。

---

### 5. 服務物件與背景任務

| 類別／Job | 職責 | 備註 |
|---|---|---|
| `Platform::Appeals::Intake` | 受理：建 `appeals`＋首個 `appeal_events`＋算 `sla_due_at` | 商家端呼叫亦走此入口 |
| `Platform::Appeals::SlaClock` | 工作天推算、暫停／恢復、剩餘天數 | 純函式＋`business_calendar_days` 查表 |
| `Platform::Appeals::Decide` | 決議＋回滾處置＋積分回沖＋通知 | 單一 transaction；通知丟 job |
| `Platform::Appeals::RecusalPolicy` | 迴避判定 | 唯讀 |
| `Platform::Appeals::SlaWatchJob` | 每 15 分鐘：T-1 工作天提醒指派人；逾期 → 通知 `admin`＋開 P1 工單（比對原型 `TICKETS` 的「逾 SLA」呈現） | 逾期事件本身寫審計 `appeal.sla_breached`（`outcome: alert`） |
| `Platform::Appeals::InfoRequestTimeoutJob` | 每小時：補證逾期 → 回 `under_review`、恢復計時、記事件 | |
| `Platform::Appeals::UnassignedSweepJob` | 每小時：受理後 4 小時未指派 → 依 kind 輪派並通知（原型出現「負責人 —」的逾期案，這條就是為了防它） | 輪派規則**待定，需使用者確認** |
| `Platform::Appeals::NotifyJob` | 決議結果 email＋商家後台通知 | 33 §2.7「結果 email 通知」 |

---

### 6. 關鍵流程與演算法

#### 6-1 工作天 SLA 時鐘（含補證暫停）

```ruby
# app/services/platform/appeals/sla_clock.rb
module Platform
  module Appeals
    # 申訴 SLA 時鐘。
    #
    # 為什麼是「工作天」不是「自然日」：33 §2.7 原文為「知識產權 3–7 工作天」。
    # 用自然日換算會在連假時系統性逾期（台灣春節可連 9 天），逾期告警會被雜訊淹沒，
    # 進而讓真正的逾期案被忽略——這是 SLA 機制最常見的失效方式。
    #
    # 為什麼補證期間要暫停：球在商家手上時把時間算給平台，等於逼審理員在商家不回覆時
    # 硬做決議。暫停秒數累計在 appeals.sla_paused_seconds，決議時可完整重建時間線。
    class SlaClock
      # @param appeal [Appeal]
      def initialize(appeal) = @appeal = appeal

      # 立案時計算絕對到期時點。
      # @param business_days [Integer] 來自 appeal_sla_policies（33 §2.7：IP 類 3–7）
      def self.due_at(from:, business_days:)
        BusinessCalendar.tw.advance_business_days(from, business_days).change(hour: 18, min: 0)
        # 為什麼收在 18:00：SLA 以「工作日下班前」為界；若用 24:00 會出現「凌晨兩點還沒逾期」
        # 的荒謬狀態，值班人員無法據此排工。18:00 為【建議值】，33 未載，需使用者確認。
      end

      # 剩餘工作天（負數＝已逾期）。
      def remaining_business_days(now: Time.current)
        return nil if @appeal.decided_at.present?
        effective_now = now - paused_total(now)
        BusinessCalendar.tw.business_days_between(effective_now, @appeal.sla_due_at)
      end

      def overdue?(now: Time.current) = remaining_business_days(now).to_i.negative?

      # 已累計暫停秒數（含當下仍在暫停中的區間）
      def paused_total(now)
        base = @appeal.sla_paused_seconds
        base += (now - @appeal.paused_at) if @appeal.paused_at.present?
        base.seconds
      end

      # 進入補證：暫停計時
      def pause!(at: Time.current)
        return if @appeal.paused_at.present?
        @appeal.update!(paused_at: at)
      end

      # 商家回覆或補證逾期：恢復計時，並把暫停時長往後推 sla_due_at
      # 為什麼要同時推 due_at：只累計 paused_seconds 而不推 due_at 的話，
      # 「剩餘天數」與「到期時點」兩個顯示會互相矛盾，客服解釋不清。兩者一起改，單一真相。
      def resume!(at: Time.current)
        return if @appeal.paused_at.blank?
        paused = (at - @appeal.paused_at).to_i
        @appeal.update!(
          paused_at: nil,
          sla_paused_seconds: @appeal.sla_paused_seconds + paused,
          sla_due_at: BusinessCalendar.tw.advance_business_seconds(@appeal.sla_due_at, paused)
        )
      end
    end
  end
end
```

#### 6-2 迴避原則

```ruby
# app/services/platform/appeals/recusal_policy.rb
# 為什麼要迴避：33 §2.7 要求「須留審理人」，留痕的前提是審理人與處置人可區分。
# 若同一人可以自己處置、自己駁回申訴，申訴機制在制度上等於不存在——這是驗收會被打回的設計缺陷。
module Platform::Appeals::RecusalPolicy
  module_function

  # @return [Boolean] true 表示該員必須迴避
  def recused?(staff, appeal)
    return false if staff.nil?
    subject = appeal.subject
    case subject
    when ViolationCase
      actor_ids = subject.violation_actions.pluck(:applied_by) + [subject.opened_by_staff_id]
    when KycSubmission
      actor_ids = [subject.reviewed_by]
    when ComplianceFinding
      actor_ids = []            # 系統自動判定，無人工執行人 → 不迴避
    else
      actor_ids = []
    end
    actor_ids.compact.include?(staff.id)
  end
end
```

#### 6-3 撤銷處分的回滾與積分回沖

```ruby
# app/services/platform/appeals/decide.rb（節錄）
IRREVERSIBLE = %w[forced_refund public_warning product_delete shop_homepage_delete].freeze

def call
  return failure(:RECUSAL_REQUIRED, "你是本案原處置執行人，不得審理（迴避原則）") if RecusalPolicy.recused?(@actor, @appeal)
  return failure(:ALREADY_DECIDED, "本案已決議") if @appeal.decided_at.present?
  return failure(:RATIONALE_TOO_SHORT, "決議理由至少 30 字") if @rationale.to_s.length < 30

  targets = ViolationAction.where(id: @revert_ids, shop_id: @appeal.shop_id)
  blocked = targets.select { IRREVERSIBLE.include?(_1.action_key) }
  if blocked.any? && @remedy_note.blank?
    return failure(:IRREVERSIBLE_ACTION,
      "#{blocked.map(&:action_key).join('、')} 無法自動回滾，請填寫人工補救說明")
  end

  ActiveRecord::Base.transaction do
    Platform::Idempotency.claim!(@key, scope: "appeal_decide", shop_id: @appeal.shop_id)
    targets.reject { IRREVERSIBLE.include?(_1.action_key) }.each do |act|
      Platform::Violations::RevertAction.new(action: act, actor: @actor,
        reason: "申訴 #{@appeal.code} 撤銷處分").call
    end
    if @reverse_points && @decision != "UPHOLD"
      # 為什麼用反向列不是刪列：積分帳本是 append-only（模組四同一原則），
      # 稽核時必須看得到「曾經扣過分、後來因申訴回沖」的完整歷程。
      kase = @appeal.subject
      Platform::Violations::PointsLedger.new(@appeal.shop).accrue!(
        track: kase.track, delta: -kase.points, case_id: kase.id,
        kind: "adjust", reason: "申訴 #{@appeal.code} 撤銷", actor_staff_id: @actor.id
      )
    end
    @appeal.update!(state: state_for(@decision), decided_by_staff_id: @actor.id,
                    decided_at: Time.current, rationale: @rationale)
    AppealDecision.create!(shop_id: @appeal.shop_id, appeal_id: @appeal.id, decision: @decision,
                           reverted_action_ids: targets.ids, points_reversed: @reverse_points,
                           rationale: @rationale, decided_by: @actor.id, idempotency_key: @key)
    AppealEvent.create!(shop_id: @appeal.shop_id, appeal_id: @appeal.id, kind: "decided",
                        actor_type: "platform_staff", actor_id: @actor.id, body: @rationale,
                        occurred_at: Time.current)
    Platform::Audit.record!(action: "appeal.decide", actor: @actor, shop_id: @appeal.shop_id,
      target_type: "Appeal", target_id: @appeal.id,
      previous: { state: @appeal.state_previously_was },
      next_state: { state: @appeal.state, decision: @decision },
      reason: @rationale, source: "UI")
  end
  Platform::Appeals::NotifyJob.perform_later(@appeal.id)   # transaction 外（11 §2）
  success
end
```

---

### 7. 需要的工具、gem 與外部依賴

- **不需新 gem**。工作天計算自寫（`business_calendar_days` 查表＋Solid Cache 快取當年度日曆，key 帶年份）。**不用 `business_time` gem**：該 gem 的假日設定是進程內全域狀態，多租戶／多時區下容易誤用。
- **快取**：`BusinessCalendar.tw` 以 `Rails.cache.fetch(["biz-cal", "TW", year], expires_in: 1.day)` 載入整年 `Set<Date>`；`advance_business_days` 為純記憶體運算，無 N+1。
- **外部依賴**：台灣行政機關辦公日曆表（政府資料開放平臺 CSV）——**匯入方式與更新排程待定，需使用者確認**；未匯入前 job 應**拒絕啟動**並告警（缺日曆會靜默把假日算成工作天，比壞掉更糟）。
- **檔案儲存**：`appeal_evidences.blob_ref` 走 Active Storage；商家上傳的證據需過病毒掃描與 MIME 白名單（11 §1 輸入淨化）。

---

### 8. 實作步驟（順序化 todo）

1. `business_calendar_days` 表＋匯入 rake task＋當年度資料；缺資料時 `BusinessCalendar.tw` 拋例外。
2. `appeal_sla_policies` seed：`violation_ip` = 3/7 工作天（33 §2.7）；其餘 kind 留 `null` 並在 GraphQL 回 `slaBusinessDays: null`＋UI 顯示「SLA 待定」。
3. `appeals` / `appeal_events` / `appeal_evidences` / `appeal_decisions` 四表；`appeal_events` 掛 append-only 三層防護（模型 `readonly?`＋DB grant＋trigger，做法見模組四 §6-1）。
4. `SlaClock`＋單元測試（跨連假、暫停恢復、逾期）。
5. `Intake`（平台端與商家端共用）＋`RecusalPolicy`＋`Decide`。
6. GraphQL：平台端 8 支＋商家端 4 支；商家端授權層對 `restricted` 開白名單（33 §2.1）。
7. 四個 Job＋逾期告警接入原型 `TICKETS` 的工單模組。
8. React 看板頁（四欄 kanban）＋申訴詳情抽屜。
9. 與模組一銜接：`violation_cases.status` 在申訴進行中顯示「申訴中」；撤銷後回寫。
10. `docs/dev/m8-appeals.md`。

---

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/appeals/sla_clock_spec.rb` | ① 3 工作天跨週末正確落在下週二 ② 跨春節連假（`business_calendar_days` 灌 9 天假）正確順延 ③ 補證暫停 2 天後 `sla_due_at` 往後推 2 個工作天 ④ 未匯入當年度日曆 → 拋 `MissingCalendarError` ⑤ 逾期回負數 |
| `spec/services/platform/appeals/recusal_policy_spec.rb` | ① 原處置執行人 → `recused? == true` ② 原立案人 → true ③ 系統自動處置無執行人 → false ④ `platform_owner` 不豁免 |
| `spec/services/platform/appeals/decide_spec.rb` | ① 迴避者決議 → `RECUSAL_REQUIRED` ② 理由 <30 字 → `RATIONALE_TOO_SHORT` ③ 撤銷 → 對應 action 被 revert、restriction 解除、積分反向列產生 ④ 含 `forced_refund` 且無補救說明 → `IRREVERSIBLE_ACTION` ⑤ 重放同 key → 不重複回沖積分 ⑥ 已決議再決議 → `ALREADY_DECIDED` |
| `spec/models/appeal_event_spec.rb` | 事件列 update／destroy 皆拋 `ActiveRecord::ReadOnlyRecord` |
| `spec/requests/platform/appeals_graphql_spec.rb` | ① `read_only` 決議 → 200＋`FORBIDDEN` ② 看板 query 四欄 count 與 `platformAppeals` filter count 一致（數字同源） |
| `spec/requests/admin/appeal_create_spec.rb` | **`restricted` 狀態的商家仍可成功建立申訴**（33 §2.1 例外）；`frozen` 狀態同樣可提（帳單頁與申訴為兩個必留例外） |
| `spec/jobs/platform/appeals/sla_watch_job_spec.rb` | ① T-1 工作天發提醒且只發一次（冪等） ② 逾期開 P1 工單並寫審計 `outcome: alert` ③ 已決議案不再告警 |
| `spec/system/platform/appeal_board_spec.rb` | 快樂路徑：看板拖入 → 要求補證 → 商家補件 → 撤銷處分 → 商家收信 → 處置已解除 |

---

### 10. 驗收清單

1. 四態與 33 §2.7 完全一致：`待審／補件／維持原判／撤銷處分`；看板四欄件數與查詢同源。
2. IP 類 SLA 為 3–7 工作天且**工作天計算跨連假正確**；非 IP 類顯示「SLA 待定」不得亂填。
3. 補證期間 SLA 暫停、恢復後 `sla_due_at` 與「剩餘天數」兩處顯示一致。
4. 每案皆可從 `appeal_events` 重建完整審理過程（審理人＋證據＋時間）；事件列不可改不可刪。
5. 迴避原則生效，`platform_owner` 不豁免。
6. 撤銷處分後：`violation_actions` 已 revert、`shop_restrictions` 對應旗標已解、積分有反向列、商家收到通知——四項各有測試。
7. 不可逆動作被正確識別並要求補救說明。
8. `restricted`／`frozen` 商家仍可提出申訴（33 §2.1 兩個必留例外之一）。
9. 逾期案自動開 P1 工單且寫審計；未指派案 4 小時後自動輪派。
10. 全部決議 mutation 帶 `idempotencyKey` 並通過重放測試。
11. UI 對照原型 `appealboard` 逐控件打勾。

---

### 11. 前端（React/TS）

**元件樹**

```
<AppealsPage>                                  // 路由 /appeals
  ├─ <PageHead title="申訴" sub="{open} 件・SLA 3–7 工作天" overdue={n}/>
  ├─ <Kanban cols={4}>                         // data-doc=appealboard
  │    └─ <KanbanColumn state="under_review" count={2}>
  │         └─ <AppealCard sla={...} onClick={openDrawer}/>   // .kitem
  └─ <AppealDrawer>
       ├─ <RecusalBanner show={recused}/>
       ├─ <Timeline events={appeal.events}/>
       ├─ <EvidenceList uploadable/>
       └─ <DecisionFooter>                     // 要求補證／維持原判／撤銷處分／升級
```

**狀態管理**：看板用 `platformAppealBoard` 單一 query（四欄一次拿，避免四支請求造成欄位間 count 不一致）；`refetchInterval: 60_000`（SLA 是時間敏感畫面，但不做 websocket——量太小不值得）。剩餘天數在**前端每分鐘重算**（純函式，輸入 `slaDueAt` 與 `pausedSeconds`），不靠 server 回傳的快照值。

**GraphQL**

```graphql
query PlatformAppealBoard {
  platformAppealBoard {
    underReview { count nodes(first:20){ ...AppealCard } }
    infoRequired { count nodes(first:20){ ...AppealCard } }
    upheld       { count nodes(first:20){ ...AppealCard } }
    overturned   { count nodes(first:20){ ...AppealCard } }
  }
}
fragment AppealCard on Appeal {
  id code kind state receivedAt slaDueAt slaPausedSeconds isOverdue
  shop { id name }
  subject { __typename ... on ViolationCase { code category { label } } }
  assignee { id name }
}
```

**三態**
- **Loading**：四欄各 2 張卡片骨架（高 72）；欄標題 count 顯示 `—` 不顯示 0。
- **Empty**：單欄空 → 欄內細字「無」；四欄皆空 → 整塊替換為置中「目前沒有申訴案」。
- **Error**：整塊 `note note-crit`＋重試；單欄失敗不可能（單一 query）。

**響應式**
- **≤1279**：`.kanban{grid-template-columns:repeat(2,1fr)}` 四欄轉 2×2。
- **≤1023**：抽屜改全寬；`two-col` 轉單欄。
- **≤767**：`.kanban{grid-template-columns:1fr}` 單欄直排，欄標題 sticky；抽屜轉貼底 sheet（`92dvh`＋sticky `modal-foot`，`modal-foot .btn{flex:1}` 三鈕平分）；決議理由 textarea `font-size:16px` 防 iOS 放大。
- **≤429**：決議按鈕改為直排堆疊（`page-actions .btn{flex:1}` 已處理頁首；抽屜 footer 需額外 `flex-wrap:wrap`）；時間軸時間戳改為第二行。
- **pointer:coarse**：`kitem` 最小高 48；`btn-xs` 命中區偽元素撐 ≥44px。
- **prefers-reduced-motion**：看板欄切換與 sheet 動畫關閉。

---

## 合規（波次 W3）

> 本模組含四條獨立法遵線，共用一個導覽區（原型 `v-compliance`）：**3A DSR 資料主體請求**、**3B 台灣電子發票管線**、**3C 個資 72 小時通報與年度稽核**、**3D 前台合規巡檢器**。每條線的資料模型與 job 各自獨立，但共用 `compliance_deadlines` 計時器基礎設施與同一套逾期升級告警。

### 1. 這是什麼、給誰用、解決什麼問題（含法源）

**是什麼**：把**有法定硬時限**的義務變成有計時器、有升級路徑、有留痕的佇列。這四條線的共同特徵是「逾期不是服務品質問題，是違法」。

**給誰用**：合規／法務窗口（主要）、`support`（DSR 執行與發票救火）、`ops`（巡檢器與發票 job 維運）、`platform_owner`（個資外洩通報的決策人）。

**解決什麼問題**：
1. **DSR 逾期＝裁罰風險**，且 erasure 與訴訟保全（legal hold）衝突時沒人知道哪個優先。
2. **電子發票字軌耗盡＝當天無法開立**——原型 `einvoice` 直接寫明「這是台灣營運最常見的事故來源」。
3. **外洩 72 小時通報**沒有計時器就一定會漏。
4. **前台合規巡檢是我們的差異化**（33 §7.2「西方平台沒有這個，台灣平台方卻有實質責任」）。

**法源總表**：

| 線 | 義務 | 期限／數值 | 出處 |
|---|---|---|---|
| 3A | GDPR 回覆期限 | **1 個月**；複雜案可延 **2 個月**（合計 3），且須**在 1 個月內告知延期理由** | 33 §2.13（GDPR Art.12(3)） |
| 3A | CCPA/CPRA 回覆期限 | **45 天**（可再延 45） | 33 §2.13 |
| 3A | erasure 與 legal hold 衝突 | **hold 優先** | 33 §5-9；GDPR Art.17(3)(e)（法律主張之建立、行使或防禦） |
| 3A | Shopify redact 模型（我們對 app 生態的對等義務） | `customers/data_request`／`customers/redact`（近 6 個月有下單則延後，否則**最少延遲 10 天**）／`shop/redact`（解安裝後 **48 小時**）；皆 HMAC 驗簽、**30 天內完成** | 33 §2.13 |
| 3B | 字軌餘量 | 耗盡即無法開立；**15% 門檻**主動告警 | 33 §2.14＋原型 `einvoice`／`shopinvoice` |
| 3B | 工商憑證 | 效期 **5 年**，**到期前 60 天內**須重新申請 | 33 §2.14 |
| 3B | 開立時機 | 三選一：付款／**出貨（建議）**／收貨 | 33 §2.14＋原型 `shopinvoice`「出貨時（官方建議，避免取消後作廢）」 |
| 3B | 作廢與折讓 | 全額取消**自動作廢**、部分退貨**自動折讓** | 33 §2.14 |
| 3C | 個資外洩通報 | **72 小時內**依附表二通報數位部 | 33 §2.13（《數位經濟相關產業個資檔案安全維護管理辦法》） |
| 3C | 軌跡保存 | 蒐集處理利用紀錄與自動化機器軌跡**至少 5 年** | 33 §2.13 |
| 3C | 年度稽核 | 資本額 1,000 萬或個資 5,000 筆以上者**每 12 個月至少一次** | 33 §2.13 |
| 3C | 租戶守則 | 平台業者須訂定個資保護守則並**要求租戶遵守** | 33 §2.13 |
| 3D | 稅籍與前台揭露 | 達起徵點（2025/1/1 起貨物月銷 **10 萬**、勞務 **5 萬**）須辦稅籍登記，並於銷售網頁**揭露營業人名稱與統一編號**；稅籍須登錄網域與網路位址 | 33 §2.14 |
| 3D | 鑑賞期例外 | 七款（易腐／客製化／報紙期刊／已拆封影音軟體／非有形媒介數位內容／已拆封個人衛生用品／國際航空客運）→ 商品層需「排除鑑賞期」旗標＋前台強制告知 | 33 §2.14（《通訊交易解除權合理例外情事適用準則》） |

> **待定，需使用者確認**：①台灣《個人資料保護法》對查閱／複製／更正／刪除的**法定回覆天數**——33 §2.13 只寫了台灣的外洩通報與稽核，未寫 DSR 期限。實作先以「GDPR／CCPA 兩制取嚴」為內部 SLA，`regime='pdpa_tw'` 的 `statutory_due_at` 欄位留 `null` 並在 UI 標「法定期限待確認」。②電子發票「48 小時上傳」期限：33 §9 明載「來自媒體整理，建議以財政部《電子發票實施作業要點》原文複核」——**不得寫死**。③發票作廢的期別限制（是否須在該期別申報前完成）33 未載。④外洩 72 小時的起算點是「知悉」或「發生」，33 未載。

**Controller／Processor 分工（3A 核心）**

| 資料類別 | Controller | Processor | 誰受理 DSR |
|---|---|---|---|
| 租戶的買家個資（訂單、地址、瀏覽軌跡） | **商家** | **平台** | 商家受理；平台提供工具與執行 |
| 平台帳號（`platform_staffs`）、平台審計、計費與發票資料 | **平台** | — | 平台自行受理與決定 |
| 租戶負責人／KYC 文件個資 | **平台**（法遵義務自負） | — | 平台受理 |

**因此的硬規則**：平台若**直接**收到資料主體請求（買家寄信到平台客服），平台**不得自行決定**是否刪除，必須在受理後轉交該商家並記錄轉交時點——processor 的通知義務。`dsr_requests.controller_party` 決定後續流程分支。轉交時限 **24 小時**為【建議值，33 未載，待定】。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `dsr`（DSR 表） | 請求／商店／類型／剩餘／狀態 | 欄位對照原型 `DSR`：`DSR-118 / 花見選物 / erasure / 5 天 / 執行中`。**剩餘 ≤7 天轉紅**（原型 `renderAll`：`parseInt(d[3])<=7 ? var(--critical)`）。類型 `access／erasure／portability`（原型 `dsr`） | 剩餘天數由 `min(statutory_due_at, operational_due_at)` 推算；`blocked_by_hold` 狀態列顯示鎖頭 icon 並標「legal hold 優先」 |
| DSR 詳情：雙時鐘 | 法定期限＋內部 SLA 並列 | **兩欄並列**（比照 33 §2.5 爭議率雙欄設計語言）：`法定 GDPR 1 個月 → 2026-09-11` ／ `內部 SLA 30 天 → 2026-09-10`。取嚴者驅動告警 | GDPR 延期後顯示三段：原期限／延期後期限／**告知理由的截止時點（＝原期限）**，未告知即到期時整列轉紅並開 P1 |
| DSR 詳情：「申請延期」 | GDPR +2 個月／CCPA +45 天 | 必填 `extension_reason`；系統自動寄「延期告知」給資料主體並記 `extension_notified_at`；**若當下已超過 received_at + 1 個月 → 拒絕延期**（GDPR 要求須在 1 個月內告知，33 §2.13） | 延期上限 1 次；已延期再申請 → `EXTENSION_LIMIT_REACHED` |
| DSR 詳情：「執行 erasure」 | 觸發刪除管線 | 執行前**強制**跑 legal hold 檢查；命中 → 不執行、狀態轉 `blocked_by_hold`、產生「拒絕理由通知」草稿（仍須在期限內回覆） | hold 覆蓋部分資料時 → 部分執行＋部分保留，回覆文件需逐項說明 |
| `pdpa`（個資事件與稽核卡） | 外洩狀態／年度稽核／軌跡保存／守則簽署／legal hold 數 | 原型五列：`目前無進行中的外洩事件・上次演練 2026-06-18`／`年度稽核 2026-03-11 完成`／`軌跡保存（法定 5 年）已設 5 年`／`租戶守則簽署 1,204 / 1,284`／`Legal hold 生效中 2 家` | 有進行中外洩事件時第一列轉 `note note-crit` 並顯示**72 小時倒數**（時／分）；稽核距上次 >10 個月轉 warning、>12 個月轉 critical |
| PDPA：「宣告外洩事件」 | 建 incident 並啟動 72h 計時 | 必填 `detected_at`、`data_categories[]`、`affected_count`（可為估算，須標 `is_estimate`）；建立即通知 `platform_owner`＋開 P1 工單 | `detected_at` 不可填未來；填過去 >72h 時強制填「延遲發現原因」 |
| `einvoice`（管線卡） | 字軌餘量／憑證到期／今日開立統計／失敗待重試 | 原型四列：`字軌餘量低於 15% 的商店 37 家`／`工商憑證 60 天內到期 8 家`／`今日開立／作廢／折讓 18,402 / 214 / 486`／`開立失敗待重試 12 張`。底部 `note note-warn` 說明字軌耗盡即無法自動開立（33 §2.14） | 任一列 >0 皆可點進逐店清單；`開立失敗待重試` 超過 100 張 → 觸發頂列橫幅（比照 32 §3-1 健康列規則） |
| `shopinvoice`（租戶詳情） | 加值中心／開立時機／字軌餘量／工商憑證／本月統計 | 原型 `dl` 五列。字軌 12% 顯示 `critical` badge「低於門檻」；憑證顯示到期日＋「到期前 60 天內須重新申請」副標（33 §2.14） | 未委任加值中心 → 全卡替換為「尚未完成委任」＋引導；字軌 0 → 紅色橫幅「已無法開立，所有訂單開立轉人工佇列」 |
| `frontscan`（巡檢摘要） | 四項達成率長條 | 原型：統編揭露 1,207/1,284（94%）／隱私權政策 1,271/1,284（99%）／退換貨政策 1,130/1,284（88%，warn）／鑑賞期告知 1,078/1,284（84%，warn）。底部說明「不合格自動開工單給商家（每日 06:00 掃描）」 | 分母＝**應受檢**店數（排除 `draft`／`closed`／`deleted`），不是全部店數；分母變動時長條旁顯示 `▲/▼` |
| `frontscan`「全平台重掃」 | 觸發全量巡檢 | 原型 toast：「背景 job，約 20 分鐘」。實際節流：同一小時內只允許 1 次，第 2 次回 `RATE_LIMITED` | 進行中顯示進度（已掃 n / 應掃 m）與預估剩餘 |
| `shopcompliance`（租戶詳情） | 六項逐項檢查結果 | 原型六項：營業人名稱與統一編號揭露／隱私權政策頁／退換貨政策頁／七天鑑賞期告知／鑑賞期例外商品標示／稅籍登記網域一致。通過 `badge success`、不通過 `badge critical`＋「已開工單」；末列「上次掃描：今天 06:00（每日自動）」 | 不通過項可點開看**證據**（抓到的 HTML 片段＋URL＋抓取時間）；旁邊「申訴誤判」入口（見 §6-4） |
| `shopcompliance`「重新掃描」 | 單店即時重掃 | 每店每小時上限 3 次（禮貌性節流，§6-4） | 掃描中按鈕 loading 並顯示「約 8 秒」 |

---

### 3. 資料模型

#### 3A DSR（租戶域，除 `legal_holds` 可為平台級）

```ruby
# db/migrate/20260901000050_create_dsr_requests.rb
# 對應 33 §6「dsr_requests（shop_id, subject_email, kind, due_at, state）／legal_holds」
create_table :dsr_requests do |t|
  t.references :shop, null: false, foreign_key: true
  t.string   :code,   null: false                        # DSR-118（原型）
  t.string   :subject_email, null: false                 # PII → 日誌過濾清單必收（11 §5）
  t.string   :subject_ref                                # customer GID（驗證身分後回填）
  t.string   :kind,   null: false                        # access / erasure / portability / rectification / opt_out
  t.string   :regime, null: false                        # gdpr / ccpa / pdpa_tw
  t.string   :controller_party, null: false              # merchant / platform（見 §1 分工表）
  t.string   :state,  null: false, default: "received"
  # received / identity_pending / verified / in_progress / awaiting_merchant /
  # blocked_by_hold / fulfilled / rejected / withdrawn
  t.datetime :received_at,   null: false
  t.datetime :verified_at
  t.datetime :statutory_due_at                           # 法定：GDPR received+1.month／CCPA +45d／pdpa_tw NULL（待定）
  t.datetime :operational_due_at, null: false            # 內部 SLA：min(statutory, received+30d)（33 §2.13 Shopify 模型）
  t.datetime :extended_until
  t.text     :extension_reason
  t.datetime :extension_notified_at                      # 必須 <= received_at + 1.month（GDPR Art.12(3)）
  t.datetime :forwarded_to_merchant_at                   # processor 通知義務
  t.boolean  :hold_blocked, null: false, default: false
  t.bigint   :blocking_legal_hold_id
  t.string   :artifact_ref                               # access／portability 產出包（簽名連結）
  t.datetime :closed_at
  t.string   :rejection_code
  t.text     :rejection_reason
  t.timestamps
end
add_index :dsr_requests, [:shop_id, :state, :operational_due_at], name: "idx_dsr_shop_state_due"
add_index :dsr_requests, [:shop_id, :subject_email]
add_index :dsr_requests, :code, unique: true
```

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `dsr_tasks` | `shop_id`, `dsr_request_id`, `system_key`(orders / customers / marketing / analytics / logs / backups / third_party), `state`, `executed_at`, `record_count`, `notes` | 一個請求拆成多個系統的執行任務；`backups` 任務多半是「標記待清、下次備份輪替後生效」 |
| `legal_holds` | `shop_id`（可 null＝平台級）, `scope`(shop / subject / order_range), `subject_email`, `reason`, `matter_ref`, `issued_by`, `effective_from`, `expires_at`（可 null＝無限期）, `released_at`, `released_by`, `release_reason` | **hold 優先**的判定依據（GDPR Art.17(3)(e)）。`released_at` 不可為 UPDATE 以外的方式清除，變更全寫審計 |
| `dsr_events` | `shop_id`, `dsr_request_id`, `kind`, `actor_type`, `actor_id`, `body`, `occurred_at` | append-only |
| `app_redact_deliveries` | `shop_id`, `topic`(customers/data_request, customers/redact, shop/redact), `app_id`, `payload_digest`, `scheduled_at`, `delivered_at`, `acked_at`, `attempts` | Shopify redact 模型的對等實作（33 §2.13）；HMAC 簽章、at-least-once |

#### 3B 電子發票（租戶域）

```ruby
# 對應 33 §6「einvoice_settings（shop_id, provider, merchant_id, hash_key_ref, issue_timing, cert_expires_at）
#            ／einvoice_tracks（range_start, range_end, remaining）」
create_table :einvoice_settings do |t|
  t.references :shop, null: false, foreign_key: true, index: { unique: true }
  t.string   :provider,     null: false            # ecpay / newebpay（33 §2.14 加值中心）
  t.string   :merchant_id,  null: false
  t.string   :hash_key_ref, null: false            # Rails credentials 的 key 名，不存明文（11 §1）
  t.string   :hash_iv_ref,  null: false            # 33 §6 未列，綠界／藍新 API 需要，本手冊增補
  t.string   :issue_timing, null: false, default: "on_fulfillment"
  # on_payment / on_fulfillment（建議，33 §2.14）/ on_delivery
  t.string   :delegation_state, null: false, default: "pending"  # pending / active / revoked
  t.string   :cert_serial
  t.date     :cert_expires_at                      # 工商憑證，效期 5 年（33 §2.14）
  t.date     :cert_renewal_started_on
  t.timestamps
end

create_table :einvoice_tracks do |t|
  t.references :shop, null: false, foreign_key: true
  t.string   :period,       null: false            # 期別。33 §6 未列此欄，【待定，需使用者確認】格式與雙月制規則
  t.string   :prefix,       null: false            # 字軌（2 碼英文）。33 §6 未列，本手冊增補
  t.integer  :range_start,  null: false            # 33 §6
  t.integer  :range_end,    null: false            # 33 §6
  t.integer  :next_number,  null: false            # 本地估算游標
  t.integer  :remaining_local,    null: false      # = range_end - next_number + 1（本地估算）
  t.integer  :remaining_reported                   # 加值中心回報值（可能延遲）
  t.datetime :reported_at
  t.string   :state,        null: false, default: "active"  # active / exhausted / retired
  t.timestamps
end
add_index :einvoice_tracks, [:shop_id, :period, :prefix], unique: true, name: "idx_track_shop_period_prefix"
add_index :einvoice_tracks, [:shop_id, :state, :remaining_local], name: "idx_track_shop_state_remaining"
```

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `einvoices` | `shop_id`, `order_id`, `track_id`, `invoice_number`, `invoice_date`, `total_cents`, `tax_cents`, `buyer_type`(b2c / b2b), `buyer_tax_id`, `carrier_type`, `carrier_id`, `love_code`, `state`(reserved / issuing / issued / failed / voided / number_burned), `provider_ref`, `issued_at`, `void_at`, `void_reason`, `attempts`, `last_error_code`, `idempotency_key` | 金額 **integer cents**（CLAUDE.md 鐵律 3）。`number_burned` = 號碼已耗用但開立永久失敗，供字軌對帳 |
| `einvoice_allowances` | `shop_id`, `einvoice_id`, `refund_id`, `allowance_number`, `amount_cents`, `tax_cents`, `state`, `provider_ref`, `issued_at`, `idempotency_key` | 部分退貨自動折讓（33 §2.14）。🔴 **累計上限**：`Σ amount_cents(per einvoice_id) ≤ einvoices.total_cents`，以**條件式 UPDATE** 保證（`limits.einvoice.allowance_cumulative_cap`）——見下方註 |

<!-- 依 docs/specs/55 §B.2、§D G-02／G-04 補寫（2026-08-12）：
     ① `einvoice_allowances` 原本**沒有任何累計約束**：同一張發票連續兩次各退 60% 會開出兩張各 60% 的折讓，
        折讓總額 120% > 發票金額 ⇒ 稅務申報錯誤且不可逆。與 55 §A.2「同一筆金流的多次寫入必須有累計上限」同類。
     ② 🔴 `einvoices` **不得**對 `(shop_id, order_id)` 建唯一索引：
        16-F5.5 明寫「訂單編輯造成總額上升 ⇒ **補開一張**發票」，且 V-23（部分出貨開立粒度）若定案為
        「每次出貨各開一張」也會產生多張。§6-3 原本的 `refund.order.einvoice`（**單數**）與此直接矛盾，已一併重寫。
        對照鍵：`limits.einvoice.multiple_invoices_per_order_allowed: true`。 -->
| `einvoice_events` | `shop_id`, `einvoice_id`, `kind`, `request_digest`, `response_digest`, `http_status`, `occurred_at` | 與加值中心往返的留痕；不存完整 payload（含買家 PII），只存摘要＋必要欄位 |
| `einvoice_alerts` | `shop_id`, `kind`(track_low / track_exhausted / cert_expiring / issue_failure_spike), `threshold_value`, `observed_value`, `state`(open / acknowledged / resolved), `notified_at`, `ticket_id` | 去重鍵 `[shop_id, kind, state='open']` 唯一——避免每小時重複開單 |

#### 3C 個資事件與稽核（多為平台域）

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `pdpa_incidents` | `shop_id`（可 null＝平台自身事件）, `code`, `detected_at`, `occurred_at`, `severity`, `data_categories JSON`, `affected_count`, `is_estimate`, `containment_at`, **`authority_notify_due_at`**（＝`detected_at + 72.hours`，33 §2.13）, `authority_notified_at`, `submission_ref`, `subject_notified_at`, `postmortem_ref`, `state`, `declared_by` | 平台域表（`shop_id` 可為 null），列白名單 |
| `pdpa_audits` | `year`, `scope`, `trigger`(capital_1000w / records_5000+ / voluntary), `started_at`, `completed_at`, `findings_count`, `report_ref`, `next_due_on`（＝`completed_at + 12.months`） | 平台域表 |
| `pdpa_drills` | `kind`(breach_notification / restore), `held_on`, `result`, `notes` | 原型 `pdpa`「上次演練：2026-06-18（通報流程走查通過）」 |
| `platform_policies` | `key`(tenant_pdpa_code / aup / dpa), `version`, `effective_at`, `body_ref`, `requires_acceptance`, `published_by` | 平台域表。33 §2.13「平台業者須訂定個資保護守則並要求租戶遵守」 |
| `tenant_policy_acceptances` | `shop_id`, `policy_key`, `policy_version`, `accepted_by_staff_id`, `accepted_at`, `ip`, `user_agent` | 租戶域。原型 `pdpa`「1,204 / 1,284」的分子分母來源 |

#### 3D 前台合規巡檢（規則為平台域、結果為租戶域）

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `compliance_rules` | `key`, `version`, `severity`(critical / warning / info), `legal_basis`, `applies_when JSON`, `targets JSON`, `matcher JSON`, `evidence JSON`, `ticket_template`, `auto_ticket`, `active`, `published_at` | **平台域表**（白名單）。`[key, version]` 唯一；改規則＝新增版本列，不 UPDATE |
| `compliance_scans` | `shop_id`, `started_at`, `finished_at`, `trigger`(daily / manual / post_deploy), `urls_fetched`, `bytes`, `state`(running / done / partial / unreachable), `failure_reason`, `rule_bundle_digest` | 一次掃描一列 |
| `compliance_pages` | `shop_id`, `scan_id`, `url`, `role`(home / privacy / returns / about / product / checkout_notice / sitemap), `http_status`, `etag`, `last_modified`, `content_digest`, `fetched_at`, `from_cache` | 支援 conditional GET 與 digest 快取 |
| `compliance_findings` | `shop_id`, `scan_id`, `rule_key`, `rule_version`, `result`(pass / fail / skipped / inconclusive), `evidence_url`, `evidence_excerpt`, `state`(open / disputed / false_positive / confirmed / resolved), `ticket_id`, `first_seen_at`, `last_seen_at`, `resolved_at` | 索引 `[shop_id, rule_key, state]`；同一 rule 持續失敗只更新 `last_seen_at`，不重複開單 |
| `compliance_rule_suppressions` | `shop_id`, `rule_key`, `rule_version`, `reason`, `appeal_id`, `expires_at`, `approved_by` | 誤判申訴成立後寫入；**必填 `expires_at`**（預設 180 天，待定） |

**平台域表白名單（本模組）**：`pdpa_incidents`（`shop_id` 可 null）、`pdpa_audits`、`pdpa_drills`、`platform_policies`、`compliance_rules`。理由：這五張表的主體是平台自身的法遵義務或全平台共用的規則字典，硬塞 `shop_id` 會造成「平台自身事件掛在哪家店」的假資料。全部查詢在 `Platform::` 命名空間內顯式 `ActsAsTenant.without_tenant`（32 §0）。

---

### 4. API 契約（Platform:: GraphQL）

**3A DSR**

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformDsrRequests` | query | `state, kind, regime, overdueOnly, holdBlockedOnly, first≤250, after` | `DsrRequestConnection`（含 `statutoryDueAt`, `operationalDueAt`, `daysRemaining`, `escalationLevel`） | — | 全部 |
| `platformDsrRequest` | query | `id!` | `DsrRequest`（tasks／events／blockingHold） | `NOT_FOUND` | 全部 |
| `platformDsrRequestIntake` | mutation | `input{ shopId, subjectEmail!, kind!, regime!, receivedAt!, source!, idempotencyKey! }` | `{ dsrRequest, userErrors }` | `VALIDATION_FAILED` `SHOP_NOT_FOUND` | `support`＋ |
| `platformDsrRequestVerifyIdentity` | mutation | `id!, method!, evidenceRef, idempotencyKey!` | `{ dsrRequest, userErrors }` | `ALREADY_VERIFIED` | `support`＋ |
| `platformDsrRequestForwardToMerchant` | mutation | `id!, note, idempotencyKey!` | `{ dsrRequest, userErrors }` | `NOT_MERCHANT_CONTROLLED` | `support`＋ |
| `platformDsrRequestExtend` | mutation | `id!, reason!, idempotencyKey!` | `{ dsrRequest, userErrors }` | `EXTENSION_WINDOW_CLOSED` `EXTENSION_LIMIT_REACHED` `REGIME_NOT_EXTENDABLE` | `admin`＋ |
| `platformDsrRequestExecute` | mutation | `id!, taskKeys[], dryRun=false, idempotencyKey!` | `{ dsrRequest, tasks, blockedByHold, userErrors }` | `LEGAL_HOLD_ACTIVE` `IDENTITY_NOT_VERIFIED` `INVALID_STATE` | `admin`＋（`erasure` 需 JIT 提權） |
| `platformDsrRequestFulfill` | mutation | `id!, artifactRef, responseBody!, idempotencyKey!` | `{ dsrRequest, userErrors }` | `TASKS_INCOMPLETE` | `support`＋ |
| `platformDsrRequestReject` | mutation | `id!, code!, reason!, idempotencyKey!` | `{ dsrRequest, userErrors }` | `REASON_REQUIRED` | `admin`＋ |
| `platformLegalHoldCreate` | mutation | `input{ shopId, scope!, subjectEmail, reason!, matterRef!, effectiveFrom!, expiresAt, idempotencyKey! }` | `{ legalHold, affectedDsrRequests, userErrors }` | `VALIDATION_FAILED` | `platform_owner`（四眼） |
| `platformLegalHoldRelease` | mutation | `id!, reason!, idempotencyKey!` | `{ legalHold, unblockedDsrRequests, userErrors }` | `ALREADY_RELEASED` | `platform_owner`（四眼） |

**3B 電子發票**

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformEinvoicePipeline` | query | `—` | `{ tracksBelowThreshold, certsExpiring60d, issuedToday, voidedToday, allowancesToday, failedPendingRetry }` | — | 全部 |
| `platformEinvoiceSettings` | query | `shopId!` | `EinvoiceSetting`（含 tracks、憑證狀態） | `NOT_FOUND` | 全部 |
| `platformEinvoiceTracks` | query | `shopId, state, belowRatio, first, after` | `EinvoiceTrackConnection`（`remainingLocal` / `remainingReported` 雙欄） | — | 全部 |
| `platformEinvoiceQueue` | query | `kind!(ISSUE_RETRY\|VOID\|ALLOWANCE), first, after` | `EinvoiceConnection` | — | 全部 |
| `platformEinvoiceSettingUpdate` | mutation | `shopId!, issueTiming, delegationState, certSerial, certExpiresAt, idempotencyKey!` | `{ setting, userErrors }` | `VALIDATION_FAILED` `DELEGATION_REQUIRED` | `admin`＋ |
| `platformEinvoiceTrackRegister` | mutation | `input{ shopId!, period!, prefix!, rangeStart!, rangeEnd!, idempotencyKey! }` | `{ track, userErrors }` | `TRACK_OVERLAP` `INVALID_RANGE` | `admin`＋ |
| `platformEinvoiceIssueRetry` | mutation | `ids[]!, idempotencyKey!` | `{ jobId, accepted, rejected, userErrors }` | `TRACK_EXHAUSTED` `CERT_EXPIRED` `DELEGATION_INACTIVE` | `support`＋ |
| `platformEinvoiceVoid` | mutation | `id!, reason!, idempotencyKey!` | `{ einvoice, userErrors }` | `VOID_WINDOW_CLOSED` `ALREADY_VOIDED` `HAS_ALLOWANCE` | `admin`＋ |
| `platformEinvoiceAllowanceCreate` | mutation | `input{ einvoiceId!, refundId!, amountCents!, taxCents!, idempotencyKey! }` | `{ allowance, userErrors }` | `AMOUNT_EXCEEDS_INVOICE` `INVOICE_VOIDED` | `admin`＋ |
| `platformEinvoiceAlertAck` | mutation | `id!, note, idempotencyKey!` | `{ alert, userErrors }` | `ALREADY_RESOLVED` | `support`＋ |

**3C 個資**

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformPdpaOverview` | query | `—` | `{ activeIncidents, lastDrill, lastAudit, auditNextDue, traceRetentionYears, policyAcceptance{signed,total}, activeLegalHolds }` | — | 全部 |
| `platformPdpaIncidents` | query | `state, first, after` | `PdpaIncidentConnection`（含 `hoursToAuthorityDeadline`） | — | `support`＋ |
| `platformPdpaIncidentDeclare` | mutation | `input{ shopId, detectedAt!, severity!, dataCategories[]!, affectedCount!, isEstimate, summary!, idempotencyKey! }` | `{ incident, userErrors }` | `DETECTED_AT_IN_FUTURE` `LATE_DISCOVERY_REASON_REQUIRED` | `admin`＋ |
| `platformPdpaIncidentNotifyAuthority` | mutation | `id!, submissionRef!, submittedAt!, attachmentRef, idempotencyKey!` | `{ incident, userErrors }` | `ALREADY_NOTIFIED` | `platform_owner` |
| `platformPdpaAuditRecord` | mutation | `input{ year!, scope!, startedAt!, completedAt, findingsCount, reportRef, idempotencyKey! }` | `{ audit, userErrors }` | `VALIDATION_FAILED` | `admin`＋ |
| `platformPolicyPublish` | mutation | `key!, version!, effectiveAt!, bodyRef!, requiresAcceptance!, idempotencyKey!` | `{ policy, userErrors }` | `VERSION_EXISTS` | `platform_owner` |
| `platformPolicyAcceptances` | query | `policyKey!, signed, first, after` | `TenantPolicyAcceptanceConnection` | — | 全部 |

**3D 巡檢器**

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformComplianceSummary` | query | `—` | `[{ ruleKey, label, passed, applicable, ratio, delta }]` | — | 全部 |
| `platformComplianceFindings` | query | `shopId, ruleKey, result, state, first, after` | `ComplianceFindingConnection` | — | 全部 |
| `platformComplianceScanRun` | mutation | `shopId, scope!(SHOP\|ALL), idempotencyKey!` | `{ scanId, estimatedSeconds, userErrors }` | `RATE_LIMITED` `SHOP_NOT_SCANNABLE` | `SHOP`：`support`＋／`ALL`：`admin`＋ |
| `platformComplianceFindingResolve` | mutation | `id!, decision!(CONFIRMED\|FALSE_POSITIVE), reason!, suppressUntil, idempotencyKey!` | `{ finding, suppression, userErrors }` | `SUPPRESSION_REQUIRES_EXPIRY` `ALREADY_RESOLVED` | `admin`＋ |
| `platformComplianceRulePublish` | mutation | `input{ key!, version!, ...!, idempotencyKey! }` | `{ rule, userErrors }` | `VERSION_EXISTS` `MATCHER_INVALID` | `platform_owner`（規則是法律判斷，見 §7） |

**商家端**（`/admin/api/`）：`complianceFindings(first, after)`、`complianceFindingDispute(id!, reason!)` → 建 `appeals(kind: 'compliance_scan')`，銜接模組二。

---

### 5. 服務物件與背景任務

| 類別／Job | 排程 | 職責 |
|---|---|---|
| `Platform::Dsr::DeadlineCalculator` | — | 依 regime 算 `statutory_due_at` / `operational_due_at` / 延期上限（§6-1） |
| `Platform::Dsr::HoldGuard` | — | erasure 前置檢查，回傳命中的 hold（§6-2） |
| `Platform::Dsr::ErasureExecutor` | — | 逐 `dsr_tasks` 執行；每個系統一個 adapter |
| `Platform::Dsr::AccessPackager` | — | 產出 access／portability 包（JSON＋CSV，zip 加密，簽名連結 24h） |
| `Platform::Dsr::DeadlineWatchJob` | 每小時 | T-14／T-7／T-3／T-1／逾期五級升級告警（§6-1） |
| `Platform::Dsr::RedactSchedulerJob` | 每日 | Shopify redact 模型：`customers/redact` 近 6 個月有下單則延後、否則最少延遲 10 天；`shop/redact` 解安裝後 48 小時（33 §2.13） |
| `Platform::Einvoice::TrackMonitorJob` | **每小時**（建議值） | 重算 `remaining_local`、比對 `remaining_reported`、跨 15% 門檻開 `einvoice_alerts`＋通知（§6-3） |
| `Platform::Einvoice::CertWatchJob` | 每日 08:00 | `cert_expires_at <= today + 60.days` → 告警（33 §2.14）；30／14／7 天再升級（建議值） |
| `Platform::Einvoice::IssueJob(einvoice_id)` | 事件觸發 | 依 `issue_timing` 由訂單／出貨事件觸發；provider 呼叫**在 transaction 外**（§6-3） |
| `Platform::Einvoice::VoidJob` / `AllowanceJob` | 事件觸發 | 全額取消→作廢、部分退貨→折讓（33 §2.14） |
| `Platform::Einvoice::ReconcileJob` | 每日 05:00 | 拉加值中心日報，回填 `remaining_reported`、比對 `number_burned`、產差異清單 |
| `Platform::Pdpa::IncidentClockJob` | 每 15 分鐘 | 72 小時倒數；T-24／T-12／T-6／T-2 小時升級；逾期 → 全域告警 |
| `Platform::Pdpa::AuditDueJob` | 每日 | 距上次稽核 10／11／12 個月三級告警（33 §2.13） |
| `Platform::Pdpa::PolicyAcceptanceSweepJob` | 每日 | 統計簽署率；新版守則發布後 N 天未簽 → 提醒（N 待定） |
| `Platform::Compliance::ScanShopJob(shop_id)` | 每日 06:00 起 90 分鐘窗內抖動 | 抓取＋跑規則＋寫 findings＋開工單（§6-4） |
| `Platform::Compliance::ScanAllJob` | 每日 06:00 | 依 `shop_id` hash 分桶入列，每桶延遲 `hash % 90` 分鐘 |
| `Platform::Compliance::TicketJob` | 事件觸發 | fail 且 `auto_ticket` → 開商家工單（原型 `shopcompliance`「未通過・已開工單」） |

---

### 6. 關鍵流程與演算法

#### 6-1 DSR 雙時鐘、延期閘門與逾期升級

```ruby
# app/services/platform/dsr/deadline_calculator.rb
module Platform
  module Dsr
    # DSR 法定期限計算。
    #
    # 為什麼要「雙時鐘」：33 §2.13 同時給了兩個數字——法規面是 GDPR「1 個月」、CCPA「45 天」；
    # 而 Shopify redact 模型是「30 天內完成」。「1 個月」≠「30 天」（可能 28~31 天），
    # 原型 dsr 卡片寫的是「GDPR 30 天」。兩者不是同一件事：
    #   statutory_due_at  = 法定義務，逾期＝違法，用曆月推算（ActiveSupport 的 1.month 正確處理月底）
    #   operational_due_at= 內部 SLA，取兩者較嚴者，所有告警以它為準
    # 只留一個會出事：只留 30 天會在 2 月案件上「提早」逾期造成假警報；
    # 只留曆月會在對接 app 生態時違反 30 天承諾。所以兩個都存、都顯示。
    class DeadlineCalculator
      def self.for(regime:, received_at:)
        statutory =
          case regime
          when "gdpr"    then received_at + 1.month     # 33 §2.13 GDPR Art.12(3)
          when "ccpa"    then received_at + 45.days     # 33 §2.13
          when "pdpa_tw" then nil                       # 【待定，需使用者確認】33 未載台灣 DSR 期限
          end
        operational = [statutory, received_at + 30.days].compact.min  # 33 §2.13 Shopify 模型
        { statutory_due_at: statutory, operational_due_at: operational }
      end

      # 延期閘門。
      # GDPR：可延 2 個月（合計 3），但「須在 1 個月內告知延期理由」——
      # 因此延期申請本身若已超過 received_at + 1.month，就是遲了，系統必須擋下並要求走「逾期處理」流程。
      def self.extend!(dsr, reason:, now: Time.current)
        return [:REGIME_NOT_EXTENDABLE, nil] if dsr.regime == "pdpa_tw"
        return [:EXTENSION_LIMIT_REACHED, nil] if dsr.extended_until.present?

        notify_deadline = dsr.received_at + (dsr.regime == "gdpr" ? 1.month : 45.days)
        return [:EXTENSION_WINDOW_CLOSED, notify_deadline] if now > notify_deadline

        extension = dsr.regime == "gdpr" ? 2.months : 45.days   # 33 §2.13：GDPR 可延 2 個月、CCPA 可延 45 天
        dsr.update!(extended_until: dsr.statutory_due_at + extension,
                    extension_reason: reason, extension_notified_at: now,
                    statutory_due_at: dsr.statutory_due_at + extension,
                    operational_due_at: dsr.operational_due_at + extension)
        [nil, dsr]
      end

      # 升級層級：T-14 / T-7 / T-3 / T-1 / overdue（【建議值】，33 只規定法定期限本身）
      LEVELS = { 14 => :notice, 7 => :warn, 3 => :urgent, 1 => :critical }.freeze
      def self.escalation_level(dsr, now: Time.current)
        return :overdue if now > dsr.operational_due_at
        days = ((dsr.operational_due_at - now) / 1.day).floor
        LEVELS.keys.sort.find { days <= _1 }&.then { LEVELS[_1] } || :none
      end
    end
  end
end
```

#### 6-2 Legal hold 優先於 erasure

```ruby
# app/services/platform/dsr/hold_guard.rb
module Platform
  module Dsr
    # erasure 與 legal hold 衝突時，hold 優先。
    #
    # 法源：GDPR Art.17(3)(e)——當處理係為「法律主張之建立、行使或防禦」所必要時，
    # 刪除權不適用。33 §5-9 把這條列為驗收項目：「erasure 與 legal hold 衝突時 hold 優先」。
    #
    # 三個容易寫錯的地方，這裡都處理掉：
    # 1) hold 優先「不代表可以不回覆」——回覆義務的期限照跑，只是回覆內容從「已刪除」
    #    變成「依 Art.17(3)(e) 拒絕，理由如下，保全事由結束後將重新評估」。所以本方法
    #    不會關閉請求、不會停時鐘，只把 state 改成 blocked_by_hold。
    # 2) hold 可能只涵蓋部分資料（例如只保全某段期間的訂單）——要支援部分執行。
    # 3) 判定必須在「執行的同一個 transaction 內再查一次」，否則審核員按下按鈕到 job 執行
    #    之間新設的 hold 會被繞過（TOCTOU）。
    class HoldGuard
      # @return [Array<LegalHold>] 命中的 hold（空陣列＝可執行）
      def self.blocking_holds(dsr, at: Time.current)
        LegalHold.where(released_at: nil)
                 .where("effective_from <= ?", at)
                 .where("expires_at IS NULL OR expires_at > ?", at)
                 .where(shop_id: [dsr.shop_id, nil])   # nil＝平台級 hold，涵蓋所有租戶
                 .select { |h| h.scope == "shop" || h.subject_email.casecmp?(dsr.subject_email) }
      end

      # @param task_keys [Array<String>] 要執行的子系統
      # @return [Hash] { executed: [...], blocked: [...], holds: [...] }
      def self.partition_tasks(dsr, task_keys, at: Time.current)
        holds = blocking_holds(dsr, at:)
        return { executed: task_keys, blocked: [], holds: [] } if holds.empty?

        # scope=shop 的 hold 擋全部；scope=order_range 只擋 orders 相關任務
        blanket = holds.any? { _1.scope.in?(%w[shop subject]) }   # scope=shop/subject 擋全部
        blocked = blanket ? task_keys : task_keys & %w[orders]
        { executed: task_keys - blocked, blocked:, holds: }
      end
    end
  end
end

# app/services/platform/dsr/erasure_executor.rb（節錄）
def call
  return failure(:IDENTITY_NOT_VERIFIED) if @dsr.verified_at.blank?

  result = nil
  ActiveRecord::Base.transaction do
    # TOCTOU 防護：在 transaction 內、拿 row lock 後重查一次 hold
    @dsr.lock!
    result = HoldGuard.partition_tasks(@dsr, @task_keys)

    if result[:blocked].any?
      @dsr.update!(hold_blocked: true, blocking_legal_hold_id: result[:holds].first.id,
                   state: result[:executed].any? ? "in_progress" : "blocked_by_hold")
      DsrEvent.create!(shop_id: @dsr.shop_id, dsr_request_id: @dsr.id, kind: "hold_blocked",
                       actor_type: "system", occurred_at: Time.current,
                       body: "GDPR Art.17(3)(e)：#{result[:holds].map(&:matter_ref).join(',')} 保全中，" \
                             "以下項目不予刪除：#{result[:blocked].join('、')}")
      Platform::Audit.record!(action: "dsr.erasure_blocked_by_hold", actor: @actor,
        shop_id: @dsr.shop_id, target_type: "DsrRequest", target_id: @dsr.id,
        previous: { state: "in_progress" }, next_state: { state: @dsr.state, blocked: result[:blocked] },
        reason: "legal hold 優先（GDPR Art.17(3)(e)）", source: "UI", outcome: "blocked")
    end

    result[:executed].each { |k| @dsr.dsr_tasks.find_by!(system_key: k).update!(state: "queued") }
  end
  # 實際刪除在 transaction 外的 job 逐系統執行（11 §2：長時間操作不佔鎖）
  result[:executed].each { |k| Platform::Dsr::EraseSystemJob.perform_later(@dsr.id, k) }
  success(result)
end
```

#### 6-3 電子發票：字軌餘量監控與號碼保留

```ruby
# app/services/platform/einvoice/track_monitor.rb
module Platform
  module Einvoice
    # 字軌餘量監控。
    #
    # 為什麼這支 job 是本模組最重要的一支：33 §2.14 與原型 einvoice 都明講
    # 「字軌耗盡即無法開立」，而且原型把它標成「台灣營運最常見的事故來源」。
    # 字軌用完不會有任何技術錯誤——開立 API 就是回失敗，訂單照常成立，
    # 客訴在三天後才會到，那時已經累積上千張未開發票。所以要在 15% 就叫。
    #
    # 為什麼要雙欄（local / reported）：33 §2.14 說字軌由加值中心「代辦」，
    # 但餘量「須自行監控」——代表真實游標在加值中心那邊，我們的 next_number 只是估算。
    # 這與 33 §2.5 爭議率「卡組織回報值／我方即時估算值雙欄並列」是同一個設計語言，
    # 告警一律取兩者較小值，寧可早叫。
    LOW_RATIO = 0.15   # 33 §2.14／原型 einvoice「15% 門檻主動通知」

    def call
      EinvoiceTrack.where(state: "active").find_each(batch_size: 500) do |track|
        total     = track.range_end - track.range_start + 1
        local     = track.range_end - track.next_number + 1
        effective = [local, track.remaining_reported].compact.min
        ratio     = effective.to_f / total

        track.update_columns(remaining_local: local)   # 純計算欄，不觸發 callback

        if effective <= 0
          upsert_alert!(track, :track_exhausted, 0, effective)
        elsif ratio < LOW_RATIO
          upsert_alert!(track, :track_low, (LOW_RATIO * total).floor, effective)
        else
          resolve_alerts!(track)
        end
      end
    end

    # 去重：同一 shop＋kind 的 open 告警唯一（DB 唯一索引兜底，11 §2）。
    # 不去重的話這支 job 每小時跑一次，一個字軌不足的商家 30 天會產生 720 張工單。
    def upsert_alert!(track, kind, threshold, observed)
      alert = EinvoiceAlert.find_or_initialize_by(shop_id: track.shop_id, kind:, state: "open")
      first_time = alert.new_record?
      alert.assign_attributes(threshold_value: threshold, observed_value: observed)
      alert.save!
      return unless first_time
      Platform::Einvoice::NotifyJob.perform_later(alert.id)   # 商家 email＋後台橫幅＋平台工單
    end
  end
end
```

```ruby
# app/services/platform/einvoice/issue.rb（號碼保留 → 外部呼叫 → 回寫，三段式）
# 為什麼要三段：transaction 內禁外部 IO（11 §2、CLAUDE.md 鐵律 5）。
# 加值中心 API p95 可能到數秒，若包在 transaction 裡，字軌那一列的鎖會被持有數秒，
# 尖峰時所有開立請求排隊 → 連線池耗盡 → 全站掛。這是 11 §8 坑 2 的教科書案例。
def call
  # 第一段（短 transaction）：以條件式 UPDATE 原子性取號（11 §3 三板斧第一招，無鎖等待）
  invoice = ActiveRecord::Base.transaction do
    affected = EinvoiceTrack.where(id: @track.id, state: "active")
                            .where("next_number <= range_end")
                            .update_all("next_number = next_number + 1, remaining_local = remaining_local - 1")
    raise TrackExhausted if affected.zero?
    t = @track.reload
    Einvoice.create!(shop_id: @shop.id, order_id: @order.id, track_id: t.id,
                     invoice_number: format("%08d", t.next_number - 1),
                     total_cents: @order.total_cents, tax_cents: @order.tax_cents,   # integer cents
                     state: "reserved", idempotency_key: @key)
  end

  # 第二段（transaction 外）：呼叫加值中心
  resp = provider_client.issue(invoice)      # 逾時 10s，重試由 job 層負責

  # 第三段（短 transaction）：回寫結果
  ActiveRecord::Base.transaction do
    if resp.success?
      invoice.update!(state: "issued", provider_ref: resp.ref, issued_at: Time.current)
    elsif resp.retryable?
      invoice.update!(state: "failed", attempts: invoice.attempts + 1, last_error_code: resp.code)
    else
      # 永久失敗：號碼已耗用但無發票 → 標 number_burned，供 ReconcileJob 與加值中心對帳
      invoice.update!(state: "number_burned", last_error_code: resp.code)
    end
    EinvoiceEvent.create!(shop_id: @shop.id, einvoice_id: invoice.id, kind: "issue",
                          http_status: resp.status, response_digest: resp.digest, occurred_at: Time.current)
  end
end
```

**作廢與折讓的觸發規則**（33 §2.14）：

```ruby
# app/services/platform/einvoice/refund_router.rb
# 全額取消 → 自動作廢；部分退貨 → 自動折讓。
# 判定必須用「金額」而非「是否有剩餘品項」——部分品項退貨但金額等於全額（例如另有運費折抵）
# 的情況要走作廢；反之亦然。金額一律 integer cents 比較（CLAUDE.md 鐵律 3）。
#
# 🔴 本方法於 2026-08-12 由 55 號盤點重寫（docs/specs/55 §B.2、§D G-02/G-03/G-04/G-10）。
#    原版本為 `invoice = refund.order.einvoice；if refund.amount_cents >= invoice.total_cents`，
#    「單張發票 × 單次退款」判定，有四個破口：
#      ① 無累計上限 → 兩次各退 60% 開出兩張各 60% 的折讓 ⇒ 折讓總額 120% > 發票金額 ⇒ 稅務申報錯誤且不可逆
#      ② 下方留了 window_open? 掛勾卻**從不呼叫** ⇒ 跨期別全額退款嘗試作廢被拒 ⇒ 該筆銷售永遠無沖銷憑證
#      ③ `refund.order.einvoice`（單數）假設一訂單一發票 ⇒ 與 16-F5.5「編輯加收補開一張」直接矛盾
#      ④ `state != "issued"` 把**開立在途**（issuing）當成沒有發票 ⇒ 加值中心 p95 數秒的窗口內退款永久遺失稅務動作
#    任何人翻舊版看到 `refund.amount_cents >= invoice.total_cents` 都不要改回去。
#
# 入參 refund_cash_cents ＝「**扣除禮品卡與商店抵用金分配後**的實際金流退款額」（16-F5.5(a)、⚠ V-20/V-22）
# ——不是 refund.amount_cents，也不是 suggested_refund 名目值。
def route(order, refund_cash_cents)
  raise ArgumentError unless refund_cash_cents.is_a?(Integer)   # 傳入 float 即 raise（既有測試 38:1508）

  # ① 在途保護：開立中的發票不得被當成「沒有發票」
  return :defer if order.einvoices.exists?(state: "issuing")    # limits.einvoice.defer_when_issuing

  invoices = order.einvoices.where(state: "issued")
  return :no_invoice if invoices.empty?                         # 尚未開立 ⇒ no-op，不產生孤兒作廢

  # ② 沖銷順序：能追溯到退款品項的先沖該張；不能追溯者 LIFO（後開的先沖，離作廢窗關閉最遠）
  #    ⚠ 無官方來源，本專案決策（limits.einvoice.allowance_offset_order: traceable_then_lifo）
  remaining = refund_cash_cents
  ordered_invoices(order, invoices).each do |inv|
    allowed = inv.total_cents - inv.allowances.sum(:amount_cents)   # 該張剩餘可沖額＝累計上限
    take    = [remaining, allowed].min
    next if take.zero?

    if take == inv.total_cents && inv.allowances.empty? && EinvoiceVoidPolicy.window_open?(inv)
      Platform::Einvoice::VoidJob.perform_later(inv.id, reason: "order_fully_refunded")
    else
      # 「本該作廢但作廢窗已關」也落在這裡 ⇒ 降級為全額折讓，**不是失敗**
      # （limits.einvoice.void_window_closed_fallback: full_allowance）
      Platform::Einvoice::AllowanceJob.perform_later(inv.id, amount_cents: take)
    end
    remaining -= take
  end

  # ③ 超額退款：沒有稅務憑證可沖，🔴 不得憑空產生折讓
  enqueue_manual_review!(order, remaining) if remaining.positive?
  remaining.positive? ? :partial_with_manual_review : :routed
end
# 累計上限一律以條件式 UPDATE 落地於 AllowanceJob（limits.einvoice.allowance_cap_enforcement），
# 禁止先 SELECT 再 INSERT——兩筆併發退款會各自算出「還可以折讓」而雙雙寫入。
#
# 【待定，需使用者確認】作廢是否受「該期別申報前」的時間窗限制（33 未載，⚠ V-06）。
# EinvoiceVoidPolicy.window_open?(invoice) 掛勾預設回 true，待法規確認後填實
# （limits.einvoice.void_window_policy: null / verify_void_window: true）。
```

#### 6-4 前台合規巡檢器：爬取策略、規則結構、誤判申訴

**爬取策略（禮貌性與可預測性）**

| 面向 | 設計 | 理由／數值出處 |
|---|---|---|
| 頻率 | 每日一次，06:00 起（原型 `shopcompliance`「上次掃描：今天 06:00（每日自動）」）；手動重掃單店每小時 3 次上限、全平台每小時 1 次 | 原型；節流值為【建議值】 |
| 起跑抖動 | `ScanAllJob` 依 `shop_id % 90` 分鐘延遲入列，把 1,284 家攤在 06:00–07:30 | 避免 thundering herd 打爆自家 storefront（凌晨也是備份與 feed 推送時段） |
| 併發 | 全域 ≤20 併發；**單一 host ≤1 併發**且相鄰請求間隔 ≥1 秒 | 原型 toast「全平台重掃約 20 分鐘」的可行性驗算：1,284 店 × 8 URL × 1s ÷ 20 併發 ≈ 8.6 分鐘，留足餘裕 |
| 每店抓取量 | ≤8 個 URL：首頁／隱私政策／退換貨政策／關於或商家資訊／2 個商品頁（隨機抽樣，含一個 `excluded_from_cooling_off` 商品若有）／結帳前告知頁／`robots.txt` | 【建議值】；抽樣可讓「鑑賞期例外商品標示」這種商品層規則以可負擔成本檢查 |
| 快取 | `If-None-Match` / `If-Modified-Since`；回 304 或 `content_digest` 未變 → **沿用上次判定**，不重跑規則（除非 `rule_bundle_digest` 變了） | 大幅降低運算與抓取；規則改版時自動全量重判 |
| 逾時 | connect 5s／read 10s／總 15s；回應體上限 2 MB（超過截斷並標 `inconclusive`） | 防單店拖垮批次 |
| 重試 | 3 次指數退避 1s／4s／16s＋±25% jitter；**同一天內不再重試** | |
| 失敗處理 | 單次失敗 → `compliance_scans.state='unreachable'`，**不開工單**；**連續 2 日**皆 unreachable → 開 P3 工單「前台無法連線」 | 網路抖動不該產生法遵工單；連續 2 日為【建議值】 |
| robots.txt | 平台子網域（`*.mychilllove.com`）以資料控管者身分掃描，不受 robots 限制；**自訂網域**讀 robots 並以 `CHILLLOVEComplianceBot` UA 白名單比對，被 disallow 時記 `skipped_by_robots` 並開工單要求租戶放行——放行義務寫進租戶守則（33 §2.13「平台業者須訂定個資保護守則並要求租戶遵守」） | 這是本模組唯一會踩到「爬別人網站」倫理線的地方，必須有明文依據 |
| UA | `CHILLLOVEComplianceBot/1.0 (+https://help.chilllove.tw/compliance-bot)` | 可辨識、可查詢、可聯絡 |
| JS 渲染 | 預設純 HTML 解析；首頁文字內容 <200 字且偵測到 SPA 殼 → 丟 `compliance_render` 佇列用 headless 重抓（低頻、獨立佇列、併發 2） | Liquid 前台為 SSR（D4），理論上不需要；此為 fallback |
| PII | 抓取內容**不落地全文**，只存 `content_digest` 與命中處前後各 120 字的 `evidence_excerpt` | 11 §7 合規基線 |

**規則結構（可維護性）**——規則存 `db/compliance_rules/*.yml`，部署時 upsert 進 `compliance_rules`（新版本＝新列，不改舊列）：

```yaml
# db/compliance_rules/tw_tax_id_disclosure.yml
key: tw.tax_id_disclosure
version: 3
severity: critical
label: 營業人名稱與統一編號揭露
legal_basis: >
  達起徵點（2025/1/1 起貨物月銷 10 萬、勞務 5 萬）須辦稅籍登記，並於銷售網頁揭露
  營業人名稱與統一編號；稅籍須登錄網域與網路位址（33 §2.14）
applies_when:                      # 不適用時 result=skipped，不計入分母
  shop_has_tax_id: true
targets: [home, about, footer_all_pages]
matcher:
  all:
    - kind: text_regex
      pattern: '統一編號\s*[:：]?\s*(\d{8})'
      capture: tax_id
    - kind: equals_shop_field
      capture: tax_id
      field: tax_id                # 揭露的統編必須等於 shops.tax_id，不是「有八碼數字就過」
    - kind: text_contains_shop_field
      field: legal_name
evidence: { snippet_chars: 240 }
remediation:
  auto_ticket: true
  ticket_priority: P2
  ticket_template: tw_tax_id_missing
```

支援的 matcher 原語（可組合 `all` / `any` / `none`）：`text_regex`、`text_contains`、`equals_shop_field`、`text_contains_shop_field`、`link_exists`（依 href pattern 或錨文字）、`page_reachable`（該 role 的頁面 HTTP 200 且字數 ≥N）、`dom_selector_present`、`product_flag_consistency`（商品有 `excluded_from_cooling_off` 旗標時，前台商品頁必須出現例外告知——對應原型第 5 項「鑑賞期例外商品標示」）、`domain_matches_tax_registration`（對應原型第 6 項「稅籍登記網域一致」）。

**為什麼規則不做成 UI 可編輯**：法遵規則是法律判斷，改一個 regex 就可能讓 1,284 家店集體變成「不合格」並自動開工單。規則走 PR review（含法務會簽）＋版本化，UI 只提供**單店例外**（suppression）。`platformComplianceRulePublish` 保留給 `platform_owner`，正常流程仍是部署。

**誤判申訴路徑**

```
巡檢 fail
  → compliance_findings(state: open) → 自動開商家工單（原型「未通過・已開工單」）
  → 商家在其後台點「這是誤判」→ complianceFindingDispute(id, reason)
  → 建 appeals(kind: 'compliance_scan', subject: ComplianceFinding)  ← 進模組二看板
  → finding.state = 'disputed'（工單轉「申訴中」，暫停催辦）
  → 審理：
      成立 → platformComplianceFindingResolve(FALSE_POSITIVE, suppressUntil)
             ├ 寫 compliance_rule_suppressions（必填 expires_at，預設 180 天【待定】）
             ├ 該店該規則在到期前不再判 fail（達成率分母排除，標 skipped）
             └ 自動在工程 backlog 開「規則改進」issue，附證據，避免同一誤判在他店重演
      不成立 → CONFIRMED，finding 回 open，工單恢復催辦，通知商家並附理由
```

**為什麼 suppression 必須有到期日**：無到期的例外會累積成「合規黑洞」——一年後沒人記得為什麼這家店的統編檢查被關掉。到期前 14 天自動重新評估並通知審理人。

---

### 7. 需要的工具、gem 與外部依賴

| 用途 | 選型 | 說明 |
|---|---|---|
| HTTP 抓取 | Ruby 3.x 內建 `Net::HTTP`＋自寫連線池；**不引入 Faraday/HTTParty**（AGENTS.md：不引入未討論依賴） | 需要精確控制逾時、重試、conditional GET、UA、per-host 併發 |
| HTML 解析 | `nokogiri`（Rails 既有傳遞依賴） | `dom_selector_present` 與文字擷取 |
| 文字正規化 | 自寫：全形→半形、去零寬字元、`NFKC`（Ruby `String#unicode_normalize`） | 防「統一編號：１２３４５６７８」全形繞過 |
| headless 渲染（fallback） | 既有無頭 Chromium（11 §6 已列為測試工具） | 獨立佇列、併發 2 |
| 電子發票 | 綠界 ECPay／藍新 NewebPay HTTP API（自寫 client，AES 加簽） | HashKey／HashIV 走 Rails credentials，**絕不進 git**（11 §1）；`hash_key_ref` 只存 key 名 |
| DSR 匯出包 | 自寫 zip（`rubyzip`）＋Active Storage 簽名連結 24h | 包內含 JSON＋CSV；加密密碼另管道給付 |
| 排程 | Solid Queue recurring（Rails 8 內建，不用 Redis／sidekiq-cron） | D1 決策 |
| 監控 | 既有 lograge／Sentry／OpenTelemetry（11 §5）；新增指標：`dsr_overdue_count`、`einvoice_track_low_count`、`einvoice_issue_failure_rate`、`compliance_scan_unreachable_rate`、`pdpa_incident_hours_remaining` | 皆需 dashboard |
| **外部依賴風險** | 加值中心 API 為單點：其停機＝全平台無法開立。需 `統一發票` 元件納入對外狀態頁（原型 `SP` 已有「電子發票」元件且示範為 degraded） | |

**不做**：不接第三方合規掃描 SaaS（會把租戶前台與商品資料送出境）；不做圖片內文字辨識（統編寫在圖片裡的情況記 `inconclusive` 並人工複核）。

---

### 8. 實作步驟（順序化 todo）

**共用地基**
1. `compliance_deadlines` 計時器 concern（`due_at` + `escalation_level` + 告警去重）供 3A／3C 共用。
2. 告警通道：平台工單、商家 email、商家後台橫幅、頂列健康列（32 §3-1）四個出口統一走 `Platform::Alerting`。

**3A DSR**
3. 建 `dsr_requests` / `dsr_tasks` / `legal_holds` / `dsr_events` / `app_redact_deliveries`。
4. `DeadlineCalculator`（雙時鐘＋延期閘門）＋單元測試。
5. `HoldGuard`＋`ErasureExecutor`（含 TOCTOU 鎖）；逐系統 adapter：orders／customers／marketing／analytics／logs／backups／third_party。
6. `AccessPackager`；`DeadlineWatchJob` 五級升級。
7. `RedactSchedulerJob`（33 §2.13 三個 topic 的延遲規則）＋HMAC 驗簽。
8. GraphQL 11 支；`platformDsrRequestExecute` 掛 JIT 提權檢查。

**3B 電子發票**
9. 建 5 張表；`config/limits.yml` 加 `einvoice.track_low_ratio: 0.15`、`einvoice.cert_warn_days: 60`。
10. Provider client（ecpay／newebpay）＋契約測試（VCR 錄製，敏感值遮罩）。
11. `Issue` 三段式＋`TrackMonitorJob`＋`CertWatchJob`＋`ReconcileJob`。
12. `RefundRouter`＋`VoidJob`／`AllowanceJob`；接訂單取消與退款事件。
13. GraphQL 11 支＋租戶詳情 `shopinvoice` 卡片。

**3C 個資**
14. 建 5 張表；`PdpaIncidentClockJob` 72h 倒數；宣告表單。
15. 稽核紀錄與 `AuditDueJob`；演練紀錄。
16. `platform_policies` 版本管理＋租戶簽署流程（商家後台阻斷式 modal）。

**3D 巡檢器**
17. `compliance_rules` YAML loader＋6 條種子規則（對應原型 `shopcompliance` 六項）。
18. Fetcher（per-host 併發控制、conditional GET、UA、robots）。
19. Matcher 原語 9 種＋規則執行器；`ScanShopJob` / `ScanAllJob`。
20. `TicketJob`＋誤判申訴串接模組二＋`suppressions`。
21. 摘要 rollup（`platformComplianceSummary` 分母＝應受檢店數）。
22. React 四張卡片（`dsr`／`pdpa`／`einvoice`／`frontscan`）＋租戶詳情兩張（`shopcompliance`／`shopinvoice`）。
23. `docs/dev/m9-compliance.md`。

---

### 9. 測試清單

**3A DSR**

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/dsr/deadline_calculator_spec.rb` | ① GDPR 1/31 受理 → `statutory_due_at` 為 2/28（曆月，非 +30 天） ② GDPR `operational_due_at` = received+30d（較嚴） ③ CCPA 45 天 ④ `pdpa_tw` → `statutory_due_at` 為 nil 且不告警為逾期 ⑤ 延期在 received+1 個月**之後**申請 → `EXTENSION_WINDOW_CLOSED` ⑥ 延期成功後兩個時鐘同步後移且 `extension_notified_at` 有值 ⑦ 二次延期 → `EXTENSION_LIMIT_REACHED` |
| `spec/services/platform/dsr/hold_guard_spec.rb` | ① 有效 shop 級 hold → erasure 全部 blocked ② subject 級 hold（email 大小寫不同）→ 仍命中 ③ 平台級 hold（`shop_id: nil`）→ 命中所有租戶 ④ 已 `released_at` 的 hold → 不阻擋 ⑤ `expires_at` 已過 → 不阻擋 ⑥ `order_range` scope → 只擋 orders 任務，其餘照執行 ⑦ **TOCTOU**：執行 job 排入後、transaction 前新增 hold → 仍被擋（用 `after_commit` hook 插入 hold 模擬） |
| `spec/services/platform/dsr/erasure_executor_spec.rb` | ① blocked 時 **state 轉 `blocked_by_hold` 但時鐘不停**、`operational_due_at` 不變 ② blocked 事件寫入 `dsr_events` 且 body 含「GDPR Art.17(3)(e)」 ③ 審計列 `outcome: blocked` 存在 ④ 未驗證身分 → `IDENTITY_NOT_VERIFIED` |
| `spec/jobs/platform/dsr/deadline_watch_job_spec.rb` | 五級升級各發一次且冪等；逾期開 P1 並寫審計；已 `fulfilled` 不再告警 |
| `spec/jobs/platform/dsr/redact_scheduler_job_spec.rb` | ① 近 6 個月有下單 → 排程延後至滿 6 個月 ② 無下單 → 至少延遲 10 天 ③ `shop/redact` 解安裝後 48 小時 ④ HMAC 錯誤的入站 redact → 拒收（33 §2.13） |

**3B 電子發票**

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/einvoice/track_monitor_spec.rb` | ① 餘量 14.9% → 開 `track_low` 告警 ② 15.1% → 不開 ③ 連跑 3 次只有 1 張 open 告警（去重） ④ `remaining_reported` 低於 `remaining_local` 時以較小值判定 ⑤ 餘量 0 → `track_exhausted` 且通知含「已無法開立」 ⑥ 補了新字軌後 open 告警自動 resolved |
| `spec/services/platform/einvoice/cert_watch_job_spec.rb` | 到期前 61 天不叫、60 天叫、30／14／7 天各升級一次且不重複 |
| `spec/services/platform/einvoice/issue_spec.rb` | ① 取號為原子操作：20 執行緒併發開立 → 號碼連續無重複（唯一索引兜底） ② 字軌用盡 → `TRACK_EXHAUSTED` 且不建 `einvoices` 列 ③ **provider 呼叫不在 transaction 內**（用 `ActiveRecord::Base.connection` 的 `transaction_open?` 斷言，或 WebMock hook 檢查） ④ 永久失敗 → `number_burned` 且餘量已扣（對帳可見） ⑤ 相同 `idempotencyKey` 重放不重複取號 |
| `spec/services/platform/einvoice/refund_router_spec.rb` | ① 退款金額 == 發票金額 → 走作廢 ② 小於 → 走折讓 ③ 大於（超額退款）→ 走作廢 ④ 已作廢發票再退款 → `INVOICE_VOIDED` ⑤ 金額比較全程 integer cents（傳入 float 即 raise） |
| `spec/services/platform/einvoice/reconcile_job_spec.rb` | 加值中心日報回填 `remaining_reported`；本地與回報差異 >10 → 產差異清單並告警 |

**3C 個資**

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/pdpa/incident_spec.rb` | ① 宣告即算 `authority_notify_due_at = detected_at + 72.hours` ② `detected_at` 為未來 → `DETECTED_AT_IN_FUTURE` ③ `detected_at` 距今 >72h → 要求填延遲發現原因 ④ 已通報再通報 → `ALREADY_NOTIFIED` |
| `spec/jobs/platform/pdpa/incident_clock_job_spec.rb` | T-24／T-12／T-6／T-2 各告警一次；逾 72h 未通報 → 全域告警＋通知 `platform_owner`＋寫審計 `outcome: alert` |
| `spec/jobs/platform/pdpa/audit_due_job_spec.rb` | 距上次 10／11／12 個月三級告警（33 §2.13「每 12 個月至少一次」） |
| `spec/models/tenant_policy_acceptance_spec.rb` | 新版守則發布後，舊版簽署不算數；簽署率分母＝應簽署租戶數 |

**3D 巡檢器**

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/compliance/fetcher_spec.rb` | ① 同 host 併發被限為 1 且間隔 ≥1s ② 304 回應沿用上次 finding ③ `content_digest` 相同但 `rule_bundle_digest` 變了 → 重跑規則 ④ 3 次重試後標 `unreachable` ⑤ 自訂網域 robots disallow → `skipped_by_robots`＋開工單 ⑥ 回應 >2MB 截斷並標 `inconclusive` |
| `spec/services/platform/compliance/matchers_spec.rb` | ① 全形統編「１２３４５６７８」正規化後命中 ② 統編格式對但與 `shops.tax_id` 不符 → fail（不是「有八碼就過」） ③ 商品有 `excluded_from_cooling_off` 但前台無告知 → fail（33 §2.14 七款例外） ④ `applies_when` 不成立 → `skipped` 且不計入分母 |
| `spec/services/platform/compliance/scan_shop_job_spec.rb` | ① fail 且 `auto_ticket` → 開工單一次；隔日仍 fail 不重複開單（只更新 `last_seen_at`） ② 有效 suppression → 該規則 `skipped` ③ suppression 到期 → 恢復判定並重新開單 |
| `spec/requests/admin/compliance_dispute_spec.rb` | 商家提誤判申訴 → `finding.state='disputed'`、工單暫停催辦、`appeals` 產生 kind=`compliance_scan` |
| `spec/services/platform/compliance/summary_spec.rb` | 達成率分母排除 `draft`／`closed`／`deleted` 與 `skipped`；四項比例與 `platformComplianceFindings` count 一致（數字同源） |

---

### 10. 驗收清單

**3A DSR**
1. GDPR 1 個月／CCPA 45 天計時器正確，**且以曆月而非 30 天推算法定期限**；雙時鐘兩欄並列顯示。
2. GDPR 延期須在 1 個月內告知：逾期申請被擋，`extension_notified_at` 有值且 ≤ `received_at + 1 個月`。
3. **erasure 與 legal hold 衝突時 hold 優先**（33 §5-9）：全域／subject／order_range 三種 scope 各有測試，且 hold 期間**回覆義務時鐘不停**。
4. 逾期升級五級告警各發一次；逾期案自動開 P1 工單並寫審計。
5. controller／processor 分工落地：平台直收的買家請求 24 小時內轉交商家並留痕。
6. `access`／`portability` 產出包可下載且連結 24h 失效；包內無其他資料主體的 PII（抽測）。
7. Shopify redact 三 topic 的延遲規則（6 個月／10 天／48 小時）與 HMAC 驗簽各有測試。

**3B 電子發票**
8. 字軌餘量 <15% 主動告警且**同一店同類型不重複開單**；餘量 0 時商家後台出現紅色橫幅。
9. 工商憑證到期前 60 天告警（33 §2.14），30／14／7 天升級。
10. 開立時機三選一可設定，預設 `on_fulfillment`（33 §2.14 建議值）。
11. 全額取消自動作廢、部分退貨自動折讓，金額判定全程 integer cents。
12. **取號為原子操作**：併發測試 20 執行緒無重號、無跳號（跳號僅允許 `number_burned` 且對帳表可解釋）。
13. **provider 呼叫不在 transaction 內**（靜態＋執行期雙重斷言，11 §2）。
14. 電子發票元件納入對外狀態頁（原型 `SP`）。

**3C 個資**
15. 外洩宣告即啟動 72 小時倒數（33 §2.13），四級告警＋逾期全域告警。
16. 年度稽核距上次 >12 個月時卡片轉 critical；`pdpa_audits.next_due_on` 自動推算。
17. 軌跡保存 5 年設定生效——**與模組四的 12 個月保留期不衝突**（見 §12 規格衝突，必須以 `retention_class` 解）。
18. 租戶守則簽署率分子分母正確（原型 1,204 / 1,284）；新版發布後未簽戶被正確識別。

**3D 巡檢器**
19. 六項檢查全部實作（原型 `shopcompliance`）並在租戶詳情逐項顯示通過／不通過＋證據。
20. 每日 06:00 自動掃描，起跑抖動生效，全平台重掃 ≤20 分鐘（原型 toast 承諾）。
21. 單一 host 併發 ≤1、間隔 ≥1s；conditional GET 生效（第二日抓取的 304 比例 >70%）。
22. 連續失敗才開工單，單次網路抖動不開單。
23. 誤判申訴路徑完整：dispute → 申訴看板 → FALSE_POSITIVE → suppression（**必有到期日**）→ 自動開規則改進 issue。
24. 規則以版本化 YAML 管理，改規則走 PR；UI 不可改規則本體。
25. 達成率分母＝應受檢店數，與逐店 findings 同源（CLAUDE.md §7 數字同源）。

---

### 11. 前端（React/TS）

**元件樹**

```
<CompliancePage>                                  // 路由 /compliance
  ├─ <TwoCol>
  │    ├─ <DsrCard>                               // data-doc=dsr
  │    │    └─ <IndexTable cols={5} rows={dsr}/>  // 剩餘 ≤7 天 → color:var(--critical)
  │    └─ <PdpaCard>                              // data-doc=pdpa
  │         ├─ <BreachBanner countdown={72h}/>    // 有事件時 note note-crit
  │         └─ <UsageRow×4/>
  └─ <TwoCol>
       ├─ <EinvoicePipelineCard/>                 // data-doc=einvoice
       └─ <FrontScanCard/>                        // data-doc=frontscan，四條 meter
<ShopDetail>
  └─ <ComplianceTab>
       ├─ <ComplianceChecklist items={6}/>        // data-doc=shopcompliance
       └─ <InvoiceCard/>                          // data-doc=shopinvoice（dl 五列）
<DsrDrawer>  <PdpaIncidentModal>  <FindingEvidenceModal>
```

**狀態管理**
- 四張卡片各一支 query，但 `platformComplianceSummary` 與 `platformComplianceFindings` 共用 `['compliance', shopId]` key 以保證數字同源。
- **倒數類 UI（DSR 剩餘天數、PDPA 72 小時）在前端每 30 秒重算**（純函式，輸入 ISO8601 的 `dueAt`），不靠伺服器輪詢；伺服器只在 `refetchInterval: 300_000`（5 分鐘）刷新狀態。
- 「全平台重掃」按 `useMutation` → 回 `{scanId, estimatedSeconds}` → 切換為進度輪詢 `platformComplianceScan(scanId)`，`refetchInterval: 5_000`，完成後停止並 `invalidateQueries(['compliance'])`。

**GraphQL**

```graphql
query PlatformComplianceOverview {
  platformDsrRequests(first: 20, state: [RECEIVED, VERIFIED, IN_PROGRESS, AWAITING_MERCHANT, BLOCKED_BY_HOLD]) {
    nodes { id code kind regime state statutoryDueAt operationalDueAt daysRemaining
            escalationLevel holdBlocked shop { id name } }
    pageInfo { hasNextPage endCursor }
  }
  platformPdpaOverview {
    activeIncidents { id code detectedAt hoursToAuthorityDeadline }
    lastDrill { heldOn result }
    lastAudit { completedAt nextDueOn }
    traceRetentionYears
    policyAcceptance { signed total }
    activeLegalHolds
  }
  platformEinvoicePipeline {
    tracksBelowThreshold certsExpiring60d
    issuedToday voidedToday allowancesToday failedPendingRetry
  }
  platformComplianceSummary { ruleKey label passed applicable ratio delta }
}
```

**三態**
- **Loading**：四張卡片各自骨架（表格 3 列／meter 灰條），不阻塞其他卡片（四支 query 獨立 suspense boundary）。
- **Empty**：DSR 無在辦件 → 「目前沒有待處理的資料主體請求」；PDPA 無事件 → 保留原型的 `note note-ok`「目前無進行中的外洩事件」（**這是有意義的正向狀態，不可當空狀態隱藏**）；巡檢無資料 → 「尚未執行首次掃描」＋「立即掃描」鈕。
- **Error**：卡片內 `note note-crit`＋重試；電子發票卡片額外顯示「加值中心連線狀態」連結到狀態頁（外部依賴故障時要能一眼分辨是我們壞還是綠界壞）。

**響應式**
- **≤1279**：`two-col` 維持雙欄；DSR 表 `min-width:max-content` 橫捲；巡檢 meter 標籤縮短。
- **≤1023**：`.two-col{grid-template-columns:1fr}` 四張卡片直排；`usage-row` 轉 `110px 1fr 140px`；`dl` 轉 `100px 1fr`（`shopinvoice` 卡片受影響）。
- **≤767**：`html{font-size:14px}`；DSR 表加 `card-table` 轉堆疊卡片（每個 `<td>` 必須有 `data-label`：請求／商店／類型／剩餘／狀態）；DSR 抽屜與外洩宣告 modal 轉貼底 sheet；72 小時倒數字級提升到 20px 並置頂 sticky。
- **≤429**：`usage-row{grid-template-columns:1fr}` 標籤與數值上下排；`dl{grid-template-columns:1fr}`（`shopinvoice` 五列轉標籤在上、值在下）；巡檢四條 meter 的 `u-num` 靠左。
- **pointer:coarse**：`mini-list li{min-height:48px}`（`shopcompliance` 六項清單）；「重新掃描」`btn-sm` 命中區 ≥44px。
- **prefers-reduced-motion**：倒數數字不做 tick 動畫；進度條改為直接跳值。

---

## 審計日誌（波次 W1）

### 1. 這是什麼、給誰用、解決什麼問題（含法源）

**是什麼**：平台域**唯一**的寫入軌跡真相源。每一個平台人員（或自動化）對租戶做過的事，都留下一列含 before/after JSON 的不可竄改紀錄，可篩選、可 diff、可匯出、可即時串流到外部 SIEM。

**給誰用**：全部平台角色可讀（原型 `RM`「檢視全部」五角色皆 ✓）；匯出限 `owner`／`admin`（32 §5、原型 `RM`「審計匯出 ✓ ✓ — — —」）；租戶自己也能看到與自己有關的部分（33 §7.4 差異化：「誰在什麼時候代登入、做了什麼」）。

**解決什麼問題**：
1. **出事沒有真相**——「誰把這家店凍結的？」在沒有審計時只能翻 Slack。
2. **審計本身被竄改**——多數系統把審計寫在應用可讀寫的表裡，管理員刪一列沒人知道。本手冊的核心工作就是讓這件事在**DB 帳號層面不可能發生**。
3. **保留期沒人管**——PCI 要 12 個月、台灣個資辦法要 5 年（見 §12 規格衝突），沒有分層就只能全部存最久，成本與查詢效能都撐不住。

**制度出處**：

| 面向 | 出處 | 內容 |
|---|---|---|
| 欄位集 | 33 §2.8（Vercel schema） | `timestamp｜action（如 tenant.freeze）｜actor_id｜actor_name｜actor_email｜ip｜user_agent｜request_id｜previous(JSON)｜next(JSON)` |
| 關聯維度 | 33 §2.8（Okta System Log） | `outcome.result`、`transaction_id`（同一操作多事件串接）、`session_id`、`target_type/target_id`、`source（UI/API/自動化）` |
| 保留期 | 33 §2.8 | **PCI DSS 10.5.1：至少 12 個月，最近 3 個月須可立即查詢**（同時滿足 SOC 2） |
| 不可竄改 | 33 §2.8、32 §7 | **append-only，DB 層不授權 update/delete** |
| 台灣軌跡 | 33 §2.13 | 蒐集處理利用紀錄與自動化機器軌跡**保存至少 5 年** |
| 覆蓋率 | 32 §9-4 | 每個平台寫入動作在 `platform_audit_logs` 有對應列（抽測 100%） |
| 匯出與串流 | 原型 `v-audit` 頁首 | 「匯出（簽名連結 24h 失效）」、「日誌串流至 S3／Datadog／Splunk」 |
| 篩選維度 | 原型 `auditfilter` | 人員／動作／**來源（UI／API／自動化）**／關鍵字（對象、request_id） |

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| 頁首副標 | 「append-only・保留 12 個月（近 3 個月即時查詢，PCI 10.5.1）」 | 文案即承諾，數值來自 `config/audit.yml`，不硬編碼 | 查詢區間跨入冷儲區時，副標下方追加提示條「查詢區間包含冷儲資料，將以背景作業處理」 |
| 「匯出」 | CSV 匯出 | >50 筆轉背景 job＋簽名連結 **24h 失效**（32 §3-2、原型 toast）。匯出動作**本身寫一列審計**（`audit.export`） | 匯出上限單次 100 萬列；超過要求縮小區間。`support`／`ops`／`read_only` 看不到此鈕（`RM`） |
| 「日誌串流」 | 設定 S3／Datadog／Splunk sink | 至少一次投遞＋游標；每批 500 列；HMAC 簽章 header；連續失敗 20 次自動停用並告警 | 已設定 sink 時按鈕顯示 sink 數量；`platform_owner` 才可新增／刪除 sink |
| `auditfilter`（篩選列） | 人員／動作／來源／關鍵字 | 三個 select＋一個搜尋框（原型）。來源三態 `UI／API／自動化`（33 §2.8）。搜尋支援 `對象` 與 `request_id`（原型 placeholder）。**白名單欄位編譯 SQL**（11 §1 防注入） | 時間區間預設「近 7 天」；切到 >3 個月自動提示冷儲；篩選條件可存為 saved view（P1） |
| `audittable`（審計表） | 時間／人員／動作／對象／來源／結果／IP／diff | 八欄對照原型 `AUDIT`。`action` 用 `<code>` 呈現（`tenant.freeze`／`dispute.threshold_crossed`／`tenant.access_grant`／`limits.override`／`flag.rollout_approve`／`tenant.unfreeze`）。`outcome` 為 `success` 顯示 `badge success`＋實圈 pip，其他（`alert`／`blocked`／`denied`／`failure`）顯示 `badge warning`＋半圈 | **整表唯讀，無任何編輯入口**；cursor 分頁 ≤250（28 §0.3）；排序固定 `(created_at DESC, id DESC)`（11 §8 坑 6 需 tiebreaker） |
| 列點擊 → `ovDiff` | 展開 previous/next JSON 對照 | 左右雙欄 `PREVIOUS` / `NEXT`（原型 `.diff`）；`dfMeta` 顯示 時間／人員／對象／來源／結果／IP／`request_id`。modal 底部固定說明欄位集與保留期（原型已寫死此段文案） | JSON >64KB 時只渲染前 200 行＋「下載完整 JSON」；敏感欄位（密碼、token、卡號、`hash_key`）在**寫入時**即已過濾，不是顯示時才遮（11 §5 `filter_parameters`） |
| 整合性徽章（新增） | 顯示該區間的封緘驗證結果 | `platformAuditIntegrity(from,to)` 回 `verified / broken / pending`；broken 時整頁頂端紅色橫幅並自動通知 `platform_owner` | 冷儲區間需先還原才能驗證，顯示「驗證中」 |
| `shopaudit`（租戶詳情） | 這家店被平台做過什麼 | 全域審計 `WHERE shop_id = ?`（32 §3-3）；append-only；**租戶端亦可見**（33 §7.4） | 租戶可見版本需過濾平台內部欄位（`session_id`、內部 staff email 只顯示姓名與角色） |
| `audittail`（總覽） | 最近 4 筆 | 與審計頁**同源**（原型 `renderAll` 取 `AUDIT.slice(0,4)`） | 空時顯示「尚無操作紀錄」 |

---

### 3. 資料模型

**平台域表白名單（本模組全部）**：`platform_audit_logs`、`platform_audit_seals`、`platform_audit_archives`、`platform_audit_exports`、`platform_audit_sinks`。理由：審計是跨租戶的平台級設施；`platform_audit_logs.shop_id` 為**可空的關聯欄位**（用於 `shopaudit` 篩選），不是租戶隔離鍵——平台自身動作（新增人員、發布 flag）沒有 shop。全部查詢在 `Platform::` 命名空間顯式 `ActsAsTenant.without_tenant`（32 §0）。

```sql
-- db/structure.sql（本模組強制 config.active_record.schema_format = :sql，理由見 §6-2）
-- 對應 33 §2.8 欄位集（Vercel 10 欄 + Okta 關聯維度）與 32 §7
CREATE TABLE chilllove_audit.platform_audit_logs (
  id              BIGINT       NOT NULL AUTO_INCREMENT,
  created_at      DATETIME(6)  NOT NULL,          -- 33 §2.8 timestamp
  action          VARCHAR(64)  NOT NULL,          -- tenant.freeze / dsr.erasure_blocked_by_hold ...
  actor_type      VARCHAR(24)  NOT NULL,          -- platform_staff / system / api_key / break_glass
  actor_id        BIGINT       NULL,              -- 33 §2.8 actor_id
  actor_name      VARCHAR(120) NULL,              -- 快照，人員改名後歷史仍正確
  actor_email     VARCHAR(255) NULL,              -- 快照
  ip              VARBINARY(16) NULL,             -- INET6_ATON，同時容 v4/v6
  user_agent      VARCHAR(512) NULL,
  request_id      VARCHAR(64)  NULL,
  transaction_id  VARCHAR(64)  NULL,              -- Okta：同一操作多事件串接
  session_id      VARCHAR(64)  NULL,              -- Okta
  source          VARCHAR(16)  NOT NULL,          -- UI / API / 自動化（原型 auditfilter 三態）
  outcome         VARCHAR(16)  NOT NULL,          -- success / failure / denied / alert / blocked
  target_type     VARCHAR(48)  NULL,              -- Okta
  target_id       BIGINT       NULL,
  target_label    VARCHAR(160) NULL,              -- 顯示用快照（原型「對象」欄顯示店名）
  shop_id         BIGINT       NULL,              -- 關聯欄，非租戶隔離鍵（見上）
  reason          VARCHAR(255) NULL,
  note            TEXT         NULL,
  previous        JSON         NULL,              -- 33 §2.8
  `next`          JSON         NULL,              -- 33 §2.8（next 為 MySQL 保留字，需反引號）
  impersonated    TINYINT(1)   NOT NULL DEFAULT 0,-- 32 §4-3 代登入雙寫
  retention_class VARCHAR(16)  NOT NULL DEFAULT 'pci_12m',  -- pci_12m / pdpa_5y（見 §12 衝突解法）
  row_digest      CHAR(64)     NOT NULL,          -- SHA256(canonical_json(本列))，寫入時算，永不變
  PRIMARY KEY (id, created_at),                   -- 分割鍵必須進 PK（MySQL 分割限制）
  KEY idx_created         (created_at, id),
  KEY idx_actor           (actor_id, created_at),
  KEY idx_action          (action, created_at),
  KEY idx_shop            (shop_id, created_at),
  KEY idx_target          (target_type, target_id, created_at),
  KEY idx_request         (request_id),
  KEY idx_transaction     (transaction_id),
  KEY idx_retention       (retention_class, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
PARTITION BY RANGE COLUMNS(created_at) (
  PARTITION p2026_06 VALUES LESS THAN ('2026-07-01'),
  PARTITION p2026_07 VALUES LESS THAN ('2026-08-01'),
  PARTITION p2026_08 VALUES LESS THAN ('2026-09-01'),
  PARTITION pmax     VALUES LESS THAN (MAXVALUE)
);
```

> **刻意違反 11 §2「每個外鍵都建 DB 級 FK 約束」的兩處，須在 migration 檔頭註明**：
> ① **無 FK**：MySQL 8 的分割表不支援外鍵；且審計必須在被引用物件刪除後仍存在（32 §2「刪除後審計永久保留（去識別化 shop 名）」），FK 會反而阻擋刪除。以 `target_label`／`actor_name` 快照替代。
> ② **無 `updated_at`**：append-only 表沒有「更新」概念，留著會誤導。

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `platform_audit_seals` | `id`, `sealed_at`, `kind`(interval / daily), `range_start_id`, `range_end_id`, `row_count`, `payload_digest`, `prev_seal_digest`, `seal_digest`, `external_ref` | **雜湊鏈只存在這裡**（見 §6-3 為什麼）。`external_ref` 為寫入 WORM 物件儲存後的 key |
| `platform_audit_archives` | `period`(YYYY-MM), `retention_class`, `object_key`, `row_count`, `min_id`, `max_id`, `bytes`, `sha256`, `sealed_at`, `retain_until`, `purged_at` | 冷儲清單。`retain_until` 對映物件儲存的 Object Lock 到期日 |
| `platform_audit_exports` | `requested_by`, `filter JSON`, `format`, `state`, `row_count`, `object_key`, `url_expires_at`, `created_at` | 匯出任務。**每次匯出本身也寫一列 `platform_audit_logs`（`action: audit.export`）** |
| `platform_audit_sinks` | `kind`(s3 / datadog / splunk / webhook), `endpoint`, `secret_ref`, `filter JSON`, `format`(jsonl / cef), `state`, `cursor_id`, `last_delivered_at`, `consecutive_failures` | 串流設定 |

---

### 4. API 契約（Platform:: GraphQL）

GID：`gid://chilllove/PlatformAuditLog/{id}`（32 §6 已定義）。

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformAuditLogs` | query | `actorId, action, source, outcome, targetType, targetId, shopId, requestId, transactionId, from, to, query, first≤250, after` | `PlatformAuditLogConnection`（含 `tier: HOT\|COLD`） | — | 全部（`read_only` 含） |
| `platformAuditLog` | query | `id!` | `PlatformAuditLog`（previous／next JSON） | `NOT_FOUND` `ARCHIVE_UNAVAILABLE` | 全部 |
| `platformAuditIntegrity` | query | `from!, to!` | `{ status, checkedSeals, firstBrokenSealId, checkedRows }` | `RANGE_TOO_LARGE` | `admin`＋ |
| `platformAuditExport` | mutation | `filter!, format!(CSV\|JSONL), idempotencyKey!` | `{ exportId, state, signedUrl, expiresAt, userErrors }` | `FORBIDDEN` `ROW_LIMIT_EXCEEDED` `RANGE_TOO_LARGE` | `owner`／`admin`（32 §5） |
| `platformAuditArchiveSearch` | mutation | `filter!, idempotencyKey!` | `{ jobId, periods[], estimatedSeconds, userErrors }` | `ARCHIVE_UNAVAILABLE` `RANGE_TOO_LARGE` | `owner`／`admin` |
| `platformAuditSinkCreate` | mutation | `input{ kind!, endpoint!, secretRef!, filter, format!, idempotencyKey! }` | `{ sink, userErrors }` | `FORBIDDEN` `ENDPOINT_UNREACHABLE` | `platform_owner` |
| `platformAuditSinkSetState` | mutation | `id!, state!(ENABLED\|DISABLED), idempotencyKey!` | `{ sink, userErrors }` | `NOT_FOUND` | `platform_owner` |

**沒有的操作（刻意）**：**不存在** `platformAuditLogUpdate`／`platformAuditLogDelete`／任何形式的 `*Set`。Schema 層就沒有這些欄位入口——這是四層防護的第一層（§6-1）。

**商家端**（`/admin/api/`，33 §7.4 差異化）：`shopPlatformActivity(first, after)` — 回傳 `shop_id = 當前店` 且 `action` 在白名單內的列（代登入、凍結、限制、上限覆寫、合規處置），欄位裁剪為 `occurredAt / action / actorRoleLabel / reason / previous / next`，**不含**平台人員 email、`session_id`、`ip`。

---

### 5. 服務物件與背景任務

| 類別／Job | 排程 | 職責 |
|---|---|---|
| `Platform::Audit` （模組門面） | — | `Platform::Audit.record!(action:, actor:, ...)`——**全平台唯一寫入口**（§6-4） |
| `Platform::Audit::Context` | — | 從 `Current`（request_id／session_id／ip／ua／source／transaction_id）補齊欄位 |
| `Platform::Audit::Digest` | — | canonical JSON（鍵排序、UTC ISO8601、null 省略）→ SHA256 |
| `Platform::Audit::SealJob` | 每 5 分鐘＋每日 00:05 | 產 `platform_audit_seals`（interval／daily）；daily seal 額外寫入 WORM 物件儲存 |
| `Platform::Audit::VerifyJob` | 每日 01:00 | 全量重算近 3 個月封緘；不符 → 全域告警＋鎖定匯出（防止用匯出掩蓋） |
| `Platform::Audit::PartitionMaintainJob` | 每月 25 日 | 預建下下個月分割（用 `REORGANIZE PARTITION pmax`）——**不預建會在月初 00:00 全部寫入落到 pmax，效能斷崖** |
| `Platform::Audit::ArchiveJob` | 每月 1 日 03:00 | 把 4 個月前的分割匯出成 gz-JSONL → 物件儲存（Object Lock）→ 寫 `platform_audit_archives` → **驗證 sha256 與 row_count 相符後**才 `ALTER TABLE ... DROP PARTITION` |
| `Platform::Audit::PurgeJob` | 每日 04:00 | `retain_until` 已過且 Object Lock 到期的封存物件 → 刪除 → 記 `purged_at`＋寫一列審計（`action: audit.purge`，元審計） |
| `Platform::Audit::ExportJob` | 事件觸發 | 串流產生 CSV／JSONL → 物件儲存 → 簽名連結 24h |
| `Platform::Audit::ArchiveSearchJob` | 事件觸發 | 下載相關 period 物件 → 過濾 → 產結果檔＋簽名連結 |
| `Platform::Audit::StreamJob(sink_id)` | 每 30 秒 | 由 `cursor_id` 往前讀 500 列 → 投遞 → 推進游標；失敗指數退避，連續 20 次停用＋告警 |

---

### 6. 關鍵流程與演算法

#### 6-1 append-only 的四層防護（硬要求 1）

> **設計原則**：「model 層禁 update/destroy」只擋得住誠實的代碼。真正要擋的是 `rails console` 裡的 `ActiveRecord::Base.connection.execute("DELETE ...")`，以及被入侵的應用程式行程。因此四層都要有，且第 2 層（DB 授權）是**唯一無法被應用程式繞過**的一層。

**第 1 層：GraphQL schema 無入口**——不存在 update/delete mutation（§4）。

**第 2 層：DB 帳號不授權（核心）**

審計表放**獨立 schema** `chilllove_audit`。**為什麼一定要分 schema**：MySQL 的權限是分層累加的，`REVOKE UPDATE ON db.tbl` 在只有 `GRANT ... ON db.*` 的情況下會直接失敗（`ERROR 1147 (42000): There is no such grant defined`）——同 schema 內做不到「其他表全權、審計表只讀寫」的乾淨授權。分 schema 之後只要兩行 GRANT 就能表達完整意圖，且新表加入不會意外繼承審計表的權限。MySQL 支援跨 schema JOIN 與跨 schema FK，Rails 只需 `self.table_name = "chilllove_audit.platform_audit_logs"`。

```sql
-- ============================================================
-- db/grants/audit_append_only.sql
-- 對應 docs/design/33-platform-admin-benchmark.md §2.8
-- 「append-only，DB 層不授權 update/delete」
-- 部署方式：由 DBA/IaC 執行，**不由 Rails migration 執行**（migration 帳號不得能改自己的權限）
-- ============================================================

CREATE DATABASE IF NOT EXISTS chilllove_audit
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- 1) 應用執行帳號：業務庫全權，審計庫【只有 SELECT 與 INSERT】
--    注意：沒有 UPDATE、沒有 DELETE、沒有 DROP（TRUNCATE 需要 DROP，因此也被擋）、
--    沒有 ALTER（無法拆掉 trigger）、沒有 TRIGGER（無法新建繞過用的 trigger）。
CREATE USER IF NOT EXISTS 'cl_app'@'10.%' IDENTIFIED BY '${CL_APP_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON chilllove.*        TO 'cl_app'@'10.%';
GRANT SELECT, INSERT                 ON chilllove_audit.*  TO 'cl_app'@'10.%';

-- 2) Migration 帳號：只在部署時的一次性容器使用，執行期不存在於任何長駐行程的環境變數中
--    有 DDL 權限但【沒有 DELETE、沒有 UPDATE】——它能建表、能加索引、能改分割，
--    但改不了任何一列既有審計資料。這是本設計最關鍵的一條。
CREATE USER IF NOT EXISTS 'cl_migrate'@'10.%' IDENTIFIED BY '${CL_MIGRATE_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
                                     ON chilllove.*        TO 'cl_migrate'@'10.%';
GRANT SELECT, INSERT, CREATE, ALTER, INDEX, TRIGGER
                                     ON chilllove_audit.*  TO 'cl_migrate'@'10.%';

-- 3) 保留期維護帳號：唯一擁有 DROP 的帳號，用於 ALTER TABLE ... DROP PARTITION
--    （MySQL 8 的 DROP PARTITION 需要 ALTER + DROP）。
--    憑證只存在排程維護容器的 secret，不在 app、不在 CI。
CREATE USER IF NOT EXISTS 'cl_archiver'@'10.%' IDENTIFIED BY '${CL_ARCHIVER_PASSWORD}';
GRANT SELECT, ALTER, DROP            ON chilllove_audit.platform_audit_logs TO 'cl_archiver'@'10.%';
GRANT SELECT, INSERT, UPDATE         ON chilllove_audit.platform_audit_archives TO 'cl_archiver'@'10.%';

-- 4) 唯讀分析帳號（BI／稽核員直連）
CREATE USER IF NOT EXISTS 'cl_readonly'@'10.%' IDENTIFIED BY '${CL_READONLY_PASSWORD}';
GRANT SELECT ON chilllove.* TO 'cl_readonly'@'10.%';
GRANT SELECT ON chilllove_audit.* TO 'cl_readonly'@'10.%';

FLUSH PRIVILEGES;
```

**第 3 層：DB trigger（防呆，擋住有 UPDATE 權限的帳號誤操作）**

```sql
DELIMITER $$
CREATE TRIGGER trg_pal_no_update BEFORE UPDATE ON chilllove_audit.platform_audit_logs
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
    'platform_audit_logs is append-only (33 §2.8)';
END$$
CREATE TRIGGER trg_pal_no_delete BEFORE DELETE ON chilllove_audit.platform_audit_logs
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
    'platform_audit_logs is append-only (33 §2.8); use partition drop for retention';
END$$
DELIMITER ;
-- 為什麼 trigger 不會擋到保留期清理：ALTER TABLE ... DROP PARTITION 是 DDL，
-- 不會觸發 row-level trigger。TRUNCATE 同樣不觸發 trigger，但它需要 DROP 權限，
-- 而 cl_app 沒有 DROP —— 兩條路都被封死。
```

**第 4 層：Model 層**

```ruby
# app/models/platform_audit_log.rb
# 平台審計日誌。append-only：本 model 永遠唯讀，寫入只能經 Platform::Audit.record!。
# 規格出處：33 §2.8「append-only，DB 層不授權 update/delete」、32 §7。
class PlatformAuditLog < ApplicationRecord
  self.table_name = "chilllove_audit.platform_audit_logs"

  # 為什麼是「持久化後唯讀」而不是全程唯讀：全程唯讀連 create! 都會被擋。
  # new_record? 期間允許寫，落地後永久唯讀。
  def readonly? = persisted?

  # 為什麼還要覆寫 destroy：readonly? 只擋 save，不擋 destroy。
  def destroy  = raise ActiveRecord::ReadOnlyRecord, "platform_audit_logs is append-only"
  def destroy! = destroy
  def delete   = destroy

  # 為什麼要擋類別方法：delete_all / update_all 走的是 relation，不經 instance callback。
  def self.delete_all(*)  = raise ActiveRecord::ReadOnlyRecord, "append-only"
  def self.update_all(*)  = raise ActiveRecord::ReadOnlyRecord, "append-only"
  def self.destroy_all(*) = raise ActiveRecord::ReadOnlyRecord, "append-only"
end
```

**遷移策略（migration 帳號怎麼分離）**

Rails 沒有內建「migration 用另一個 DB 帳號」的設定。做法是**部署期換 `DATABASE_URL`**，而不是在 `database.yml` 裡放兩組連線（放兩組會讓執行期行程也持有 DDL 憑證，等於白做）：

```yaml
# config/deploy.yml（Kamal）
# 為什麼在 pre-deploy hook 而非 app 容器內跑 migration：
# app 容器只拿得到 cl_app 憑證，跑不了 DDL；DDL 憑證只在這個一次性容器的生命週期內存在。
env:
  secret: [DATABASE_URL]          # → cl_app
servers:
  job: { cmd: bin/jobs }
```
```bash
# .kamal/hooks/pre-deploy
docker run --rm \
  -e DATABASE_URL="$MIGRATION_DATABASE_URL" \
  -e RAILS_MASTER_KEY="$RAILS_MASTER_KEY" \
  "$KAMAL_IMAGE" bin/rails db:migrate
```
```ruby
# config/initializers/audit_guard.rb
# 執行期自我檢查：如果 app 行程拿到了有 DDL 權限的帳號，直接拒絕啟動。
# 為什麼要這條：憑證配錯是必然會發生的事，靜默配錯等於整套 append-only 保證失效，
# 而且沒有任何徵兆。開機就炸比上線半年後才發現好。
Rails.application.config.after_initialize do
  next if Rails.env.test?
  grants = ActiveRecord::Base.connection.select_values("SHOW GRANTS FOR CURRENT_USER()")
  audit_grants = grants.grep(/chilllove_audit/i)
  forbidden = audit_grants.grep(/\b(UPDATE|DELETE|DROP|ALTER|ALL PRIVILEGES)\b/)
  raise "審計庫授權過寬，拒絕啟動：#{forbidden.inspect}（33 §2.8）" if forbidden.any?
end
```

**保留期用分割而非 DELETE**：12 個月保留期的清理若用 `DELETE FROM ... WHERE created_at < ?`，就必須給某個帳號 DELETE 權限，整套設計立刻破功。改用 `ALTER TABLE ... DROP PARTITION p2025_08`——這是 DDL、不觸發 trigger、不需要 DELETE 權限、而且是 O(1) 的檔案刪除（DELETE 一億列會鎖表數十分鐘）。

#### 6-2 冷熱分層（12 個月保留、近 3 個月即時查詢）

```
┌── 熱層（MySQL，即時查詢，PCI 10.5.1「最近 3 個月須可立即查詢」）────────────┐
│  chilllove_audit.platform_audit_logs                                        │
│  RANGE COLUMNS(created_at) 月分割 × 4（當月 + 前 3 月）+ pmax               │
│  全索引；GraphQL 直接查；p95 目標 < 300ms（11 §4 後台預算）                 │
└─────────────────────────────────────────────────────────────────────────────┘
        │ 每月 1 日 03:00 ArchiveJob（第 4 個月的分割）
        ▼
┌── 冷層（物件儲存，還原式查詢，滿足 PCI「至少 12 個月保留」）────────────────┐
│  s3://cl-audit/{retention_class}/{YYYY-MM}/part-{n}.jsonl.gz                │
│  Object Lock = COMPLIANCE mode，retain_until:                               │
│     pci_12m → created + 12 個月（33 §2.8）                                  │
│     pdpa_5y → created + 5 年（33 §2.13 軌跡保存至少 5 年）                  │
│  清單與雜湊記在 platform_audit_archives；每日封緘另寫一份到同 bucket        │
└─────────────────────────────────────────────────────────────────────────────┘
        │ PurgeJob（retain_until 過期且 Object Lock 解除後）
        ▼
      刪除，並寫一列 `audit.purge` 的元審計（誰都不能無聲刪掉歷史）
```

**轉冷的安全順序（順序錯了會遺失資料）**：
1. `SELECT` 整個分割 → 串流寫 gz-JSONL 到物件儲存（分片 100MB）。
2. 讀回物件，重算 `sha256` 與 `row_count`，與來源比對。
3. 設定 Object Lock `retain_until`（**Lock 設完才算落地**——沒有 Lock 的物件仍可被刪）。
4. 寫 `platform_audit_archives`（含 `min_id`／`max_id`，供查詢路由）。
5. **以上四步全部成功**才執行 `ALTER TABLE ... DROP PARTITION`。
6. 任一步失敗 → 保留分割、告警、不重試自動刪除（人工介入）。

**查詢路由**：`platformAuditLogs` 依 `from/to` 與 `platform_audit_archives.min_id/max_id` 決定 tier。跨層查詢的回應會標 `tier: COLD` 並在 `userErrors` 之外回一個 `notice`：「本區間含冷儲資料，請用 `platformAuditArchiveSearch` 取得完整結果」。**不做**「自動即時解冷」——那會讓一個誤點的查詢拉下 40GB。冷儲查詢目標 ≤30 分鐘（【建議值】，33 未載）。

**`retention_class` 的判定**（見 §12 規格衝突）：寫入時由 `action` 的註冊表決定。凡是「涉及個人資料之蒐集、處理、利用或存取」的動作（代登入、DSR 執行、客戶資料匯出、KYC 文件檢視、審計匯出本身）一律 `pdpa_5y`；其餘 `pci_12m`。註冊表放 `config/audit_actions.yml`，缺漏時**預設 `pdpa_5y`**（保守側錯，多存不違法，少存違法）。

#### 6-3 封緘雜湊鏈（偵測「連 DB 都被繞過」的竄改）

```ruby
# app/services/platform/audit/seal_job.rb
module Platform
  module Audit
    # 封緘。
    #
    # 為什麼雜湊鏈放在 seals 表而不是每列的 prev_digest 欄位：
    # 「每列存前一列的 digest」需要在 INSERT 時讀取前一列 → 所有審計寫入被序列化在同一個鎖上，
    # 而審計寫入是跟著業務 transaction 走的，等於把全平台寫入串成一條線。更糟的是，
    # 若改成事後回填 prev_digest，那就需要 UPDATE ——直接違反 append-only。
    #
    # 解法：每列只存「自己內容的 digest」（寫入時算完即固定，永不需要改），
    # 鏈存在獨立的 seals 表：每 5 分鐘封一個 id 區間，seal 之間互相串鏈。
    # 竄改任何一列 → 該區間 payload_digest 對不上；刪掉整個區間 → 鏈斷；
    # 偽造整條鏈 → 需同時改掉已寫入 WORM 物件儲存的每日封緘。
    class SealJob < ApplicationJob
      queue_as :default

      def perform(kind: "interval")
        last = PlatformAuditSeal.order(:id).last
        from_id = (last&.range_end_id || 0) + 1
        rows = PlatformAuditLog.where(id: from_id..).order(:id).limit(50_000)
        return if rows.empty?

        digests = rows.pluck(:row_digest)          # 已在寫入時算好，這裡不重算內容
        payload = Digest::SHA256.hexdigest(digests.join("\n"))
        seal_digest = Digest::SHA256.hexdigest([last&.seal_digest, payload, rows.last.id].join("|"))

        seal = PlatformAuditSeal.create!(
          sealed_at: Time.current, kind:,
          range_start_id: rows.first.id, range_end_id: rows.last.id,
          row_count: rows.size, payload_digest: payload,
          prev_seal_digest: last&.seal_digest, seal_digest:
        )
        # 每日封緘額外寫進 WORM（Object Lock），讓「連 DB 主機都被拿下」的情境仍可偵測
        Platform::Audit::WormWriter.put!(seal) if kind == "daily"
        seal
      end
    end
  end
end
```

驗證（`platformAuditIntegrity`）：對區間內每個 seal 重算 `payload_digest` 與 `seal_digest`，並檢查 `prev_seal_digest` 是否等於前一 seal 的 `seal_digest`。任一不符 → `status: BROKEN` ＋ 全域告警 ＋ **暫時鎖定匯出功能**（避免有人用「匯出一份乾淨的」來掩蓋）。

#### 6-4 唯一寫入口與 100% 覆蓋率保證

```ruby
# app/services/platform/audit.rb
module Platform
  # 平台審計唯一寫入口。
  # 32 §9-4 驗收：「每個平台寫入動作在 platform_audit_logs 有對應列（抽測 100%）」。
  module Audit
    module_function

    # @param action [String] 動作代碼，須存在於 config/audit_actions.yml（未註冊即 raise，
    #   這是覆蓋率的正向保證：新增動作時忘了註冊，測試就會紅）
    # @param actor [PlatformStaff, nil] nil 代表系統／自動化
    # @param previous [Hash] 變更前狀態（33 §2.8）
    # @param next_state [Hash] 變更後狀態
    # @return [PlatformAuditLog]
    def record!(action:, actor: nil, shop_id: nil, target_type: nil, target_id: nil,
                target_label: nil, previous: nil, next_state: nil, reason: nil, note: nil,
                source: nil, outcome: "success")
      meta = ActionRegistry.fetch!(action)     # 未註冊 → KeyError
      ctx  = Context.current                   # request_id / session_id / ip / ua / transaction_id / source

      attrs = {
        created_at: Time.current, action:,
        actor_type: actor ? "platform_staff" : "system",
        actor_id: actor&.id, actor_name: actor&.name, actor_email: actor&.email,
        ip: ctx.ip_binary, user_agent: ctx.user_agent, request_id: ctx.request_id,
        transaction_id: ctx.transaction_id, session_id: ctx.session_id,
        source: source || ctx.source, outcome:,
        target_type:, target_id:, target_label:, shop_id:, reason:, note:,
        previous: filter(previous), next: filter(next_state),
        impersonated: ctx.impersonated?,        # 32 §4-3
        retention_class: meta.fetch("retention_class", "pdpa_5y")   # 缺漏時保守側錯
      }
      attrs[:row_digest] = Digest.canonical_sha256(attrs)
      PlatformAuditLog.create!(attrs)
    end

    # 敏感欄位在【寫入時】就過濾掉，不是顯示時才遮。
    # 為什麼：一旦寫進 append-only 表就再也刪不掉——寫錯了只能整批封存作廢。
    # 沿用 Rails filter_parameters 清單（11 §5）並額外加上平台專屬鍵。
    EXTRA_FILTERED = %w[hash_key hash_iv otp_secret recovery_codes access_code break_glass].freeze
    def filter(hash) = ParameterFilter.new(hash).call
  end
end
```

**覆蓋率的雙向保證**：
- **正向**：`action` 必須在 `config/audit_actions.yml` 註冊，否則 `record!` 直接 raise。
- **反向（CI 靜態掃描）**：掃 `app/services/platform/**/*.rb` 中所有 public 的寫入型 service（類名結尾 `Apply`／`Create`／`Update`／`Delete`／`Execute`／`Decide` 或有 `call` 且內含 `save!|create!|update!|destroy!`），斷言其原始碼中出現 `Platform::Audit.record!`；白名單放 `config/audit_exempt.yml` 且每一條需附理由。

**`transaction_id` 串接**：一個平台操作可能產生多列（凍結 → 六旗標各一列 → 停 webhook → 停 feed）。`Platform::Audit::Context` 在 controller 進入點產生一個 `transaction_id`（ULID），該 request 內所有 `record!` 共用（33 §2.8 Okta「同一操作多事件串接」）。UI 的 diff modal 顯示「本次操作共 n 個事件」並可展開。

---

### 7. 需要的工具、gem 與外部依賴

- **MySQL 8**：原生 RANGE COLUMNS 分割、`SIGNAL SQLSTATE`、`INET6_ATON`、JSON 型別。**注意 8.0.29+ 已移除非 InnoDB 的通用分割處理器**，本表為 InnoDB 無影響。
- **`schema_format = :sql`**：分割、trigger、跨 schema 表名 `schema.rb` 表達不了，必須用 `db/structure.sql`。**這是全專案設定，需在 PR 說明並同步告知其他模組負責人**。
- **`strong_migrations`**（11 §2）：分割維護 DDL 需加 `safety_assured` 並註明理由。
- **物件儲存**：S3 相容且**支援 Object Lock（COMPLIANCE mode）**——這是不可協商的需求，Lock 是「連我們自己也刪不掉」的唯一技術保證。自架 MinIO 亦支援。**選型待定，需使用者確認**（33 未指定）。
- **gem**：`aws-sdk-s3`（或相容 client）；壓縮用 Ruby 內建 `Zlib::GzipWriter`；**不引入專用審計 gem**（`paper_trail`／`audited` 都預設可 UPDATE／DELETE，與本設計相衝）。
- **外部 SIEM（可選）**：Datadog Logs／Splunk HEC／S3。串流是 sink 模式，平台不依賴其可用性。
- **CI**：新增一個以 `cl_app` 身分連線的 job，跑 `spec/database/audit_grants_spec.rb`（見 §9）。**這個測試在 CI 用真 MySQL container 跑，不能用 SQLite 或 mock**。

---

### 8. 實作步驟（順序化 todo）

1. 全專案切 `config.active_record.schema_format = :sql`；`db/structure.sql` 進版控。
2. `db/grants/audit_append_only.sql` 寫入 repo；本機／CI／staging／production 四環境的 provisioning 腳本都要跑。
3. 建 `chilllove_audit` schema 與 `platform_audit_logs`（含分割與 8 個索引）；`PlatformAuditLog` model 四層防護第 4 層。
4. 兩個 trigger（第 3 層）；`config/initializers/audit_guard.rb`（開機自檢）。
5. Kamal pre-deploy hook 換 `MIGRATION_DATABASE_URL`；移除 app 容器中的 DDL 憑證。
6. `config/audit_actions.yml`（含 `retention_class`）＋`ActionRegistry`；`Platform::Audit.record!` 門面＋`Context`＋`Digest`＋`ParameterFilter`。
7. CI 靜態掃描（反向覆蓋率）＋`audit_exempt.yml`。
8. `platform_audit_seals`＋`SealJob`＋`VerifyJob`＋WORM writer。
9. `PartitionMaintainJob`（**先做這支再上線**，否則第一個月底就會全落 pmax）。
10. `platform_audit_archives`＋`ArchiveJob`（五步安全順序）＋`PurgeJob`（含元審計）。
11. GraphQL 7 支＋商家端 `shopPlatformActivity`（欄位裁剪）。
12. `platform_audit_exports`＋`ExportJob`（簽名連結 24h）；`platform_audit_sinks`＋`StreamJob`。
13. React：篩選列、審計表、diff modal、整合性徽章、冷儲提示。
14. `docs/dev/m8-platform-audit.md`。

---

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| **`spec/database/audit_grants_spec.rb`**（**核心，必須以真 MySQL 跑**） | ① 以 `cl_app` 身分 `UPDATE chilllove_audit.platform_audit_logs SET action='x' WHERE id=1` → 拋 `Mysql2::Error` 且 errno **1142（TABLEACCESS_DENIED）** ② `DELETE` 同樣 1142 ③ `TRUNCATE TABLE` → 1142 ④ `DROP TABLE` → 1142 ⑤ `ALTER TABLE ... DROP TRIGGER` → 1142 ⑥ `INSERT` 成功 ⑦ `SELECT` 成功 ⑧ 以 `cl_migrate` 身分 `UPDATE` → 1142（migration 帳號也不能改資料） ⑨ `SHOW GRANTS FOR 'cl_app'@'%'` 不含審計庫的 UPDATE/DELETE/DROP/ALTER |
| `spec/database/audit_triggers_spec.rb` | 以有 UPDATE 權限的測試帳號（模擬誤設）執行 UPDATE → 拋 SQLSTATE 45000 且訊息含 `append-only`；DELETE 同樣 |
| `spec/models/platform_audit_log_spec.rb` | ① 落地後 `readonly?` 為 true，`update!` 拋 `ReadOnlyRecord` ② `destroy` 拋 ③ `PlatformAuditLog.delete_all` 拋 ④ `update_all` 拋 ⑤ `create!` 成功且 `row_digest` 已填 |
| `spec/services/platform/audit_spec.rb` | ① 未註冊的 action → `KeyError` ② 密碼／token／`hash_key`／`otp_secret` 出現在 previous/next 時**不落庫** ③ 同一 request 內多次 `record!` 共用 `transaction_id` ④ 代登入情境 `impersonated=true`（32 §4-3） ⑤ `retention_class` 依註冊表判定，未指定時為 `pdpa_5y` ⑥ 系統來源 `actor_id` 為 nil 且 `actor_type='system'` |
| `spec/services/platform/audit/seal_job_spec.rb` | ① 封緘鏈連續（`prev_seal_digest` 串得起來） ② 竄改任一列的 `row_digest`（直接以 DBA 帳號改）→ `platformAuditIntegrity` 回 BROKEN 並指出第一個斷點 ③ 刪除整個區間 → 鏈斷可偵測 ④ 每日封緘有 `external_ref`（已寫 WORM） |
| `spec/jobs/platform/audit/archive_job_spec.rb` | ① 五步順序：Lock 未設成功時**不 drop 分割** ② sha256 或 row_count 不符 → 中止＋告警＋分割保留 ③ 成功後熱層查不到、`platform_audit_archives` 有列 ④ `pdpa_5y` 的 `retain_until` 為 5 年、`pci_12m` 為 12 個月 |
| `spec/jobs/platform/audit/purge_job_spec.rb` | ① `retain_until` 未到 → 不刪 ② 刪除後寫入一列 `audit.purge` 元審計 |
| `spec/jobs/platform/audit/partition_maintain_job_spec.rb` | 預建下下月分割；重複執行冪等（分割已存在不報錯） |
| `spec/requests/platform/audit_graphql_spec.rb` | ① schema 中**不存在** `platformAuditLogUpdate`／`platformAuditLogDelete`（introspection 斷言） ② `read_only` 匯出 → 200＋`FORBIDDEN`（32 §5） ③ 查詢跨 3 個月前 → 回 `tier: COLD` 與提示 ④ 匯出動作本身在審計表產生一列 ⑤ 排序有 tiebreaker，同秒多列分頁不重複不遺漏（11 §8 坑 6） |
| `spec/requests/admin/shop_platform_activity_spec.rb` | 租戶只看得到自己的列；回傳不含平台人員 email／`session_id`／`ip`（33 §7.4） |
| `spec/services/platform/audit/coverage_spec.rb` | 靜態掃描：所有平台寫入型 service 皆呼叫 `Platform::Audit.record!`；豁免清單每條有理由 |
| `spec/jobs/platform/audit/stream_job_spec.rb` | ① 游標推進正確、重啟不重送已確認批次 ② 連續 20 次失敗自動停用＋告警 ③ HMAC header 正確 |

---

### 10. 驗收清單

1. **以 `cl_app` 帳號對審計表執行 UPDATE／DELETE／TRUNCATE／DROP 全部回 MySQL errno 1142**——這條是本模組的核心驗收，CI 必跑真 MySQL（33 §2.8）。
2. `cl_migrate` 亦無 UPDATE／DELETE 權限；app 容器環境變數中不存在 DDL 憑證；開機自檢會在授權過寬時拒絕啟動。
3. GraphQL schema introspection 中不存在任何審計更新／刪除操作。
4. 欄位集完整覆蓋 33 §2.8：Vercel 10 欄 ＋ Okta 五個關聯維度（`outcome`／`transaction_id`／`session_id`／`target_type,target_id`／`source`），逐欄比對。
5. 保留 12 個月、近 3 個月即時查詢（PCI DSS 10.5.1）；熱層 p95 < 300ms（11 §4）；冷層有還原路徑且有 SLA 顯示。
6. 保留期清理用 `DROP PARTITION`，**全系統無任何一處對審計表下 DELETE**（`grep -rn "platform_audit_logs" | grep -i delete` 為空）。
7. 冷儲物件設有 Object Lock COMPLIANCE mode，`retain_until` 依 `retention_class` 分 12 個月／5 年（解 §12 衝突）。
8. 封緘鏈可驗證；竄改／刪除可被 `platformAuditIntegrity` 偵測；BROKEN 時匯出被鎖定。
9. 每個平台寫入動作皆有審計列（32 §9-4 抽測 100%）；CI 靜態掃描通過。
10. 同一操作的多列以 `transaction_id` 串接，diff modal 可展開。
11. 敏感欄位在寫入時已過濾（抽查 previous/next 內無 token／密碼／`hash_key`）。
12. 匯出 >50 筆轉 job＋簽名連結 24h 失效；匯出動作本身留痕。
13. 串流 sink 至少一次投遞、游標可恢復、失敗自動停用。
14. 租戶可見版本欄位裁剪正確（33 §7.4），無平台內部識別資訊外洩。
15. UI 對照原型 `auditfilter`／`audittable`／`ovDiff` 逐控件打勾。

---

### 11. 前端（React/TS）

**元件樹**

```
<AuditPage>                                   // 路由 /audit
  ├─ <PageHead sub="append-only・保留 12 個月（近 3 個月即時查詢，PCI 10.5.1）">
  │    ├─ <Button variant="ghost" onClick={exportCsv}>匯出</Button>      // owner/admin only
  │    └─ <Button variant="sec" onClick={openSinks}>日誌串流</Button>
  ├─ <IntegrityBadge status={verified|broken|pending}/>
  ├─ <Card>
  │    ├─ <FilterBar>                          // data-doc=auditfilter
  │    │    ├─ <Select name="actor"/> <Select name="action"/> <Select name="source"/>
  │    │    ├─ <DateRangePicker default="7d"/>
  │    │    └─ <SearchInput placeholder="搜尋對象／request_id"/>
  │    ├─ <ColdTierNotice show={rangeCrossesArchive}/>
  │    └─ <AuditTable/>                        // data-doc=audittable，8 欄，整列可點
  ├─ <DiffModal/>                              // #ovDiff：dl meta + PREVIOUS/NEXT 雙欄 pre
  └─ <SinksDrawer/>
```

**狀態管理**
- `useInfiniteQuery(['audit', filters], ...)`，`getNextPageParam: last => last.pageInfo.endCursor`；游標分頁不用 offset（11 §8 坑 6）。
- 篩選變更 debounce 300ms（跨租戶查詢成本高，與本地表格過濾不同——32 §3-2 的「本地即時過濾」不適用於此頁）。
- 匯出：mutation → 若回 `state: PROCESSING` 則進 polling（`refetchInterval: 3_000`，最多 5 分鐘），完成後直接觸發下載並顯示「連結 24 小時後失效」toast。
- `IntegrityBadge` 用 `staleTime: 300_000` 的獨立 query；`broken` 時**不可被 dismiss**（強制可見）。

**GraphQL**

```graphql
query PlatformAuditLogs($actorId:ID, $action:String, $source:AuditSource,
                        $from:DateTime, $to:DateTime, $query:String,
                        $first:Int!, $after:String){
  platformAuditLogs(actorId:$actorId, action:$action, source:$source,
                    from:$from, to:$to, query:$query, first:$first, after:$after){
    tier
    nodes {
      id createdAt action outcome source ip requestId transactionId
      actor { id name email }
      target { type id label }
      shop { id name }
      previous next            # JSON scalar（28 §0.3）
    }
    pageInfo { hasNextPage endCursor }
  }
}
```

**三態**
- **Loading**：表格骨架 10 列；篩選列保持可互動（不整頁 blocking）。
- **Empty**：有篩選 → 「沒有符合條件的紀錄」＋「清除篩選」；區間落在冷儲 → 「本區間資料已封存」＋「發起冷儲查詢」主鈕（**不是空狀態，是不同的動作**）。
- **Error**：`RANGE_TOO_LARGE` → 提示縮小區間並提供「改為近 30 天」快捷；其他錯誤 → `note note-crit`＋重試；`ARCHIVE_UNAVAILABLE` → 顯示物件儲存狀態連結。

**響應式**
- **≤1279**：`.idx{min-width:max-content}` 八欄橫捲（八欄在 1279 以下必然放不下，橫捲優於截字）；`.tscroll` 容器顯示左右漸層提示。
- **≤1023**：篩選列 wrap 成兩行，搜尋框 `margin-left:auto` 失效改為佔滿次行；diff modal 由 `wide` 降為全寬。
- **≤767**：`html{font-size:14px}`；審計表加 `card-table` 轉堆疊卡片，`data-label` 為 時間／人員／動作／對象／來源／結果／IP；**第一格（時間）為卡片標題不顯示 label**；diff modal 轉貼底 sheet 且 `.modal .diff{grid-template-columns:1fr}` PREVIOUS/NEXT 上下排（原型已有此規則）；篩選 select `font-size:16px`／`height:40px` 防 iOS 放大。
- **≤429**：`page-actions{width:100%}` 且兩個按鈕 `flex:1`；`dl{grid-template-columns:1fr}` diff meta 轉單欄；JSON `pre` 加 `overflow-x:auto` 與 `font-size:11px`。
- **pointer:coarse**：列高提升（`.idx td` padding 由 `8px 12px` 增至 `12px 12px`）；「diff」`btn-xs` 命中區偽元素 ≥44px。
- **prefers-reduced-motion**：modal 進場動畫關閉（原型全域規則已覆蓋）。

---

## 人員與權限（波次 W1，複核 campaign 為 W5）

### 1. 這是什麼、給誰用、解決什麼問題（含法源）

**是什麼**：平台自身的身分治理——五角色矩陣、兩層權限不繼承、零常設權限（ZSP）＋JIT 提權、break-glass、2FA 強制、定期複核 campaign。

**給誰用**：`platform_owner`（唯一可管人員與角色，32 §5、原型 `RM`）；其餘角色只能讀自己與同僚的權限狀態、發起 JIT 提權請求。

**解決什麼問題**：
1. **平台後台是全租戶資料的單點**——一個被盜的 `admin` 帳號可以看光 1,284 家店的訂單。常設高權限就是這個風險的來源。
2. **緊急時無人可救**——SSO 掛掉、owner 休假時沒有 break-glass，事故會從 30 分鐘變成 6 小時。
3. **權限只增不減**——沒有定期複核，三年後每個人都是 admin。

**制度出處**：

| 面向 | 出處 | 內容 |
|---|---|---|
| 五角色矩陣 | 32 §5、原型 `RM` | `owner／admin／support／ops／read_only` × 9 動作 |
| 兩層不繼承 | 33 §2.15（Shopify Plus）、原型 `rolematrix` | 組織層與商店層**完全獨立、互不繼承**；一人可掛多角色、**權限累加**；User group 批次綁定；四頁（Users／Roles／Groups／Activity logs）**皆可 CSV 匯出** |
| 組織層權限僅 5 項 | 33 §2.15 | Stores／Business entities（**四級：View／View sensitive／Edit／Add**）／Billing（兩級）／Analytics overview／Feature test drives |
| 三軸補充 | 33 §2.15（SFCC） | 模組權限／功能動作權限／語系權限，可 scope 到單站 |
| 資源詞彙表共用 | 33 §2.15（VTEX） | **role = resource 集合，且人與程式（API key）共用同一套 resource 詞彙表** |
| 2FA 自助重設 | 33 §2.15 | **驗證網域擁有權後，可自助重設該網域使用者的 2FA** |
| 2FA 強制 | 32 §0 | 平台後台 2FA 強制，**72h 寬限後鎖定** |
| JIT／ZSP | 原型 `jit`、`staffchip` | 零常設權限；高危動作須臨時提權＋**四眼核准**＋過期自動撤銷；staff chip 顯示剩餘時間（原型：「剩 42 分」） |
| break-glass | 原型 `jit` | **非 SSO、密碼分持、使用即全域告警**；「近 90 天未動用」 |
| 定期複核 | 33 §1 模組矩陣（W5「權限定期複核 campaign」）、原型 `v-staff` 按鈕 | 季度複核，**未回覆預設 revoke** |
| 邀請與角色變更 | 32 §3-4 | 邀請 24h 有效；角色變更僅 owner；bot 帳號 API token 可輪換 |
| 危險動作四眼 | 原型 `RM` 第 9 列 | 金流通道變更 `✓＋四眼` |

> **待定，需使用者確認**：①JIT 提權的**最長 TTL** 與各權限類別的預設 TTL——原型只顯示「剩 42 分」（推得 ≤60 分鐘，與 32 §4 代登入 60 分鐘一致），最長值 33 未載。②break-glass 使用後的**強制事後檢討時限**。③複核 campaign 的**回覆期限**（未回覆預設 revoke 的觸發點）。④SSO／IdP 選型與是否強制（33 §2.15 提到 break-glass「非 SSO」，隱含有 SSO，但未指定）。

**兩層權限在「我們」的語境是什麼**（重要的解讀，實作前必須共識）：33 §2.15 的兩層是**商家組織層 ↔ 商家商店層**。原型把「組織層與商店層不繼承」寫在**平台角色矩陣**卡片上，因此本手冊採用的落地解讀是：

- **第一層＝平台層（Platform layer）**：`platform_staffs` 的五角色，管的是「平台這個系統」的操作權（凍結、flag、審計匯出、人員管理）。
- **第二層＝租戶層（Shop layer）**：進入某一家店的資料與後台的權限。
- **不繼承的硬規則**：**平台層的任何角色（含 `platform_owner`）都不自動獲得任何一家店的租戶層權限**。要進店只有兩條路：①`access_grants` 授權式代登入（W1，需商家 4 位數授權碼核准，33 §2.9）；②`Platform::` 命名空間內的**聚合查詢**，且聚合結果**不得包含個別買家 PII**。
- 這條規則同時解釋了為什麼審計要記 `impersonated`（32 §4-3）：跨層行為必須可辨識。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| 頁首「5 位・2FA 強制（72h 寬限後鎖定）」 | 人數與政策提示 | 人數＝`platform_staffs` 未停用數；72h 出自 32 §0 | 有人 2FA 未啟用且寬限剩 <24h → 頁首轉紅並列出姓名 |
| 「開複核」（page-actions） | 開啟權限複核 campaign | 原型 toast：「季度權限複核 campaign——未回覆預設 revoke」。W5 波次 | 已有進行中的 campaign → 按鈕 disabled 並顯示「進行中（剩 n 天）」 |
| 「邀請人員」 | 邀請新平台人員 | 邀請信 **24h 有效**（32 §3-4、原型 toast）；重寄即舊 token 作廢（12 §F3） | 僅 `platform_owner` 可見；email 網域白名單（`@chilllove.tw`）外需二次確認 |
| `jit`（JIT 提權卡） | 顯示進行中的提權 | 原型一列：`陳柏睿 → 危險區操作權・核准人：林昀真・事由：工單 #5102 關店作業・剩 42 分・[撤銷]`。**核准人必須≠申請人**（四眼）；**事由必須綁工單編號**（比對原型 `accessrequest`「代登入必須綁工單編號」，`tickettable` 亦載此規則） | 無進行中提權 → 顯示「目前沒有臨時提權」；剩餘 ≤5 分鐘 badge 轉 critical；到期自動消失（前端每 30 秒重算，不等後端） |
| `jit` 內 break-glass 註記 | `note note-ai` 顯示 break-glass 狀態 | 原型：「break-glass 帳號 1 個（非 SSO、密碼分持、使用即全域告警）——近 90 天未動用」 | **使用中**時整條轉 `note note-crit` 並閃爍一次（reduced-motion 下不閃）；同時觸發頂列全域橫幅 |
| `stafftable`（人員表） | 姓名／Email／角色／2FA／最後活躍 | 五欄對照原型 `STAFF`：`platform_owner／admin／support／ops／read_only`；`read_only` 的 bot 帳號 2FA 欄顯示 `API token`（不是「已啟用」）。`platform_owner` 列**無編輯鈕**（原型：不可自我降權） | 2FA `待啟用` 顯示 `badge attention`＋空圈 pip；超過 72h 寬限 → 帳號鎖定，該列整列灰化並顯示「已鎖定」 |
| `stafftable`「匯出」 | CSV | 原型 toast：「Users／Roles／Groups／Activity 四頁皆可匯出」（33 §2.15） | 匯出動作寫審計；含 email 屬 PII，匯出需 `platform_owner` |
| 人員列「編輯」 | 改角色／群組／停用 | **角色變更僅 owner**（32 §5、原型 toast）；不可修改自己的角色（防自我提權）；停用非刪除（12 §F3 坑：`deactivated_at`） | 唯一的 `platform_owner` 不可停用也不可降權（`LAST_OWNER_PROTECTED`） |
| 人員詳情「重設 2FA」 | 支援動作 | **需 owner 覆核（四眼）**（32 §3-3）；或提供已驗證的網域擁有權證明（33 §2.15） | 重設後強制下次登入重新綁定；舊 recovery codes 全部作廢 |
| `rolematrix`（角色矩陣） | 五角色 × 九動作 | 九列對照原型 `RM`：檢視全部／凍結解凍關店／排程刪除／上限覆寫 flags／請求存取（代登入）／webhook 重試佇列／人員管理角色／審計匯出／**金流通道變更（✓＋四眼）**。副標「組織層與商店層不繼承；一人多角色權限累加」 | 矩陣為**唯讀展示且由代碼生成**——不是手工表格，來源是 `Platform::Authz::MATRIX`，改代碼即改畫面（防止畫面與實作不一致） |
| 角色詳情（P1） | 展開該角色的 resource 清單 | 33 §2.15 VTEX：role＝resource 集合，人與 API key 共用同一詞彙表 | API key 綁定同一組 resource key，畫面共用元件 |

---

### 3. 資料模型

**平台域表白名單（本模組全部，無 `shop_id`）**：`platform_staffs`（32 §7 已明列為豁免）、`platform_permissions`、`platform_roles`、`platform_role_permissions`、`platform_role_assignments`、`platform_user_groups`、`platform_user_group_members`、`platform_user_group_roles`、`platform_api_keys`、`jit_elevations`、`break_glass_accounts`、`break_glass_activations`、`access_review_campaigns`、`access_review_items`。理由：這些表描述的是平台自身員工與程式帳號，與任何租戶無關；硬加 `shop_id` 會產生無意義的 null 欄與錯誤的索引前綴。

```ruby
# db/migrate/20260901000070_create_platform_authz.rb
# 對應 32 §7「platform_staffs（無 shop_id，平台域表，豁免多租戶鐵律，集中列管）」
#      33 §2.15（兩層權限／多角色累加／User group／VTEX 資源詞彙表）

create_table :platform_staffs do |t|
  t.string   :email,  null: false, index: { unique: true }
  t.string   :name,   null: false
  t.string   :kind,   null: false, default: "human"   # human / bot（原型 report-bot）
  t.string   :password_digest
  t.string   :otp_secret_ref                          # credentials key 名，不存明文（11 §1）
  t.datetime :otp_enabled_at
  t.datetime :otp_grace_until                         # = 建立時間 + 72h（32 §0）
  t.datetime :locked_at
  t.string   :lock_reason
  t.datetime :last_active_at
  t.datetime :deactivated_at
  t.timestamps
end

create_table :platform_permissions, id: false do |t|   # VTEX 模型：人與 API key 共用詞彙表
  t.string  :key,     null: false, primary_key: true   # tenant.freeze / audit.export / payment_channel.update ...
  t.string  :label,   null: false
  t.string  :grade,   null: false                      # read / write / danger
  t.boolean :jit_required,        null: false, default: false
  t.boolean :dual_control,        null: false, default: false   # 四眼（原型 RM 第 9 列）
  t.integer :default_ttl_minutes                       # JIT 預設 TTL（【待定】各類別數值）
end

create_table :jit_elevations do |t|
  t.references :staff, null: false, foreign_key: { to_table: :platform_staffs }
  t.string   :permission_key, null: false
  t.bigint   :scope_shop_id                            # 可空；限縮到單一租戶時填
  t.text     :reason,     null: false
  t.string   :ticket_ref, null: false                  # 必綁工單（原型 jit「事由：工單 #5102」）
  t.datetime :requested_at, null: false
  t.bigint   :approver_staff_id                        # 四眼：必須 != staff_id
  t.datetime :approved_at
  t.datetime :expires_at
  t.datetime :revoked_at
  t.bigint   :revoked_by_staff_id
  t.datetime :first_used_at
  t.integer  :use_count, null: false, default: 0
  t.timestamps
end
add_index :jit_elevations, [:staff_id, :permission_key, :expires_at], name: "idx_jit_active"
```

| 表 | 關鍵欄位 | 說明 |
|---|---|---|
| `platform_roles` | `key`(platform_owner / admin / support / ops / read_only), `label`, `builtin`, `layer`(platform / shop) | `layer` 是「不繼承」的實作基礎：平台層角色不可被指派為租戶層 |
| `platform_role_permissions` | `role_key`, `permission_key` | 矩陣的真相源；`Platform::Authz::MATRIX` 由此生成，UI 亦由此生成 |
| `platform_role_assignments` | `staff_id`, `role_key`, `layer`, `granted_by`, `granted_at`, `expires_at` | **一人多角色，權限累加**（33 §2.15）。`expires_at` 支援臨時角色 |
| `platform_user_groups` / `_members` / `_roles` | `key`, `label` ／ `group_id, staff_id` ／ `group_id, role_key` | User group 批次綁定（33 §2.15） |
| `platform_api_keys` | `label`, `token_digest`, `prefix`(`clat_`, 28 §0.2), `role_key`, `permission_keys JSON`, `last_used_at`, `rotated_at`, `expires_at`, `revoked_at` | bot 帳號 token 可輪換（32 §3-4）；**與人共用 `platform_permissions` 詞彙表**（33 §2.15 VTEX） |
| `break_glass_accounts` | `label`, `custodian_a_staff_id`, `custodian_b_staff_id`, `credential_ref_a`, `credential_ref_b`, `sealed_at`, `last_activated_at`, `state` | 密碼分持：兩半分別由兩位保管人持有，單獨無用 |
| `break_glass_activations` | `account_id`, `activated_at`, `reason`, `incident_ref`, `custodian_a_confirmed_at`, `custodian_b_confirmed_at`, `deactivated_at`, `review_due_at`, `reviewed_at`, `review_ref` | 使用即全域告警（原型 `jit`） |
| `access_review_campaigns` | `key`, `period`, `scope`(all_staff / role / group), `opened_at`, `due_at`, `state`, `default_action`(revoke), `opened_by` | 未回覆預設 revoke（原型 toast） |
| `access_review_items` | `campaign_id`, `subject_type`(role_assignment / group_membership / api_key / standing_permission), `subject_id`, `staff_id`, `reviewer_staff_id`, `decision`(keep / revoke / modify / no_response), `decided_at`, `note` | 到期未決 → `no_response` 並執行 `default_action` |

---

### 4. API 契約（Platform:: GraphQL）

GID：`gid://chilllove/PlatformStaff/{id}`（32 §6 已定義）、`gid://chilllove/JitElevation/{id}`。

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformStaffs` | query | `role, active, twoFactorState, first, after` | `PlatformStaffConnection` | — | 全部 |
| `platformRoleMatrix` | query | `—` | `[{ permissionKey, label, grade, dualControl, roles{ roleKey, allowed } }]` | — | 全部 |
| `platformJitElevations` | query | `activeOnly, staffId, first, after` | `JitElevationConnection`（含 `remainingSeconds`） | — | 全部 |
| `platformAccessReviewCampaigns` | query | `state, first, after` | `AccessReviewCampaignConnection` | — | 全部 |
| `platformStaffInvite` | mutation | `email!, role!, groupKeys[], idempotencyKey!` | `{ staff, inviteExpiresAt, userErrors }` | `FORBIDDEN` `EMAIL_TAKEN` `DOMAIN_NOT_ALLOWED` | `platform_owner`（32 §5） |
| `platformStaffRoleSet` | mutation | `id!, roleKeys[]!, idempotencyKey!` | `{ staff, userErrors }` | `FORBIDDEN` `SELF_MODIFICATION_FORBIDDEN` `LAST_OWNER_PROTECTED` | `platform_owner` |
| `platformStaffDeactivate` | mutation | `id!, reason!, idempotencyKey!` | `{ staff, userErrors }` | `LAST_OWNER_PROTECTED` `SELF_MODIFICATION_FORBIDDEN` | `platform_owner` |
| `platformStaff2faReset` | mutation | `id!, approverStaffId!, evidence, idempotencyKey!` | `{ staff, userErrors }` | `DUAL_APPROVAL_REQUIRED` `SELF_APPROVAL_FORBIDDEN` | `platform_owner`＋覆核（32 §3-3） |
| `platformStaffGroupSet` | mutation | `id!, groupKeys[]!, idempotencyKey!` | `{ staff, userErrors }` | `FORBIDDEN` | `platform_owner` |
| `platformApiKeyCreate` / `Rotate` / `Revoke` | mutation | `label!, roleKey!, permissionKeys[], expiresAt` ／ `id!` ／ `id!, reason!` | `{ apiKey, plaintextToken（僅建立與輪換時回一次）, userErrors }` | `FORBIDDEN` `KEY_REVOKED` | `platform_owner` |
| `platformJitElevationRequest` | mutation | `permissionKey!, scopeShopId, reason!, ticketRef!, durationMinutes, idempotencyKey!` | `{ elevation, userErrors }` | `TICKET_REF_REQUIRED` `TTL_EXCEEDS_MAX` `ALREADY_ELEVATED` | 全部（含 `support`／`ops`） |
| `platformJitElevationApprove` | mutation | `id!, idempotencyKey!` | `{ elevation, expiresAt, userErrors }` | `SELF_APPROVAL_FORBIDDEN` `APPROVER_LACKS_PERMISSION` `REQUEST_EXPIRED` | 具該權限的 `admin`＋ |
| `platformJitElevationRevoke` | mutation | `id!, reason!, idempotencyKey!` | `{ elevation, userErrors }` | `ALREADY_REVOKED` | 申請人本人／`admin`＋ |
| `platformBreakGlassActivate` | mutation | `accountId!, reason!, incidentRef!, custodianConfirmations[]!, idempotencyKey!` | `{ activation, credentialHandoffRef, userErrors }` | `CUSTODIAN_CONFIRMATION_MISSING` `INCIDENT_REF_REQUIRED` | 任一 custodian（**需兩位皆確認**） |
| `platformBreakGlassDeactivate` | mutation | `id!, summary!, idempotencyKey!` | `{ activation, reviewDueAt, userErrors }` | `NOT_ACTIVE` | 任一 custodian |
| `platformAccessReviewCampaignOpen` | mutation | `scope!, dueAt!, defaultAction=REVOKE, idempotencyKey!` | `{ campaign, itemCount, userErrors }` | `CAMPAIGN_IN_PROGRESS` | `platform_owner` |
| `platformAccessReviewItemDecide` | mutation | `id!, decision!, note, idempotencyKey!` | `{ item, userErrors }` | `NOT_REVIEWER` `CAMPAIGN_CLOSED` | 指派的 reviewer |
| `platformStaffExport` | mutation | `page!(USERS\|ROLES\|GROUPS\|ACTIVITY), idempotencyKey!` | `{ exportId, signedUrl, userErrors }` | `FORBIDDEN` | `platform_owner`（33 §2.15 四頁皆可匯出） |

---

### 5. 服務物件與背景任務

| 類別／Job | 排程 | 職責 |
|---|---|---|
| `Platform::Authz` | — | **唯一授權判斷入口**：`allow?(actor, permission_key, scope: nil)`；合併角色累加＋群組＋JIT（§6-1） |
| `Platform::Authz::Matrix` | — | 由 `platform_role_permissions` 生成矩陣；供 GraphQL 與 UI 共用 |
| `Platform::Jit` | — | 提權申請／核准／撤銷／查詢有效提權 |
| `Platform::BreakGlass` | — | 啟用／停用／告警扇出 |
| `Platform::AccessReview` | — | campaign 生成 items、決議、到期執行 |
| `Platform::Jit::ExpiryJob` | 每分鐘 | 標記過期提權並發通知。**注意：授權判斷不依賴這支 job**（§6-2） |
| `Platform::Staff::TwoFactorGraceJob` | 每小時 | `otp_grace_until` 已過且未啟用 2FA → 鎖定帳號＋通知＋寫審計（32 §0） |
| `Platform::Staff::InviteExpiryJob` | 每小時 | 24h 未接受的邀請作廢（32 §3-4） |
| `Platform::AccessReview::DueJob` | 每日 | campaign 到期 → 未決項目執行 `default_action`（revoke）＋通知＋寫審計 |
| `Platform::ApiKey::RotationReminderJob` | 每週 | `expires_at` 前 30／7 天提醒（【建議值】，33 §9 明載「VTEX API key 到期與輪換政策官方頁未能載入」＝無可抄範本，數值待定） |
| `Platform::BreakGlass::ReviewDueJob` | 每日 | 使用後未完成事後檢討 → 每日提醒 `platform_owner` |

---

### 6. 關鍵流程與演算法

#### 6-1 授權判斷：多角色累加＋兩層不繼承＋JIT

```ruby
# app/services/platform/authz.rb
module Platform
  # 平台授權唯一入口。
  #
  # 三條規則（33 §2.15 與原型 rolematrix）：
  #   1) 一人可掛多角色，權限【累加】（union，不是取最小）
  #   2) 平台層與租戶層【不繼承】——平台角色再大也不自動有任何一家店的租戶層權限
  #   3) 標記 jit_required 的權限，即使角色矩陣給了，仍需一張有效的 JIT 提權（零常設權限）
  #
  # 為什麼授權要收在單一模組：12 §F3 要求 Pundit `verify_authorized` 全 controller 強制，
  # 但 Pundit policy 分散在各檔案時，「平台層不繼承租戶層」這條跨切面規則很容易被某個
  # policy 漏掉。收成一個 allow? 讓它只有一個地方可能寫錯，且可被單一測試矩陣覆蓋。
  module Authz
    module_function

    # @param actor [PlatformStaff, PlatformApiKey]
    # @param permission_key [String] 見 platform_permissions
    # @param scope [Hash, nil] 例 { shop_id: 42 }；租戶層資源必填
    def allow?(actor, permission_key, scope: nil)
      return false if actor.nil? || actor.locked_at.present? || actor.deactivated_at.present?

      perm = PlatformPermission.find(permission_key)   # 未註冊的 key → 直接炸，不預設放行

      # 規則 2：租戶層資源必須有 access_grant，平台角色不代表可進店。
      # 33 §2.9 授權式代登入：4 位數授權碼＋商家核准＋60 分鐘 TTL。
      if perm.layer == "shop"
        return false if scope&.dig(:shop_id).blank?
        return false unless Platform::AccessGrants.active?(actor, scope[:shop_id], permission_key)
      end

      # 規則 1：多角色 union（含 user group 帶來的角色）
      granted = effective_permission_keys(actor)
      return false unless granted.include?(permission_key)

      # 規則 3：ZSP——jit_required 的權限需要有效提權
      return true unless perm.jit_required
      Platform::Jit.active_elevation?(actor, permission_key, scope_shop_id: scope&.dig(:shop_id))
    end

    # 直接角色 ∪ 群組角色，且過濾掉已到期的指派。
    # 用 Solid Cache 快取 60 秒：授權判斷在每個 request 會被呼叫十幾次，
    # 但撤銷必須快——60 秒是「效能」與「撤銷延遲」的折衷；【建議值】，33 未載。
    # 注意：JIT 與 access_grant 的檢查【不快取】（撤銷必須立即生效）。
    def effective_permission_keys(actor)
      Rails.cache.fetch(["authz", actor.class.name, actor.id, actor.updated_at.to_i], expires_in: 60) do
        role_keys = actor.role_assignments.active.pluck(:role_key) |
                    actor.user_groups.joins(:group_roles).pluck("platform_user_group_roles.role_key")
        PlatformRolePermission.where(role_key: role_keys).pluck(:permission_key).to_set
      end
    end
  end
end
```

#### 6-2 JIT 提權：四眼、TTL、撤銷即時生效

```ruby
# app/services/platform/jit.rb
module Platform
  module Jit
    module_function

    # 申請提權。
    # 事由必須綁工單編號——原型 jit 顯示「事由：工單 #5102 關店作業」，
    # 且原型 accessrequest／tickettable 都載明「代登入必須綁工單編號」。
    # 沒有工單的提權在事後檢討時無法還原「為什麼需要」，等於沒有留痕。
    def request!(staff:, permission_key:, reason:, ticket_ref:, duration_minutes: nil, scope_shop_id: nil)
      perm = PlatformPermission.find(permission_key)
      return [:TICKET_REF_REQUIRED, nil] if ticket_ref.blank?
      ttl = duration_minutes || perm.default_ttl_minutes
      max = Limits.get("jit.max_ttl_minutes")            # 【待定】33 未載最長值；原型可推得 ≤60 分
      return [:TTL_EXCEEDS_MAX, max] if ttl > max
      return [:ALREADY_ELEVATED, nil] if active_elevation?(staff, permission_key, scope_shop_id:)

      e = JitElevation.create!(staff:, permission_key:, scope_shop_id:, reason:, ticket_ref:,
                               requested_at: Time.current, expires_at: nil)
      Platform::Audit.record!(action: "jit.request", actor: staff, target_type: "JitElevation",
        target_id: e.id, next_state: { permission_key:, ticket_ref:, ttl_minutes: ttl }, source: "UI")
      Platform::Alerting.notify_approvers(e, ttl)
      [nil, e]
    end

    # 核准（四眼）。
    # 為什麼核准人也必須「本身具備該權限」：否則一個 support 可以核准另一個 support 拿到
    # owner 級權限，四眼變成兩個人一起繞過矩陣。這是 dual control 最常見的實作漏洞。
    def approve!(elevation:, approver:, ttl_minutes:)
      return [:SELF_APPROVAL_FORBIDDEN, nil] if elevation.staff_id == approver.id
      unless Platform::Authz.effective_permission_keys(approver).include?(elevation.permission_key)
        return [:APPROVER_LACKS_PERMISSION, nil]
      end
      return [:REQUEST_EXPIRED, nil] if elevation.requested_at < 30.minutes.ago  # 【建議值】

      elevation.update!(approver_staff_id: approver.id, approved_at: Time.current,
                        expires_at: Time.current + ttl_minutes.minutes)
      Platform::Audit.record!(action: "jit.approve", actor: approver, target_type: "JitElevation",
        target_id: elevation.id, previous: { approved: false },
        next_state: { approved: true, expires_at: elevation.expires_at }, source: "UI")
      [nil, elevation]
    end

    # 是否有有效提權。
    # 為什麼判斷式自己算而不看某個 state 欄位：state 欄位需要 job 來更新，
    # 而 job 可能延遲、可能掛掉。「到期即失效」必須是查詢時的時間比較，
    # 不能依賴背景任務——ExpiryJob 只負責發通知與清畫面，不負責安全。
    def active_elevation?(actor, permission_key, scope_shop_id: nil)
      JitElevation.where(staff_id: actor.id, permission_key:)
                  .where(revoked_at: nil)
                  .where.not(approved_at: nil)
                  .where("expires_at > ?", Time.current)
                  .then { |s| scope_shop_id ? s.where(scope_shop_id: [scope_shop_id, nil]) : s }
                  .exists?
    end
  end
end
```

#### 6-3 break-glass：密碼分持與全域告警

```ruby
# app/services/platform/break_glass.rb
# break-glass 帳號（原型 jit：「非 SSO、密碼分持、使用即全域告警」）。
#
# 為什麼要「非 SSO」：break-glass 存在的理由之一就是 IdP 掛掉。若它也走 SSO，
# 在最需要它的那一刻它同樣進不去。因此它是本地密碼＋硬體 TOTP，且不受 SSO 政策管轄。
#
# 為什麼要「密碼分持」：單人持有＝單人就能繞過整套權限體系。密碼切成兩半，
# 由兩位保管人（通常是 platform_owner 與另一位主管）分別保管，啟用時兩人各自確認。
#
# 為什麼「使用即全域告警」而不是「使用需核准」：緊急時等核准就失去意義。
# 設計是「先用，但所有人立刻知道」——嚇阻力來自不可隱藏，不是來自審批。
def activate!(account:, reason:, incident_ref:, confirmations:)
  return [:INCIDENT_REF_REQUIRED, nil] if incident_ref.blank?
  confirmed = confirmations.map { _1[:custodian_staff_id] }.uniq
  unless confirmed.sort == [account.custodian_a_staff_id, account.custodian_b_staff_id].sort
    return [:CUSTODIAN_CONFIRMATION_MISSING, nil]
  end

  act = BreakGlassActivation.create!(
    account:, activated_at: Time.current, reason:, incident_ref:,
    custodian_a_confirmed_at: Time.current, custodian_b_confirmed_at: Time.current,
    review_due_at: 24.hours.from_now      # 【待定】事後檢討時限，33 未載
  )

  # 全域告警扇出：四個出口同時走，任一失敗不阻擋（緊急路徑不可被通知失敗卡住）
  Platform::Alerting.broadcast!(
    severity: :critical, title: "break-glass 帳號已啟用",
    body: "#{account.label}・事由：#{reason}・事故：#{incident_ref}",
    channels: %i[pagerduty email_all_owners platform_banner audit],
    swallow_errors: true
  )
  Platform::Audit.record!(action: "break_glass.activate", actor: nil, actor_type: "break_glass",
    target_type: "BreakGlassAccount", target_id: account.id,
    next_state: { reason:, incident_ref: }, outcome: "alert", source: "自動化")
  # 使用後憑證強制輪換：停用時由 job 產生新的兩半並重新分發
  [nil, act]
end
```

#### 6-4 定期複核 campaign（未回覆預設 revoke）

```ruby
# app/services/platform/access_review.rb（節錄）
# 季度複核（原型 v-staff：「季度權限複核 campaign——未回覆預設 revoke」；33 §1 列為 W5）。
#
# 為什麼預設是 revoke 而不是 keep：預設 keep 的複核等於沒有複核——忙起來所有人都不回覆，
# 權限就自動延續。預設 revoke 會逼出真實需求，代價是要有快速恢復路徑（JIT 提權即為此）。
def open!(scope:, due_at:, opened_by:, default_action: "revoke")
  return [:CAMPAIGN_IN_PROGRESS, nil] if AccessReviewCampaign.where(state: "open").exists?

  campaign = AccessReviewCampaign.create!(scope:, due_at:, default_action:, opened_by:,
                                          opened_at: Time.current, state: "open",
                                          period: Time.current.strftime("%Y-Q#{(Time.current.month - 1) / 3 + 1}"))
  # 複核對象＝角色指派 ∪ 群組成員 ∪ API key ∪ 常設高危權限
  items = build_items(scope)
  # reviewer 指派規則：直屬主管優先，無主管者由 platform_owner 複核；
  # 【待定，需使用者確認】組織層級（誰是誰的主管）資料來源，33 未載。
  AccessReviewItem.insert_all!(items)
  campaign
end

def close_overdue!(campaign)
  campaign.items.where(decision: nil).find_each do |item|
    item.update!(decision: "no_response", decided_at: Time.current)
    next unless campaign.default_action == "revoke"
    Platform::AccessReview::Revoker.new(item).call     # 撤角色／踢群組／停用 API key
    Platform::Audit.record!(action: "access_review.auto_revoke", actor: nil,
      target_type: item.subject_type, target_id: item.subject_id,
      previous: { active: true }, next_state: { active: false },
      reason: "複核逾期未回覆，依政策預設撤銷", source: "自動化", outcome: "success")
  end
  campaign.update!(state: "closed")
end
```

---

### 7. 需要的工具、gem 與外部依賴

- **`rotp`**（TOTP，12 §F2 已列為 P1 選型）＋ recovery codes（自產，bcrypt 存摘要）。
- **`pundit`**（12 §F3 已定案）：policy 一律轉呼叫 `Platform::Authz.allow?`，policy 本身不寫規則——避免規則兩份。
- **`bcrypt`**（`has_secure_password`，cost 12，12 §F2）。
- **`rack-attack`**（登入限流，11 §1；平台後台登入每 IP 10 次/分＋每帳號 10 次/10 分）。
- **Solid Cache**：授權快取 60 秒（不快取 JIT／grant）。
- **告警扇出**：PagerDuty 或等價 on-call 工具（**選型待定，需使用者確認**）＋email＋平台橫幅＋審計，四出口。
- **SSO／IdP**：33 §2.15 隱含存在（break-glass 定義為「非 SSO」），但**選型與是否強制待定，需使用者確認**。實作預留 `platform_staffs.idp_subject` 欄位與 OIDC adapter 介面，不先實作。
- **硬體金鑰（WebAuthn）**：33 未提，**不做**；預留 `platform_staffs.kind` 與 2FA 方法欄位。
- **不引入**：`cancancan`（與 Pundit 重複）、`rolify`（角色模型自寫更貼合兩層設計）。

---

### 8. 實作步驟（順序化 todo）

1. `platform_permissions` 詞彙表 seed：把原型 `RM` 九列拆成 permission key（含 `payment_channel.update` 標 `dual_control: true`）；`jit_required` 標在危險區、排程刪除、審計匯出、金流通道、DSR erasure、違規嚴重處置。
2. `platform_roles` ＋ `platform_role_permissions` seed 五角色；寫一支 rake task 從 DB 產出矩陣 markdown，與 32 §5／原型 `RM` **diff 比對**（防漂移）。
3. `platform_staffs` 認證：密碼、TOTP、`otp_grace_until = created_at + 72h`（32 §0）、鎖定流程、rack-attack。
4. `Platform::Authz.allow?`＋Pundit 接線＋`verify_authorized` 全 controller 強制。
5. **兩層不繼承的守衛**：任何存取 `Shop` 子資源的 resolver 都必須帶 `scope: {shop_id:}`；寫一支 CI 靜態掃描，斷言 `Platform::` 下對租戶模型的查詢不是 `without_tenant` 就是有 `access_grant` 檢查。
6. `jit_elevations`＋`Platform::Jit`（申請／四眼核准／撤銷／`active_elevation?`）＋`ExpiryJob`。
7. staff chip 的剩餘時間 API（原型 `staffchip`）。
8. `break_glass_accounts`／`activations`＋分持憑證流程＋四出口告警＋事後檢討提醒。
9. `platform_api_keys`（`clat_` 前綴，28 §0.2）＋輪換與撤銷；與人共用 permission 詞彙表。
10. `platform_user_groups` 三表＋批次綁定 UI。
11. 四頁 CSV 匯出（Users／Roles／Groups／Activity，33 §2.15）。
12. `access_review_campaigns`／`items`＋`DueJob`（W5，可延後但表先埋，33 §4「M0 必須先埋的」精神）。
13. 2FA 重設四眼流程＋網域擁有權證明路徑（33 §2.15）。
14. React：`jit` 卡、`stafftable`、`rolematrix`（由 API 生成）、邀請 modal、複核 campaign 頁。
15. `docs/dev/m8-platform-staff-authz.md`。

---

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/authz_spec.rb`（**矩陣表格驅動**） | ① 五角色 × 九動作 = 45 格逐格斷言，期望值直接讀原型 `RM` 轉成的 fixture ② 一人掛 `support`＋`ops` → 權限為兩者聯集 ③ 未註冊的 permission key → raise（不預設放行） ④ 已停用／已鎖定帳號 → 一律 false ⑤ **`platform_owner` 存取租戶層資源且無 access_grant → false**（兩層不繼承核心測試） ⑥ 有 access_grant 但已過 60 分鐘 → false |
| `spec/services/platform/jit_spec.rb` | ① 無 `ticket_ref` → `TICKET_REF_REQUIRED` ② 自我核准 → `SELF_APPROVAL_FORBIDDEN` ③ 核准人本身無該權限 → `APPROVER_LACKS_PERMISSION` ④ TTL 超過上限 → `TTL_EXCEEDS_MAX` ⑤ `expires_at` 過後 `allow?` 立即為 false（**不執行 ExpiryJob**，證明安全不依賴 job） ⑥ 撤銷後下一次 `allow?` 立即 false（不受 60 秒快取影響） ⑦ 重複申請同權限 → `ALREADY_ELEVATED` |
| `spec/services/platform/break_glass_spec.rb` | ① 只有一位保管人確認 → `CUSTODIAN_CONFIRMATION_MISSING` ② 啟用觸發四個告警出口且任一失敗不阻擋 ③ 審計列 `actor_type: break_glass`、`outcome: alert` ④ 停用後憑證被標記需輪換 ⑤ 24h 未完成事後檢討 → 每日提醒 |
| `spec/services/platform/access_review_spec.rb` | ① 已有進行中 campaign → `CAMPAIGN_IN_PROGRESS` ② 到期未回覆 → `no_response` 並執行 revoke ③ revoke 後角色確實移除且寫審計 ④ 決議 `keep` 的項目不動 |
| `spec/models/platform_staff_spec.rb` | ① 建立後 `otp_grace_until` = +72h（32 §0） ② 寬限過期未啟用 2FA → `TwoFactorGraceJob` 鎖定 ③ 唯一 owner 不可停用（`LAST_OWNER_PROTECTED`） ④ 不可修改自己的角色 |
| `spec/requests/platform/staff_graphql_spec.rb` | ① `admin` 呼叫 `platformStaffRoleSet` → 200＋`FORBIDDEN`（32 §5「人員管理／角色變更僅 owner」） ② `platformStaff2faReset` 自我核准 → `SELF_APPROVAL_FORBIDDEN` ③ API key 明文 token 只在建立／輪換回一次，後續查詢不回 ④ 四頁匯出 `read_only` → `FORBIDDEN` |
| `spec/lint/two_layer_isolation_spec.rb`（靜態） | 掃 `app/graphql/platform/**` 與 `app/services/platform/**`：對租戶模型的查詢必須在 `without_tenant` block 內或先過 `AccessGrants.active?`；違反即失敗（32 §0 跨租戶查詢紅線） |
| `spec/lint/role_matrix_drift_spec.rb`（靜態） | 由 DB 生成的矩陣與 32 §5 表格、原型 `RM` 常數三者 diff 為空 |
| `spec/system/platform/jit_flow_spec.rb` | 快樂路徑：support 申請危險區權限 → admin 核准 → staff chip 顯示倒數 → 執行動作成功 → 60 分鐘後（`travel_to`）同動作被擋 |

---

### 10. 驗收清單

1. 五角色 × 九動作矩陣與 32 §5＋原型 `RM` 三者完全一致，且矩陣**由代碼生成**、有防漂移測試。
2. **兩層不繼承**：`platform_owner` 在無 `access_grant` 時無法讀寫任何租戶層資源（33 §2.15）；靜態掃描通過（32 §0）。
3. 一人多角色權限累加（33 §2.15）。
4. 零常設權限：所有 `jit_required` 權限在無有效提權時被擋；提權需四眼且核准人本身具備該權限。
5. JIT TTL 到期**不依賴背景 job** 即失效；撤銷立即生效（不受授權快取影響）。
6. JIT 事由必須綁工單編號（原型 `jit`／`accessrequest`）。
7. break-glass：非 SSO、兩位保管人分持、使用即四出口全域告警、事後檢討提醒、憑證強制輪換（原型 `jit`）。
8. 2FA 強制，72h 寬限後鎖定（32 §0）；重設需四眼或已驗證的網域擁有權（32 §3-3、33 §2.15）。
9. 邀請 24h 有效、重寄舊 token 作廢（32 §3-4）。
10. bot 帳號 API token 可輪換，明文只回一次；與人共用同一套 permission 詞彙表（33 §2.15 VTEX）。
11. User group 批次綁定可用；Users／Roles／Groups／Activity **四頁皆可 CSV 匯出**（33 §2.15）。
12. 定期複核 campaign：未回覆預設 revoke，執行結果寫審計（W5）。
13. 唯一 owner 保護、禁止自我改角色、停用非刪除（12 §F3）。
14. 所有本模組寫入動作在 `platform_audit_logs` 有 before/after（模組四）。
15. UI 對照原型 `jit`／`stafftable`／`rolematrix`／`staffchip` 逐控件打勾。

---

### 11. 前端（React/TS）

**元件樹**

```
<TopBar>
  └─ <StaffChip>                              // data-doc=staffchip：身分／角色／JIT 剩餘時間
       └─ <JitCountdown seconds={remaining}/> // 每 30 秒本地重算
<StaffPage>                                   // 路由 /staff（.view.narrow）
  ├─ <PageHead sub="{n} 位・2FA 強制（72h 寬限後鎖定）">
  │    ├─ <Button variant="sec">開複核</Button>       // W5
  │    └─ <Button variant="pri">邀請人員</Button>     // owner only
  ├─ <JitCard>                                // data-doc=jit
  │    ├─ <ElevationRow staff approver ticketRef remaining onRevoke/>
  │    └─ <BreakGlassNote state={idle|active} lastUsedDays={90}/>
  ├─ <StaffTable/>                            // data-doc=stafftable，5 欄＋編輯
  └─ <RoleMatrix/>                            // data-doc=rolematrix，由 API 生成，overflow-x:auto
<InviteModal>  <RoleEditModal>  <JitRequestModal>  <TwoFaResetModal>  <ReviewCampaignDrawer>
```

**狀態管理**
- `platformRoleMatrix` 用 `staleTime: Infinity`（矩陣只在部署時變）。
- JIT 剩餘時間：query 回 `expiresAt`（ISO8601），前端 `setInterval(30_000)` 本地重算並在歸零時自動 `invalidateQueries(['jit'])`——**不靠伺服器推播**，也不在歸零前提早刷新（避免所有人同時打 API）。
- staff chip 的提權狀態掛在全域 `useJitStatus()` hook，`refetchInterval: 60_000`；有提權時提高到 `15_000`（時間敏感）。
- break-glass 啟用中時，`<GlobalBanner severity="critical">` 由 layout 層渲染，**不可 dismiss**。

**GraphQL**

```graphql
query PlatformStaffPage {
  platformStaffs(first: 100) {
    nodes { id name email kind lastActiveAt deactivatedAt lockedAt
            twoFactor { state graceUntil }
            roles { key label } groups { key label } }
  }
  platformJitElevations(activeOnly: true) {
    nodes { id permissionKey permissionLabel remainingSeconds ticketRef reason
            staff { id name } approver { id name } }
  }
  platformRoleMatrix { permissionKey label grade dualControl roles { roleKey allowed } }
  platformBreakGlassStatus { accounts { id label state lastActivatedAt daysSinceLastUse } }
}
```

**三態**
- **Loading**：人員表骨架 5 列；矩陣骨架 9×5 灰格；JIT 卡顯示單行骨架。
- **Empty**：無 JIT 提權 → 「目前沒有臨時提權」＋細字說明 ZSP 政策（**這是正常狀態，用中性語氣不用空狀態插圖**）；無 break-glass 帳號 → `note note-warn`「尚未設定 break-glass 帳號」＋設定引導（**缺少它本身是風險，要用警告色**）。
- **Error**：`FORBIDDEN` → 該卡片替換為「你的角色無法檢視人員資料」；其他 → `note note-crit`＋重試。

**響應式**
- **≤1279**：`.view.narrow` 版寬 998（23 §1）；矩陣 `overflow-x:auto`（原型已在 `roleMatrix` 外層包 `div[style="overflow-x:auto"]`）。
- **≤1023**：`two-col` 轉單欄；JIT 卡的 `usage-row{grid-template-columns:1fr auto auto}` 在窄寬下把「撤銷」鈕移到第二行。
- **≤767**：`html{font-size:14px}`；人員表加 `card-table` 轉堆疊卡片（`data-label`：姓名／Email／角色／2FA／最後活躍，姓名格為卡片標題無 label）；**角色矩陣不轉卡片**——矩陣的價值在於橫向比較，改為橫捲＋首欄 `position:sticky; left:0` 凍結動作名稱；所有 modal 轉貼底 sheet；`.staff-chip span:not(.avatar){display:none}` 只留頭像（原型規則），JIT 倒數改以頭像右上角紅點＋長按顯示。
- **≤429**：`page-actions{width:100%}`＋兩鈕 `flex:1`；JIT 卡三段式 `usage-row` 完全直排；矩陣首欄 sticky 寬度縮為 96px。
- **pointer:coarse**：`.staff-chip{min-height:44px}`（原型規則）；「撤銷」`btn-xs` 命中區 ≥44px；`.chk input{width:20px;height:20px}`（邀請 modal 的群組勾選）。
- **prefers-reduced-motion**：break-glass 橫幅不做閃爍，改為靜態紅底＋圖示。
---

## 附錄 §12：規格衝突與待定清單（本手冊五個模組範圍內）

### 12.1 規格衝突（必須由使用者裁決後才能實作）

| # | 衝突 | A 方說法 | B 方說法 | 影響模組 | 本手冊暫採解法 |
|---|---|---|---|---|---|
| **C1** | **審計保留期：12 個月 vs 5 年** | 33 §2.8：審計日誌「保留期採 PCI DSS 10.5.1：**至少 12 個月**，最近 3 個月須可立即查詢」 | 33 §2.13：台灣辦法要求「蒐集處理利用紀錄與**自動化機器軌跡保存至少 5 年**」；原型 `pdpa` 卡片已顯示「軌跡保存（法定 5 年）已設 5 年」 | 4（審計）、3C | 加 `platform_audit_logs.retention_class`：涉及個資之蒐集／處理／利用／存取的動作（代登入、DSR 執行、客戶資料匯出、KYC 文件檢視、審計匯出）→ `pdpa_5y`；其餘 → `pci_12m`。分類表放 `config/audit_actions.yml`，**未分類時預設 5 年**（保守側錯）。**若只實作 12 個月即違反台灣辦法**——這是本手冊發現的最嚴重衝突 |
| **C2** | **GDPR 期限：1 個月 vs 30 天** | 33 §2.13：GDPR「**1 個月**（複雜可延 2 個月，合計 3）」 | 原型 `dsr` doc-key 與卡片副標：「GDPR **30 天**・CCPA 45 天」；33 §2.13 另引 Shopify redact 模型「**30 天內完成**」 | 3A | 兩者都存：`statutory_due_at`＝曆月（法定，逾期＝違法）、`operational_due_at`＝`min(法定, 30 天)`（內部 SLA，驅動所有告警）。UI 雙欄並列。**只實作 30 天會在 2 月案件產生假逾期；只實作曆月會違反對 app 生態的 30 天承諾** |
| **C3** | **申訴 SLA 適用範圍** | 33 §2.7：「**知識產權** 3–7 工作天」——SLA 綁在 IP 類 | 原型 `v-appeals` 頁首與 `appealboard`：「5 件・**SLA 3–7 工作天**」——套用到全部申訴，看板含 KYC 駁回申訴與限流誤判 | 2 | `appeal_sla_policies` 逐 kind 設定；IP 類 seed 3/7 工作天，其餘 kind 的 SLA 值留 `null` 並在 UI 顯示「SLA 待定」。**不得把 3–7 天套用到所有類別**（客服會依此承諾，錯了要賠） |
| **C4** | **處置階梯第 4 項名稱** | 33 §2.7：違規處理 11 項第 4 項為「刪除**微頁面**」 | 原型 `ovLadder`：「刪除**頁面**」 | 1 | enum key 用 `micropage_delete`（對齊 33 有贊原文），顯示文案用「刪除頁面」（對齊原型）。**兩者指的是同一件事，但 enum 一旦上線就改不動**，先確認 |
| **C5** | **角色矩陣列數與命名** | 32 §5：8 列，第 5 列名為「**代登入**」 | 原型 `RM`：9 列，第 5 列名為「**請求存取（代登入）**」，第 9 列新增「**金流通道變更 ✓＋四眼**」 | 5 | 以原型 9 列為準（原型晚於 32、且 33 §2.9 已把無條件 impersonate 改為授權式代登入）。32 §5 應更新。已寫防漂移測試比對三處 |
| **C6** | **「兩層權限不繼承」指的是哪兩層** | 33 §2.15：**商家組織層 ↔ 商家商店層**（Shopify Plus 模型） | 原型 `rolematrix`（平台角色矩陣卡片）副標：「組織層與商店層不繼承」——寫在**平台**的矩陣上 | 5 | 採「平台層 ↔ 租戶層不繼承」解讀（模組五 §1 已詳述）。**這個解讀決定了 `Platform::Authz` 的核心結構**，若使用者實際要的是「幫商家管理他們的兩層權限」，模組五的資料模型要重做 |
| **C7** | **審計表 FK 與 11 §2 的衝突** | 11 §2：「每個外鍵都建 DB 級 FK 約束」 | 32 §2：關閉後「審計永久保留（去識別化 shop 名）」；MySQL 8 分割表**不支援 FK** | 4 | `platform_audit_logs` 不建 FK，改存 `actor_name`／`target_label` 快照。已在 migration 檔頭註明例外理由。**這是刻意違反，需在 PR 說明** |
| **C8** | **`shop_id` 鐵律的例外範圍** | CLAUDE.md 鐵律 2：全表帶 `shop_id`，複合索引以 `shop_id` 開頭 | 本手冊有 21 張平台域表無 `shop_id`（詳見 12.3 白名單） | 1/2/3/4/5 | 全部列入白名單並在各模組 §3 註明理由；`platform_audit_logs.shop_id` 為**可空關聯欄**不是隔離鍵，其索引 `idx_shop (shop_id, created_at)` 是查詢用不是租戶用 |

### 12.2 「待定，需使用者確認」清單（33 號未載，不得自創）

| # | 項目 | 模組 | 為什麼不能先猜 |
|---|---|---|---|
| T1 | 違禁品四類（保健食品／醫療器材／藥事法／酒類廣告）各自的**法條條號、主管機關、罰則** | 1 | 通知信會引用法源，寫錯條號等於平台發出錯誤法律陳述 |
| T2 | A／B 積分**節點分數對應措施表**（12／24／48 各觸發什麼） | 1 | 33 §9 明載官方頁未展開；只確認 B 類 48 為分水嶺 |
| T3 | B 類滿 48 分時 **A 軌是否一併結轉** | 1 | 33 §2.7 原文可兩讀；已在 `year_end_settle!` 註明改動點只有一處 |
| T4 | 商家**提出申訴的期限**（處置後 N 日內） | 1/2 | 33 只給審理 SLA，未給申訴窗口 |
| T5 | 誤判 suppression 的**預設有效期**（暫定 180 天） | 1/3D | 無到期＝合規黑洞 |
| T6 | 非 IP 類申訴的 SLA 數值 | 2 | 見 C3 |
| T7 | 申訴**次數上限**與可否二次申訴 | 2 | |
| T8 | 補證要求**次數上限**（暫定 2 次）與補證期限（暫定 3 工作天） | 2 | |
| T9 | SLA 到期的**時點**（暫定當日 18:00） | 2 | 影響值班排工 |
| T10 | **台灣行政機關辦公日曆表**的資料來源與年度更新方式 | 2 | 缺日曆會把假日算成工作天，靜默失效 |
| T11 | 未指派申訴的**輪派規則** | 2 | |
| T12 | 台灣《個資法》對**查閱／複製／更正／刪除的法定回覆天數** | 3A | 33 §2.13 只寫外洩通報與稽核，未寫 DSR 期限 |
| T13 | 平台直收買家請求後**轉交商家的時限**（暫定 24 小時） | 3A | processor 通知義務的具體天數 |
| T14 | DSR 逾期升級的**分級點**（暫定 T-14／7／3／1／逾期） | 3A | 33 只規定法定期限本身 |
| T15 | 電子發票「**48 小時上傳**」期限 | 3B | 33 §9 明載此值來自媒體整理，須以財政部原文複核，**不得寫死** |
| T16 | 發票**作廢的期別時間窗**（是否須在該期別申報前） | 3B | 已留 `EinvoiceVoidPolicy.window_open?` 掛勾 |
| T17 | `einvoice_tracks` 的**期別格式與雙月制規則**、字軌 prefix 規則 | 3B | 33 §6 只列 `range_start / range_end / remaining` |
| T18 | 字軌監控 job 的**執行頻率**（暫定每小時）與憑證告警的二級門檻（暫定 30／14／7 天） | 3B | |
| T19 | 外洩 72 小時的**起算點**（「知悉」或「發生」） | 3C | 差一天就是違法 |
| T20 | 新版租戶守則發布後的**寬限期**與未簽署的強制手段 | 3C | 33 只說「須要求租戶遵守」，未給執行槓桿 |
| T21 | 巡檢器：每店抓取 URL 數（暫定 ≤8）、連續失敗開單門檻（暫定 2 日）、單店手動重掃節流（暫定 3 次/小時） | 3D | 皆為【建議值】 |
| T22 | 冷儲查詢的**還原 SLA**（暫定 ≤30 分鐘） | 4 | |
| T23 | 物件儲存**選型**（須支援 Object Lock COMPLIANCE mode） | 4 | 這是 append-only 在儲存層的唯一技術保證，選型錯了整套失效 |
| T24 | 授權快取 TTL（暫定 60 秒） | 5 | 撤銷延遲與效能的折衷 |
| T25 | JIT 提權的**最長 TTL**與各權限類別預設 TTL | 5 | 原型可推得 ≤60 分，最長值未載 |
| T26 | JIT 核准請求的**逾時作廢時間**（暫定 30 分鐘） | 5 | |
| T27 | break-glass 使用後的**事後檢討時限**（暫定 24 小時） | 5 | |
| T28 | 複核 campaign 的**回覆期限**與 reviewer 指派所需的**組織層級資料來源** | 5 | 沒有主管關係資料就無法自動指派 |
| T29 | **SSO／IdP 選型**與是否強制 | 5 | 33 §2.15 隱含存在（break-glass 定義為「非 SSO」）但未指定 |
| T30 | API key 的**到期與輪換政策** | 5 | 33 §9 明載「VTEX API key 到期與輪換政策官方頁本次未能載入」＝無範本 |
| T31 | on-call 告警工具選型（PagerDuty 或等價） | 5 | break-glass 四出口之一 |

### 12.3 平台域表白名單（豁免 `shop_id` 鐵律，集中列管）

| 模組 | 表 | 豁免理由 |
|---|---|---|
| 1 | `violation_point_policies`、`prohibited_rules` | 全平台共用政策與規則字典 |
| 2 | `appeal_sla_policies`、`business_calendar_days` | 全平台共用政策與日曆 |
| 3 | `pdpa_incidents`（`shop_id` 可 null）、`pdpa_audits`、`pdpa_drills`、`platform_policies`、`compliance_rules` | 平台自身法遵義務／全平台規則字典 |
| 4 | `platform_audit_logs`（`shop_id` 為可空關聯欄）、`platform_audit_seals`、`platform_audit_archives`、`platform_audit_exports`、`platform_audit_sinks` | 跨租戶平台級設施（32 §7 已明列豁免） |
| 5 | `platform_staffs`（32 §7 已明列）、`platform_permissions`、`platform_roles`、`platform_role_permissions`、`platform_role_assignments`、`platform_user_groups`、`platform_user_group_members`、`platform_user_group_roles`、`platform_api_keys`、`jit_elevations`、`break_glass_accounts`、`break_glass_activations`、`access_review_campaigns`、`access_review_items` | 平台員工與程式帳號，與任何租戶無關 |

**共同約束**：以上全部查詢必須位於 `Platform::` 命名空間內並顯式 `ActsAsTenant.without_tenant`（32 §0 跨租戶查詢紅線）；CI 靜態掃描斷言此清單之外的表**全部**帶 `shop_id` 且首個複合索引以 `shop_id` 開頭。
