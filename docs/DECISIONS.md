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
