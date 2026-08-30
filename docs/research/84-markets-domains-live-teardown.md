# 84 — Markets／Domains admin 實測 teardown（包 32 取證輪）

> 取證：**2026-08-31**，測試店 `chill-love-u5q5mnzq`（Plus dev，已獲全權寫入授權）；
> 工具＝本地 Chrome（claude-in-chrome）；方法＝親自點擊＋DOM 收割（原生 select 選項
> 截圖不可見，一律 `querySelectorAll('select')` 深掃含 shadow root）。
> 本檔只記**本輪親測**的形態；Markets 模型的規則正典仍是 `docs/research/29`（§1）、
> 白名單契約是 `docs/specs/67` §C.8、前綴規則是 67 §F.1。消費者＝包 32 資料層
> （migration `20260831150000`、`app/models/market*.rb`、`app/services/markets/*`）。

## §1 Markets 索引頁（/markets）

- 導航：側欄 Markets（子項 Catalogs／Rollouts）；頁頂「Graph view」切換＋「Create market」。
- 左樹：`Store default`（根）＋「＋ ▢ Regions」資料夾——與 29 §1.5 的「根為 Store Default」一致。
- 表格欄：Market／Status／Includes／Customizations。既有一列：United States·Active·🇺🇸 United States
  （dev 店的 primary market；名稱＝國名）。
- 建議列「Create International Market ＋」（AI 建議，可 ×）。

## §2 市場詳情（/markets/40566653163——從索引列真實 href 導航）

- Name 卡：名稱輸入＋status select；Includes 區＝region 編輯器。
- **「Customized」區（空）＋「Inherited」區 8 維度**，逐列帶 ⊕：Currency→HKD／Catalogs→
  All products／Discounts／Online Store→ella-7-2-0-theme-source／Checkout and accounts／
  **Domain and language→chill.deals • English, Chinese (Traditional)**／Taxes and duties→
  Not collecting／Returns and cancellations→No rules set。右欄：Parent market→Store default、
  Shipping（2 rates）、Customer privacy。
  ⇒ 與 29 §1.5(c)「UI 8 維度、NULL＝繼承、繼承分區顯示生效值」逐項吻合（本輪為既存記錄的正面複驗）。
- **Domain and language 的 ⊕ popover**：動作「New subfolder on chill.deals」＋網域勾選清單
  （chill.deals English［Primary］／chill-love-u5q5mnzq.myshopify.com English）
  ⇒ presence 的兩形＝**子資料夾 XOR 網域**，與 29 §1.2 XOR 同構（`ck_mwp_domain_xor_subfolder` 的依據）。

## §3 Create market 表單（/markets/new；取證後 Discard，零資料殘留）

- 欄位：Name（文字）＋ **status 原生 select＝恰兩值 `DRAFT`／`ACTIVE`，新表單預設 ACTIVE**
  （DOM 收割逐字：`[{"name":"status","options":[{"v":"DRAFT"...},{"v":"ACTIVE","sel":true}]}]`）。
  ⇒ `Market::STATUSES`（存小寫、序列化層升大寫）的值域實證。
- **Includes →「Market conditions」modal**：`Includes [Regions ⌄]` 條件類型 popover **恰四值**（逐字）：
  **Regions／POS locations／Company locations／Channels**＋國家 checkbox 清單（附搜尋、全選）。
  ⇒ 29 §1.1 MarketType 四個條件型的 UI 實證（`NONE`＝無條件市場，UI 上即「不加條件直接 Save」）。
- 右欄「Save to show market hierarchy」⇒ lineage 是存檔後推導的（29 §1.5(a)：不是手動指定欄位）。

## §4 Settings → Domains（/settings/domains）

- 列表欄：Domain／Status。三列：`chill.deals`（**Primary** 徽章）·Connected；
  `chill-love-u5q5mnzq.myshopify.com`·Connected；`www.chill.deals`·Connected。
  動作：「Connect existing ▾」＋「Buy new domain」。
  ⇒ **每店恰一個 Primary 徽章**＝`uq_domains_single_primary` 生成欄位唯一索引的依據；
  平台子網域（myshopify）**是列表中的一列**＝我方把平台子網域 host 種進 `domains` 的依據。
- **網域詳情**（/settings/domains/145102799083——domain 有獨立 id）：
  「Managed by Cloudflare · Added on Jul 14, 2026」；兩張檢查卡＝「DNS records are pointing to
  Shopify」＋「Domain is live in all regions globally」（六大洲逐項綠、Last checked 時戳）；
  「Domain settings ▾」＝恰一項 **Delete domain**；
  「**Domain target and type**」卡：Target＝Online Store；Type＝Primary domain＋Change 鈕。
- **Change domain type 對話＝domain type 的完整值域（恰三值，說明逐字）**：
  1. **Primary domain (Current)**——“Displayed in the address bar when visitors are browsing Online Store.”
  2. **Redirecting domain**——“Directs users to the primary domain for Online Store.”
  3. **Alias domain**——“Displays contents of Online Store but doesn't redirect or update the
     browser address bar. Misuse can harm SEO.”
  ⇒ `Domain::DOMAIN_TYPES = %w[primary redirect alias]` 的值域實證。redirect／alias 的**行為**
  實作屬步 2（hosting）；DNS 檢查／SSL 屬平台 ops（bt3 配套），v1 `status` 先 pending|active 兩值。

## §5 證據五件套（鐵律 14.4）與已知限制

| 格 | URL（去 token）| 觸發步驟 | 形狀節錄 | 取證日 |
|---|---|---|---|---|
| status 值域 | admin…/markets/new | 開表單→深掃 select | `DRAFT`/`ACTIVE`, sel=ACTIVE | 2026-08-31 |
| 條件類型 | 同上 | Includes→Add condition→型別 popover | Regions/POS locations/Company locations/Channels | 2026-08-31 |
| 繼承 8 維度 | admin…/markets/40566653163 | 詳情頁截圖 | Customized(空)＋Inherited 8 列各帶 ⊕ | 2026-08-31 |
| presence 兩形 | 同上 | Domain and language ⊕ | New subfolder on chill.deals ∥ 網域勾選清單 | 2026-08-31 |
| domains 列表 | admin…/settings/domains | 直開 | 3 列、恰一 Primary 徽章 | 2026-08-31 |
| domain type 值域 | admin…/settings/domains/145102799083 | Domain target and type→Change | 三值＋說明逐字（§4） | 2026-08-31 |

- 本輪**未**實際建立市場（Create market 走到值域取證即 Discard；避免污染 dev 店唯一 primary
  market 的 lineage）。「保存後的 submarket 繼承徽章變化」＝**未取得**，登記待步 3／4 消費時補測。
- 市場的 GraphQL payload（persisted-query）本輪未抓包——值域全部來自 UI 原生控件 DOM，
  不涉及 payload 斷言（鐵律 14.1 的射程是「請求／回應形狀的規則性斷言」，本輪無此類斷言）。
