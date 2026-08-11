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
