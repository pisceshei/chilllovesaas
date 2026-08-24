# 庫存管理介面（M1，排程第 18 包）

## 概述

商家看與改庫存數量的三個介面：**庫存列表頁**（`/admin/inventory`）、**商品頁庫存卡**、
**調整記錄頁**（`/admin/inventory/:itemId/history`）。第 17 包已經把寫入端做完
（`Inventory::Adjust` 是唯一入口、ledger append-only、CAS、冪等），本包是**讀取面 ＋ UI**：
把那些能力接到畫面上，讓「調 1 件」變成商家點得到的動作。

對應 Shopify：Products → Inventory 列表、商品／變體頁的 Available/Total 儲存格、
以及儲存格 popover 進去的 **Inventory history** 頁。

## 規格出處

- `docs/plans/2026-08-24-第18包執行規格.md`（本包執行規格，含 DoD）
- `docs/research/94`（庫存頁 teardown：§2 列表八欄／§2b 商品頁卡／§2.5 歷程七欄）
- `docs/research/95`（調整語義：reason 值域、ledgerDocumentUri 條件）
- `docs/plans/2026-08-24-庫存ledger形狀總裁定.md`（ledger 形狀與第八式）
- `docs/DECISIONS.md` D42（`inventory.view` 權限）、D43（CSV 延後 ＋ 直寫 cop）、D44（冪等鍵碰撞 fail-closed）

## 架構與資料流

```
讀：  SPA ── GraphQL query ──▶ QueryType#inventory_items / #locations / #inventory_history
                                    │  authorize_inventory!（D42：inventory.view）
                                    ▼
                        Inventory::ItemsQuery      Inventory::HistoryQuery
                        （一個 JOIN 撈齊五個數量）  （window running sum ＝ 第八式）

寫：  SPA ── inventoryAdjustQuantities / inventorySetQuantities ──▶ Inventory::Adjust（第 17 包，唯一入口）
```

### 讀取面的兩個要害

**① 一個 JOIN 撈齊數量（`app/services/inventory/items_query.rb`）**
五個數量欄全部由 `inventory_levels` 的同一列供應，SELECT 直接帶別名
（`level_available`⋯）。`InventoryItemType` 讀 `object.read_attribute("level_available")`，
**不走 association** ——走 association 就是 N+1，而庫存列表一頁 50 列 × 5 個數量
是這個頁面最容易退化的地方。`spec/requests/inventory_read_spec.rb` 有**正數計數**守衛
（別名在 SQL log 中恰好出現 1 次），已用注入回歸驗過。

**② 第八式：window 要在日期過濾之前開（`app/services/inventory/history_query.rb`）**
`quantityAfterChange`（期後值）＝ ledger delta 的 running sum。SQL 形狀是
**CTE 先在整條 ledger 上開 window，外層才套保留期過濾**：

```sql
WITH ledger AS (SELECT …, SUM(delta) OVER (ORDER BY created_at, id) AS available_after FROM inventory_adjustments WHERE …)
SELECT … FROM ledger l JOIN inventory_adjustment_groups g … WHERE l.created_at >= NOW(6) - INTERVAL … DAY
```

🔴 把日期條件寫進 CTE 的 `WHERE` 就錯了——window 只會看到窗內的列，
於是**期後值變成「窗內累計」而不是真實庫存**。實測：一筆窗外 +100 之後窗內 +5，
正確答案 105，錯誤寫法給 5。這條有專門的 spec，並已用「把日期條件搬進 CTE」注入驗過（紅）。

## API

| 操作 | 型別 | 說明 |
| --- | --- | --- |
| `inventoryItems(first/after/last/before, locationId, query, productId)` | query | cursor 分頁（≤250，`config/limits.yml`）。`productId` 給商品頁卡用——**不靠標題搜尋**，同名商品會撈錯。 |
| `locations` | query | 地點選擇器來源。 |
| `inventoryHistory(inventoryItemId, locationId, first)` | query | 該 (品項, 地點) 的歷程列，含 `changes { name delta quantityAfterChange }`。 |
| `inventoryAdjustQuantities` / `inventorySetQuantities` | mutation | 第 17 包既有，本包只是接上 UI。 |

三個 query 都過 `authorize_inventory!`（D42）。`InventoryItemType.locationId` 取
`context[:inventory_location_id]`——那是 resolver 解析出來的**實際**地點（呼叫端可以不傳）。

## 資料表

本包**不改 schema**。讀的是第 17 包建的 `inventory_items` / `inventory_levels` /
`inventory_adjustments`（ledger）/ `inventory_adjustment_groups`（一次呼叫一列）。
`staff_members` 在 71 §A G24 白名單內（組織層），所以 `createdBy` 不包 tenant wrapper；
它**沒有 `name` 欄**，resolver 退回 email。

## 前端

| 檔案 | 角色 |
| --- | --- |
| `app/frontend/admin/pages/InventoryPage.tsx` | A 塊：列表八欄、地點選擇器、行內調整、SaveBar 批次送出 |
| `app/frontend/admin/components/InventoryCard.tsx` | B 塊：商品頁卡（變體 × 地點），卡內自己的儲存鈕 |
| `app/frontend/admin/pages/InventoryHistoryPage.tsx` | C 塊：歷程七欄，Incoming 為條件欄 |
| `app/frontend/admin/components/InventoryAdjustPopover.tsx` | **A/B 塊共用**的行內調整浮層；第 29 包變體子頁直接複用 |
| `app/frontend/admin/lib/inventoryLimits.ts` | reason 值域的**前端鏡像**（不是第二份真相，見下） |

### 兩段式（stage → 儲存）

浮層的 ✓ **只 stage 不打 API**；真正送出在 SaveBar（A 塊）或卡內儲存鈕（B 塊）。
一個 pending 項送**一次** mutation、帶**一個新的 `idempotencyKey`**——
一次呼叫 ＝ 一個鍵 ＝ 一列 `inventory_adjustment_groups`（第 17 包的契約）。
`compareAgainst` ＝**畫面上當時看到的值**，原封不動送出當 CAS 基準；
所以別人在這期間改過就會拿到 `CHANGE_FROM_QUANTITY_STALE`，
前端**不自行預擋**（預擋等於前端自己做一次 race，還是會輸）。
儲存後**一律重讀**——寫入後的真值只有伺服器知道，不本地推算。

### 🔴 與本尊的兩處刻意差異

1. **商品頁庫存卡用卡內自己的儲存鈕**，不掛頁面 SaveBar。本尊商品頁的庫存調整走頁面同一個
   Save。我方分開的理由：商品頁 SaveBar 屬於 `productSet` 那棵樹，把庫存併進去會讓
   **一顆按鈕觸發兩條非原子的 API**，其中一條失敗時商家看不出哪一半存進去了。
   要合併的話改的是 `InventoryCard` 與 `ProductDetailPage` 的 save handler，資料契約不動。
2. **CSV 匯入／匯出鈕 disabled**（D43，延後到第 19 包後）。按鈕保留是為了讓位置與
   本尊一致，但點不下去比點下去沒反應誠實。

### `inventoryLimits.ts` 是鏡像不是真相

reason 的 7 個手動值域寫在前端，是為了**畫下拉選單**。真正的防線是後端的 inclusion
驗證（`Inventory::Adjust` ＋ `config/limits.yml`）——前端漏一個值只是選單少一項，
多一個值會被後端擋掉。這一條寫在該檔檔頭，避免有人把它當成「改這裡就能加 reason」。

## 關鍵取捨

- **期後值一律由後端算**。前端拿到 `quantityAfterChange` 就直接顯示，不自行累加：
  前端只有畫面上這一頁的列，累加出來的是「本頁累計」。
- **歷程無變動的欄留白，不顯示 0**。顯示 0 會被讀成「這次把它調成 0」。
- **Incoming 是條件欄**：整份歷程都沒有 incoming 變動就不顯示——這正是 help 列 8 欄、
  實測 7 欄的成因（94 §2.5）。
- **未追蹤品顯示「未追蹤」而不是 0**：0 是一個數量，未追蹤是「沒有數量這回事」。
- **商品頁卡：選取地點與「資料屬於哪個地點」是兩個 state**。混成一個會在 mount 時抓兩次
  （`""` → 抓 → 設成 L1 → 又抓），而白抓的那次會蓋掉使用者在等待期間 stage 的東西。
  有測試守著（注入回歸驗過）。

## 測試

| 檔案 | 覆蓋 |
| --- | --- |
| `spec/requests/inventory_read_spec.rb` | 三個 query、權限、N+1 正數計數守衛、**第八式**（含保留期窗外列） |
| `app/frontend/admin/pages/InventoryPage.test.tsx` | 八欄、值域窮舉（模式 2 值／reason 7 值）、兩段式、payload 形狀、CAS stale toast、CSV disabled |
| `app/frontend/admin/components/InventoryCard.test.tsx` | B 塊獨有三件：Total 欄名、`productId` 一定帶、卡內儲存鈕 ＋ 單次抓取 |

**注入回歸驗證**（每個守衛都做過，紅了才算守衛）：
拿掉 SELECT 別名 → N+1 守衛紅；日期條件搬進 CTE → 第八式紅（105 變 5）；
`.then` 改設 `selection` → 單次抓取紅（2 變 3）；`onStage` 直接送出 → 兩段式紅；
查詢丟掉 `productId` → B 塊紅。

**手動驗證**（bt3）：列表看到數量 → 行內 +1 → 儲存 → 歷程頁出現「(+1) 26」
→ `Inventory::Reconcile.call(shop:)` 回空（七條恆等式無差異）。

## 已知限制與 TODO

- CSV 匯入／匯出：D43 延後，按鈕 disabled。
- 商品頁卡的「卡內儲存鈕」是與本尊的差異（理由見上），若日後裁定合併需另開一輪。
- 歷程頁的參考文件目前直接顯示 URI 字串；本尊是 popover。形態差異，資料已在手上。
- 地點選擇器不做「移動」（本尊浮層的 origin→destination 語義）——v1 不做 Move。
- 商品頁卡只取第一頁變體（`DEFAULT_PAGE_SIZE`＝50）。`product.max_variants` 是 2048，
  超過 50 個變體的商品，卡上看不到後面的——本包不做卡內分頁，第 20–23 包（變體）處理。
- `.cl-status-filter` 這個 class 在 `ProductsPage` 與 `InventoryPage` 都用、但 admin.css
  裡沒有定義（既存狀態，非本包引入）。要補要另開一輪，本包不擴大範圍。

## 變更記錄

- 2026-08-24：建立（排程第 18 包）
