# Handoff — S10 catalog 第三層：price_lists（D76）

## ① 我改了什麼

輸入：main=8bd37ee（S9 合併後）；分支 m2/s10-catalog-price-lists。
新增 price_lists 表＋PriceList model＋SalesCatalog.has_one(dependent: :destroy)；
82 §21 補測（含 More actions 誤認更正與 CatalogDelete op）；D76；91 §3.47。
驗證：spec 6/6 綠；突變 K1/K2/K3 各紅後還原綠；全套 1305/0；測試店兩顆 catalog 已清場。
連動修復兩處：S0 migration spec 的 DDL 往返組補「先回滾 price_lists」（新 FK 擋
越序 down 的實踩＝832 例連鎖紅）；cache_stamp_sources 絆線觸發，
`price_list_updated_at` → `price_lists.updated_at`（詳 worklog）。

## ② 為什麼這樣改

S10 的三件組只缺 price list（S0 已建 catalog 表與 publications FK）。
一 catalog 一張＝官方單數所有格＋§9.5b 單支 CatalogPriceListCreate；
decrease≤100＝負價格數學閘（非官方抄襲）；increase 上限官方未取得 ⇒ 不發明。
孤兒 price list 刻意結構性禁止（NOT NULL＋FK＋dependent destroy）——官方
deleteDependentResources:false 允許孤兒，我方不對位，方向同 S1 孤兒 publication 處置。
被推翻的假設：「detail 頁 More actions＝Markets/Company locations」——那是指派列
的 context 型別切換器；真 More actions 在 shadow DOM 裡（Archive/Delete）。

## ③ 還有什麼沒解決

91 §3.47 四條 ⚪（admin delete variables／increase 上限／price_list_prices／producer）。
全部掛 M5，無阻塞。

## ④ 下一個人要注意什麼

- `/catalogs` 頁是 `s-internal-*` web component：find／a11y tree 看不到控件，
  要 shadow 遞迴獵取或截圖座標；network 工具讀不到 POST body（14.3 登記）。
- price_list_prices 建表時＝金額欄，`*_cents` 全套（鐵律 3）；不得沿用
  adjustment_basis_points 的整數 bp 形態（金額另有 *_cents 全套紀律）。
- catalog 刪除路徑經 `Publications::Write.delete → destroy_orphan_catalog!`——
  K3 格守著「帶 price list 仍可刪」；改動該路徑先跑 spec/models/price_list_spec.rb。
