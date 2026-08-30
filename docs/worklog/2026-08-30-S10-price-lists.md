# 2026-08-30 — S10 catalog 第三層：price_lists（D76）

## 已完成的工作 (Done)

- 鐵律 16 研究：priceListCreate 輸入形（name!/currency!/parent!）、
  PriceListAdjustmentType 與 PriceListCompareAtMode 各恰二值（逐字）、
  CatalogStatus 三值、CatalogContextInput 兩欄、catalogDelete 的
  deleteDependentResources 語義——全帶 URL＋取證日 2026-08-30。
- 鐵律 12/14 補測（82 §21）：catalogs 列表值域（含列表獨有的 Draft 檢視）、
  詳情 More actions＝Archive/Delete 恰二項（更正先前誤認）、刪除確認框逐字、
  CatalogDelete op 名（variables＝工具限制未取得）、空 context 建立成功。
  兩顆測試 catalog 已刪除清場。
- `price_lists` migration＋`PriceList` model＋`SalesCatalog has_one dependent: :destroy`。
- spec 6 格綠；突變 K1（decrease>100）/K2（單 catalog 單表）/K3（孤兒清理帶
  price list）實跑各紅。

## 修改的檔案與核心邏輯 (Changes)

- `db/migrate/20260830010000_create_price_lists.rb`：一 catalog 一張
  （uq_price_lists_catalog）；tenant-safe 複合 FK；adjustment_basis_points
  整數 basis points 欄（1bp=0.01%；🔴 非金額——首版用 decimal(5,2) 被 C3 判準
  （migration 全面禁 decimal/float）正確擋下，改整數 bp 同時消掉小數誤差）。
- `app/models/price_list.rb`：enum 二值×2、decrease≤100（數學必然非抄襲）、
  increase 上限不發明（官方未取得）。
- `app/models/sales_catalog.rb`：has_one :price_list, dependent: :destroy
  （孤兒 price list 結構性不存在；官方 false 分支刻意不對位，登記 82 §21）。
- `docs/research/82` §21、`docs/DECISIONS.md` D76、`docs/specs/91` §3.47。
- **兩處被絆線抓到的連動**（20.2②「生產者改、消費者同步」的正向案例）：
  ①`spec/migrations/s0_backfill_sales_catalogs_spec.rb` DDL 往返組——新 FK 讓
  越序 `migrate(:down)` 半途炸、測試庫留在改名前狀態（實踩 832 例連鎖紅）；
  修＝該組先按序回滾 price_lists、after 還原（宣告序使還原先於 shop 銷毀）。
  ②`config/limits.yml` cache_stamp_sources——預埋絆線「表一建就紅」如設計觸發；
  `price_list_updated_at`（規劃名）改 `price_lists.updated_at`（現況帶前綴），
  spec 的 known_pending 同步移除。

## 尚未完成或需注意的風險 (Pending / TODO)

- producer（catalog 管理 UI＋priceListCreate mutation）＝M5；本包資料層無呼叫端
  是刻意的（91 §3.47 ⚪）。
- price_list_prices（變體固定價、金額欄 `*_cents`）＝M5，鐵律 3 全套適用。
- CatalogDelete 的 admin variables 未取得（工具限制）；increase 官方上限未取得。
