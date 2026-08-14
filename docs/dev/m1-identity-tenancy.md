# 身分與租戶（M1 地基）

> 補寫於 2026-08-14。PR #21 落地時漏了本篇，由 PR #22／#23 的 review 指出
> （AGENTS.md §註釋與文檔 第 3 條：新增功能的 PR 必須同時新增本目錄一篇）。

## 概述

「誰是使用者、他能進哪些店、在該店能做什麼」這三個問題的資料模型與判定路徑。

對應 Shopify 的行為：本尊 2026 已改 **RBAC 且使用者掛組織層**——使用者在
`/settings/organization-account` 底下（**不在**單一商店的設定裡），一個帳號可跨多店，
角色可跨店重用（R12 實測，71-R12-STRUCT1）。

M0 依當時的鐵律 2「全表帶 `shop_id`」把身分表建成商店級。**M0 沒有寫錯**——
是鐵律 2 在 2026-08-14 被裁定加上窄範圍豁免（D8／§A G24）。

## 規格出處

- `docs/specs/85-identity-tenancy-decision.md` — 兩案評估與 A 案的完整條件（**本篇的契約**）
- `docs/specs/71-admin-parity-sweep.md` §A **G24**、§F R12-STRUCT1／R12-V3
- `docs/DECISIONS.md` **D8**
- `CLAUDE.md` 鐵律 2 註釋（豁免白名單的權威清單）
- `docs/specs/12-spec-tenancy-auth-permissions.md` F1–F4（原始的租戶與權限規格）

## 架構與資料流

```
request
  └─ Rack TenantResolver          → Current.shop / Current.staff / Current.admin_session
       └─ (ensure) Current.reset  → 同時清 ActsAsTenant.current_tenant 與兩個記憶化欄位

授權判定（兩層，不可只做一層）
  第一層：能不能進這間店   Current.can_access_shop?(shop_id)  ← user_store_assignments
  第二層：進來後能做什麼   staff.can?(key, shop:)             ← 該店指派的 role → role_permissions
```

🔴 **兩層是 AND，不是二選一**。第一層漏掉 ⇒ 只要猜到別家店的 id 就能操作；
第二層漏掉 ⇒ 進得去的人什麼都能做。

**為什麼第一層必須存在**：身分表升組織層之後，`staff_members` 等表不再有 `shop_id`，
於是**資料庫層不再保證「這個 staff 屬於這間店」**——原本那是複合外鍵
`["shop_id", "id"]` 擋住的。G24 豁免的是「表有沒有 `shop_id` 欄」，
**不豁免「查詢要不要帶 `shop_id`」**，所以那道保證必須在應用層原地補回來。

## API

本次未新增 GraphQL 操作。權限鍵的判定由 `StaffMember#can?` 提供給後續的 policy 層
（Pundit）使用；`resourceVerb` 契約見 `docs/research/28`。

🔴 **M1 接手時**：所有 admin GraphQL resolver 都必須在進入業務查詢前經過上面那兩層，
不得只依賴 `acts_as_tenant`——業務資料表確實還有 `acts_as_tenant`（它們沒被豁免），
但**它保護的是「查到別家店的資料」，不保護「這個人不該進這家店」**。

## 資料表

| 表 | shop_id | 說明 |
|---|---|---|
| `staff_members` | ❌ 已移除 | 平台層帳號；`email` 唯一性由 `(shop_id, email)` 改為**全平台** |
| `roles` / `role_permissions` | ❌ 已移除 | 角色可跨店重用 |
| `sessions` | ❌ 已移除 | session 屬於人不屬於店（一個人多間店只有一個 session） |
| **`user_store_assignments`** | ✅ **必須有** | user × shop 的關聯本體，**不是**豁免項；帶 `role_id`（角色是 (user, shop) 的屬性） |

**migration**：`db/migrate/20260814000000_identity_tables_to_organization_level.rb`
（`down` 為 `IrreversibleMigration`——email 唯一性由店級放寬到平台級之後，
回退會遇到無法自動決定歸屬的重複 email）。

**表定義出處**：`staff_members`／`roles`／`role_permissions` 見 `docs/research/06` §7；
🔴 `user_store_assignments` **不在 06 §7**（06 成文時是單店身分模型，沒有這個概念），
定義出處為 `docs/specs/85` §3。

### 🔴 豁免白名單必須逐字對得上三處

`CLAUDE.md` 鐵律 2 註釋 ＝ `docs/specs/71` §A G24 ＝ `scripts/check-tenant-isolation.rb`
的 `ORG_LEVEL_TABLES`。改一處要改三處（G24 配套條款③）。

**2026-08-14 修正**：寫本篇時對照 `db/schema.rb` 發現三處對不上——規則清單抄的是
**本尊的表名**，列了 5 張我方沒建的表、把必須帶 `shop_id` 的 `user_store_assignments`
列成豁免、**卻漏列真正被豁免的 `sessions`**。已全部修正，並在 CI 腳本加白名單自檢。

## 關鍵取捨

| 取捨 | 選擇 | 為什麼不選另一邊 |
|---|---|---|
| 身分表要不要保留 `shop_id` | **移除**（A 案） | 保留＝同一個人在 3 間店有 3 筆帳號、3 個密碼、3 次改 email；且與本尊的組織層模型永久對不上 |
| 角色掛在哪 | `user_store_assignments.role_id` | 掛 `staff_members` 就無法表達「在 A 店是店長、在 B 店是客服」 |
| 失去 DB 層保護怎麼辦 | 應用層 fail-closed ＋ CI 機制 | 只寫規範不做機制＝紀律，紀律會漂移（本篇的白名單事故就是實例） |
| 無 shop context 時 `can?` 回什麼 | **false** | 回「用任一角色判斷」等於讓 A 店的店長權限在 B 店生效 |

**fail-closed 的定義**（`Current#accessible_shop_ids` 的「為什麼」註釋）：
任何無法明確證明有權限的情況一律回**空集合**，而不是回 `nil` 或丟例外讓呼叫端決定——
後者一旦有人忘記處理就是越權。

## 測試

- `spec/models/session_spec.rb` — 🔴 原本的跨租戶測試**改寫而非刪除**：舊測試證明的是
  「token 帶 shop_id 所以跨店查不到」，那個機制已經不存在了；新測試證明
  **新機制**擋得住（token 組織層解析得到 → `Current.can_access_shop?` 對未指派的店回 false），
  並補一條孤兒帳號（無任何指派）的 fail-closed 測試。
  **舊測試留著會綠燈通過但什麼都沒證明**，那比沒有測試更危險。
- `scripts/check-tenant-isolation.rb` — 三條規則＋白名單自檢，正反皆測。
  跑法：`ruby scripts/check-tenant-isolation.rb`（CI 的 quality job 已掛）。

## 已知限制與 TODO

- 🔴 **CI 檢查是靜態結構檢查**，無法保證「每一句查詢都帶了 `shop_id` 條件」——
  那需要 runtime 或 AST 分析。業務資料表的 query 隔離仍由 `acts_as_tenant` 承擔。
- **群組層未做**：本尊完整鏈是使用者↔**群組**↔角色↔權限（115 權限／17 群組／3 層級）。
  群組是 Plus 專屬的第四段，排 M5（71-R12-V9）。目前只有角色↔權限兩層。
- **權限依賴圖未做**：本尊的權限相依是**圖不是樹**（授予往上傳播、撤銷往下傳播，
  部分邊不可取消勾選），我方尚未實作（71 §F）。
- **`user_groups` / `user_group_roles` / `organizations` / `user_roles` 四張表未建**，
  白名單已預留位置但標明「未建」。
- 🔴 **M1 動工時**：admin GraphQL 的每個 resolver 都要過兩層判定，見上方 API 段。

## 變更記錄

- 2026-08-14 PR #21：身分表升組織層（A 案）＋兩道安全網落地
- 2026-08-14 PR #24：補寫本篇；修正三處白名單不一致；修正 `StaffMember`／`Role`
  升級後未同步的類別註釋
