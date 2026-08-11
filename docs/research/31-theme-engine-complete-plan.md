# 31 — 主題引擎與編輯器「一安裝就能用」完整補齊計畫

> **本專案當前最高優先級。** 目標重述（使用者原話）：讓所有 Shopify 第三方主題「一安裝，就能使用」，編輯器體驗與 Shopify 完全一樣。本文把 24/25/26/27 號的研究與 PoC 成果收斂成**可執行的工作包全集**：R（渲染完備）、E（端點完備）、ED（編輯器建置）、IN（安裝管線）、D（資料模型）五條線，每個工作包＝做什麼＋怎麼做＋驗收。現況基線：PoC 已證明架構可行（poc/liquid-engine，0 錯誤渲染 Ella 真實檔案）；本文是從 PoC 到生產的全部剩餘工程。

## 0. 「一安裝就能用」的精確定義（DoD）

商家上傳任一 OS 2.0／theme-blocks 世代主題 zip →（≤60 秒）驗證＋相容報告＋授權聲明 → 出現在主題庫（含該主題全部 demo presets）→ 點「自訂」進編輯器：左欄樹完整、全部設定控件可操作、拖拽即時預覽、儲存生效 → 發佈後前台全站可逛可加購可結帳，主題自帶 JS（cart drawer/變體切換/predictive search/快速加購）全部工作。**驗收矩陣見 §6。**

## 1. R 線——渲染完備性（Liquid 平台層補齊）

### R1. Filters 全量（154 個；PoC 已有 ~70 個雛形）

按 26 號分組推進，每組=一個 Ruby module＋對照測試表：

| 組 | 數量 | 要點 |
|---|---|---|
| money 族 | 5 | 讀 shop 貨幣格式模板＋presentment currency（29 §3.5）；零小數貨幣 |
| media 族 | 12 | `image_url`（見 R2 CDN）、`image_tag`（srcset/widths/sizes 生成）、`video_tag`/`external_video_*`（YouTube/Vimeo iframe）、`model_viewer_tag`、`media_tag`、`placeholder_svg_tag`（30 種 placeholder 名） |
| hosted_files | 6 | asset_url/file_url/global_asset_url…→ CDN URL scheme |
| color 族 | 16 | 完整色彩運算（lighten/darken/saturate/mix/contrast/extract/brightness/modify/to_rgb/to_hsl…）——用 Ruby 色彩庫實作，golden 值對照 Shopify 輸出 |
| font 族 | 3 | font_face（@font-face 塊）、font_url（woff2）、font_modify（weight/style 派生）——依 R3 字型庫 |
| localization | 3 | `t`（完整：巢狀鍵/插值 `{{ var }}`/複數 one·other/**fallback 鏈 locale→region→default**）、format_address（per-country 格式表）、currency_selector |
| string/html 平台 | 22 | handleize/camelize/url_escape/url_param_escape/highlight/pluralize/newline_to_br/strip_html（gem 有基礎版，平台語義對齊）… |
| array/metafield | 8 | where/map 已在 gem；metafield 渲染（rich_text schema→HTML、file_reference→file drop、list.* 展開） |
| tag/url | 7 | link_to_tag/link_to_add_tag/link_to_remove_tag（faceted 搜尋 URL 生成）、sort_by/url_for_type/url_for_vendor |
| payment/customer | 9 | payment_type_svg_tag（自繪 26 種卡牌 SVG——**不可抄 Shopify 資產**）、payment_button、login_button（渲染空）、customer_login_link… |
| format/default | 10 | date（strftime＋`%B` 在地化月名）、json、default、default_errors、structured_data（30 §2 的 JSON-LD 生成器！）、weight_with_unit、time_tag、unit_price_with_measurement |
| 其餘 | ~10 | base64 族、hash 族（hmac_sha256…）、inline_asset_content（PoC 已有）、item_count_for_variant、line_items_for、class_list、attribute 雜項 |

驗收：26 號清單逐 filter 打勾；`theme-liquid-docs/data/filters.json` 自動生成「filter 存在性＋簽名」測試；Ella/Dawn 渲染 miss 遙測歸零（T0/T1 範圍）。

### R2. 圖片管線（image_url 的真身——獨立基建）

- **架構**：上傳原圖 → S3/MinIO 存原件 → 前台 URL `/cdn/shop/files/{hash}/{filename}?width=&height=&crop=&format=&quality=&pad_color=` → **imgproxy（MIT, libvips）** 即時變換＋CDN 快取。
- 參數語義照抄：width/height（≤5760）、crop（top/center/bottom/left/right/region）、format（auto→AVIF/WebP 內容協商）、quality（1-100）；`image_tag` 自動生成 srcset（widths 參數）＋sizes＋loading=lazy（**首屏例外**，30 §4）。
- image drop 屬性齊全：src/width/height/aspect_ratio/alt/id/media_type/preview_image/presentation。
- 驗收：Ella 的 `widths="240, 352, 832…"` 全鏈路出圖；Lighthouse 圖片項全綠。

### R3. 字型庫（font_picker 的資料源）

- Shopify 字型庫不可抄。自建：**Google Fonts OFL 子集 ~120 家族**（涵蓋 Ella/Dawn 常用：Assistant/Poppins/Inter/Playfair/DM Sans…）＋系統字型 15 種；自 host woff2（隱私＋效能）。
- 資料表 `font_families(handle, family, weights[], styles[], fallback, files jsonb)`；setting 值格式照抄 `{family}_n{weight}`（`assistant_n4`）；font drop（family/weight/style/fallback_families/baseline_ratio/system?/variants）；font_face → @font-face＋font-display: swap。
- 編輯器 font_picker 控件：分類瀏覽＋搜尋＋預覽字樣＋weight 選擇。
- 驗收：Ella settings_data 引用的全部字型能解析或映射到替代（映射表＋告警）。

### R4. Objects 全量（138 drops；PoC 已有 ~25）

- 依 26 §1 分批：T0 40 個（PoC 基礎擴完整屬性）→ T1 60 個（blog/article/comment/search/filter 族/customer/order/address/paginate 完整/recommendations/predictive_search/localization 完整/metafield/metaobject）→ T2 nil-stub 保持＋遙測。
- 生成器：`theme-liquid-docs/data/objects.json` → drop 骨架＋屬性存在性測試自動生成（26 §6.5）。
- **faceted `filter` 物件**（91 處 Ella 引用）＝collection 篩選後端：filters 定義（由 admin 設定：available/price/option/vendor/type/metafield）→ URL 參數 `filter.v.option.color=Red&filter.v.price.gte=` → filter/filter_value drops（label/count/active/url_to_add/url_to_remove）。
- 驗收：Ella collection 頁篩選側欄完整互動；main-search 頁渲染。

### R5. 搜尋與推薦後端

- predictive search：`/search/suggest.json`＋`?section_id=` 兩形（25 §5）；MySQL ngram（14 號）demo 級，介面照抄。
- recommendations：related（同系列+同 vendor+共購）/complementary（手動 metafield）；`/recommendations/products` 兩形。
- 驗收：Ella header 搜尋抽屜逐鍵出結果；商品頁推薦區有貨。

### R6. 翻譯執行面（29 號的渲染側）

- locale 檔載入鏈：`{locale}.json` → `{lang}.json` → `*.default.json`；t filter fallback；`request.locale`／`localization` drop 接 RequestContext；section rendering 與 Ajax 面全部 locale-aware。
- 動態內容翻譯：drops 讀 translations 表（29 §2.2 fallback）——product.title 在 fr 請求下自動回法文。
- 驗收：切語言後 Ella 整站字串＋商品內容雙層翻譯生效。

### R7. Metafields/Metaobjects 渲染

- `product.metafields.{ns}.{key}` 鏈式訪問→ 依 type 回 drop（rich_text→HTML、file→file drop、reference→resource drop、list→array）；metaobject template（`templates/metaobject/{type}.json`）路由 `/metaobjects/{type}/{handle}`（佔位）。
- 驗收：dynamic sources（24 §4.1）從 metafield 取值渲染成功。

### R8. 剩餘模板類型

gift_card.liquid（`{{ gift_card.* }}`＋QR）、customers/* 全 7 頁（form 家族 tags）、password、404、robots.txt.liquid、search、list-collections、cart 完整頁。驗收：Ella 47 個 templates 全部可路由渲染。

## 2. E 線——端點完備性

25 §5 表全實作（cart 家族雙格式/SRA 兩形/predictive/recommendations/localization 雙欄位名/shipping_rates/`?view=`）＋ `window.Shopify.*` globals 注入（designMode/routes/currency/locale/CountryProvinceSelector/PaymentButton stub/ModelViewerUI stub/loadFeatures no-op/postLink）＋ `content_for_header` 注入器（meta/canonical/hreflang/JSON-LD/preload/editor bridge script when design_mode）。驗收＝27 §8 第 2/3 條＋headless E2E（加購→改量→移除→結帳跳轉）。

## 3. ED 線——編輯器建置（React，30 種控件全表）

### ED1. 三面板 shell＋路由
頂列（離開/三面板切換/主題名+狀態 badge/市場切換/頁面切換/裝置切換/undo redo/儲存）＋左欄 300px＋預覽 iframe。**URL 狀態化**：`?section=`、`?context=theme&category=`、`?market=`、`?template=`（24 §1.1）。

### ED2. Sections 樹
巢狀 8 層渲染（虛擬化）；拖拽（dnd-kit）：同容器排序＋跨容器移動（白名單校驗）；hover 眼睛/刪除；靜態 block 鎖定樣式＋虛線眼睛；「＋新增區段/區塊」入口；右鍵選單（複製/貼上/重新命名/複製到…）。

### ED3. 設定面板——30 種 input 控件全表（各控件＝React 元件＋值序列化）

| 控件 | 行為要點 |
|---|---|
| text/textarea | debounce 300ms 即時 patch |
| number/range | range 帶 unit 顯示＋拖動即時 |
| checkbox | 即時 |
| select/radio | segmented（≤3 選項自動轉按鈕組，仿 Horizon 觀察） |
| color | popover picker（PoC 觀察：漸層面板+hex+滴管+色相條）；值=hex 或 rgba |
| color_background | 支援 gradient 字串 |
| color_scheme | 色票下拉（引用 scheme id） |
| color_scheme_group | **色票組管理器**（新增/編輯/刪除 scheme，13 組上限觀察值） |
| font_picker | R3 字型瀏覽器 |
| image_picker | 媒體庫 modal（上傳/選取/alt/焦點）＋**動態來源 ⛁** |
| video / video_url | 媒體庫影片／URL 驗證（YouTube/Vimeo） |
| url | 資源 picker（商品/系列/頁面/blog/自訂 URL）＋動態來源 |
| richtext / inline_richtext | 迷你 RTE（b/i/link/list；inline 版無 block 元素）；值=受限 HTML |
| html / liquid | code textarea（CodeMirror）；liquid 型渲染期執行 |
| product / product_list | 資源 picker 單/多選（list 帶排序） |
| collection / collection_list | 同上 |
| blog / article / page | 同上 |
| link_list | 選單 picker |
| metaobject / metaobject_list | metaobject picker |
| text_alignment | 三鈕組 |
| header / paragraph | 純展示（分組標題/說明） |
| **visible_if** | **條件顯示引擎**（Ella 實用！）：值=Liquid 布林式（`{{ block.settings.x == false }}`）→ 前端安全求值器（僅支援 settings 引用+比較+and/or），設定變更即重算可見性 |

Schema 翻譯：label/info/options 的 `t:` 鍵 → `locales/{lang}.schema.json` 解析（fallback en）。

### ED4. 預覽橋（editor bridge——與主題 JS 的契約）
iframe 注入 bridge script（design_mode 時）：①接收 editor 指令（select/hover 描框、scroll_to、patch CSS var、替換 section outerHTML＋**手動重跑 script**）；②派發 **8 個 DOM 事件**（27 §6.1 全表：detail/target/bubbles 精確照抄）；③點擊預覽元素 → postMessage 回 editor 選中（data-shopify-editor-* 反查）；④阻止導航（連結點擊→提示或 editor 內切頁）。

### ED5. Draft 渲染管線
op stack（六原子操作＋rename）→ draft template JSON → `POST /editor/render_section`（28 §10）→ unload→替換→load→select(load:true)；**快通道**：color/text 類 setting 直接 patch CSS variable／文字節點（PoC 實測行為）；全域 theme settings 變更 → 重渲染可視 sections（節流 500ms）。

### ED6. Undo/Redo＋儲存
op stack 雙向（Ctrl+Z/⇧Z）；儲存＝draft publish（原子寫 theme_files）＋清 stack＋toast；離開攔截（dirty 警告）；autosave 草稿（30s，另存 draft 不落正式檔）。

### ED7. Picker（新增區段/區塊）
雙欄：分類清單（presets 的 category 分組、name 排序、enabled_on/disabled_on 過濾、搜尋）＋hover **即時預覽**（render_section with preset data——就是 draft 渲染通道複用）；區塊 picker：白名單 ∪ @theme（排 `_` 私有）、顯式優先＋Show all；「應用程式」tab（app blocks 佔位）。preset 實例化演算法照 27 §6.4（深拷貝+ID 生成+動態來源字串保留）。

### ED8. 佈景主題設定面板
settings_schema 分類手風琴（`t:` 翻譯）＋全 30 控件複用＋color_scheme_group 編輯器＋**presets/demo 切換器**（Ella 16 組：套用=settings_data.presets[name]→current，含確認 modal）＋app embeds 面板（佔位）。

### ED9. 頁面切換器與模板管理
模板清單（24 §1.7 全項）＋子選單（該類型資源/alternate templates）＋「建立範本」（新 JSON template：複製 default）＋metaobject 範本入口（佔位）。

### ED10. 市場 context（P1，29 §7.3）
頂列市場切換 → 編輯=寫 `template_overrides` 差異；覆寫標記（設定旁小點）＋「重設為預設」；繼承斷開規則照 24 §4.3。

### ED11. Code editor（編輯代碼）
檔案樹（layout/templates/sections/snippets/blocks/assets/config/locales）＋CodeMirror（Liquid 語法高亮）＋儲存=themeFilesUpsert＋schema 錯誤即時 lint（theme-check 子集）；「未儲存」標記；唯讀鎖（正在被編輯器 draft 佔用的檔案警告）。

### ED12. 主題庫頁
已安裝清單（預覽卡+作用中 badge）＋動作（自訂/預覽/重新命名/複製/下載/刪除）＋「新增主題」（上傳 zip/從 URL）＋**發佈流程**（確認 modal＋原主題自動降級）。

## 4. IN 線——安裝管線（25 §4 落地＋UX）

上傳（拖放 zip ≤50MB，進度條）→ 解析（tolerant JSON＋schema 剝離）→ theme-check（Node sidecar，錯誤=紅色清單附行號）→ 相容掃描（對照 26 號：**綠=T0 全支援／黃=降級清單（人話描述每項影響）／紅=拒收**）→ **授權聲明 gate**（勾選+說明文案，25 §8）→ 入庫＋編譯（AST cache 預熱）→ 完成頁（「自訂」CTA＋demo presets 選擇）。失敗每步可重試；報告存檔可回看（`theme_import_reports`）。

## 5. D 線——資料模型完備

```
themes(id, shop_id, name, role[main|unpublished|development], source[imported|first_party], version, licensing_ack_at)
theme_files(theme_id, path, content/blob_ref, checksum, updated_at)  # AST cache key
theme_drafts(theme_id, template_path, draft_json, op_stack jsonb, editor_session_id, autosaved_at)
theme_versions(theme_id, snapshot_ref, published_at, published_by)    # 發佈快照=可回滾
template_overrides(theme_id, template_path, context[market handle|b2b], diff jsonb)   # 29 §7.3
theme_import_reports(theme_id, status, errors jsonb, degradations jsonb, created_at)
font_families(...R3)
```

## 6. 驗收矩陣（golden themes）

| 驗收項 | Ella 7.2.0 | Dawn（結構自寫復現版）| 任一 OS 2.0 舊主題 |
|---|---|---|---|
| 安裝管線全綠＋報告 | ✅ 27 §8-全 | ✅ | ✅（黃色降級允許） |
| 前台全站渲染 0 error | ✅ | ✅ | ✅ |
| cart drawer E2E | ✅ | ✅ | ✅ |
| 變體切換/快速加購/predictive | ✅ | ✅ | — |
| 編輯器樹＋巢狀拖拽 | ✅ 4 層 | ✅ | ✅（local blocks） |
| 30 控件全可操作 | ✅ 6,687 設定抽測 | ✅ | ✅ |
| 商品頁卡片裝修（27 §8-4/5） | ✅ | ✅ | — |
| 編輯器事件觸發主題互動（27 §8-7） | ✅ | ✅ | — |
| demo presets 換裝 | ✅ 16 組 | — | — |
| 佈景主題設定＋色票組 | ✅ 19 類/13 組 | ✅ | ✅ |

每格＝headless E2E＋人工體感各一輪；「與 Shopify 完全一樣」的體感基準＝21/24 號實測錄屏對照。

## 7. 工作量與順序（M2/M6 重排定案）

| 階段 | 工作包 | 估量（全職週） |
|---|---|---|
| M2a 渲染核心 | R1(T0 filters)+R2+R4(T0)+E 線 cart/SRA | 3–4 |
| M2b 前台完備 | R3+R5+R6(P0)+R8+E 線其餘 | 3 |
| M6a 編輯器核心 | ED1–ED7＋D 線 | 4–5 |
| M6b 編輯器完備 | ED8–ED12＋IN 線＋R4(T1)+R7 | 3–4 |
| M6c 驗收硬化 | §6 矩陣全綠＋效能（編輯器互動 <100ms、draft 渲染 <800ms） | 2 |

依賴鏈：R2（圖片）與 R3（字型）無前置可先行；ED4/ED5 依賴 E 線 SRA；IN 線依賴 R 線 T0。**總計 15–18 週全職**——這就是「最重要的一塊」的真實代價，列給排期用。
