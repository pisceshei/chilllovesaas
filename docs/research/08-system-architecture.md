# 08 — Shopify 服務端系統架構（工程內幕與復刻對應）

> 本篇整理 Shopify 自己怎麼蓋這套系統（來源以 shopify.engineering 官方工程部落格與公開演講為主），每節附「復刻對應」——同樣的設計原則在一人＋AI 的專案裡簡化成什麼。

## 1. 整體形態：Rails Modular Monolith

- 主應用內部稱 **Core**：2004–2006 年起持續開發的 Ruby on Rails 單體，約 280 萬行 Ruby、50 萬 commits（2020–2021 數字）；1000+ 工程師同 repo，日均約 400 commits、**每天部署約 40 次**。
- Shopify 明確**拒絕全面微服務化**：拆散單體會大增整體複雜度。路線是 **modular monolith**——把 Core 依 DDD 切成約 37 個 components（orders、checkout、merchandising…），每個有明確 public entrypoint 與 owner 團隊；邊界靠自研開源的 **Packwerk**（靜態分析依賴、接進 PR 擋違規）；型別用 **Sorbet** 漸進導入。
- 單體之外只為「好理由」拆服務：**Storefront Renderer**（讀路徑效能）、信用卡 vault（PCI 隔離）、Shop app 等獨立產品；全公司 100+ services，但主體業務邏輯仍在 Core。

**復刻對應**：單一 codebase（monorepo），按領域分模組資料夾 + import 邊界 lint；TypeScript 從第一天。不拆服務——Shopify 拆的那兩個，等價物是「前台 SSR + CDN 快取」與「把卡號完全交給 Stripe」。

## 2. 資料層：MySQL Sharding 與 Pod 架構

- 2014–15 年起以 **shop 為分片單位**做 MySQL 水平分片：一個 shop 的資料完整落在同一 shard，不做跨庫查詢（多租戶天然可分割）。
- 2016 年演進為 **Pod 架構**：一個 pod = 一組 shops + **完全隔離的資料層（MySQL、Redis、memcached）**；pod 間零依賴。無狀態 web/job workers 可共用，但單一請求只碰一個 pod。規模約 100+ pods。
- **路由**：LB 層的「Sorting Hat」（nginx/Lua）依 shop 判斷 pod、加 header 定向。
- **故障隔離**：pod 掛掉只影響該 pod 的商店；每 pod 有 active + recovery 兩個資料中心，Pod Mover 可約一分鐘整 pod 搬遷；現行跑在 GCP 多 region。
- **再平衡**：用開源 **Ghostferry** 零停機搬 shop（批次拷貝 + binlog tailing + 短暫鎖寫切換）；演算法用 TLA+ 驗證。Core 未見公開採用 Vitess（Shop app 已遷 Vitess）(待確認)。
- **ID 設計**：shard 內自增 BIGINT，對外用 GraphQL global ID（`gid://shopify/Product/123`）；新系統改用含 shop_id 的 composite primary key 讓鎖與資料局部性對齊租戶。

**復刻對應**：單一 PostgreSQL；**所有表帶 `shop_id`** + 複合索引 `(shop_id, …)`；用 middleware/RLS 強制租戶隔離、測試保證「查詢必帶 shop_id」——這就是未來可分片的邏輯前提。failover 交給雲託管 DB。

## 3. 流量層：Edge 與 Storefront Renderer

- 邊緣是 **nginx + OpenResty（Lua）可程式化 LB**：路由、checkout throttle、排隊頁都寫成 Lua script 放在 edge，不動應用碼；最外層 CDN 現由 Cloudflare 承接 (待確認)。
- **Storefront Renderer（SFR）**：2019–20 年把買家前台（Liquid 渲染）從 Rails 拆出，重寫成**專用純 Ruby 應用**。動機：前台是讀多、延遲極敏感的路徑，值得用實作複雜度換效能。手法：手寫 SQL 減少 round trip、按請求型態 eager-load、三層快取（DB query KV cache、進程內 cache、full-page cache）、verifier 雙跑比對後漸進切流。成果：平均回應快 4–6 倍。

**復刻對應**：前台 = Next.js SSR + CDN full-page/fragment cache。繼承的洞見是「**前台本質是可極致快取的 read path**」，不需要真的拆服務。

## 4. 結帳與搶購：Flash Sale 對策與規模數字

- **Checkout 排隊**：edge 的 Lua leaky bucket 只對寫重的 checkout 路徑限流；超量者導去可快取的排隊頁，放行者發簽名 cookie 全程免再排；後續演進為高吞吐下近似 FIFO 的公平佇列。
- **庫存熱點**（2026 公開）：checkout 的庫存預留從 Redis 改回 **MySQL**（與 ledger 同庫才有交易原子性）：**one-row-per-unit**（10 件庫存 = 10 列）+ MySQL 8 `SKIP LOCKED` 消除單列熱點；bounded pool + inline 補貨；READ COMMITTED 避 gap lock；實測瓶頸反而是連線耗盡，靠 SQL comment 標記呼叫方追蹤、砍掉 checkout 路徑一半多餘讀取。
- **BFCM 準備**：每年 9 個月 readiness——自研壓測工具 Genghis、開源 Toxiproxy 注入故障、Game Days 混沌演練、Resiliency Matrix；2025 年以每分鐘 2 億請求做全平台彩排。
- **規模數字**：BFCM 2024——GMV $11.5B、峰值銷售 $4.6M/分鐘、edge 峰值 2.84 億 req/min（約 470 萬 RPS）；**BFCM 2025——GMV $14.6B、峰值 $5.1M/分鐘、edge 峰值 4.89 億 req/min（約 815 萬 RPS）**、週末 81M+ 消費者。

**復刻對應**：MVP 只需「冪等 checkout + 交易內 `UPDATE inventory SET available = available - n WHERE available >= n`」；搶購需求出現後再加 per-shop token bucket 與排隊頁。one-row-per-unit / SKIP LOCKED 是單機每秒數千次同商品扣減才需要的招。

## 5. 非同步與事件：Jobs、Kafka、Webhooks

- **背景任務**：Redis-backed 佇列（Resque 系自研，經 ActiveJob）(待確認)；關鍵創新是開源 **job-iteration**：長任務寫成可中斷續跑的 enumerator——這是每天部署 40 次的前提。黑五等級會出現百萬級 backlog，公平性（防大商店占滿 workers）是核心議題。
- **Kafka**：月約 1.75 兆訊息。用途：事件/log 聚合；**CDC**（每個 MySQL shard 一個 Debezium connector 讀 binlog → per-table topics，取代查詢式 ETL）；Flink 即時分析（BFCM live map 端到端 21 秒）；服務間訊息。生產端不直連 broker：app 寫本機佇列、Go producer 轉發。
- **Webhooks**：模型變更觸發 → 背景佇列非同步派送 → HMAC 簽名、指數退避重試、長期失敗自動移除訂閱。

**復刻對應**：任務佇列用 Postgres（SKIP LOCKED）或 BullMQ；事件先做 **outbox 表**（與業務同交易寫入）+ 單一 dispatcher；Kafka 等到出現第二個獨立消費系統再說。

## 6. 搜尋、部署與其他基礎設施

- **搜尋**：早年 Elasticsearch；2025 公開的商品搜尋已是自研 C++ 引擎 + ML 排序（LightGBM/transformer/embeddings）——官方明言開源引擎在其規模需大改所以自建。
- **部署**：開源 Shipit 部署引擎 + BuildKite CI（10 萬+ 測試、15–20 分鐘 build）+ Merge Queue；**沒有 staging/canary**，靠 feature flags + 秒級 rollback。
- **雲**：2017 年後遷 GCP/GKE 全面容器化。可觀測性：ServicesDB、Semian（circuit breaker）、全區即時 dashboard。

**復刻對應**：GitHub Actions + 單一 Docker image 部署（Fly/Railway/雲 VM）；feature flag 一張表；搜尋用 Postgres FTS 或 Meilisearch，永遠不要自研。

## 7. 可繼承的四條核心原則

Shopify 架構裡服務「人的規模」的部分（merge queue、元件治理、guild）對一人專案歸零；服務「流量與租戶」的觀念全部可繼承：

1. **shop_id 貫穿一切**（租戶隔離是資料模型問題，不是部署問題）
2. **read path 可快取**（前台與後台分離的本質）
3. **寫路徑冪等**（checkout、webhook、job 全部可安全重試）
4. **任務可中斷重跑**（部署不等待長任務）

## 來源

shopify.engineering: shopify-monolith、deconstructing-monolith、enforcing-modularity-rails-apps-packwerk、a-pods-architecture-to-allow-shopify-to-scale、mysql-database-shard-balancing-terabyte-scale、horizontally-scaling-the-rails-backend-of-shop-app-with-vitess、how-shopify-reduced-storefront-response-times-rewrite、surviving-flashes-of-high-write-traffic-using-scriptable-load-balancers、scaling-inventory-reservations、capturing-every-change-shopify-sharded-monolith、bfcm-readiness-2025、successfully-merging-work-1000-developers、world-class-product-search、e-commerce-at-scale-inside-shopifys-tech-stack；shopify.com（BFCM 2024/2025 新聞稿）；InfoQ（flash sale 演講）；Strange Loop 2022（公平佇列）；factorhouse.io（Kafka 架構分析）
