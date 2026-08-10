# Design Critique — Round 1 紀錄（2026-08-10）

流程示範：我產出兩個高保真 mockup → 交給 design critique（design:design-critique 方法）獨立評審 → 依嚴重度修復 → 留下 backlog。這就是之後每批畫面的固定工序（見 20 §6）。

## 已修復（本輪 20 項）

**Admin**
- 【BUG】捨棄變更還原到錯誤值（改為 focusin 快照 + checkbox/select 支援）
- 【BUG】隱藏頁面時 resize 畫壞圖表（加 clientWidth 守衛 + 回首頁重繪）
- 【BUG】指標卡數據與圖表對不上帳（銷售額/訂單數/AOV 改為由同一組陣列計算：407,700 / 240 / 1,699；轉換率 sparkline 改真實下降序列）
- Save bar 跨頁殘留（導航時攔截 + toast 提示）
- `--text-3` 對比不足 3.37:1 → `#74767b`（4.55:1，AA）
- ⌘K palette 假承諾 → 實作輸入過濾 + ↑↓/Enter 鍵盤操作 + 補齊死項目的 onclick
- 商品列表零結果無空狀態 → 補「找不到 + 清除搜尋」
- 間距離網格（12/14/9/7px → 16/16/8/8）+ 版寬分級（Index 1200 / Home、Detail 998）
- 字級修正（t-value 24px、nav 13px）；中文標題負字距歸零
- Emoji/圖標紀律：🏠🧾📦👋▲▼⚠♥ 全數移除或改 inline SVG
- 死按鈕補回饋（7天/90天、新增商品、側欄子項）；toast/palette 加 aria 屬性

**Storefront**
- 【BUG】免運進度條動畫死碼（innerHTML 重建 → 固定 DOM 只改 width，動畫真的會播）
- 【BUG】marquee 每 26 秒跳接縫（gap → margin-right，-50% 無縫）+ hover 暫停 + prefers-reduced-motion
- 行動版導航消失 → 橫向捲動 fallback；觸控目標 ≤760px 加大（44px）
- `.quick` 觸控/鍵盤不可達 → hover:none 常駐 + focus-within
- `--ink-3` 對比 3.08:1 → `#7d7367`（4.57:1）；footer 底欄同步提亮
- sticky header 蓋住錨點 → scroll-margin-top
- feTurbulence 濫用（10+ 濾鏡實例）→ 商品卡/分類卡移除 grain，保留 hero/story
- hero 中文假斜體 → 正體 + 品牌色底線
- 死按鈕（搜尋/會員）補回饋；「24 件」數據對帳改 8 件；♥🎉 → SVG/文字
- 字級歸位（pname 14、drawer 標題 20、story/news 32、wordmark 20、section 96px）

## Backlog（下輪處理）

dialog focus trap 與焦點還原；pcard/ccard 語意化（div→button/a）；字級全面 token 化（尚有 11.5/12.5 殘留）；admin skeleton 示範位；成本→毛利即時重算；＋−✕ 字元全面 SVG 化；行動版正式漢堡選單；admin 全域字距 0.01→0.02em 決策。
