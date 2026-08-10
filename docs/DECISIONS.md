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
- 規格文件：24（編輯器/結帳 teardown）、25（相容層架構）、26（API 全量 checklist）。
