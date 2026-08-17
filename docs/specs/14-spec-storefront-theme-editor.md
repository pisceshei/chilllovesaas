# 14 — 功能規格：前台渲染、主題系統、主題編輯器（生產級）

> 覆蓋功能：storefront SSR 與快取、section 渲染、搜尋、SEO/sitemap、密碼保護頁、theme JSON 模型、三欄編輯器、發佈流程。規格對照研究 03，基線見 11。

## F1. Storefront 渲染管線

**生產級做法**：
1. 管線：ResolveShop（12-F1）→ 取 published theme（快取）→ 取當前頁 template JSON → 依 `order` 逐 section render（ViewComponent）→ layout 包殼。
2. **單一 section 失敗不可拖垮整頁**：render 外層 rescue → 上報 Sentry → 該區塊輸出空（生產）或錯誤卡（preview 模式）。
3. Russian doll 快取：頁級 key = `[shop_id, theme.version, template.updated_at, locale, currency]`；section 級 key 再加 `[section_digest, 資料 max(updated_at)]`（如 featured-collection 帶 collection.updated_at）。命中目標：匿名流量 >90%。
4. 買家個人化內容（cart badge、登入態）**不進頁快取**：用 Turbo Frame 延遲載入小片段，頁本體人人相同。
5. 查詢預算：每頁 ≤15 條 SQL 寫進 system test；collection 頁商品卡一次 preload（variants 最低價、首圖、badge 所需欄位）。
6. 效能預算：快取命中 p95 <200ms、未命中 <500ms；圖片全 CDN + 尺寸屬性。

**⚠️ 坑**：
- 快取 key 忘了 locale/currency → 之後上多語系時 A 幣別頁面餵給 B 用戶（先把 key 結構做對，值先單一）。
- `touch` 鏈：商品更新要讓 featured-collection 快取失效——靠 key 帶 `collection.products.maximum(:updated_at)` 的 rollup 欄位（collections 表加 `products_updated_at`，商品變更時 update 一欄），不要用 touch 連鎖。
- 快取雪崩：theme publish 瞬間全站 key 換新 → publish 後跑預熱 job（打首頁/前 10 collection/前 50 商品）。
- robots：preview/draft theme URL 要 `noindex`；密碼保護開啟時全站 `noindex` + 401 語意。

## F2. Theme 資料模型與 settings 驗證

**生產級做法**：
1. 表：`themes`（name、role: draft/published、version）+ `templates`（theme_id、key: index/product/collection/…、body JSON）+ `theme_settings`（全站 JSON）。
2. **一切 JSON 寫入走 server 端 schema 驗證**：section type 必須在 registry、settings 逐鍵驗證型別/範圍/enum、`order` 與 `sections` 鍵一致、上限（25 sections / 50 blocks）強制——用 registry 裡每個 section 的 schema DSL 自動生成驗證器。
3. 版本化：每次儲存寫 `template_versions`（保留最近 50 份）→ 編輯器 undo/redo 與「還原歷史版本」都有了。
4. publish = 單一 transaction 內兩筆 UPDATE（舊 published→draft、新→published、version+1），原子切換。

**代碼**：

```ruby
class Sections::Base < ViewComponent::Base
  class_attribute :schema_def
  def self.schema(&blk) = (self.schema_def = SchemaDSL.new.tap { _1.instance_eval(&blk) })
  # SchemaDSL 產出 [{key:, type:, default:, min:, max:, options:}]
  # Themes::ValidateTemplate 用同一份 schema_def 驗證存入的 JSON —— 單一真相
end
```

**⚠️ 坑**：settings 只在編輯器前端驗證 = 可被直接打 API 塞任意 JSON → 存檔端必驗；`collection_picker` 等 reference 型設定要驗「該 ID 屬於本店」（跨租戶引用是隔離破口）；template JSON 上限 64KB，防塞爆。

## F3. 主題編輯器（三欄）

**生產級做法**：
1. 架構：左樹+右設定 = React（讀寫 template JSON 草稿 state）；中間 = iframe 載入 storefront 的 preview 模式。
2. Preview 機制：編輯器把「草稿 JSON」PATCH 到 `theme_drafts`（或帶簽名的 preview session），iframe 載入 `?preview=1&sid=<簽名>` → storefront 讀草稿渲染、送 `X-Robots-Tag: noindex`。**簽名限定 staff session + theme id + 30 分鐘**。
3. iframe ↔ 編輯器通訊 postMessage：選中 section 高亮、點預覽反選左樹；**兩端都驗 `event.origin`**，訊息 schema 固定（type + payload）。
4. 互動：左樹拖曳（dnd-kit）改 order；隱藏=disabled；Add section 清單來自 registry（有 preset 者）；設定表單由 schema 自動生成（type→控件映射表）。
5. 儲存：整份 JSON PATCH + `lock_version`（兩個 staff 同時編輯 → 後存者收衝突提示）；自動存草稿 debounce 2s。
6. 未儲存離開攔截沿用 SaveBar 模式（02）。

**⚠️ 坑**：
- iframe 的 storefront 與編輯器不同源（子網域 vs admin 網域）→ postMessage origin 白名單要動態帶該店 host；別用 `*`。
- preview 簽名洩漏 = 未發佈內容外流：短效 + 綁 staff session + server 端可撤銷。
- 拖曳排序只改前端不落庫的瞬間，iframe 重載會回跳 → 草稿 PATCH 成功後才重繪預覽（樂觀更新 + 失敗回滾）。
- undo/redo 用「JSON 快照棧」實作（immer），不要試圖做 op-based——編輯器複雜度的頭號來源。

## F4. 搜尋（predictive + 完整頁）

**生產級做法**：
1. MySQL FULLTEXT + **ngram parser**（中文必須）：`ALTER TABLE products ADD FULLTEXT idx_ft (title, body_text) WITH PARSER ngram;`（body_text = 描述去 HTML 的影子欄位，存檔時同步）。
2. predictive endpoint：`/search/suggest?q=`，債務限制：q ≥2 字、LIMIT 各類 5 筆、逾時 300ms 直接回空（前台體驗優先）、rack-attack 每 IP 60 次/分。
3. 完整頁 `/search?q=`：FULLTEXT 為主，<2 字 fallback `LIKE 前綴`；結果頁支援排序與（P1）篩選。
4. 同義詞/錯字（P2）：Meilisearch adapter 介面先留（`Search::Provider` 抽象）。

**⚠️ 坑**：ngram 索引讓寫入變慢、索引變大——只建在 products（不要每張表都上）；`LIKE '%q%'` 永遠掃全表，只准當 fallback 且帶 LIMIT；搜尋詞要記錄（分析用）但**別記進一般 log**（PII 邊緣），進獨立統計表匿名化。

## F5. SEO / Sitemap / 導航

**生產級做法**：
1. 每頁 title/meta/canonical/og tags 由一個 `SeoTags` helper 統一輸出（規則照 03 §6）；商品頁加 JSON-LD（Product schema：名稱、價格、幣別、庫存狀態）。
2. sitemap：nightly job 生成分頁 sitemap.xml（products/collections/pages）存 Active Storage，`/sitemap.xml` 302 過去；50k URL 分檔。
3. `url_redirects` 查詢掛在**資源不可用（404／unpublish 410）handler 前**（13-F2；範圍同 90-blueprint/12 C.5 <!-- 2026-08-17 更正（PR #52 第 14 輪）：原「404 handler 前」漏 410 形 -->）。
4. menus：巢狀 ≤3 層在存檔端強制；前台渲染遞迴 partial + 快取。

**⚠️ 坑**：JSON-LD 價格要跟頁面顯示一致（同一個 money formatter）；sitemap 別即時生成（大店會被爬掛）；分頁頁（?page=2）canonical 指向自身而非第一頁，`rel=prev/next` 已棄用不用管。

## F6. 密碼保護頁與未發佈狀態

**生產級做法**：storefront middleware 檢查 `shop.password_enabled` → 未帶通行 cookie 者一律 password page（表單 POST 驗證 → 簽名 cookie 24h）；admin preview 帶 staff 簽名者放行；全站送 noindex。

**⚠️ 坑**：密碼頁本身不能被頁快取快取到「已解鎖版本」——通行與否進 cache key 或直接跳過快取（流量小，跳過即可）。

## 本篇驗收（對照 11 §0）

匿名首頁/商品頁快取命中 >90%（壓測報告）；單 section 拋錯頁面仍 200；兩個 staff 併發編輯主題收到衝突提示；preview 簽名過期後 404；中文搜尋「短袖 上衣」能命中（ngram 驗證）；Lighthouse storefront ≥90（Performance/SEO）；XSS 測試集（設定值、富文本、搜尋詞回顯）全數逃逸。
