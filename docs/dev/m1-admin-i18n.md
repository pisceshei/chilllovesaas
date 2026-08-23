# m1 — 後台介面語言包 ML-1（en／zh-Hant／zh-Hans／ja／fr）

> 依據：`docs/plans/2026-08-23-多語言方案.md` §5（裁定 C3：新員工預設 en；C6：語言包由我方在開發端翻譯完成再部署，不接外部機翻）。
> 規格：`docs/specs/67-multilingual.md` §E.1（介面語言≠內容語言、兩個切換器不連動、平台字串不進租戶表）。
> 每單元四件事（鐵律 12.4）：①是什麼 ②功能與值域 ③怎麼做 ④跨功能影響。

## 1. 前端 i18n 機制（`app/frontend/admin/i18n/`）

- ①平台 UI 字串 bundle＋`t()`；字串隨版本部署、跨租戶共用，**不進** `translations` 表。
- ②五語 bundle `messages/{en,zh-Hant,zh-Hans,ja,fr}.json`（扁平 key，`area.screen.element` 命名）；**en 是 key 正典**，其餘四檔 key 集合必須逐字相同（`i18n/messages.test.ts` 擋缺鍵／多鍵／占位符不一致）。
- ③`format.ts`＝ICU 子集（`{name}` 插值、`{n, plural, =0{} one{} other{}}` 走 `Intl.PluralRules`、`{k, select, …}`）——自寫 ≈80 行，**不引 i18n 框架**（鐵律 1）。`I18nContext.tsx`＝`I18nProvider`（初值來自 Rails 注入）＋`useT`／`useUiLocale`／`useSetUiLocale`＋`translateWith(locale)`（非 React／測試用）；缺鍵回 key 本身（不靜默空白，原則 2）；`<html lang>` 隨語言同步。`locales.ts`＝`UI_LOCALES` 鏡像（正典 limits `i18n.admin.ui_locales`）。
- ④🔴 金額**不走**這裡（鐵律 3/10：幣別符號與位數由市場決定，lib/money.ts）。數字格式（庫存件數）用 `Intl.NumberFormat(locale)`。五檔靜態 import（數十 KB）；日後 code-split 不在本包。

## 2. 注入與持久化

- `staff_members.locale`（既有欄，ML-0 改 default en）＝介面語言；`StaffMember` 驗證 inclusion 於 `i18n.admin.ui_locales`。
- Rails `admin/spa/show.html.erb` 注入 `data-ui-locale`；`layouts/admin.html.erb` 的 `<html lang>` 同值；entrypoint 讀後傳 `AdminRoutes.uiLocale`。
- 切換器（AdminShell topbar，`UiLocaleSwitcher`）：先打 `staffLocaleUpdate(locale)` 成功才切前端狀態（失敗不切，避免「畫面換了、重整跳回」）；成功 toast 用**新**語言渲染（閉包裡的 `t` 仍是舊語言）。
- `Mutations::StaffLocaleUpdate`：只改 `context[:current_staff]` 自己；值域外回 `INVALID`；不需 idempotencyKey（純覆寫）但照義務①呼叫 `enforce_idempotency_contract!`。錯誤型別 `StaffLocaleUpdateUserError`（鐵律 4 ③）。

## 3. 伺服端訊息

- `userErrors.message` 由 `I18n.t("errors.product.*")` 產生（`Catalog::SaveProduct` 22 則訊息全部改鍵），`config/locales/{en,zh-Hant,zh-Hans,ja,fr}.yml`；GraphQL controller 以 `I18n.with_locale(ui_locale_for(Current.staff))` 包住 execute。
- `spec/config/locales_spec.rb` 擋五檔 key 同構（只比我方 `errors.product`／`errors.staff` 子樹；Rails 自帶 `errors.messages` 不在射程）與 `available_locales` 鏡像。
- 尚未改鍵的伺服端文案（登記）：GraphQL controller 的 top-level 錯誤（ACCESS_DENIED／MAX_COST_EXCEEDED／BAD_USER_INPUT）、`Idempotency::Guard::Conflict`、`translate_record_invalid` 的 model 訊息、登入頁——ML-1b。

## 4. 測試

- vitest：`i18n/messages.test.ts`（key 同構／占位符同集合／缺鍵回 key／ICU 子集）；`layout/AdminShell.test.tsx`（注入 en、切 ja 先 mutation 後換畫面＋`<html lang>`、失敗不切）；既有頁測試以 `uiLocale="zh-Hant"` 渲染（zh-Hant.json＝改版前文案逐字，斷言不變）。
- rspec：`spec/requests/staff_locale_update_spec.rb`（預設 en／正規化落庫／值域外 INVALID／同一 productSet 錯誤在 en 與 zh-Hant 員工收到不同語言）；系統測試 `m0_admin_shell_spec` 斷言改英文（真瀏覽器證明整鏈路）。
- 🔴 教訓：request spec 內 `MUTATION = <<~GRAPHQL` 這種 describe 內常數會洩漏到頂層，與 product_set_spec 撞名互相覆蓋 ⇒ 一律 `let`。

## 5. 翻譯品質與術語

- 四語包由我方翻譯（C6），術語保留英文：SKU／handle／SEO／GTIN／ledger／jurisdiction pack／sitemap；「變體」繁中沿用既有「子類」（對齊本尊繁中 admin）、簡中用「变体」、日文「バリエーション」、法文「variantes」。
- 文案為我方措辭（鐵律 9），不抄本尊各語言後台。

## 6. 已知邊界

- 內容語言（商品標題／說明／SEO 的五語）屬 ML-2，本包只做介面語言；商品頁的內容語言 chip 暫顯示「English」（來源語言）。
- 日期／時間格式尚無畫面使用；落地時走 `Intl.DateTimeFormat(locale)`，金額除外。
