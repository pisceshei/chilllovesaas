# 99 — 主題儲存與匯入 teardown（G3／步 15）

> 三源取證檔（2026-09-01）：①官方深潛（agent 報告，shopify.dev＋help.shopify.com
> 逐字）②admin 親點＝**沿用 41 §634 既有全集**（OS Themes 頁動作選單先前輪已窮舉）
> ③本地實物（Sources／AST cache 現狀）。實作對照＝`docs/dev/` 步 15 篇。

## §1 官方 GraphQL 契約（取證 2026-09-01；全文＝agent 報告）

- OnlineStoreTheme：id/name/role/prefix/processing/processingFailed/themeStoreId/
  createdAt/updatedAt/files（filenames 參數 "At most 50 filenames"、first
  "At most 2500 can be fetched at once"）。
- OnlineStoreThemeFile：filename/size/checksumMd5（"md5 digest…for data
  integrity"）/contentType/body（union 三形：Text.content／Base64.contentBase64／
  Url.url＝"short lived url"——效期數字未取得）。
- themeCreate：`source: URL!`＝"An external URL or a staged upload URL of the
  theme to import."；role 僅 UNPUBLISHED/DEVELOPMENT；**非同步**（processing→
  processingFailed）。錯誤碼逐字：INVALID_ZIP＝"Must be a zip file."／
  ZIP_IS_EMPTY／ZIP_TOO_LARGE＝"May not be used to fetch a file bigger than 50MB."
- themeFilesUpsert：🔴 "You can process a maximum of 50 files in a single
  request."；回 `job`（非同步）。themeFilesDelete／themeFilesCopy 同族。
- ThemeRole 七值逐字：MAIN（"There can only be one main theme at any time."）／
  UNPUBLISHED／DEMO（試用：可自訂、"access to the code editor and the ability
  to publish the theme are restricted until it is purchased."）／DEVELOPMENT
  （CLI 預覽）／ARCHIVED（超方案上限凍結）／LOCKED（"identified as
  unlicensed"）／MOBILE（deprecated）。
- themePublish／themeDelete（"delete an unpublished theme"）／themeUpdate（改名）。

## §2 官方 limits（…/themes/architecture/limits，逐字數值）

zip（壓縮後）50 MB／全部代碼（assets 除外）250 MB／檔案數 100,000／
JSON template 512 KB／section group 512 KB／settings_schema 512 KB／
settings_data 1.5 MB／locale 檔 1.5 MB／其他 Liquid 檔 256 KB／
JSON templates 1,000／section groups 20／每 group sections 25／每 section
blocks 50／theme blocks 巢狀 8 層／theme block 檔 300／主題名 50 字元。
每店主題數：Basic/Grow/Advanced 20、Plus 100（help 逐字）。

## §3 zip 結構（官方）

- 🔴 唯一硬要求（逐字）："Only a `layout` directory containing a `theme.liquid`
  file is required for the theme to be uploaded to Shopify."
- 目錄樹＝assets/blocks/config/layout/locales/sections/snippets/templates
  （templates 下 customers/metaobject 子目錄）。
- 🔴 zip 內單一根資料夾容忍度＝官方**無記載**（未取得）⇒ 我方 ours：全部條目
  共享唯一根目錄時剝根（常見打包形；91 §3.66 登記）。
- CLI `shopify theme package`＝"Only folders that match the default Shopify
  theme folder structure are included"（⇒ 白名單頂層目錄是官方管線自身行為）。

## §4 admin 頁動作（41 §634 既有親點全集＋本輪 help 逐字互證）

- 動作選單全集（41 §634）：Customize／Publish（確認 dialog；原主題自動退回庫）／
  Preview／Rename／Duplicate／Download（寄信 zip）／Edit code／
  Edit default theme content／Delete（確認）。
- 本輪 help 互證：現行 UI 用語＝**Draft themes** 區＋**Import theme › Upload
  zip file**；發布後舊主題 "displays in the **Draft themes** section"；
  Duplicate 命名＝"Copy Of"＋原名、達 20 上限不可複製；Download＝".zip file to
  the email"；已發布主題不可直接刪。
- ⚠️ V 項：本輪測試店 /themes 頁工具面全滅（script injection 恆逾時——
  online-store-web 已知量測坑，3 次重載＋長等未解）⇒ 選單標籤未再親驗，
  以 41 §634 既有親點為準（工具限制誠實登記，鐵律 13.4）。

## §5 我方現狀與缺口（本地實物）

- Sources.key_for＝`name.parameterize-version`；AST cache 鍵＝[key, rel]——
  🔴 匯入主題落地後，兩店同名同版本不同內容 ⇒ **跨租戶 AST 汙染**（現狀只有
  倉內/fixture 共用唯讀目錄所以安全；匯入前必須改內容定址）。
- themes 表已有 license_attested/source/version；缺 content_checksum。
- 儲存落點＝`storage/themes/{checksum}`（gitignore 既排除、跨部署持久）。

## §6 未取得清單（19.3）

1. zip 單根容忍度（§3——ours 剝根）。2. 主題檔案類型白名單（官方無窮舉）。
3. body url 效期數字。4. OnlineStoreThemeInput 完整欄位。5. processingFailed
的具體失敗原因取得法（官方無文檔）。6. admin 無效 zip 的 UI 錯誤文案。
7. 本輪 /themes 頁親驗（工具限制 V——§4）。
