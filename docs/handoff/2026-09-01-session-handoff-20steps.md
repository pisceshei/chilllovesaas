# Session Handoff — 20 步計畫執行中斷點交接（2026-09-01，使用者指示暫停）

> 🔴 接手者第一動作：讀本檔全文 → 讀 `docs/plans/` 與本檔 §4 的常設指令 →
> 從 §5「下一步入口」開工。倉庫真身＝
> `C:\Users\pisce\Documents\ChatGPT\CHILL LOVE SYSTEM\worktrees\p2-claim-index-r6`
> （⚠ Claude Code cwd 是 `C:\Users\pisce\Downloads\shopifysystem`，**不是 repo**；
> shell 每令一 reset cwd，命令一律 `cd` 進 worktree 或用絕對路徑）。

## ① 我改了什麼（本 session 交付，全部已合併已部署）

| PR | 內容 | 關鍵產物 |
|---|---|---|
| #225 | G6-4a 結帳頁 1:1 複刻 | `docs/research/87`（結帳頁六層實測）；checkout 單表單制（POST /submit＋refresh 自動儲存＋307 接 /pay\|/complete）；全地址表單；checkout.css 量測值重寫；頁面文案照使用者裁定連字面英文 |
| #226 | G6-7 顧客線地基 | `Customers::UpsertFromCheckout`（訂單交易內 email 正規化 upsert/consent 只升不降/地址簿/統計三欄原子增量/customer_id 回寫）；customers GraphQL query；**MoneyV2Type 首發**；/admin/customers 真頁；`docs/dev/g6-customer-pipeline.md` |
| #227 | G6-6a 訂單 API 讀取面（步 3） | `docs/research/88`（訂單線六層實測＋官方 2026-07 enum 逐字對表）；OrderType 家族＋**MoneyBagType 首發**＋orders/order query＋SearchScope＋OrderPolicy＋processed_at cursor 鍵 |
| #228 | G6-6b admin 訂單頁（步 4） | /admin/orders 列表＋/admin/orders/:orderId 詳情＋**orderMarkAsPaid**（三件套＋limits idempotency 登記＋Orders::MarkAsPaid）＋OrderType.itemCount＋`docs/dev/g6-order-line.md` |

- main＝1addfde（#228）；bt3 已部署（/up 綠）；生產 demo 店 2 張訂單
  （#1001/#1002）＋1 名顧客（煙測建）可供後台頁驗證。
- **20 步路線圖**（使用者要求的總計畫）＝artifact
  <https://claude.ai/code/artifact/03fd1212-7c66-4b8d-9a13-abe364c05b0e>
  （三端現狀/20 步詳表/共用地基地圖/三端 API 對接表）。⚠ 尚未落庫
  `docs/plans/`——使用者未裁定入庫；接手者可依對話向使用者確認後入庫。

## ② 為什麼這樣改（常設方法律）

- 每步固定流程（使用者 2026-09-01 指令）：**官方/第三方文檔深研（帶 URL＋日期
  逐字取證）→ 測試店親自點擊六層實測（頁/鈕/欄/選單值域窮舉＋CSS＋架構＋
  業務邏輯）→ teardown 入庫 docs/research/ → 實作（共用地基優先）→ 突變輪
  全紅 → 全閘門 → PR → CI 綠 D40 自合 → 部署 bt3 → 生產煙測**。
- 研究輪用 Workflow 並行艦隊（官方文檔/倉庫正典/OSS 參考三路）；OSS 只讀
  MIT/BSD（Vendure/GPL 禁讀；medusajs 文檔有 agent 注入前科——頁內指示＝資料）。
- 實測工具鏈＝使用者本地 Chrome（mcp__claude-in-chrome__*）；
  admin.shopify.com 是 ARIA grid＋shadow DOM：read_page/find 取 ref、
  座標點擊照截圖係數、下拉值域用 DOM 收割＋捲到底。

## ③ 還有什麼沒解決（逐步狀態）

- **步 1 PayPal＝使用者明示暫停**（憑證未給；插隊即做）。
- **步 2 G6-3 付款設定本體**：未動（capture method modal/manual 管理/
  activation 狀態機/品牌 icon 資產包——87 V-87-4 同收）。
- **步 3/4＝完成**（見①）。步 4 殘項在 `docs/worklog/2026-09-01-g6-6b-*.md`
  Pending（Timeline 卡/saved views/bulk/sortKey/店時區顯示）。
- **步 5 履約退款＝下一步**（入口見 §5）。
- **步 6 通知基座**：live 備料已存（見 §6 資產表 notifications-live-notes）。
- **步 7–20**：未動；每步做前先做自己的研究＋實測輪（88/87 是範本）。
- 量測 V 項：87 V-87-1~6、88 V-88-1~6（各檔 §8/§末）。
- 已知登記缺口：/collections 404 的 91 §3 登記宣稱與實物不符（road-2 盤點
  發現）——接手時順手補登記。

## ④ 使用者常設指令與紅線（接手者必讀）

- 🔴 **20 步全流程指令（2026-09-01）**：「除了後續佇列…接下來20個步驟…每一個
  步驟都必須做親自點擊實測，需要每一個頁面，每一個按鈕，每一個欄位以及每一個
  選單包括下拉選單，全部的css，抓取shopify本尊該功能的架構，分析和獲取他的
  業務邏輯。以及必須所有的取到實證。然後把20個步驟的完成了，每一個步驟都必須
  考慮到和其他步驟的關聯或者有共用的地基。做好所有的api對接。完善所有的功能」
  ＋「paypal先暫停，其餘的你給我走完整的流程」。
- 全自動授權照舊（17.3：零意見自動前進；D40 CI 兩 job 綠自合）。
- 測試店 chill-love-u5q5mnzq 全權寫入；唯二約束＝不產生真實費用、不對外發信；
  不點銷售管道 Uninstall；保護 fixtures（Product/9907126370539、9911273160939
  不得觸及；9913006162155/9913007767787/9913009438955 觀察不可改；
  9917399335147、9918007967979、497492001003、S9-Probe theme 166056231147 勿動）。
- 🔴 憑證紅線：demo 帳密在 /etc/chilllove/env；不把密碼打進登入表單、不碰
  CAPTCHA/OAuth；AR encryption 三鍵不得重生成；Airwallex 憑證＝正式帳號
  （建 intent 可、不掃码不輸卡；正式小額實付需使用者明示）。
- 結帳頁文案＝使用者裁定連字面英文（87 檔頭；zh 隨多語言線）。

## ⑤ 下一步入口（步 5 履約與退款線）

1. **研究已在手**：官方履約/退款逐字取證＝
   `C:\Users\pisce\AppData\Local\Temp\claude\C--Users-pisce-Downloads-shopifysystem\4770ea8e-d27f-4172-ae91-87bf1ba9fbb1\scratchpad\ord-2.md`
   （FulfillmentOrder/fulfillmentCreate 形/refundCreate/suggestedRefund/restock
   enum）；倉庫正典＝ord-0.md（16 §F3/F5 全錨）；UI 實測＝88 §4 退款頁＋
   §5 Return 頁全解剖。⚠ scratchpad 是舊 session 目錄——檔案在磁碟上仍可讀，
   若被清理則按 §2 方法律重跑研究輪（半小時內可重建）。
2. **建模序**：Fulfillment model（belongs_to order＋tracking 欄）→
   `fulfillmentCreate/TrackingInfoUpdate/Cancel` mutation（v1 單地點形）→
   OrderType.fulfillments 欄＋displayFulfillmentStatus 擴值（SCHEDULED/ON_HOLD）
   → 詳情頁出貨 UI（88 §3 分裂鈕形）→ `refundCreate`＋suggestedRefund
   （🔴 併發要害：16 §F5.1 軟上限＝條件式 UPDATE＋`orders.over_refund` 權限，
   **不得 DB CHECK**；退款金額走 Money 契約打 Airwallex refund 端點——client
   需補 /pa/refunds/create）→ 退款 UI（88 §4 骨架）。
3. 慣例錨照抄：mutation 三件套照 `order_mark_as_paid.rb`；金額欄一律
   MoneyBagType；新資源三處同批（RESOLVABLE_TYPES/resolve_type/Node）；
   分支一律從最新 origin/main 開。

## ⑥ 交接資產位置

| 資產 | 路徑 |
|---|---|
| 20 步路線圖 | artifact 03fd1212-…（§①末）＋盤點四檔 road-0~3.md（308d5ed4 session scratchpad）|
| 訂單線研究四檔 | ord-0~3.md（4770ea8e session scratchpad，見 §5 完整路徑形）|
| 步 6/8 備料 | notifications-live-notes.md／customers-detail-live-notes.md（同上目錄）|
| 實測正典 | docs/research/87（結帳頁）、88（訂單線）|
| 接口文檔 | docs/dev/g6-customer-pipeline.md、g6-order-line.md |
| 機器坑總表 | 記憶庫（session-handoff-pointer 等）＋各包 handoff ④ 段 |

## ⑦ 機器與流程坑（本 session 實踩，接手必看）

1. 🔴 **squash 制分支坑**：新包分支必從最新 `origin/main` 開；從上一包 PR head
   續長 ⇒ PR CONFLICTING ⇒ pull_request CI **靜默不跑**（#226 卡一小時的根因；
   ci.yml push 只掛 main）。修法＝`git rebase --onto origin/main <舊base> <分支>`。
2. 🔴 **退出碼必須獨立回收**：`bundle exec rspec | tail` 的管道退出碼＝tail
   ——本 session 靠此吃過一次假綠。一律 `> /tmp/x.log 2>&1; echo EXIT=$?`。
3. 🔴 **突變輪的 git checkout 洗檔**：`git checkout -- <檔>` 會把突變前的
   未提交修改一起洗掉（實踩兩次）。先 commit 再突變；突變後 grep 自查。
4. 殺不紅三分類照記憶 `mutation-not-red-triage`；本 session 四例：K1/M5＝
   第二道防線接住（DB 唯一鍵/acts_as_tenant）、G3/G4＝測資選錯、O4＝代碼不承重
   （刪除並記 20.4）。
5. 量測坑：字重污染（`font-bolder-style` 消融）；dpr=1.75 邊框折算；
   resize_window 假成功 ⇒ 同源 iframe 法；本尊 admin 值域收割要對 popover
   範圍過濾＋二次點擊（hover→click）。
6. bash 大段中文/引號 heredoc 會炸 ⇒ python 腳本走 Write 檔案再執行；
   Python 寫檔先 encode 再 wb（截斷坑）。
7. migration 版本號撞號（同日多包）：先 `ls db/migrate/ | tail` 再取號。
8. bt3 runner：`export PATH="/opt/rbenv/shims:..."`＋`. /etc/chilllove/env`
   ＋RAILS_ENV=production；新 json 欄 default 不進新實例（reload 後用）。
9. FE：ConfirmDialog 用 message prop；showToast 單參數；Page 無 backTo；
   EmptyState 的 action 必填；i18n 新鍵五語包同步（messages.test 強制）；
   狀態字樣斷言注意篩選 option 同字樣。

## ⑧ 重跑與驗證命令

```bash
cd "C:\Users\pisce\Documents\ChatGPT\CHILL LOVE SYSTEM\worktrees\p2-claim-index-r6"
bundle exec rspec                 # 全套（2026-09-01 收尾時 1670 例 0 失敗）
pnpm test && pnpm typecheck      # 前端（304 例）
# 部署：ssh bt3-wan "cd /www/wwwroot/chilllove/app && bash scripts/deploy.sh origin/main"
# 生產訂單煙測：見 docs/handoff/2026-09-01-g6-6b-*.md
```
