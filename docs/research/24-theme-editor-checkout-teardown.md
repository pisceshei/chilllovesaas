# 24 — 主題編輯器與結帳系統 完整補走（實測 teardown + 文檔研究）

> 本文補走 21 號實測時延後的兩塊：**主題編輯器**與**結帳設定＋結帳編輯器**。方法＝真實後台逐鍵走訪（Horizon 4.1.3、Shopify Plus 試用店、2026 春季版）＋ shopify.dev / help.shopify.com 系統化文檔研究。Liquid 語言與第三方主題相容層見 25/26 號。

## 0. 來源與研究方法

- 實測：`admin.shopify.com/store/chill-love-u5q5mnzq` 的 theme editor（`/themes/{id}/editor`）與 checkout editor（`/settings/checkout/editor/profiles/{id}`）、`/settings/checkout` 全頁。
- 文檔：shopify.dev `storefronts/themes/architecture` 全章、help.shopify.com theme editor / checkout-settings 各篇、checkout UI extensions targets、Branding API。
- 重要脈絡：本店跑的是 **Horizon**（2025 夏發佈的新世代主題家族，theme blocks 架構），比多數教學文所寫的 OS 2.0/Dawn 又新一代。我們的復刻直接對齊 theme-blocks 世代，OS 2.0 視為其子集。

## 1. 主題編輯器實測（Horizon 4.1.3）

### 1.1 編輯器 shell 佈局

```
頂列（52px）：
  [離開↩] [☰sections|⚙settings|▦blocks 三顆面板切換] … [⊞ Horizon (作用中)] [🏪 商店預設▾] [🏠 首頁▾]
  … [🎨?] [🔍inspector] [📱 行動版] [↺undo] [↻redo] [⋯] [儲存(dirty 才可按)]
左欄（300px）：目前面板（sections 樹 / 佈景主題設定 / blocks）
右欄：即時預覽 iframe（可直接點選 section/block）
```

- 三顆左上角圖示是**面板切換器**：sections 樹、佈景主題設定（全域 settings）、blocks 面板。
- `作用中` 綠色 pill 標明編輯的是已發佈主題（草稿主題會顯示不同 badge）；儲存即對顧客生效。
- URL 深連結：選中 section 時 URL 帶 `?section=template--{id}__{sectionId}`；開佈景主題設定帶 `?context=theme&category=gid://...OnlineStoreThemeSettingsCategory/...&first_setting_id=color_palette`——**編輯器狀態可 URL 化**（復刻時用 query param 同步器實現）。

### 1.2 Sections 樹（左欄）

實測首頁的樹：

```
Header（section group）
  ▸ 公告列
  ▸ 頁首
  ＋ 新增區段          ← group 內也能加 section
範本（template）
  ▾ 主視覺（hero）
      ＋ 新增區塊
      ≡ 標題 「Browse our latest products」
      ⌖ 按鈕
  ▸ Featured collection
  ＋ 新增區段
Footer（section group）
  ＋ 新增區段
  ▸ 頁尾
  ▸ 工具
```

- 三段結構＝`sections/header-group.json` + `templates/index.json` + `sections/footer-group.json` 的直接可視化。
- **區塊巢狀**：主視覺展開後是 blocks（標題/按鈕），Horizon 的 blocks 還能再有子 blocks（最深 8 層）。
- hover 列尾出現 眼睛（隱藏）/刪除 icon；拖曳把手重排；點列本體＝選取＋預覽捲動至該 section 並描藍框。
- 預覽內 hover section 邊界會浮出藍色 `＋` 插入點（inline add section）。

### 1.3 選中 section 後的設定面板

實測主視覺（hero）的完整設定（由上而下）：

| 群組 | 控件 |
|---|---|
| 多媒體檔案 1 | 類型（圖片/影片 segmented）、圖片（選取 picker + 動態來源 icon）、「探索免費圖片」 |
| 多媒體檔案 2 | 同上 |
| 行動版多媒體檔案 | 堆疊多媒體 toggle、在行動裝置上顯示不同的多媒體檔案 toggle |
| 區段連結 | 連結（貼上連結或搜尋 + 動態來源 icon）、在新分頁中開啟連結 toggle |
| 版面配置 | 方向（垂直/水平）、文字基線對齊 toggle、對齊（左/置中/靠右）、位置（底部 dropdown）、間距 slider（24px）、寬度（頁面/全寬） |
| 疊加層 | 多媒體檔案疊加層 toggle、疊加層顏色（#121212 color picker）、疊加層樣式（實色/漸層）、模糊反射 toggle（僅適用於圖片） |
| 內距 | 上方 slider（100px）、下方 slider（72px） |
| 佈景主題設定 | 收合連結（跳到全域 settings） |
| 自訂 CSS | 收合區（per-section custom_css） |
| （底部） | 🗑 移除區段（紅字） |

- 面板 header：section 名 + `⋯`（複製/貼上樣式等）+ `✕` 關閉。
- **預覽內浮動工具列**（選中 section 時出現在 section 下緣）：`要求修改`（Sidekick AI 按鈕——用自然語言改這個 section！2026 新）、複製、隱藏（眼睛）、刪除。

### 1.4 新增區段 picker（實測 Horizon 清單）

點「新增區段」→ 浮出雙欄 picker：左＝搜尋框＋「區段/應用程式」兩個 tab＋分類清單；右＝hover 項目的**即時預覽**（用本店資料渲染）。

Horizon 的 section 分類與清單（實測記錄）：

- **產生**（AI generate——輸入描述生成 section/block，Shopify Magic）
- **文字**：圖示加文字、多欄、富文本、常見問題、跑馬燈、重點引言
- **版面配置**：分隔線、自訂 Liquid、自訂區段
- **表單**：聯絡表單、電子郵件訂閱
- **故事敘述**：圖片比較、影片、網誌文章：網格、網誌文章：編輯風格、網誌文章：輪播、編輯風格、編輯風格：特大文字、輪播、附文字圖像
- **產品**：（清單前段）產品亮點、精選商品、精選商品系列：網格、精選商品系列：編輯風格、精選商品系列：輪播
- **橫幅**：主視覺、主視覺：底部對齊、主視覺：跑馬燈、分割展示、分層輪播、大型標誌、素材輪播：內嵌、素材輪播：滿版
- **應用程式 tab**：已安裝 app 提供的 blocks（實測見 Shop 的 Sign in with Shop Button）＋「瀏覽為佈景主題打造的 app」連結；無預覽時顯示「無可用預覽」。

### 1.5 佈景主題設定（全域 settings 面板）

實測 Horizon 的分類清單（`settings_schema.json` 的可視化）：**標誌與 favicon、調色盤、字型排版、頁面、動畫、徽章、按鈕、購物車、抽屜、圖示、輸入欄位、快顯與互動視窗、價格**（下方仍有更多）。

- **調色盤**＝Horizon 世代的 color 方案：一排色票（實測 4 格：白/黑/深灰/淺灰）＋`＋`新增；點色票開 color picker（漸層面板＋hex 輸入＋滴管＋色相條＋刪除）。
- **實測到的關鍵行為**：改色票 → **整個預覽即時重渲染**（公告列/hero 疊加層/products 區背景全變）＋ 儲存鈕立即轉可用；按 `↺` undo → 預覽復原＋儲存鈕回禁用。tooltip 顯示快捷鍵（復原 ⌘Z）。→ 復刻規格：**設定變更走 client-side 即時套用（CSS variables), save 才落庫；undo/redo 是編輯階段的 client-side 操作堆疊，儲存後清空**（與文檔研究一致）。

### 1.6 商店預設（市場切換器）

頂列 `商店預設 ▾` 下拉＝ **Markets 內容覆寫的入口**：搜尋市場、`商店預設 ✓`、「可自訂的市場」清單（實測：United States）。切到某市場後所做的修改＝該市場的 override（存成 `templates/index.context.{market}.json` 差異檔）。詳細機制見 §4.3。

### 1.7 頁面（模板）切換器

頂列 `首頁 ▾` 下拉＝模板清單（實測完整項目）：搜尋網路商店、**首頁、產品 ▸、商品系列 ▸、商品系列清單、禮品卡、購物車、結帳頁面與顧客帳號、頁面 ▸、網誌 ▸、部落格貼文 ▸、搜尋、密碼、404 頁面、＋建立 metaobject 範本**。

- 有子選單者（產品/商品系列/頁面/網誌/部落格貼文）可選「該類型下的具體資源或 alternate template」。
- **`結帳頁面與顧客帳號` 是跳板**：點擊直接離開 theme editor、進入 checkout editor（URL 換成 `/settings/checkout/editor/profiles/{id}?exitPath=...`，exitPath 記回程）。→ 兩個編輯器是獨立產品，靠頁面切換器互相跳轉。
- `＋建立 metaobject 範本`＝metaobject 自訂頁面（templates/metaobject/*.json）。

## 2. 主題資料模型（文檔研究精華）

### 2.1 檔案結構

```
layout/    theme.liquid（唯一必要檔）、password.liquid …
templates/ *.json（OS2.0+）或 *.liquid（vintage）；customers/*（legacy）；metaobject/{type}.json
sections/  *.liquid（section 定義，含 {% schema %}）＋ *.json（section groups）
blocks/    *.liquid（theme blocks，Horizon 世代；可跨 section 重用、可巢狀）
snippets/  *.liquid（render 用片段）
config/    settings_schema.json ＋ settings_data.json
locales/   *.json（前台字串＋editor 字串；*.schema.json）
assets/    css/js/img；*.liquid 後綴檔可用 settings
```

### 2.2 JSON template 格式

```jsonc
{
  "layout": "theme",          // String | false
  "wrapper": "div#main.page", // 選配
  "sections": {
    "hero_jVaWmY": {
      "type": "hero",          // 對應 sections/hero.liquid
      "settings": { "heading": "..." },
      "blocks": {
        "b1": { "type": "text", "settings": {…}, "blocks": {…}, "block_order": […] },
        "s1": { "type": "slide", "static": true, "settings": {…} }   // static block 不進 block_order
      },
      "block_order": ["b1"],
      "disabled": false,
      "custom_css": ["…"]
    }
  },
  "order": ["hero_jVaWmY"]
}
```

### 2.3 硬限制數字表（寫進 config/limits.yml）

| 項目 | 上限 |
|---|---|
| sections / template（或 section group） | 25 |
| blocks / section | 50（`max_blocks` 只可調低；static 不計） |
| blocks / template 總數 | 1250 |
| JSON templates / theme | 1000 |
| theme blocks（/blocks 檔數）/ theme | 300 |
| block 巢狀深度 | 8 層 |
| settings_data.json | ≤ 1.5MB |
| section presets | ≤ 5 組 |
| dynamic sources / template | 100（單一 setting 50） |
| section group name | ≤ 50 字元 |
| section/block ID 字元 | 英數 |

### 2.4 section schema 與 theme block schema

- section `{% schema %}`：`name / tag(article|aside|div|footer|header|section) / class / limit(1|2) / settings / blocks(本地定義 或 {"type":"@theme"} / {"type":"@app"}) / max_blocks / presets(name/category/settings/blocks) / default / locales / enabled_on|disabled_on(templates[]/groups[])`。
- theme block（`/blocks/*.liquid`）schema：`name / settings / blocks(子 block 白名單) / presets(**必須有才會出現在 picker**) / tag(可 null，需 block.shopify_attributes) / class`。不能收外部參數（與 snippet 的根本差異）；同一 section 的 local blocks 與 theme blocks **不可混用**（`@app` 例外）。
- 渲染管線：section 內 `{% content_for "blocks" %}`（按 block_order）；static block `{% content_for "block", type:"slide", id:"hero-slide" %}`；layout 內 `{% sections 'header-group' %}`。
- 編輯器 block 動態標題：取 settings 的 `heading` > `title` > `text`，否則顯示 block name（實測「標題 :Browse our latest products」即此）。

### 2.5 settings_schema.json / settings_data.json

- schema＝陣列；首項 `theme_info`（name/version/author/documentation_url/support_email XOR support_url）；其後 `{name, settings[]}`＝設定面板分類（實測 §1.5 的清單即此）。
- data＝`{ "current": { settingId: value, "blocks": { uuid: {type:"shopify://apps/...", disabled, settings} } }, "presets": {…} }`；app embeds 存在 current.blocks。
- input types 全 30 種與值格式：見 26 號 §5（實作 checklist）。

## 3. 編輯器操作 → 資料操作 對照表（復刻規格核心）

| 編輯器操作 | 資料操作 |
|---|---|
| 新增 section | template.sections 加 entry（內容取 preset）＋ order 插入位置 |
| 新增 block | 父 entry.blocks 加 entry ＋ block_order 插入 |
| 拖曳重排 | 改 order / block_order 陣列 |
| 隱藏（眼睛） | entry.disabled = true（**不是刪除**；editor 保留、渲染跳過） |
| 複製 | 深拷貝 entry、生成新 ID |
| 刪除 | 移除 entry＋order 引用；static block 不可刪只可隱藏 |
| 改 setting | entry.settings[id] = value（即時預覽：client 端 patch＋重渲染該 section） |
| 佈景主題設定 | settings_data.current[id] = value |
| App embeds 開關 | settings_data.current.blocks[uuid].disabled 切換 |
| Undo/Redo | client-side operation stack；**僅未儲存變更**；Save 後清空 |
| 儲存 | 整份 template/section-group/settings_data jsonb 寫回（PATCH）；Live 主題即生效 |
| 市場切換後編輯 | 寫 `*.context.{market}.json` 差異覆寫檔（見 §4.3） |
| AI 產生（產生/要求修改） | LLM 生成 `/blocks/ai_gen_*.liquid`（計入 300 上限）或對現有 section 提修改；Keep 才落檔 |

> 復刻決策：編輯器全部操作歸約為 **6 種原子 op**（add/remove/move/set-setting/toggle-disabled/duplicate），前端維護 op stack 支援 undo/redo，Save＝送出最終 JSON。這同時是 M6 的驗收清單。

## 4. 動態來源、App blocks、市場覆寫

### 4.1 Dynamic sources（動態來源）
- 實測：hero 的圖片/連結 setting 旁的 ⛁ icon＝連接動態來源。
- 機制：setting 值存成 **Liquid 引用字串**（如 `"{{ product.metafields.custom.tagline }}"`、`"Featuring: {{ product.title }}"`），僅允許直接值引用；渲染時以白名單 resolver 解析（不跑完整模板引擎）。
- 可連：資源屬性（product.title/vendor/…、collection、page、article、blog）、metafields、全域 metaobjects；context 決定可連來源（product template 才有 product metafields）。
- 支援的 setting 類型：article/collection/collection_list/page/product/product_list/color/image_picker/video/url/text/richtext/inline_richtext/metaobject/metaobject_list。
- 上限：100/template、50/setting；全域 theme settings 不可用。

### 4.2 App blocks 與 app embeds（theme app extensions）
- App block：`target:"section"`，加在支援 `@app` 的 section 裡（實測 picker 的「應用程式」tab）。
- App embed：`target:"head"|"body"|"compliance_head"`，在佈景主題設定的 App embeds 面板開關；存於 settings_data.current.blocks。
- 上限：extension 10MB、30 blocks、Liquid 100KB、locales 100 檔各 15KB。
- 復刻：app blocks 沿用 block 資料模型（type 帶 `app://` 命名空間）；embeds 做 shop 層 jsonb。

### 4.3 Markets 內容覆寫（商店預設）
- 四種 override：setting 級、visibility、custom section order、custom block order。
- 繼承：Default 改動同步到所有市場；**被覆寫的部分**停止繼承（其餘仍繼承）；有 custom order 的市場不再自動收到 Default 新增的 section。
- 重設：refresh icon 可按 setting/section/template 分層重設回 Default。
- 存儲：`templates/index.context.{market-handle}.json`（只存差異；B2B 為 `context.b2b`）。
- 復刻：`template_overrides(template_id, context, diff jsonb)`＋渲染期 deep-merge；order 覆寫＝整條 order 斷開繼承。

## 5. 結帳設定 /settings/checkout（實測全頁＋文檔逐欄位）

實測頁面結構（由上而下）＋每欄位後端效果：

| 區塊 | 實測內容 | 後端效果／復刻儲存 |
|---|---|---|
| 設定檔（Plus） | 「CHILL LOVE」設定 `使用中` badge、上次儲存日期、⋯選單、`編輯` →checkout editor；藍色 info：顧客帳號網域用 shopify.com 而非 chill.deals＋變更連結 | `checkout_profiles` 表；編輯＝開 editor |
| 顧客聯絡方式 | radio：電話號碼或電子郵件 / **電子郵件✓**；☑ 顯示連結讓顧客透過 Shop 追蹤訂單；☐ 要求顧客登入才能結帳（要求登入時只能用電子郵件） | `contact_method` enum；`require_login` boolean（啟用後購物車隱藏加速結帳鈕） |
| 顧客資訊 | 姓名：將名字與姓氏設為必填 ▾；公司名稱：不顯示 ▾；（地址第 2 行、VAT 同型三態）；運送地址電話號碼：選填 ▾ | 三態 enum `hidden/optional/required` 統一元件；Required 的 company 會使部分加速結帳（Apple Pay）不顯示 |
| 接受行銷資訊 | 電子郵件：`結帳頁面與登入` ▾＋預覽字 "Email me with news and offers"；「在特定地區預設勾選核取方塊」：`自動化` badge＋美國；SMS：`不顯示` ▾ | email consent（預選規則：Shopify 建議/自選地區）；SMS **不可預選**、僅結帳完成時記錄；寫進 customer 的 marketing consent（state/opt_in_level/consented_at） |
| 小費 | 說明「顧客可以從 3 個預設金額中選擇，或輸入自訂金額」；☐ 在結帳時顯示小費選項 | `tipping{enabled, presets[3], collapsed}`；上限 $1,000、≤100% 訂單額；以稅前運費前小計算 |
| 未完成結帳作業電子郵件 | 標題＋`自訂電子郵件` 鈕；info banner：新版自動化已推出→檢視自動化作業；radio 對象（任何未完成者/**電子郵件訂閱者**…）；傳送時間 radio：1 小時/6 小時/**10 小時（建議）✓**/24 小時 | `abandoned{enabled, audience, delay_hours}`；留 email 10 分鐘未完成＝棄單；不寄條件（已購/付款錯誤/不配送/僅電話/無庫存/全免費）；3 個月自動刪除 |
| 結帳頁面語言 | `英文`＋`編輯結帳頁面內容` 鈕 | checkout 字串翻譯層（`checkout_translations`），等同 15 號 spec 的 notification 模板翻譯機制 |
| 進階偏好設定 | 地址蒐集（管理蒐集運送和帳單地址的方式）▸；加入購物車數量上限 `建議` badge＋`開啟` badge ▸（保護庫存數量不外洩） | `address_prefs` jsonb（billing 預填/自動完成 22 國/驗證 20 國）；`cart_item_limit` int（例外：POS/draft/B2B/不追蹤庫存） |
| 結帳規則 | 說明＋「尚未安裝任何包含購物車或結帳頁面規則的應用程式」→ App Store 連結 | validation functions 掛載點（`checkout_validation_rules`）；對應 15 號 spec 的 cart validation service |

> 復刻：整頁＝`checkout_settings` singleton per shop（enum/boolean/jsonb），單一 PATCH endpoint；三態欄位用同一 radio 元件；棄單信 Solid Queue job（at abandoned_at+delay，寄前重查條件）。

## 6. 結帳編輯器（實測＋文檔）

### 6.1 實測結構

從 theme editor 頁面切換器點「結帳頁面與顧客帳號」進入；shell 與 theme editor 同款（三面板/市場切換/頁面切換/undo/儲存）。

左欄「結帳頁面」樹（實測）：

```
頁首 ▸        標誌、購物車連結、＋新增區塊
主要
  聯絡資訊     └ 電子郵件或電話號碼
  配送         └ 配送地址、運送方式 └ 運送選項清單
  付款         └ 付款選項
  帳單地址
  動作         └ 立即付款
  ＋新增區塊
訂單摘要 ▸    購物車 └ 購物車中的品項、總計、＋新增區塊
頁尾 ▸
```

預覽＝真實 one-page checkout 假資料渲染（Willa Howe / 1600 Pennsylvania Avenue / Fresh Rose Serum $451.50＋運費 $10＝$461.50），含 登入 連結、marketing checkbox、國家/州 dropdown、電話國旗選擇器、「儲存此資訊供下次使用」。

### 6.2 設定面板（branding，實測清單）

標誌（圖片＋對齊 靠左/置中/靠右）、配色（色票列＋`＋`）、主要內容（背景 預設）、頁首（全寬說明＋背景＋強調色「適用於連結和購物車圖示」）、訂單摘要（背景）、錯誤（紅 預設＋透明 toggle）、字型（標題/內文 預設 ▾）、**結帳頁面版面配置：單頁 ▸（可切 三頁式）**、地址自動完成 toggle、再次購買按鈕 toggle、進階（「透過 Branding API 設定的部分品牌行銷設定無法在此變更。若要取得完整控制權，請使用 API」）。

### 6.3 頁面切換器（實測）

`結帳` ▾：**結帳**（結帳）；**購買後**（感謝您）；**顧客帳號**（登入、訂單、訂單狀態、個人資料）；**網路商店佈景主題**（跳回 theme editor）。

感謝您頁實測：確認 #ABC123EXAMPLE、「Willa，感謝您！」＋藍勾、訂單已確認卡、訂單詳細資訊卡（聯絡/帳單/運送/運送方式）、聯絡我們＋繼續購物。

### 6.4 文檔補充（機制）

- **Profiles/configurations**：同時僅 1 active；draft 上限 Plus 99／其他 20；duplicate→draft、只有 draft 可刪；publish 時原 active 自動降為 draft（可回滾）。GraphQL 舊名 `checkoutProfiles`/`checkoutBrandingUpsert` → 新名 `checkoutAndAccountsConfiguration*`。
- **Branding API 結構**（jsonb 直接沿用）：`designSystem{colors{global, schemes.scheme1/2{base,control,primaryButton,secondaryButton}}, typography{primary,secondary,size{base,ratio}}, cornerRadius{small,base,large}}` ＋ `customizations{global,header,footer,main,orderSummary,section,control,textField,checkbox,select,primaryButton,secondaryButton,headingLevel1-3,favicon,buyerJourney,cartLink,expressCheckout,merchandiseThumbnail…}`；不支援逐頁樣式與 SVG。
- **App blocks**：三側欄（Sections/Settings/Apps）；每放置區最多 3 apps；行為開關（無效時阻擋結帳/是否進加速結帳/自動展開）。TY/OSP＋customer accounts＝全方案；checkout 資訊/運送/付款頁＝Plus。
- **Extension targets**：checkout 17+（`purchase.checkout.block.render`、`…delivery-address.render-before/after`、`…payment-method-list.render-before/after`、`…actions.render-before` 等）；thank-you 7；order-status/customer-account 20+（含 `customer-account.page.render` 整頁）。復刻＝React slot registry（target string → components）。
- **Customer accounts 新版**：無密碼（email 6 碼）、Sign in with Shop/Google/Facebook、session 365 天；branding 繼承 checkout 配置；頁面＝Sign-in/Orders/Order status/Profile＋app 整頁。
- **checkout.liquid 落日時間線**：2024-08 資訊/運送/付款停用 → 2025-08 TY/OSP 停用 → 2026-01 強制升級 → 2026-08 非 Plus scripts 停用。替代：UI extensions＋Branding API＋Functions＋web pixels。**我們直接復刻終局形態，不做 checkout.liquid。**
- **Functions 掛載**（結帳相關）：payment/delivery customization（各限 25 個啟用）、cart & checkout validation（=結帳規則）、discounts、cart transform。復刻為同步 Ruby service objects，介面模仿 input/output JSON 合約。

## 7. 對 CHILL LOVE 方案的補充與修正

1. **M6 重定義**（原「三欄主題編輯器」過窄）：M6 = 主題編輯器（sections 樹＋settings 面板＋picker＋預覽即時 patch＋undo stack＋市場覆寫延後）＋ **Liquid 相容渲染管線（見 25 號）**。原 14 號 spec 的 theme JSON 驗證器規格仍有效，限制數字以本文 §2.3 為準。
2. **結帳雙層架構落地**：`checkout_settings`（行為，§5）與 `checkout_profiles`（外觀＋佈局，§6）分離；15 號 spec 的 one-page checkout 欄位規格不變，新增 branding jsonb 渲染（CSS variables 映射）。
3. **資料模型增補**（06 號 40 表之上）：`theme_files`、`template_overrides`、`checkout_profiles`、`checkout_translations`、`block_definitions`（scope 欄涵蓋 local/theme blocks）。
4. **原型 v3 待辦**（chilllove-admin-v2.html 下一輪）：theme editor 三面板 shell、sections 樹（含巢狀 blocks＋眼睛/刪除 hover）、section picker 雙欄（分類＋hover 預覽）、佈景主題設定手風琴＋色票、checkout editor 樹＋branding 面板、頁面切換器兩個下拉。互動規格沿用 23 號 tokens。
5. **AI 面（P2）**：「產生」section/block 與「要求修改」浮動鈕＝LLM 生成符合 schema 的 block Liquid/設定 patch；介面先做入口與假流程。
