# m1 — 設定 › 語言 ML-4：新增／停用／發布語言（不建表、不 migration）

> 依據：`docs/plans/2026-08-23-多語言方案.md` §7；規格 `docs/specs/67-multilingual.md` §A.2（語言集合是資料）／§C.1（三條規則＋上限）／§C.3(d)（來源語言不可變）。
> 使用者 2026-08-23 提問「在設定添加了新語言，數據庫也需要添加對應的表格」——本檔 §1 正面回答；
> 後續補充「做數據庫主要是為了之後對語言商品數據的導出或者導入」——見 §5。

## 1. 為什麼新增語言不需要新表（正面回答）

| 想像中的做法 | 實際做法 | 差別 |
|---|---|---|
| 每語言一張表（`products_ja`／`products_fr`…） | 譯文全在 `translations`，一列＝(resource_type, resource_id, locale_tag, field_key, value) | 加語言＝**插一列資料**，不是改 schema |
| 加語言要寫 migration → 部署 | 商家在設定按「新增」即生效，商品／Collection 編輯頁下次載入自動多一格 | 零部署、零停機 |
| 每語言 × 每資源型別一張表 ⇒ 表爆炸 | 一張表 × 三條索引 | 20 語 × 8 種資源在前者是 160 張表 |
| 欄位級「原文已更新」偵測做不到（每表結構各自為政） | 每列自帶 `source_digest`／`outdated` | 67 §C.5 的過期偵測靠這個粒度 |
| 匯出要 UNION 20 張表 | 一次 `WHERE shop_id AND resource_type` 掃出全部語言 | §5 的匯入匯出成本 |

要動的**資料**有兩處：①`platform_locales`（平台字典：這個語言存不存在＝可不可以被選）②`shop_locales`（本店啟用了哪些）。

## 2. 平台語言字典（`PlatformLocale::CATALOG_SEED`）

- ①是什麼：商家能選到的全部語言（本輪 28 種，含 `ar`／`he` 兩個 RTL）。
- ②每列四個要點：`endonym`＝語言自稱（切換器顯示這個，不用國旗、不用語言碼）；`plural_rule`＝丟給 `Intl.PluralRules` 的識別字；`collation`＝**MySQL 8.4 實際存在**的 collation 名（站內搜尋/排序，67 §C.7）；`direction`＝ltr/rtl。
- ③新增候選語言＝在 `CATALOG_SEED` 加一列＋跑 `PlatformLocale.seed!`（migration／db:seed／spec 三處共用同一正典）。migration `20260823110000` 即此。
- ④🔴 `region` 只在**語言本身因地區而異**時才給（`pt-BR` vs `pt-PT`）；**不得**為「香港繁中」建 `zh-Hant-HK`——那是 `zh-Hant` ＋ HK 市場兩個維度（§C.1 規則 1）。

## 3. API（三支 mutation ＋ 一支候選查詢）

| 操作 | 契約 | 語義 |
|---|---|---|
| `shopLocaleEnable(locale)` | 回 `ShopLocale` | 插一列（`published: false`——語言一啟用就對前台開放＝把沒有譯文的頁面推給買家）。曾停用過的走「重新啟用」路徑，譯文原樣回來 |
| `shopLocaleUpdate(locale, published, position)` | 回 `ShopLocale` | 發布狀態與排序；🔴 來源語言取消發布 ⇒ `SOURCE_LOCALE_IMMUTABLE` |
| `shopLocaleDisable(locale)` | 回 `retainedTranslations` | **狀態轉換不是刪除**：`enabled=false`，`translations` 一列都不動；回傳保留筆數讓 UI 能誠實說「保留 N 筆譯文」 |
| `availableLocales` | `[PlatformLocale!]` | 平台字典 − 本店已有（含停用中的：它們走「重新啟用」不是「新增」） |
| `shopLocales(includeDisabled:)` | `[ShopLocale!]` | 設定頁要看到停用中的才能復原；編輯頁不帶此參數（只要 enabled） |

錯誤碼：`NOT_FOUND`（不在字典）／`ALREADY_EXISTS`／`INVALID`（非法標籤，如裸 `zh`）／`LOCALE_LIMIT_EXCEEDED`（`i18n.max_shop_locales`=20）／`SOURCE_LOCALE_IMMUTABLE`。

## 4. UI（`/admin/settings/languages`）

- 三個區塊：已啟用（來源語言標記＋發布徽章＋發布/停用鈕）、新增語言（候選下拉＋新增鈕）、已停用（重新啟用）。
- ④跨頁影響：這頁改完，商品頁與 Collection 頁的語言欄位集合**下次載入即變**（兩者都讀 `shopLocales`）；前台切換器與 hreflang 讀 `published`（M2/ML-6）。
- `/admin/settings` 從 placeholder 改成設定索引（目前只列已實作的「語言」，不放點不進去的死連結）。

## 5. 這個模型怎麼支撐匯入／匯出（使用者關切點）

翻譯是 **67 §E.6 的「第三套 CSV」**（商品 CSV／庫存 CSV／翻譯 CSV 三套分離，不合併）。現行資料形態天然對得上：

```
translations 一列 → CSV 一列（長表）
  resource_type, resource_id(或 handle), field_key, locale_tag, value, outdated, value_source
或轉寬表（每語言一欄，商家較好編輯）：
  handle, field, en(唯讀來源), zh-Hant, zh-Hans, ja, fr
```
- **匯出**：一次 `WHERE shop_id AND resource_type IN (...)` 掃出全部語言，不需要 UNION N 張表；可選擇「只匯出某語言」「只匯出過期的」（`outdated` 索引已建）。
- **匯入**：逐列 upsert 走既有 `Translations::Upsert`（同一套驗證：語言必須啟用、不可寫來源語言、欄位在射程、長度上限），`value_source` 記 `import`；🔴 空白＝不動作、清空走顯式旗標（`__CLEAR__`），覆寫走 `overwrite_existing`——67 §E.6 已定案，實作時照抄，不要重新發明。
- **對齊點**：`handle` 是匯入的自然鍵（商品 CSV 也用它）；`field_key` 與 `locale_tag` 都是封閉值域，可在解析階段就擋掉錯字。
- 本包**尚未實作** CSV 本身（ML-5b）；上面是資料層已就緒的證明與實作契約。

## 6. 已知邊界

- 排序（`position`）目前只有 API，UI 拖曳未做（下一包）。
- 來源語言變更精靈（67 §C.3(c)）仍未開放。
- per-market 語言白名單（§A.5／§C.8）屬 M2，與本頁是兩個層級：這頁是「全店有哪些語言」，市場頁是「哪個市場開放哪幾種」。
