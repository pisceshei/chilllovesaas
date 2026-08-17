# 12. 線上商店與內容（Themes / Pages / Menus / Search / SEO）

> 依 Shopify 官方文檔（shopify.dev Admin GraphQL 2026-07、theme architecture、help.shopify.com）考掘，取證日 2026-08-14。
> Liquid API 面（filters/objects/tags）已由 docs/research/25/26/27 覆蓋，本章聚焦**業務規則、狀態機、值域與上限**。
> 倉庫對照基準：docs/research/31/66/78/30、docs/specs/14。與我方裁定的差異集中在 §F。

## A. 領域物件模型

### A.1 Theme（佈景主題）

| 欄位 | 型別 | 說明 |
|---|---|---|
| id | ID! | `gid://shopify/OnlineStoreTheme/{id}` |
| name | String! | 商家可改名 |
| role | ThemeRole! | 見 §B.1（4 值） |
| prefix | String! | 主題檔案前綴 |
| processing | Boolean! | 建立/上傳後非同步處理中 |
| processingFailed | Boolean! | 處理失敗旗標 |
| themeStoreId | Int | Theme Store 來源 ID（自製主題為 null） |
| files | OnlineStoreThemeFileConnection | 主題檔案（可按 filenames 過濾） |
| createdAt / updatedAt | DateTime! | — |

（來源：Admin GraphQL `OnlineStoreTheme`，取證 2026-08-14）

**OnlineStoreThemeFile**：`filename`（唯一鍵）、`body`（union：`BodyText` / `BodyBase64` / `BodyUrl` 三形態）、`checksumMd5`、`contentType`（MIME）、`size`（bytes, UnsignedInt64）、`createdAt/updatedAt`。⇒ 我方 `theme_files` 表需存 checksum（AST cache key，31 §5 已規劃）與 content type；大檔（assets）走 blob URL 形態而非 inline text。（取證 2026-08-14）

**檔案樹**：Layout／Templates／Sections／Snippets／Assets／Config／Locales 七資料夾（78 §4 實測）＋ `blocks/`（theme blocks，2024+ 世代；可跨 section 重用、可巢狀；section schema 以 `{"type":"@theme"}` / `{"type":"@app"}` 宣告收納）。（來源：shopify.dev theme-blocks，取證 2026-08-14）

### A.2 JSON template（OS 2.0）

頂層四鍵：

| 鍵 | 型別 | 規則 |
|---|---|---|
| layout | string \| false | 預設 `theme.liquid`；`false`＝無 layout 渲染（同時關閉編輯器自訂） |
| sections | object（必填） | key＝section ID（僅英數）、value＝section 資料 |
| order | array（必填） | section ID 序列；必須與 sections 鍵一一對應、不得重複 |
| wrapper | string（選填） | 只允許 `div` / `main` / `section` 包殼 |

section 條目屬性：`type`（section 檔名去副檔名，必須存在於主題）／`disabled`（true＝可編輯不渲染，預設 false）／`settings`／`blocks`（block ID→{type, settings}）／`block_order`／`custom_css`（商家在編輯器加的 CSS，存於 **section 實例層**）。

**命名與互斥**：檔名必須是合法 template 類型（`product.json`、`product.alternate.json`）；**同名 `.liquid` 與 `.json` 不得並存**；不可做成 JSON 的 template：`gift_card`、`robots.txt`、`agents.md`、`llms.txt`、`llms-full.txt`（後三者為 2026 新增的 AI 爬蟲檔）。template 類型全集 11 種（78 §4：product／collection／list-collections／gift_card／page／cart／blog／article／search／password／404）＋ index 與 metaobject。（來源：shopify.dev json-templates，取證 2026-08-14）

**資料歸屬（settings_data vs template）**：
- `config/settings_schema.json`＝全域設定的 **schema**（有哪些設定）；
- `config/settings_data.json`＝全域設定的**值**：`current`（編輯器當前存檔值）＋`presets`（**每主題 ≤5 組**，格式同 current）＋`platform_customizations`（平台控制設定；編輯器全域 custom CSS 落在其 `custom_css`）；檔案上限 **1.5MB**；
- template JSON 裡的 section 資料**格式同 settings_data 但 template 私有**——不跨 template 共享；
- **preset 切換只覆寫「表現層設定」**（色彩/字型/checkbox/可見性），非表現層設定保留原值。
（來源：shopify.dev settings-data-json，取證 2026-08-14）⚠️ presets ≤5 與 Ella 實測 16 組（31 §6）矛盾——疑為新版規範 vs 舊主題 grandfathered，列 openQuestion。

**Section groups**：`sections/*.json`；`type` 值域【窮舉：3＋自訂】`header`／`footer`／`aside`／`custom.<name>`；`name` ≤50 字元；`sections`/`order` 可為空；layout 以 `{% sections 'header-group' %}` 渲染。**Context 覆寫**：`header-group.context.<context-string>.json` 引用父檔、供市場/B2B 差異（對應 31 §D `template_overrides`）。（取證 2026-08-14）

### A.3 內容物件

| 物件 | 關鍵欄位 | 關係 |
|---|---|---|
| Page | title、body(HTML!)、handle、isPublished、publishedAt、templateSuffix、metafields、translations | shop 1—N page |
| Blog | title、handle、commentPolicy(enum)、templateSuffix、tags（取自最近 200 篇文章）、feed(FeedBurner) | shop 1—N blog |
| Article | blog 所屬、title、body(HTML!)、summary(HTML)、handle、author(ArticleAuthor)、image、tags[String!]!、isPublished、publishedAt、templateSuffix、comments、commentsCount（預設 cap 10,000） | blog 1—N article |
| Comment | article 所屬、author(CommentAuthor!)、body/bodyHtml、ip、userAgent、status(CommentStatus!)、isPublished、publishedAt | article 1—N comment |
| Menu | title、handle、items（樹狀） | shop 1—N menu；item N—1 目標資源 |
| UrlRedirect | path!（舊路徑）、target!（新目標） | shop 1—N |

mutations 面：page/blog/article 各有 Create/Update/Delete（articleDelete 實證存在，payload 回 `deletedArticleId`）；comment 有 commentApprove／commentSpam／commentNotSpam／commentDelete；urlRedirect 有 Create/Update（另有 bulk delete 與 CSV import 系列）。（取證 2026-08-14）

**MenuItemType 值域【窮舉：13】**：`ARTICLE`／`BLOG`／`CATALOG`／`COLLECTION`／`COLLECTIONS`（全系列清單頁）／`CUSTOMER_ACCOUNT_PAGE`／`FRONTPAGE`／`HTTP`（自訂 URL）／`METAOBJECT`／`PAGE`／`PRODUCT`／`SEARCH`／`SHOP_POLICY`。（來源：Admin GraphQL `MenuItemType`，取證 2026-08-14）

**storefront filter 物件**：`type` 值域【窮舉：3】`boolean`／`list`／`price_range`；`presentation` 值域【窮舉：3，僅 list 型】`swatch`／`text`／`image`；`operator`＝AND|OR；list/boolean 型才有 `values`/`active_values`/`inactive_values`；price_range 型才有 `min_value`/`max_value`/`range_max`（=集合內最高商品價）；boolean 型有 `true_value`/`false_value`；全型有 `label`/`param_name`/`url_to_remove`。（來源：liquid objects/filter，取證 2026-08-14）

### A.4 Files（內容檔案域）

> admin 入口＝內容＞檔案（Content > Files）。本域在原稿全 15 章缺席，本節補齊。與 01 §B.3 商品 media **同構（同一 FileStatus enum）但獨立存在**：Files 是店級檔案庫；商品 media 是掛在商品上的引用。theme editor 圖片選取器、metafield `file_reference`、通知信 logo、favicon 全部掛在本域。

**File interface（Admin GraphQL）欄位**：`id`（`gid://shopify/{GenericFile|MediaImage|Video}/{id}`）／`alt`（String，≤512 字元）／`fileStatus`（FileStatus!，見 §B.6）／`fileErrors`（[FileError!]!，處理失敗原因）／`preview`（MediaPreviewImage 縮圖）／`createdAt`／`updatedAt`。（來源：Admin GraphQL File interface，取證 2026-08-14）

**檔案類型【三分】**（實作 File 的具體型別）：

| 型別 | 內容 | 型別專屬欄位 |
|---|---|---|
| MediaImage | 圖片（JPEG/PNG/WEBP/HEIC/GIF） | image（尺寸＋CDN URL）、mimeType、originalSource |
| Video | Shopify 代管影片（MOV/MP4/WEBM） | sources（多碼率轉檔輸出）、duration、preview |
| GenericFile | 泛型檔案（PDF/CSV/JSON…，禁 HTML） | url（CDN URL）、mimeType、originalFileSize |

（ExternalVideo／Model3d 屬商品 media 域（01 §B.3）；官方 File interface 頁未明列其是否實作 File ⚠️ 官方未明文，待實測。）

**mutations 面**：
- `fileCreate`：≤**250 檔/次**；input＝`contentType` 值域【窮舉：5】`IMAGE`／`VIDEO`／`EXTERNAL_VIDEO`／`MODEL_3D`／`FILE`＋`originalSource`（外部 URL 或 staged upload 的 resourceUrl）＋`filename`＋`alt`＋`duplicateResolutionMode` 值域【窮舉：3】`APPEND_UUID`（撞名補 UUID）／`RAISE_ERROR`（撞名報錯）／`REPLACE`（撞名覆蓋；⚠️ 預設值官方頁未明文，待實測）。
- `fileUpdate`：前置條件＝檔案必須 **READY**；`filename` 副檔名必須與原檔一致；`originalSource`（換內容）與 `previewImageSource`（換影片縮圖）**不可同次更新**；影片/3D 只可改 alt 與商品引用（`referencesToAdd`/`referencesToRemove`——移除引用＝從該商品 media gallery 移除）；圖片/泛型檔可換 originalSource、filename、alt。
- `fileDelete`：`fileIds!`→`deletedFileIds`；**永久、不可復原**；被商品引用的檔案刪除時**自動解除引用並重排剩餘 media 位置**（不是報錯擋下）；處理中（PROCESSING）的檔案拒刪。
- 錯誤走 `FilesUserError{field,message,code}`，已證實 code：`INVALID`／`UNACCEPTABLE_ASSET`（格式不受理）／`ALT_VALUE_LIMIT_EXCEEDED`／`FILE_DOES_NOT_EXIST`。
（來源：Admin GraphQL fileCreate/fileUpdate/fileDelete，取證 2026-08-14）

**file_reference metafield**（15 章 reference 12 型之一）：型別 `file_reference` 與 `list.file_reference`；預設接受 GenericFile，可加 validation 放寬其他型（官方例：Image）⚠️ validation 參數名官方頁未明文，待實測；值＝`gid://shopify/MediaImage/{id}` 等。（來源：shopify.dev metafield data types，取證 2026-08-14）

**CDN URL 語義**：檔案 READY 後取得公開 CDN URL（本尊網域＝cdn.shopify.com，URL 含檔名）；官方明文警告勿上傳機密/個資檔案 ⇒ Files 語義上一律視為公開資源，**無存取控制**（⚠️ 密碼保護是否遮 CDN URL 官方未明文，按上述警告推定不遮，待實測）。⚠️ URL 版本參數與刪除後 CDN 快取殘留時間官方未明文，待實測。我方 CDN 策略見 §F 差異 #13。

## B. 狀態機

### B.1 Theme role（4 態）

值域【窮舉】：`MAIN`（前台現行）／`UNPUBLISHED`（草稿庫）／`DEMO`（試用主題，購買前）／`DEVELOPMENT`（CLI 開發暫時主題）。（Admin GraphQL ThemeRole，取證 2026-08-14）

| 現態 | 動作 | 前置條件 | 副作用 | 次態 |
|---|---|---|---|---|
| （無） | themeCreate／上傳 zip／Theme Store 加入／AI 生成／GitHub/CLI push | 主題庫未達上限（見 §C.1） | `processing=true` 非同步處理；入「草稿佈景主題」區 | UNPUBLISHED |
| （無） | Theme Store 試用 | 可同時試用 ≤19 個付費主題 | 標記「Theme trial」；**不可編輯代碼、不可用 AI 生成** | DEMO |
| DEMO | 購買 | 付款 | 自訂內容保留（"Any customizations…are saved"） | UNPUBLISHED（或直接發布→MAIN） |
| UNPUBLISHED | themePublish／admin「發佈」 | 同店僅一個 MAIN；⚠️ processing 中可否發布未見官方明文 | **原 MAIN 自動轉 UNPUBLISHED**（回草稿區，客製不失）；前台立即切換 | MAIN |
| MAIN | （被另一主題發佈取代） | — | 回草稿區 | UNPUBLISHED |
| UNPUBLISHED | themeDuplicate／admin「複製」 | 未達主題數上限 | 新主題名「Copy of {原名}」，含全部客製；不含商店內容（商品/選單/Files） | 新 UNPUBLISHED |
| UNPUBLISHED/DEMO | 刪除 | 不可為 MAIN | **永久動作、不可復原** | （消滅） |
| DEVELOPMENT | CLI session | — | 暫時預覽用 ⚠️（可否發佈官方參考頁未明文，列 openQuestion） | — |

`processing=true → false`（成功）或 `processingFailed=true`（失敗；檔案不完整不可用）。無孤兒態：DEMO 出口＝購買或刪除；DEVELOPMENT 出口＝CLI 生命週期結束。
（來源：help managing-themes／adding-themes／duplicating-themes、Admin GraphQL themePublish，取證 2026-08-14）

### B.2 編輯器儲存語義

- undo/redo 只作用於**未儲存**的變更；**儲存後 undo/redo 棧清空**（官方明文 "after you save…no longer redo or undo"）。
- 編輯 MAIN 主題並儲存＝直接生效於前台（⚠️ 官方 features-overview 頁未逐字明文「立即上線」，但無任何 draft/publish 中介層記載；實測面由 66/24 支持）。編輯 UNPUBLISHED 主題＝儲存只影響該草稿主題。
- 編輯器頂列：sections／theme settings／app embeds 三面板切換＋template 切換選單＋裝置預覽切換＋分享預覽連結＋undo/redo/儲存。
- 全域 custom CSS 寫入 `settings_data.platform_customizations.custom_css`；section 級 custom CSS 寫入 template JSON 的 section 實例。
（來源：help theme-editor features-overview、settings-data-json，取證 2026-08-14）

### B.3 Page / Article 可見性（2 態＋排程）

值域【窮舉：2】：`Visible`／`Hidden`。轉移：Hidden→（設定未來發布日期，日曆選擇）→到期系統自動轉 Visible；任何時刻可手動雙向切換；支援批次「設為可見/隱藏」。API 面＝`isPublished`＋`publishedAt`（未來時間＝排程）。刪除頁面＝硬刪，**同時刪除引用它的選單項目**（官方明文副作用）。（來源：help pages，取證 2026-08-14）

### B.4 Comment 狀態機

Blog.commentPolicy 值域【窮舉：3】：`CLOSED`（不可留言）／`MODERATED`（留言需審核）／`AUTO_PUBLISHED`（直接顯示）。（Admin GraphQL CommentPolicy，取證 2026-08-14）

CommentStatus 值域【窮舉：5】：`PENDING`／`PUBLISHED`／`UNAPPROVED`／`SPAM`／`REMOVED`。（Admin GraphQL CommentStatus，取證 2026-08-14）

| 現態 | 動作 | 前置條件 | 副作用 | 次態 |
|---|---|---|---|---|
| （無） | 訪客送出留言 | policy≠CLOSED | policy=MODERATED→PENDING；policy=AUTO_PUBLISHED→PUBLISHED；Shopify 自動 spam 偵測可攔截→SPAM | PENDING / PUBLISHED / SPAM |
| PENDING/UNAPPROVED | commentApprove／admin 核准 | — | 前台可見 | PUBLISHED |
| 任意 | commentSpam／標記垃圾 | — | 前台移除、admin 仍可見 | SPAM |
| SPAM | commentNotSpam／取消垃圾 | — | help 明文「自動標為已核准」並回報 Shopify 改進過濾器；⚠️ dev 文檔則稱「回到審核佇列」——兩源矛盾，落地取 help（→PUBLISHED） | PUBLISHED（⚠️或 PENDING） |
| 任意 | commentDelete／刪除 | — | **不可復原** | REMOVED（消滅） |

🔴 官方明文：**PUBLISHED 不可退回未核准**——已核准留言只能刪除或標 spam，沒有「撤核准」動作（UNAPPROVED 是入向狀態不是可達目標）。（來源：help managing-comments，取證 2026-08-14）

### B.5 Password protection（2 態）

`enabled`（勾選＋密碼＋訪客訊息）↔ `disabled`。入口＝線上商店＞偏好設定＞Store access。**試用期不可解除**：必須先選定價方案才能取消密碼保護。enabled 期間：搜尋引擎只能見密碼頁（全站等效 noindex）；sitemap 對外不可讀。密碼頁視覺編輯在佈景主題編輯器，可編 section【窮舉：3】：密碼頁首／電子郵件訂閱橫幕／密碼頁尾（可再加 section/block）。（來源：help password-page，取證 2026-08-14）

### B.6 File 處理狀態機（4 態）

FileStatus 值域【窮舉：4】：`UPLOADED`（已上傳未處理）／`PROCESSING`（處理中）／`READY`（可顯示）／`FAILED`（處理失敗）。（Admin GraphQL FileStatus，取證 2026-08-14）

| 現態 | 動作 | 前置條件 | 副作用 | 次態 |
|---|---|---|---|---|
| （無） | fileCreate（外部 URL 或 staged resourceUrl） | 格式門檻（§C.7）／大小門檻（**§C.1 上限值總表**——（2026-08-17 更正，PR #52 第 21 輪）：原引 §C.7，該節通篇無尺寸；尺寸在 §C.1（圖片 ≤20MB／影片 ≤1GB／泛型 ≤20MB），同檔 :312 配額預檢引法為準）；≤250 檔/次；🔴 **外部 URL 抓取走平台 SSRF 防護**：scheme 僅 http/https、DNS 解析後拒 loopback/private/link-local/metadata IP **且連線時釘選已驗 IP（或 connect 時重驗）——僅驗 DNS 結果擋不住 DNS rebinding：驗證時回公網 IP、worker 二次解析時換私網 IP** （2026-08-17 更正，PR #52 第 8 輪）、redirect 每跳重驗、下載大小上限＝`outbound_http.file_fetch_download_bytes_max`、逾時＝`outbound_http.file_fetch_timeout_seconds`（config/limits.yml，鐵律 6——與 §C.7 業務規則列同一鍵源，（2026-08-17 更正，PR #52 第 21 輪）：原「＝§C.7 門檻＋逾時」①引節錯（尺寸在 §C.1）②逾時無鍵③與 §C.7 列答案不一）；staged resourceUrl 僅限自家 bucket host（2026-08-17 更正（PR #52 第 7 輪）：原契約允許租戶指向內網/雲 metadata 任意抓取落檔） | 非同步抓取來源 | UPLOADED |
| UPLOADED | 系統開始處理 | — | 圖片轉檔/影片多碼率轉碼 | PROCESSING |
| PROCESSING | 處理完成 | — | 產出 CDN URL（Video 產出 sources＋preview） | READY |
| PROCESSING | 處理失敗 | — | `fileErrors` 填入原因；不可用 | FAILED |
| READY | fileUpdate(originalSource) 換內容 | 僅 image/generic；副檔名不變 | 重新處理 ⚠️（是否回 PROCESSING 官方未逐字明文，按同構推定，待實測） | PROCESSING ⚠️ |
| READY/UPLOADED/FAILED | fileDelete | 非 PROCESSING（處理中拒刪） | **永久**；自動解除商品引用並重排 media | （消滅） |

- 與 01 §B.3 商品 media 狀態機**同構（共用 FileStatus enum）但生命週期獨立**：Files 側刪檔連動解除商品引用；⚠️ 反向（刪商品是否留下 Files 庫檔案）官方未明文，待實測。
- 無孤兒態：FAILED 出口＝刪除或（image/generic）換 originalSource 重試；輪詢面＝client 查 `fileStatus` 直到離開 PROCESSING（⚠️ files/* webhook topic 本輪未取證，落地前補查）。
（來源：Admin GraphQL FileStatus／fileUpdate／fileDelete，取證 2026-08-14）

## C. 業務規則與不變量

### C.1 上限值總表（全部應落 `config/limits.yml`）

| 項目 | 值 | 來源（取證 2026-08-14） |
|---|---|---|
| 主題庫上限 | Basic/Grow/Advanced＝**20**；Plus＝**100**；Starter＝僅 Spotlight | help adding-themes |
| 同時試用付費主題 | ≤19 | help adding-themes |
| sections／template（含 section group） | ≤25 | shopify.dev json-templates、section-groups |
| blocks／section | ≤50 | 同上 |
| blocks／template（推導） | 25×50＝1,250（78 §4 同值） | 推導＋78 |
| JSON templates／theme | ≤1,000 | shopify.dev json-templates |
| settings_data.json 大小 | ≤1.5MB | shopify.dev settings-data-json |
| presets／theme | ≤5 ⚠️（Ella 16 組矛盾） | 同上 |
| section group name | ≤50 字元 | shopify.dev section-groups |
| theme blocks 巢狀 | ≤8 層（78 §4；官方 theme-blocks 頁未給數字 ⚠️） | 78＋shopify.dev |
| 選單數／店 | ≤1,000 | help drop-down-menus |
| 選單項目／選單 | ≤10,000（含子項；有子項的項目各自計數） | 同上 |
| 選單巢狀 | 頂層下**再 2 層＝共 3 層**；footer 只顯示頂層 | 同上 |
| URL redirects | 一般方案 ≤100,000；Plus ≤20,000,000 | help url-redirect |
| storefront filters | ≤25 個 | shopify.dev storefront-filtering |
| predictive search limit | 1–10，預設 10；`limit_scope`＝all\|each | shopify.dev predictive-search |
| 前綴搜尋相符上限 | 50 筆（78 §6） | help（78 轉錄） |
| SEO 頁面標題 | 輸入上限 70 字元（建議 ≤60） | help adding-keywords |
| SEO meta description | 建議 160 字元 | 同上 |
| commentsCount 預設 cap | 10,000 | Admin GraphQL Article |
| themeFilesUpsert | ≤50 檔／次 | Admin GraphQL themeFilesUpsert |
| fileCreate 批次 | ≤250 檔／次 | Admin GraphQL fileCreate |
| 檔案 alt 文字 | ≤512 字元 | 同上 |
| 圖片檔 | ≤20MB；≤20 megapixels；長寬比 100:1–1:100 | help file-uploads |
| 影片檔 | ≤1GB；0.25 秒–10 分鐘；寬高 100–4096px；≤120fps | 同上 |
| 泛型檔案 | ≤20MB | 同上 |
| Files 總儲存空間 | 按方案分級（Basic 100GB…Plus 1TB；影片另計配額）⚠️ 各級精確值以 help 現行表為準 | 同上 |
| 影片＋3D 檔數／店 | 按方案 250–100,000 | 同上 |

### C.2 搜尋

**可搜尋資源【窮舉：3】**：product／page／article（完整頁 `?type=` 值域即此三值，預設全搜）。collection 只出現在 predictive suggestions，不在完整搜尋頁。

**完整頁 `/search` 參數**：`q`（必）／`type`／`page`／`options[prefix]`＝`last`|`none`（預設 last：只對**最後一個詞**做前綴比對）／`options[unavailable_products]`＝`show`|`hide`|`last`（預設 last：售罄商品沉底）／`sort_by`＝`relevance`|`price-ascending`|`price-descending`（價格排序時非商品結果移至陣列尾）。

**搜尋語法【窮舉】**（78 §6＋dev）：空白＝AND（預設）／`OR`／`-`＝NOT／自動前綴（僅末詞）／雙引號片語／`欄位:字詞`。商品可搜欄位 8：body、product_type、tag、title、variants.barcode、variants.sku、variants.title、vendor；page 3：author、body、title；article 4：author、body、tag、title。

**Predictive search**：
- 端點雙形：`/{locale}/search/suggest.json?q=`（JSON）與 `/{locale}/search/suggest?q=&section_id=`（HTML section rendering）。
- `resources[type]` 值域【窮舉：5】`product`／`page`／`article`／`collection`／`query`（查詢建議），預設 `query,product,collection,page`。
- `resources[options][fields]` 值域＝上述 9 欄位，預設 `title,product_type,variants.title,vendor`。
- 回應形：`resources.results.{queries,products,collections,pages,articles}`；每類 ≤10。
- **容錯規則**：拼字容錯 1 字元、**前 4 字母必須精確**；部分詞比對僅末詞；collection 建議只用商店主語言。
- 錯誤碼【窮舉】：422（參數不合法）／417（不支援的 buyer locale）／429（限流，含 Retry-After）／404（section 不存在，僅 HTML 形）。
（來源：shopify.dev predictive-search／search，取證 2026-08-14）

### C.3 Collection filters

- 資料源【窮舉】：availability／category／price／tags／product_type／vendor／變體選項／metafields（型別限 single_line_text_field 及其 list、數字型、boolean）。事前須在 admin（本尊＝Search & Discovery app）定義才可用。
- **組合邏輯**：跨 filter＝AND；同 filter 多值＝OR。
- URL 文法：`filter.{p|v}.{attribute}[.{scope}]={value}`；`p`＝商品層、`v`＝變體層；多值＝逗號或重複參數；價格＝`filter.v.price.gte=20.40`／`.lte=`（**十進位主單位**，非 cents——見 §F 差異）。
- 套變體 filter 時商品卡的 `featured_media` 與 `url` 切換為首個相符變體。
（來源：shopify.dev storefront-filtering，取證 2026-08-14）

### C.4 SEO

- **Canonical**：商品頁 `?variant=` 一律 canonical 至 `/products/{handle}` 基底；collection 內商品路徑 canonical 至商品基底 URL；**篩選後 collection URL canonical 至未篩選基底**；主題經 `{{ canonical_url }}` 輸出（值由平台計算）。⚠️ 分頁 `?page=n` 的 canonical 官方參考頁未明文（repo 30 §1.3 已裁定 self-canonical），列 openQuestion。（取證 2026-08-14）
- **Sitemap**：`/sitemap.xml`＝index，分連 products／collections／blogs（articles）／pages 子 sitemap；**內容變更自動更新**；products 片含主圖；**每個網域（含國際網域）各自生成**、需分別提交；密碼保護開啟時外部讀不到。排除規則：`seo.hidden` 資源與未發布資源不入 sitemap。⚠️ 單檔 URL 分片閾值官方未明文。（來源：help find-site-map，取證 2026-08-14）
- **noindex 雙軌**（78 §6 的機制根源）：
  1. 系統 metafield `namespace=seo, key=hidden`，型別 Integer，值域【窮舉】＝1：同時從**搜尋引擎＋sitemap＋店面搜尋**隱藏，直連 URL 仍可訪問；
  2. 主題塞 `<meta name="robots" content="noindex">`：只擋外部搜尋引擎，**店面搜尋仍可見**。
  （來源：help hide-a-page-from-search-engines，取證 2026-08-14）
- **robots.txt.liquid**：位於 templates/、**不可為 JSON**；經 `robots.default_groups`（group→user_agent＋rules＋sitemap）渲染；預設規則由平台**持續更新**（勿寫死純文字）；預設 Disallow 含 /admin、/cart、/checkout、/collections/*+*、/search、/policies/（78 §4）；可自訂 4 類【窮舉】：增删 allow/disallow 規則、crawl-delay、額外 sitemap URL、封鎖特定爬蟲；官方標明自訂屬 unsupported；**檔案綁在已發布主題**——換主題＝換 robots 規則。（取證 2026-08-14）
- **SEO 編輯區**：products／collections／pages／blog posts 皆有（頁標題／meta description／URL handle 三欄）；首頁的在偏好設定。改 handle 時提供「建立 URL redirect」勾選。

### C.5 URL redirects

- **觸發條件＝原 URL 渲染不出頁面**（help 原文措辭「404 時觸發」；**含 unpublish 資源的 410 形**——D.5 明文允許商家設 301 取代預設 410，「404」讀作「資源不可解析」而非排除 410（2026-08-17 更正，PR #52 第 11 輪）：原句「只在 404」與 D.5 互斥）；URL 仍能渲染出頁面（含 collection tag 篩選 URL）則 redirect 不生效。回應＝301（明文：被瀏覽器與搜尋引擎快取，刪除後不會立即失效）。
- path 保留字首【窮舉，不可作為來源】：`/apps`、`/application`、`/cart`、`/carts`、`/orders`、`/shop`、`/services`、`/products`、`/collections`、`/collections/all`、`/collections/vendors`、`/collections/types`、`/a/`、`/community/`、`/tools/`。
- target 可為相對路徑或完整外部 URL；`.html` 結尾與去 `.html` 版本視為同一 URL 不可互轉；query string 行為不保證；國際市場子資料夾：根路徑 redirect 自動套用到全部子資料夾，個別子資料夾差異需逐條建立。
- 管理面：CSV 匯入/匯出、批次刪除、儲存篩選檢視。
（來源：help url-redirect，取證 2026-08-14）

### C.6 併發要害與邊界

- **發布互斥**：任一時刻恰一個 MAIN——publish 必須**先鎖店級序列化列（或對現任 MAIN 行 `FOR UPDATE` 條件式降級，影響列數 ≠1 即 abort 重試）**，再於同一 transaction 內原子雙寫（新→MAIN、舊→UNPUBLISHED）。「各自包 transaction 的原子雙寫」**不是**併發防線——兩交易同讀舊 MAIN、各自降級再自升，提交後雙 MAIN（總綱 X-30）；spec 14 §F2 的單 transaction 規劃須含此鎖（（2026-08-17 更正，PR #52 第 19 輪）：原文止於原子雙寫，正是 X-30 第 18 輪判為不足的機制）。
- **編輯器併發**：本尊未見官方衝突機制明文（⚠️）；我方裁定＝`lock_version` 後存者收衝突（14 §F3），保留。
- **themeFilesUpsert 非同步**：大批次回 `job`，client 必須輪詢完成才可視為寫入成功——我方 editor 儲存管線同理（先寫後渲染，失敗回滾）。
- 邊界：order 引用不存在 section ID＝校驗失敗；section type 不存在於主題＝失敗；同名 .liquid/.json 並存＝失敗；redirect 指向仍可渲染的 URL＝靜默不生效（**不是錯誤**，落地要在 UI 提示）；刪頁面連動刪選單項（跨模組副作用）。

### C.7 Files（內容檔案）業務規則

- **格式門檻**：試用方案白名單【窮舉：10】JS／CSS／GIF／JPEG／PNG／JSON／CSV／PDF／WebP／HEIC；付費方案＝任何格式**除 HTML**。我方落地同樣必須擋 HTML（公開 CDN 上的 stored-XSS／phishing 面）；⚠️ SVG 是否受理、以 image 還是 generic 處理，官方未明文，待實測。
- **檔名保留規則**：不得以 `.` 開頭；不得以下列字尾結束【窮舉：9】`pico`／`icon`／`thumb`／`testing`／`small`／`compact`／`medium`／`large`／`grande`——這組是本尊圖片尺寸變體 URL 後綴，佔用即衝突。我方若沿用尺寸後綴式 CDN URL，此保留清單必須同步落地。
- **撞名解決**＝`duplicateResolutionMode` 三值（§A.4）；admin UI 上傳的行為對應哪一值 ⚠️ 官方未明文，待實測（實測店可驗）。
- **兩段式上傳是大檔唯一路徑**：`fileSize` 對 VIDEO／MODEL_3D 為必填（stagedUploadsCreate 會據此預檢配額）；一般檔案可直接給外部 URL 由平台抓取——🔴 `originalSource` 是 tenant 控制的出站目的地，**平台抓取必過 SSRF 防線**（同 webhook 投遞政策，總綱 A2 的細化）：scheme 白名單（https）、DNS 解析後**與連線時**雙重拒 private/link-local/metadata 位址、禁 redirect、下載大小上限＝`outbound_http.file_fetch_download_bytes_max`、逾時＝`outbound_http.file_fetch_timeout_seconds`（config/limits.yml，鐵律 6；（第 20 輪更正）：原句把時間上限也等號綁到 bytes 鍵、時間無鍵）；**本上限僅適用外部 URL 抓取路徑**——staged `resourceUrl` 走自家 bucket host 白名單，尺寸於 `stagedUploadsCreate` 依 §C.1 預檢（§D.7-5），影片 ≤1GB 不受此 20MB 抓取上限影響（（第 22 輪範圍子句）：值對齊 §C.1 後若不限定範圍，>20MB 的影片經 staged 路徑也會被抓取上限誤殺）——否則已認證商家可讓 worker 抓 loopback／內網服務／cloud metadata 並把回應存成檔案（2026-08-17 更正，PR #52 第 18 輪）。
- **刪除語義**：永久不可復原；商品引用自動解除（§B.6）；⚠️ 被 metafield `file_reference`／theme 設定（favicon、section 圖片）引用時是否阻擋或警示，官方未明文——admin 提供「Used in」篩選供刪前自查，我方落地必須做**引用計數表**（file_usages：file_id×引用者多型），刪除確認框列出引用清單。
- **多租戶**：`files` 表帶 `shop_id`＋複合索引 `(shop_id, filename)`（filename 撞名解決以店為界）；CDN 路徑帶店識別，跨店引用檔案 ID 必須被拒（同 §C.6 隔離原則）。
（來源：help file-uploads、Admin GraphQL fileCreate/stagedUploadsCreate，取證 2026-08-14）

## D. 關鍵流程

### D.1 主題安裝（zip 路徑，對應我方 IN 線）

1. 商家上傳 zip（或 Theme Store／AI 生成 ≤3 個／GitHub／CLI）。
2. 系統建 theme 記錄，`role=UNPUBLISHED`、`processing=true`，非同步解壓＋驗證。🔴 解壓**前/中強制安全邊界**（2026-08-17 更正，PR #52 第 18 輪——商家可控 zip 不設限＝zip-slip 逃逸主題目錄、zip bomb 打爆 worker 磁碟/記憶體）：entry 路徑 canonical 化後必須落在主題目錄內（拒 `../` 穿越）、拒 symlink/hardlink entry、entry 數/單檔解壓大小/總解壓大小/壓縮比上限（上限值引 `config/limits.yml`，鐵律 6——theme_import 鍵組隨本管線落地時建，出處＝本條），**邊 streaming 邊計量**，任一超限即中止＝`processingFailed`。
3. 成功→`processing=false`，入草稿區可預覽/自訂；失敗→`processingFailed=true`（檔案不完整，不可發布）。
4. 失敗分支：主題數達上限（20/100）→拒收，要求先刪除；zip 非法→processingFailed。
（我方對應：31 §4 IN 線加了 theme-check＋相容報告＋授權聲明 gate——本尊沒有授權 gate，這是我方因鐵律 9 加的。）

### D.2 發布

1. 操作者在主題庫（或編輯器內）按「發佈」→ 確認 modal。
2. 系統原子切換：新主題→MAIN、原 MAIN→UNPUBLISHED（客製保留、可隨時發回）。
3. 前台立即改用新主題；robots.txt.liquid、alternate templates 全部隨主題切換。
4. 事件：`themes/publish` webhook（＋我方：快取雪崩預熱 job，14 §F1）。
5. 失敗分支：DEMO 未購買不可發布；⚠️ processing 中發布行為未明文。

### D.3 編輯器儲存（本尊語義）

1. 商家改設定/增删 section→前端維持未存變更（undo/redo 可用）。
2. 按儲存→寫入 template JSON／settings_data.json；**undo 棧清空**；編輯 MAIN＝立即生效。
3. 我方差異：31 §ED5/ED6 op-stack＋autosave 草稿（30s）＋`theme_drafts` 表——本尊無 autosave 證據（⚠️），此為我方增強，需在 UI 明示「草稿未發布」語義以免商家誤解與本尊不同。儲存管線根資料結構已裁定＝op-stack（與 14 §F3 快照棧的衝突裁定見 §F「裁定 #5」）。

### D.4 留言審核

1. 訪客在 article 頁送出留言（policy=CLOSED 時表單不渲染）。
2. 系統 spam 偵測：可疑→SPAM（前台隱藏、admin 可見）。
3. 正常路徑：MODERATED→PENDING（等待核准）；AUTO_PUBLISHED→PUBLISHED。
4. 商家於 內容＞部落格貼文＞管理留言：核准（→PUBLISHED）／標 spam／取消 spam（→PUBLISHED＋回報過濾器）／刪除（不可復原）。
5. 不變量：PUBLISHED 無退回未核准的轉移。

### D.5 Redirect 解析（前台請求管線）

1. 請求進入 storefront 路由；能解析出資源→正常渲染（**redirect 不參與**）。
2. **資源不可用分支（404 與 unpublish 的 410 皆含）**→查 `url_redirects`（path 精確比對）→命中回 301 至 target；未命中依形態回 404 頁或 410（2026-08-17 更正（PR #52 第 7 輪）：原鏈只在 404 分支查 redirect，unpublish 資源先終止於 410、商家設的 301 永不生效——30 §1.3 明文允許以 301 取代預設 410（（2026-08-17 更正，PR #52 第 9 輪）：原引 §9-5 錯節——該節只有 410 紀律本身））。
3. 我方落地：查詢掛在**資源不可用（404／unpublish 410）handler 前**（specs 13-F2/14-F5 已定；範圍同 C.5 分支（2026-08-17 更正，PR #52 第 13 輪）），需帶 shop_id 複合索引 `(shop_id, path)`。

### D.6 Predictive search 請求

1. 前台輸入→theme JS 打 `/search/suggest.json?q=&resources[type]=…`（section rendering 形則回 HTML 片段）。
2. 限流超標回 429＋Retry-After；q 過短由主題自行節制（本尊未明文最小長度）。
3. 完整搜尋頁提交→`/search?q=`＋分頁；`terms` 高亮由主題 highlight filter 處理。

### D.7 檔案上傳（stagedUploadsCreate 兩段式）

1. client 呼叫 `stagedUploadsCreate`（input：`filename`＋`mimeType`＋`resource`＋`httpMethod`；`fileSize` 對 VIDEO／MODEL_3D 必填）→ 回 `StagedMediaUploadTarget`：`url`（上傳端點）＋`parameters`（一次性簽名鍵值對）＋`resourceUrl`（上傳完成後的取用 URL）。`resource` 值域含 PRODUCT_IMAGE／VIDEO／MODEL_3D／COLLECTION_IMAGE／SHOP_IMAGE／URL_REDIRECT_IMPORT 等（⚠️ 全集本輪未逐值取證，落地前對 enum 頁補齊）。
2. client 帶 `parameters` 將檔案直傳 `url`（⚠️ 簽名有效時長官方未明文，待實測）。
3. 呼叫 `fileCreate(originalSource: resourceUrl)`（或 productUpdate 掛 media）→ UPLOADED → 非同步 PROCESSING → READY／FAILED；client 輪詢 `fileStatus`。
4. 失敗分支：格式不受理→`UNACCEPTABLE_ASSET`；alt 超長→`ALT_VALUE_LIMIT_EXCEEDED`；來源 URL 非法→`INVALID`；處理失敗→FAILED＋`fileErrors`。
5. 我方落地：staged 端點＝我方物件儲存 presigned POST（同構）；theme editor 圖片選取器與商品 media 上傳共用此管線，入庫後統一進 Files 庫；本尊 resource 細分是否合併為 FILE/IMAGE/VIDEO 三值＝實作時裁定，但**配額預檢（§C.1 大小/儲存上限）必須在第 1 步做**，不得等抓取後才失敗。
（來源：Admin GraphQL stagedUploadsCreate／fileCreate，取證 2026-08-14）

## E. 跨模組耦合

- **發出事件（本尊 webhook topics）**：`themes/create`、`themes/publish`、`themes/update`、`themes/delete`（⚠️ pages/articles 與 files 的 webhook topic 面本輪未逐一取證，落地前補查）。我方 outbox 事件至少要有：theme.published（→快取失效＋預熱）、theme.processing_finished、page.published/unpublished、article.published、comment.status_changed、redirect.created/deleted（→路由快取失效）、menu.updated（→前台 header 快取失效）、file.ready/file.failed（→等待中的引用方解鎖）、file.deleted（→引用方失效＋CDN purge）。
- **消費依賴**：
  - Themes ⇢ Products/Collections（section 設定引用資源 ID——**引用需驗 shop_id 歸屬**，14 §F2 坑）；
  - Menus ⇢ 全內容域（13 種 link 型別）；**刪除 page 連動刪 menu item**（本尊硬行為，我方要在刪除確認框揭示）；
  - Filters ⇢ 商品/變體/metafields 定義（admin 配置）＋ Markets（價格 filter 按 presentment 幣別）；
  - SEO/sitemap ⇢ 商品發布狀態（unpublish→410 紀律，30 §9-5）＋ Markets（per-domain sitemap＋hreflang）；
  - robots.txt ⇢ 已發布主題（換主題換規則——我方要在發布確認流程警示 robots 差異）；
  - Password page ⇢ 訂價方案狀態（試用不可解除）；
  - Files ⇢ 全域消費者：theme editor 圖片選取器（從 Files 庫選取或現場上傳入庫）、theme settings favicon、通知信 logo、metafield `file_reference`（15 章）、RTE 內嵌圖片、商品 media（01 §B.3，同構共用 FileStatus 但生命週期獨立）——刪檔連動面見 §B.6/§C.7，我方需引用計數表支撐「Used in」檢視與刪除確認；
  - Checkout 網域：2017-07 起 checkout 跑在**商店主網域**（有自訂網域＝自訂網域、無＝myshopify.com），不再導去 checkout.shopify.com；⚠️ 第三方文章稱非 Plus 的 checkout 停在 myshopify 網域，與官方 blog 矛盾——落地前以實測店驗證。
- **架構邊界**：本尊把 `/themes` 與 `/online_store/preferences` 做成內嵌 sales-channel app（跨域 iframe，78 §0.2）；我方是否照抄此邊界＝遞延裁定 71-R9-V1。

## F. 落地對應

**對應倉庫文件**：specs/14（storefront＋editor 規格）、research/31（工程計畫 R/E/ED/IN/D 線）、research/66（Ella 資料模型解剖）、research/78（admin 按鈕級 teardown）、research/30（SEO/feed）、research/25/26/27（Liquid API 面）、specs/71 §F（V 項登記簿）。

**本尊 vs 我方裁定 差異清單**：

| # | 面向 | 本尊 | 我方裁定 | 出處 |
|---|---|---|---|---|
| 1 | 金額 | filter 價格參數、JSON-LD price 皆十進位主單位字串 | 內部一律 integer cents（`Money::Storage`）；**渲染層出十進位一律經 `Money::Decimal`**，filter URL 解析入站立即轉 cents，禁止裸字串比價 | 鐵律 3、65 |
| 2 | JSON-LD 一致性 | feed 與頁面標記須同值（GMC 硬規） | 同一 rollup/同一 formatter 生成（數字同源鐵律 7 延伸） | 30 §6.2 |
| 3 | 稅務/法域 | 全球單一行為 | robots/sitemap/JSON-LD 為核心；稅務憑證、發票欄位走 jurisdiction pack | 鐵律 11 |
| 4 | 轉址入口 | 內容區（選單頁頂鈕） | 已對齊本尊（71-R9-STRUCT1 修正案） | 78 §7 |
| 5 | Undo/redo | 儲存即清棧、無 autosave 證據 | op-stack＋30s autosave 草稿（增強）；UI 必須標示草稿語義。**儲存模型衝突已裁定＝op-stack**，見本表下方「裁定 #5」 | 31 ED5/ED6；14 §F3 依裁定待修訂 |
| 6 | 編輯器併發 | 未明文 | `lock_version` 後存者衝突提示 | 14 §F3 |
| 7 | 主題授權 | 無安裝 gate | 上傳 zip 需授權聲明 gate（鐵律 9） | 31 §4 |
| 8 | 搜尋引擎 | 專有引擎＋容錯 | MySQL FULLTEXT ngram demo 級，介面照抄，`Search::Provider` 抽象留升級口 | 14 §F4 |
| 9 | 線上商店邊界 | 內嵌 sales-channel app | 是否照抄＝遞延 71-R9-V1 | 78 §0.2 |
| 10 | 選單巢狀 | 共 3 層（頂＋2）、1,000 選單、10,000 項 | 14 §F5 寫「巢狀 ≤3 層」＝對齊；上限三值需落 limits.yml | 本章 §C.1 |
| 11 | redirect 觸發 | 資源不可渲染時（help 措辭「404」；unpublish 410 亦查，D.5（2026-08-17 更正，PR #52 第 11 輪）） | 同本尊（掛**資源不可用（404／unpublish 410）handler 前**，同 :298 落地句（2026-08-17 更正，PR #52 第 14 輪）：原「404 handler 前」舊錨點）；UI 加「來源仍可訪問則不生效」提示（本尊只寫在 help） | 14 §F5 |
| 12 | presets | 官方 ≤5 | 待裁定：golden theme Ella 有 16 組，安裝管線不得拒收（相容優先），新建主題按 ≤5 | 本章 openQuestion |
| 13 | Files CDN | cdn.shopify.com 公開 URL、無存取控制、尺寸變體後綴保留字尾 | 我方 CDN 網域策略＝M0 基建裁定項；檔名保留字尾（§C.7 九值）同樣封鎖以保留尺寸後綴語義；儲存/檔數上限落 limits.yml 按方案分級；HTML 一律拒收 | 本章 §A.4/§C.7 |

**裁定 #5（編輯器 undo/儲存模型；2026-08-14 本章補強輪裁定）**：

- 衝突原文：14 §F3＝JSON 快照棧（每步 push 完整 template JSON，undo＝pop）；31 ED5/ED6＝op-stack（操作序列）＋30s autosave。這是編輯器儲存管線的根資料結構，不定案則 §B.2 儲存語義與 §D.3 流程無法開工。
- **裁定：採 op-stack（31 ED5/ED6）為根資料結構；14 §F3 的 JSON 快照棧不再作為記憶體 undo 結構，降級為 autosave 落盤的壓實格式（見下）。**
- 理由：
  1. 本尊可觀測語義（儲存清棧＋儲存即生效，§B.2）兩案皆可實作，官方證據不裁決，故按工程成本裁；
  2. 快照棧單步成本＝整份 template JSON（settings_data 級上限 1.5MB，§C.1），長編輯 session 的記憶體與 autosave 傳輸為 O(棧深×檔案大小)；op-stack 為 O(棧深×op 大小)；
  3. 差異 #6 的併發裁定（`lock_version` 後存者衝突提示）需要變更集來呈現衝突內容——op-stack 天然攜帶 diff，快照棧需另行計算；
  4. 快照的正確直覺（恢復簡單）不丟棄：**autosave 落盤格式＝基底快照＋其後 op 序列**，每個儲存點（或每 N ops）壓實為新基底——恢復簡單性保留在持久層（`theme_drafts`），不在記憶體棧。
- 同步義務：14 §F3 需按本裁定修訂，**期限＝editor 儲存管線動工前（對應里程碑見 HANDOFF §5），由該線首個 PR 一併攜帶修訂**；修訂落地前以本章裁定為準。§B.2／§D.3 據此解除阻塞。

**開發驗收要點**：
1. 狀態機測試：publish 原子切換（併發兩人同時 publish 不得出現雙 MAIN／零 MAIN）；comment **4 態由動作可達**（PENDING/PUBLISHED/SPAM/REMOVED）＋ **UNAPPROVED 僅入向**（唯一入徑＝匯入/外部遷移寫入；斷言「無任何 UI/API 動作以 UNAPPROVED 為目標」而非其可達性 <!-- 2026-08-17 更正（PR #52 第 5 輪） -->：原「全 5 態可達」與 B.4 轉移表/入向狀態自述互斥，測試不可能通過）；PUBLISHED 無退回轉移；page 排程發布到期自動可見。
2. 值域測試：MenuItemType 13 值、filter type 3 值、CommentPolicy 3 值、predictive resources[type] 5 值全部入 enum，禁自創。
3. 上限全部引 `config/limits.yml`（§C.1 表逐項），缺一 CI fail。
4. 隔離測試：section 設定引用他店資源 ID 必須被拒；redirect/menu/page 查詢全帶 shop_id。
5. SEO 驗收：`seo.hidden=1` 同時從 sitemap＋店面搜尋＋JSON-LD 消失；篩選 collection URL canonical 至基底；redirect 301 帶快取語義註記。
6. 併發：同 template 兩 staff 編輯衝突提示；themeFiles 批次寫入 ≤50/次並輪詢 job。
7. Files 驗收：FileStatus 4 態全可達且 FAILED 有出口；PROCESSING 中 fileDelete 被拒；HTML 上傳被拒；檔名保留字尾（§C.7 九值）被拒；fileCreate >250/次被拒；fileUpdate 換副檔名被拒；刪檔連動解除商品引用＋引用計數表歸零；跨店檔案 ID 引用被拒（shop_id 隔離）；`file_reference` metafield 解引用 MediaImage 與 GenericFile 皆通。

## G. 來源

全部取證日期：2026-08-14。

- https://shopify.dev/docs/api/admin-graphql/latest/objects/OnlineStoreTheme （Theme 欄位、role、mutations）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/themePublish
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/themeFilesUpsert （50 檔上限、body 三形態、async job）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/OnlineStoreThemeFile （checksum/size/content type）
- https://shopify.dev/docs/storefronts/themes/architecture/templates/json-templates （25 sections/50 blocks/1,000 templates、命名互斥、custom_css）
- https://shopify.dev/docs/storefronts/themes/architecture/config/settings-data-json （current/presets≤5/platform_customizations、1.5MB）
- https://shopify.dev/docs/storefronts/themes/architecture/section-groups （type 值域、name≤50、context 覆寫）
- https://shopify.dev/docs/storefronts/themes/architecture/blocks/theme-blocks （blocks/ 資料夾、@theme/@app）
- https://shopify.dev/docs/storefronts/themes/architecture/templates/robots-txt-liquid （robots 物件、不可 JSON、規則持續更新）
- https://help.shopify.com/en/manual/online-store/themes/adding-themes （20/100 主題上限、19 試用、AI 生成、trial 限制）
- https://help.shopify.com/en/manual/online-store/themes/managing-themes/publishing-themes （發布後原主題回草稿）
- https://help.shopify.com/en/manual/online-store/themes/managing-themes/duplicating-themes （Copy of 命名、20 上限阻擋、刪除永久）
- https://help.shopify.com/en/manual/online-store/themes/customizing-themes/theme-editor/features-overview （undo/redo 儲存清棧、三面板、預覽分享）
- https://help.shopify.com/en/manual/online-store/themes/password-page （試用不可解除、3 sections、SEO 效果）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/Page ＋ help .../theme-structure/pages （可見性排程、刪頁連動刪選單項）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/Blog ／ enums/CommentPolicy （3 值）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/Article ／ mutations/articleDelete
- https://shopify.dev/docs/api/admin-graphql/latest/objects/Comment ／ enums/CommentStatus （5 值）
- https://help.shopify.com/en/manual/online-store/blogs/managing-comments （留言動作、PUBLISHED 不可退回、spam 回報）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/MenuItemType （13 值）
- https://help.shopify.com/en/manual/online-store/menus-and-links/drop-down-menus （3 層巢狀、1,000 選單、10,000 項、footer 限頂層）
- https://help.shopify.com/en/manual/online-store/menus-and-links/url-redirect （404 觸發、保留字首、100k/20M、301 快取）
- https://shopify.dev/docs/api/admin-graphql/latest/objects/UrlRedirect
- https://shopify.dev/docs/api/ajax/reference/predictive-search （參數/值域/容錯/錯誤碼全表）
- https://shopify.dev/docs/storefronts/themes/navigation-search/search （/search 參數與排序）
- https://shopify.dev/docs/storefronts/themes/navigation-search/filtering/storefront-filtering （filter URL 文法、AND/OR、25 上限）
- https://shopify.dev/docs/api/liquid/objects/filter （type/presentation 值域、14 屬性）
- https://help.shopify.com/en/manual/promoting-marketing/seo/find-site-map （sitemap index 結構、自動更新、per-domain）
- https://help.shopify.com/en/manual/promoting-marketing/seo/hide-a-page-from-search-engines （seo.hidden metafield 語義）
- https://help.shopify.com/en/manual/promoting-marketing/seo/adding-keywords （title 70/60、description 160）
- https://www.shopify.com/blog/introducing-checkout-on-your-own-domain （checkout 於主網域，2017-07）
- https://help.shopify.com/en/manual/domains （myshopify 網域僅可改 1 次、國際網域）
- https://shopify.dev/docs/api/admin-graphql/latest/interfaces/File （File interface 欄位）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/FileStatus （UPLOADED/PROCESSING/READY/FAILED 4 態）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/fileCreate （250/次、contentType 5 值、alt≤512、錯誤碼）
- https://shopify.dev/docs/api/admin-graphql/latest/enums/FileCreateInputDuplicateResolutionMode （APPEND_UUID/RAISE_ERROR/REPLACE）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/fileUpdate （READY 前置、副檔名不可換、originalSource/previewImageSource 互斥、引用增删）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/fileDelete （永久刪除、自動解除商品引用、處理中拒刪）
- https://shopify.dev/docs/api/admin-graphql/latest/mutations/stagedUploadsCreate （兩段式流程、fileSize 必填條件、resource 值域）
- https://help.shopify.com/en/manual/shopify-admin/productivity-tools/file-uploads （格式白名單/除 HTML、20MB/1GB/20MP、檔名保留字尾、儲存與檔數配額、Used in 檢視）
- https://shopify.dev/docs/apps/build/custom-data/metafields/list-of-data-types （file_reference 與 list.file_reference、預設 GenericFile）
