# m1 — 多語言地基 ML-0：四張表＋五語種子＋來源語言 en（2026-08-23）

> 依據：`docs/plans/2026-08-23-多語言方案.md` §3（使用者裁定 C1–C7）；規格 `docs/specs/67-multilingual.md` §C.1／C.2／C.3／C.6。
> 每個單元四件事（鐵律 12.4）：①是什麼 ②功能與值域 ③怎麼做 ④跨功能影響。

## 1. `platform_locales`（平台字典表）

- ①跨租戶共用的語言字典，**無 shop_id**（鐵律 2 新增「平台字典表」類別；`scripts/check-tenant-isolation.rb` NON_TENANT_TABLES）。
- ②欄：`tag`(PK, BCP-47) / `language` / `script` / `region`（通常 NULL）/ `endonym` / `direction` / `plural_rule` / `date_format_id` / `number_format_id` / `collation` / `status`。種子五列：`en` English／`zh-Hant` 繁體中文／`zh-Hans` 简体中文／`ja` 日本語／`fr` Français。
- ③Migration `20260823100000` 內 `INSERT IGNORE`（冪等）；model `PlatformLocale`（`self.primary_key = :tag`）寫入層驗證標籤（`Locales::Tag`）。
- ④消費者：介面語言切換器（endonym）、設定 › 語言的「新增語言」候選清單、`shop_locales.locale_tag` FK。🔴 不得為「香港繁中」插 `zh-Hant-HK`（67 §C.1 規則 1）。

## 2. `shop_locales`（租戶啟用語言）

- ①某店啟用了哪些語言、哪個是來源語言、哪些已發布到前台。
- ②`is_source`（每店恰一；DB 生成欄位 `source_guard = IF(is_source,1,NULL)` 唯一索引兜底）／`published`／`enabled`（false＝下架保留譯文）／`position`。上限 `i18n.max_shop_locales`=20。
- ③`ShopLocale` 驗證：單一來源、來源恆 published+enabled、不可刪（`before_destroy` throw :abort，錯誤碼 `SOURCE_LOCALE_IMMUTABLE`）、上限（`LOCALE_LIMIT_EXCEEDED`）、標籤正規化。新店由 `Shop#enable_launch_locales`（after_create）依 `i18n.launch_locales` 建五列，`i18n.source_locale_default`=en 為來源。既有店由 migration 用**同一規則**回填。
- ④🔴 `Shop` 對三張 i18n 表用 `dependent: :delete_all`（不是 destroy）：整店刪除時不能被「來源語言不可刪」守門擋住（shop_spec 三條即此）。非交易式併發 spec 的 purge 順序要先刪這三表再刪 shops。編輯頁的語言欄位集合＝`ShopLocale.enabled`（ML-2 消費）。

## 3. `translations`（內容譯文）

- ①一列＝一個 (resource, locale, field) 的譯文；base row 永遠是來源語言文字。
- ②v1 值域：`resource_type` ∈ PRODUCT／COLLECTION；`field_key` ∈ title／body_html／meta_title／meta_description；`value_source` ∈ human／machine／script_conversion／import；`outdated_severity` ∈ none／minor／major。六稽核欄語義見 model 註釋。
- ③唯一鍵 `(shop_id, resource_type, resource_id, locale_tag, field_key)` 五欄 NOT NULL；`review_required` 在 `before_validation` 對 machine／script_conversion 強制 true；`locale_tag ≠ source_locale_tag`；`Translation.digest_for(text)`＝CRLF 正規化＋strip 後 SHA-256（67 §C.5）。
- ④🔴 不做 per-locale JSON blob（67 §E.2-1 硬規則 1）。ML-2 的 `Translations::Upsert` 在 productSet 同一 tx 寫入並重算 `translation_status`；前台 `Translations::Resolve`（ML-6）讀它。

## 4. `translation_status`（進度物化）

- ①每 (resource, locale) 一列：`required_fields`／`translated_fields`／`outdated_count`／`review_pending`。
- ②鐵律 7：編輯頁徽章、商品列表翻譯欄、設定頁總覽**只讀這張表**。
- ③`TranslationStatus#complete?`；ML-2 在譯文寫入同 tx 重算。
- ④表名單數 `translation_status`（`self.table_name` 顯式指定）。

## 5. `Locales::Tag`（app/services/locales/tag.rb）

- 命名避開 Rails `I18n` 模組。`normalize`（語言小寫／script Title／region 大寫）、`validate!`（格式 `iso639_1[-iso15924][-iso3166]`、禁用表不分大小寫、zh 必帶 script）。🔴 `EU`／`UK` 正規化後會長得像合法語言碼（`eu` 甚至是巴斯克語），所以禁用表比對用 downcase 整標籤。

## 6. limits.yml 變更

- `i18n.launch_locales: [en, zh-Hant, zh-Hans, ja, fr]`（原三語）；新增 `i18n.source_locale_default: en`。
- `i18n.admin.create_only_in_source_locale: false`（裁定 C1 翻轉，原文保留註釋）；新增 `i18n.admin.ui_locales`／`ui_locale_default: en`（ML-1 消費）。
- `staff_members.locale` default `zh-Hant` → `en`（裁定 C3；只改 default 不動既有列）。

## 7. 測試

- `spec/models/shop_locale_spec.rb`：首發語言、單一來源（model＋DB 兩層）、SOURCE_LOCALE_IMMUTABLE 三態、上限、正規化、停用保留。
- `spec/models/translation_spec.rb`：唯一鍵雙層、review_required 強制、locale≠source、值域封閉、digest 正規化、租戶隔離。
- `spec/services/locales/tag_spec.rb`：正規化與禁用表。
- 全套 rspec 353/0；`check-tenant-isolation`／`check-limits-keys` 綠。

## 8. 已知邊界

- 本包不含 GraphQL 面與 UI（ML-1／ML-2）；`translations` 目前零寫入路徑（與 idempotency_keys 當年同型：表先到，行為後到）。
- 來源語言變更精靈（67 §C.3(c)）未做；`is_source` 切換目前只能靠 migration 級操作。
