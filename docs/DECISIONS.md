# 專案決策紀錄（DECISIONS）

## 2026-08-10 — 第二階段開工前三決策

### D1. 技術棧：Rails + React（本尊同款）

- 選擇：跟 Shopify 相同形態——**Ruby on Rails**（modular monolith）+ **MySQL** + **React + TypeScript 後台**（自建 Polaris 風格元件庫）+ 伺服器端渲染的買家前台。
- 對應研究：08（Shopify 用 Rails Core 單體 + MySQL Pods + React 後台 + Liquid 前台）。
- 實務註記：
  - 開發與展示在雲端工作區進行；Windows 本機要跑的話建議 WSL2 或 Docker（Rails 在原生 Windows 體驗較差）。
  - demo 階段資料庫用 MySQL（與本尊一致）；所有表帶 shop_id（06 的多租戶原則）。
  - 後台 React 以 Vite 構建、掛在 Rails 之上；買家前台走 Rails 伺服器渲染（對應 Storefront Renderer 的讀路徑思路）。

### D2. 路線：A → B → C（全都要，按此順序）

1. **A 成交閉環**（M0 地基 → M1 商品 → M2 前台 → M3 結帳/Stripe test）
2. **B 後台深化**（M4 訂單出貨退款/顧客 → M5 折扣/報表/設定）
3. **C 主題編輯器**（M6 三欄編輯器 + section 庫）

### D3. 品牌名：**CHILL LOVE**

- 平台（SaaS 本體）品牌名，用於 logo 文字、後台左上角、登入頁、通知信署名與網域規劃。
- 全部做成單一變數/設定，之後可一行改名。
- demo 內不出現 Shopify 字樣與其品牌資產（07 §10 的紅線）。

## 2026-08-10（同日晚間）— 前台引擎重大修訂

### D4. 前台改走 Liquid 相容主題引擎（第三方 Shopify 主題可直接匯入）

- 選擇：買家前台的渲染引擎從「Rails ViewComponent 自有 section 系統」改為 **Shopify/liquid gem（MIT）＋ 自行實作平台層（138 objects / 9 tags / 94 filters）＋ 主題 JS 硬依賴端點（/cart/*.js、Section Rendering API 等）1:1 實作**。
- 動機：使用者明確要求「Shopify 本身的第三方主題可以直接套用」。
- 影響範圍：**取代** 07 號 §與 10 號中「前台用 ViewComponent 簡化」的舊方案；M2/M6 里程碑內容修訂（見 25 號 §9、HANDOFF §5）；14 號 spec 的 theme JSON/編輯器規格仍有效。
- 法律基礎：liquid gem、theme-check（TS 版）、theme-liquid-docs 皆標準 MIT；**但 Dawn/Horizon 授權含「僅限與 Shopify 互通」限制（非純 MIT）、Theme Store 主題授權限單一 Shopify 商店**——平台不預載/散布任何 Shopify 主題或其衍生物，第一方預設主題從零自寫，商家匯入第三方主題須過授權聲明 gate（詳見 25 號 §8，含 2026-06 Shopify v. SHOPLINE 和解先例）。
- 規格文件：24（編輯器/結帳 teardown）、25（相容層架構）、26（API 全量 checklist）、27（Ella golden theme）、31（完整補齊計畫）。

## 2026-08-11 — 全面 API 化與國際化三決策

### D5. API-first：admin 與服務端只經 GraphQL Admin API 對話

- 選擇：**1:1 仿 Shopify GraphQL Admin API 工程慣例**（官方文檔查證）——版本化 URL `/admin/api/{YYYY-MM}/graphql.json`、GID `gid://chilllove/{Type}/{id}`＋Node、cursor 分頁（≤250）＋pageInfo、mutation `resourceVerb`＋`userErrors{field,message,code}`（HTTP 恆 200）、MoneyV2/MoneyBag、cost 制限流＋`extensions.cost` 回報、webhooks（topic `資源/動詞`＋HMAC-SHA256＋5 秒 2xx）、bulk operations 契約保留（demo 同步分批）。
- 三端對接：admin React SPA→GraphQL；買家前台→Liquid SSR＋Ajax/SRA 面；外部整合→token＋webhooks；編輯器高頻操作走內部 REST（draft/render_section）。
- 契約文件：**28 號**（§0 慣例＋§1–14 逐模組操作表＋§15 webhooks＋§16 前台面＋§17 對接矩陣）。

### D6. 基建對映：全面走 Shopify 路線（demo 形態 → 生產路線）

| Shopify 生產 | 我們 demo | 我們生產路線 |
|---|---|---|
| Rails modular monolith | Rails 8.1 單體 | 同（Packwerk 模組化） |
| MySQL + Vitess Pods | MySQL 8 | MySQL → Vitess/PlanetScale 分片（shop_id 鍵） |
| Memcached + Redis | Solid Cache | + Redis（session/限流桶） |
| Kafka 事件流 | Solid Queue + outbox 表 | + Kafka（webhooks/分析管線） |
| Elasticsearch | MySQL ngram | OpenSearch（商品/訂單搜尋） |
| 自建圖片 CDN | imgproxy + S3 相容存儲 | 同 + CDN 邊緣 |
| Storefront Renderer（獨立讀路徑） | 同進程 ThemeRuntime | 抽獨立 renderer 服務（無狀態、可水平擴） |
| GraphQL Admin API | 同（D5） | 同 |

### D7. Markets/i18n 一級公民＋SEO/feed 內建

- 多語言/多貨幣/多市場按 29 號 P0（M2 隨行：locales＋translations＋多幣顯示）→ P1（M5/M6：markets 全模型＋市場定價＋hreflang 全量＋Adapt）→ P2（price lists/duties/B2B）。
- SEO 合規（30 號 §1–5/§9）內建於 storefront 渲染層（M2）：self-canonical 引擎、JSON-LD 注入分工、sitemap 分片、robots.txt.liquid、410 紀律、CWV 預算。
- 商品 feed（30 號 §6–8）：以 GMC 規格為 canonical schema 的生成器＋per-channel 轉換（M5+）；**Google 側直接實作 Merchant API**（Content API 2026-08-18 落日）；IndexNow 事件 ping；Simprosys 走「自建底座＋connector 加值」雙軌（30 §10.3），不做 Shopify 偽裝。

## 2026-08-14 — parity R11–R13 收口四裁定

> 背景：parity sweep 跑到 R13，§F 累積 86 條未結案，而實作仍停在 M0（PR #12 未合）。
> 這四條是「擋住地基或會讓後續輪次反覆重提」的部分，先裁定再往下走。
> 保護清單條目：`docs/specs/71` §A **G24–G27**（凡在 §A 者，任何對比輪不得建議改回與 Shopify 一致）。

### D8. 身分與權限表豁免鐵律 2 的 `shop_id`（G24）

- **問題**：R13 實測證實本尊 2026 已改 RBAC，且**身分與權限掛在組織層**（使用者↔群組↔角色↔權限，
  角色可跨店）。這與鐵律 2「全表帶 `shop_id`」正面衝突，而 PR #12 的 schema 正是地基。
- **選擇：窄範圍豁免**，而非硬套 shop_id（做不出跨店角色）或全面放寬（失去隔離保證）。
- **理由不是「本尊這樣所以照抄」，而是分層本來就不同**：鐵律 2 保護的是**業務資料的租戶隔離**；
  身分與權限是**授予租戶存取權的那一層**，邏輯上位於租戶之上。這也正是本尊把「使用者」
  放在組織區塊而非商店區塊的原因。
- **白名單（逐表列舉，不得口頭擴充）**：`organizations`／`users`／`roles`／`role_permissions`／
  `user_roles`／`user_groups`／`user_group_roles`／`user_store_assignments`。白名單以外一律照舊。
- **三條配套約束**（缺一條這個豁免就變成隔離漏洞）：
  1. 白名單表**不得**存放任何業務資料欄位（只放身分、角色、指派關係）；
  2. 🔴 **豁免的是「表有沒有 `shop_id` 欄」，不是「查詢可不可以不帶 `shop_id`」**——
     跨店存取一律先由 `user_store_assignments` 解析出可及 shop_id 集合，查詢層仍逐表帶條件；
  3. 新增白名單表必須同步改 `CLAUDE.md` 鐵律 2 與 `71` §A G24，且 PR 描述標明。
- **影響**：`CLAUDE.md` 鐵律 2 與 `AGENTS.md` §技術鐵律 2 已加註；71-R12-STRUCT1 結案；
  RBAC 資料表本體的實作仍在 M1。

### D9. AOV 不與 `net_sales` 同源——鐵律 7 的具名例外（G25）

- **問題**：本尊的 AOV 分子**刻意排除 post-order adjustments**，因此 `AOV ≠ net_sales / orders`。
  照鐵律 7「同指標同一份 rollup」的直覺實作，數字會與本尊對不上。
- **選擇：照抄本尊的例外**——AOV 有自己的 rollup 分子。專案前提是 1:1，且官方公式寫得很清楚。
- **配套兩條**：①**總銷售額允許負值**（撤銷 > 銷售的日子，官方明列）⇒ 金額元件與 badge 要支援負值；
  ②`any_click` 歸因各通路加總會超過 metric 本身（設計如此）⇒「小計＝總計」一致性測試須白名單。
- **影響**：`CLAUDE.md` 鐵律 7 已加註（主文不改，例外以註釋掛在條文下）；71-R11-V13 結案。

### D10. 不實作 POS，但資料模型保留 POS 活口（G26）

- **問題**：R13 取得 POS Lite/Pro 完整對照與 9 群組權限；範圍需裁定。
- **選擇：不做 POS**。理由：POS 是**第二個產品不是一個模組**——牽涉硬體、離線、裝置管理、
  店員 PIN、班次、現金抽屜，且**權限模型與後台完全不同**（organization role・只能指派角色不可逐權限・
  以裝置所在地點為軸）。以目前規模，把 POS Lite 做「對」的成本遠大於價值。
- **保留活口**：訂單來源標記、地點、員工歸屬三個欄位面現在就留著，之後要加不用改表。
- 🔴 **任何輪次不得因「本尊有 POS」而建議補做**——要翻案須推翻本裁定。
- **影響**：71-R13-V1 結案；R13 已建的 POS 管道殼保留為展示層。

### D11. UCP 延後至 M6 後評估，但受限 render context 現在就吃進主題引擎（G27）

- **問題**：R13 查明 UCP 是 Shopify 與 Google 共同開發的開放標準（規格在 ucp.dev），
  五個 MCP 端點、能力協商、checkout 四態都有官方文檔——技術面不再是未知，剩產品決策。
- **選擇：UCP 相容層延後**（在有商店有商品之前實作沒有意義）。
- 🔴 **但有一條現在就要吃**：`agents.md.liquid` 是**受限 render context**——
  只有 `request` 與 `agents` 兩個物件可用，且 `agents.md`／`llms.txt`／`llms-full.txt`
  **不可為 JSON template**。這是**架構約束不是功能**，M2 設計 render context 時沒算進去，之後補會很痛。
- **影響**：71-R13-V7 結案；71-R13-V3（主題引擎支援受限 context）**維持 M2 前必答**。
