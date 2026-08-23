# m1 — 商品內容多語言 ML-2（標題／說明／SEO 三組，五語）

> 依據：`docs/plans/2026-08-23-多語言方案.md` §3／§4／§6（裁定 C1 建立態即可填多語）；
> 規格：`docs/specs/67-multilingual.md` §C.2（逐欄位一列）／§C.4(b)（空值）／§C.5（過期）／§C.6（進度）／§E.2-1（兩種 UI 模式）。
> 每單元四件事（鐵律 12.4）：①是什麼 ②功能與值域 ③怎麼做 ④跨功能影響。

## 1. GraphQL 契約

- `ProductSetInput.translations: [TranslationInput!]`，`TranslationInput{ locale, field, value }`。
  ②值域：`locale` ∈ 該店 enabled 且 ≠ 來源語言；`field` ∈ `title`／`body_html`／`meta_title`／`meta_description`；
  `value` 空字串（或語義空 HTML）＝**刪除該譯文列**（前台回落來源語言）。
  ③缺席（整個 `translations` 沒帶）＝不動任何譯文，但**過期偵測照跑**（見 §3）。
  ④錯誤碼：`LOCALE_NOT_ENABLED`（productSet 專屬碼）／`INVALID`（來源語言或不可翻欄位）／`TOO_LONG`。
- `Product.translations(locales: [String!])`：逐列回 value＋六稽核欄的可見部分（outdated／outdatedSeverity／valueSource／reviewRequired／updatedAt）。
- `Product.translationStatus`：每語言一列（requiredFields／translatedFields／outdatedCount／reviewPending／complete）。鐵律 7：進度只從這裡來。
- `Query.shopLocales`：本店已啟用語言（來源語言排第一、其餘照 position）；**編輯頁靠它決定要長幾格欄位**——語言集合是資料，新增語言零部署（67 §A.2 驗收 I18N-2）。

## 2. 服務層 `Translations::Upsert`

- ①宣告式寫入某資源一批譯文，並在**呼叫端的 transaction 內**完成 digest／過期／進度重算。
- ②③流程：驗證（語言啟用／非來源語言／欄位在射程／長度依來源欄位上限）→ 逐條 upsert 或 delete → `refresh_outdated` → 逐語言 `recompute_status`。
- 🔴 `save_translations!` **在譯文缺席時仍然執行**：最常見情境是「商家改了英文標題、沒動翻譯」，那時過期偵測必須照樣標記。早期版本 `return [] if entries.nil?`，導致改來源文字後譯文不標過期（`spec/requests/product_translations_spec.rb` 抓到）。
- 🔴 驗證失敗 ⇒ `TranslationRejected` ⇒ 整棵樹回滾（B.4 全樹語義：不得留下「base 存了、譯文沒存」的半套）。
- ④`Locales::Registry`（enabled_tags／source_tag／translatable_tags）是語言集合的唯一查詢入口，ML-3（Collection）與 ML-4（設定頁）共用。

## 3. 過期偵測（67 §C.5）

- 每條譯文存建立當下的來源文字 `source_digest`；每次商品寫入後比對現值：不同 ⇒ `outdated=true`，severity 依長度變化比例（≤ `i18n.outdated_minor_change_ratio` ⇒ minor）。
- 🔴 **不影響前台渲染**（`outdated_affects_storefront_render: false`）：仍輸出舊譯文，只在後台顯示徽章。
- 譯文本身**不被改動**（spec 明確斷言值不變）。

## 4. 前端 `LocalizedField`（兩種佈局，一個資料契約）

- `stacked`（標題）：對已啟用語言 repeat 輸入框，各標 endonym；來源語言置頂且 `required`。
  🔴 一次看完所有語言，是「把中文打進英文版標題」那個事故的視覺防線（67 §E.1）。
- `tabbed`（說明、SEO 標題、SEO 描述）：語言 tab＋**單一編輯器實例**；非來源 tab 上方可摺疊顯示原文對照；tab 上以圓點標「未翻譯」與「原文已更新」。
- 🔴 兩種模式寫進去的都是 `(locale, field)` 列（`mode_does_not_affect_schema`）；**不得**做成「一語言一份 JSON」——那會同時破壞欄位級 digest、outdated、進度分子與翻譯 CSV，而且要到匯出才發現。
- 表單狀態：`values.translations[locale][field]`；來源語言那一格讀寫的是 base 欄位（title／description／seoTitle／seoDescription），送出時**略過來源語言**。
- ④dirty／SaveBar／捨棄還原沿用既有快照機制（譯文進 `FormValues` 即自動涵蓋）。

## 5. 測試

- 後端 `spec/requests/product_translations_spec.rb`：建立即多語（C1）／來源語言 reject／未啟用語言／不可翻欄位／空值刪列／改來源標過期（值不變）／缺席不動／超長回滾／租戶隔離／shopLocales 排序。
- 前端 `ProductDetailPage.test.tsx` 新增五例：堆疊三語同時可見、分頁切語言換值＋原文對照、過期資料帶入、儲存逐欄位一列且不含來源語言、清空送空字串。
- 🔴 教訓：頁面掛載時三支查詢並發（suggestions／shopLocales／product），測試一律用路由式 stub（`BASE_ROUTES`）；建立態要 `findByLabelText` 等語言清單回來。

## 6. 已知邊界

- 標題以外的欄位（選項名／值、變體 title、媒體 alt）不在 v1 射程（67 §B.2 有清單，屬後續包）。
- 內容語言切換器（頁首 chip）目前只顯示來源語言 endonym；本包用內嵌形態，不做「整頁切語言」。
- 翻譯進度徽章只在編輯頁 tab 上；商品列表的「翻譯」欄與設定頁總覽屬 ML-4。
- RTE 尚未落地（說明仍是 textarea）；分頁式的 `renderTabbed` 已預留給 RTE 實例。
