# G6 步 10：分析地基（rollup 引擎＋analyticsOverview＋首頁 KPI）

> 規格＝`docs/specs/19-spec-analytics-settings-api.md` F1/F2；紅線＝
> `docs/research/80` §3（官方三例外）。

## 1. 架構（19-F2 兩層）

- `daily_rollups`（shop_id/date/metric/dimension/value；uq 四欄；金額 cents、
  計數原值——單位辭典＝`Analytics::Metrics`）。查詢永遠打 rollup，不對 orders
  做大範圍即時聚合。
- `Analytics::RollupDaily`：整日重算＋upsert **覆蓋制**（MySQL upsert_all 無
  :unique_by——ON DUPLICATE 由 uq 索引驅動；update_only [:value]）。
- `Analytics::RollupJob`（recurring 每 15 分）：每店「今日＋昨日」（shop 時區）
  ——今日給新鮮度、昨日補換日窗遲到寫入；冪等（重跑同值，MA2 紅證）。
- 日界線＝**shop 時區**（19-F2 坑；23:59:59/00:00 紅證 MA1）。

## 2. 口徑（80 §3 紅線落點）

- gross＝subtotal＋discounts（我方 subtotal 存折後）；net＝gross−discounts−returns；
  total＝net＋shipping＋taxes——🔴 **可為負**（撤銷日；MA4 紅證）。
- returns **落退款日**、不回改訂單日。
- 🔴 **AOV 分子排除 post-order adjustments**（官方例外）：aov_numerator＝成立時
  Σtotal（同日退款也不扣——MA3 紅證，equality-trap 補了同日退款格）；
  查詢端 aov＝分子/分母，**不得**由 total/orders 反推（MA5 紅證；
  `AOV × Orders ≠ Total sales` 在退款期間成立＝O2 反向斷言）。

## 3. 讀面

- `analyticsOverview(from,to)`：一支回全部卡片＋逐日 series（19-F2.3）；
  空期間全 0＋空 series（不給 0 假線）。
- `/admin/home` 佔位轉正：四 KPI 卡（Total/Orders/AOV/Net）＋範圍鈕＋逐日簡表；
  新鮮度句明示 15 分。

## 4. v1 邊界（91 §3.56）

sessions 追蹤（/collect 漏斗）／72 號 16 指標挑選器／Top products dimension 列／
compareRange 參數／rebuild rake／nightly 抽樣對帳——⚪ 隨分析頁完整版。
