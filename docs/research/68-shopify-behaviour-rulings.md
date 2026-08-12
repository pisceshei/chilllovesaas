# 68 — Shopify 實際行為逐條查證（2026-08-12 待裁決清單 B／C／D／E 共 17 條）

> **本檔的用途**：使用者裁定「其他的你給我再次去搜索 shopify 的所有文檔或者其他網站對這些問題 shopify 是怎樣處理的。**我們全部跟隨 shopify 的做法。**」
> 所以本檔**不給建議**，只查「Shopify 實際怎麼做」，然後寫出跟隨後我方要改成什麼。
> 對象清單＝`docs/handoff/2026-08-12-open-decisions.md` §B（7 條）／§C（6 條）／§D（3 條）／§E（1 條）。
>
> **查證日**：2026-08-12。**只新增本檔，未改任何既有檔案。**「要改哪些檔案」一律只列清單。
>
> 🔴 **三條凌駕規則**（本檔逐條套用，遇到就明講，不靜默處理）：
> 1. **使用者裁定 > Shopify 做法**。已裁定的事項（見 open-decisions §F）即使與 Shopify 不同，也不因本檔改變。
> 2. **Shopify 無此功能** ⇒ 明寫「無」，並把「要不要仍然做」交回使用者，不自行決定。
> 3. **查不到 ⇒ 說查不到**，登記 V-180 起，不用常識補。

## 0.1 出處等級（沿用 62 §0.3）

| 等級 | 意義 | 本檔用量 |
|---|---|---|
| `dev` | shopify.dev 官方開發文檔／changelog | 6 |
| `help` | help.shopify.com 官方說明中心 | 7 |
| `test` | **本輪對真實 Shopify 店鋪的一手實測**（`/collections.json`、`/products.json`、canonical 抓取） | 9 |
| `press` | Shopify Community（含 staff 回覆）、Shopify Engineering、第三方技術文 | 11 |
| `ours` | 我方推論 | — |

> `test` 的方法：Shopify 店鋪的 `/products.json`、`/collections.json` 是公開端點，同時回傳 `title` 與 `handle`。**同一列的 title→handle 若與生成規則吻合即為自動生成**；明顯被改寫的（如 `Cacti & Succulents → cacti-succulent`）一律標為「商家手改」不採信。受測店：`kith.com`、`thesill.com`、`otherland.com`、`hardware.shopify.com`（Shopify 自營）、`goodsofdesire.com`（香港）、`kurand.jp`（日本）、`allbirds.com`。

---

## 0.2 一覽表（17 條）

| # | 事項 | Shopify 實際做法 | 我方是否要改 |
|---|---|---|---|
| B-1 | handle 為空擋不擋發布 | **不擋**；且 CJK 標題**不會**產生空 handle——Shopify **保留 CJK**，從不落 `product-{id}` | ⚠ 「不擋」照做；「落代碼 fallback」**維持我方**（裁定 > Shopify） |
| B-2 | 未覆核機翻前台可見 | **立刻可見**，無審核／發布閘門 | ✅ 已一致；補「重跑不覆蓋人工譯文」 |
| B-3 | 翻譯 CSV 空白語義 | 生態事實標準（Matrixify）＝**空白＝刪除該譯文**，與商品 CSV **同向** | 🔴 **要改**：`blank_means_unchanged` 翻面 |
| B-4 | 來源語言粒度 | **店級單一值**，可改，改了會**刪掉目標語言既有譯文** | ✅ 已一致；改語義描述 |
| B-5 | SKU 強制唯一 | **無此功能**（只警告、不阻擋、無開關） | ✅ 軟唯一已一致；硬唯一開關＝超出 Shopify，待使用者決定 |
| B-6 | 變體獨立 URL | 預設無；`?variant=` canonical **去參數**（實測）；要獨立 URL 走 **Combined Listings**（Plus） | ⚠ 預設一致；**缺 Combined Listings 等價物** |
| B-7 | UCP／代理商務 | 2026-01-11 起分階段推出；Google／Copilot 通路 rolling out；admin 內有 Agentic Storefronts | ✅ 節奏相容；補「通路」後台形態 |
| C-1 | `llms-full.txt` | 🔴 **預設開**，內容＝`agents.md` 別名（不是整站打包） | 🔴 **要改**：`false → true` |
| C-2 | 多市場網域預設 | 建議子資料夾，但**新市場預設沿用主網域結構、不自動建子資料夾**（2023-05-23 起） | 🔴 **要改**：預設值不是子資料夾 |
| C-3 | 地區自動重導預設 | 🔴 **新店預設開**（地區重導）；**自動語言偵測預設關** | 🔴 **要改**：`enabled_default: false → true` |
| C-4 | handle 品質閘門 | **Shopify 無此概念**（它不需要，因為保留 CJK） | 我方獨有，維持（裁定衍生物） |
| C-5 | 中英混排保留英文片段 | 同上，Shopify 無此概念 | 我方獨有，維持 |
| C-6 | `&` `%` 詞彙展開 | 🔴 **不展開**（`Carroll&Chan → carroll-chan`，實測 ×5） | ✅ **與 Shopify 完全一致** |
| C-4/5/6 附帶 | 重複 handle 尾碼 | **自 `-1` 起算**（官方例 `potion`／`potion-1`；實測 `ceiling-fans-1`） | 🔴 **要改**：我方 `-2` 起算 |
| D-1 | 剩餘上限值搬 `limits.yml` | 純內部工程 | **照做**（不需查 Shopify） |
| D-2 | `max_smart_collections_per_shop` 改名 | 純內部工程 | **照做**（不需查 Shopify） |
| D-3 | exponent=3 幣別 | 幣別代碼**支援**（enum 含 KWD/BHD/JOD/OMR/TND），但金額**四捨五入到 2 位**；Shopify Payments 不支援該三國開店 | 🔴 **要改**：不擋幣別，改成明文「2 位小數 ＋ PSP 未宣告即 reject」 |
| E-1 | 顯示價 ≠ 結帳價 | **無價格鎖定機制**，結帳一律重算；官方**只當排錯問題處理，沒有合規說明** | ⚠ 技術面已一致；**法遵面 Shopify 給不出答案**，仍需使用者決定 |

---

## B. 產品政策（7 條）

### B-1 純中文標題的 handle：Shopify 會產生什麼？擋不擋發布？

**Shopify 實際做法**

**(a) 基本生成規則**（`dev`：`shopify.dev/docs/api/liquid/basics` §Handles）
一律小寫；空白與特殊字元轉成 `-`；**連續**的空白／特殊字元收斂成單一 `-`；**開頭**的空白／特殊字元移除。重複時自動加數字尾碼（官方例：兩個同名商品 ⇒ `potion` 與 `potion-1`）。建立後**改標題不會改 handle**，要手動改。

**(b) 非 ASCII 的處置——這是本條的核心答案**

Shopify **不是一致地移除**，而是**分兩類**：

| 類別 | 行為 | 證據 |
|---|---|---|
| **拉丁系變音符號／拉丁擴充** | **折疊成 ASCII** | `mašīna → masina`（`press`，REST log）；`{{ '… ŭ' \| handleize }} → …-u`（`press`，Shopify staff 已復現）；實測 `Créature de Keis → creature-de-keis`、`Home Furnishing & Décor → home-furnishing-decor`（`test`, goodsofdesire.com） |
| **非拉丁字集（CJK／西里爾／希伯來／emoji）** | 🔴 **原樣保留**，URL 中以 percent-encoding 呈現 | 中文 `一辆车`、俄文 `ёжик` 原樣被接受（`press`，community 80006，2021-11-22）；admin UI 由 unicode 標題生成 unicode handle，URL 以希伯來文／日文呈現，Shopify staff Liam 承認並轉產品團隊（`press`，community 239594）；日文社群：日文標題生成**很長的日文 URL**，商家反而在問「怎樣自動改成數字代碼」（`press`，community 223998）；實例頁面 URL `/pages/%E4%BC%9A%E7%A4%BE…`（`press`，5-bit.jp）；`{{ 'Abc 123-D--E 🔪 ŭ' \| handleize }}` 實際輸出**保留 emoji**（`press`，community.shopify.dev 1060，2024-10 staff 復現） |

**⇒ 純中文標題在 Shopify 得到的 handle 是「中文本身」，不是 `product-{id}`，也不是空字串。Shopify 沒有 fallback 代碼這回事，因為它不需要。**

**(c) 擋不擋發布**：**不擋**。handle 永遠有值（CJK 被保留），官方文檔完全沒有「handle 品質」的閘門、警告或健康度概念。

**(d) 一則反例**（誠實記錄）：香港店 goodsofdesire.com 的系列 `Mid-Autumn festival - 8折 for 15 Best Sellers` → `mid-autumn-festival-8-for-15-best-sellers`（`折` 消失）。該店 primary language 是英文，且同店大量 handle 明顯經人工整理，研判為**商家手改**。但這是本輪唯一與 (b) 相左的觀測 ⇒ 登記 **V-180**。

**我方原本的決定**
`handle.require_meaningful_on_publish: false`（不擋），中文標題落 `{resource}-{token8}` 確定性 fallback ＋ 四條可觀測摩擦（67 §D.2(a)）。

**跟隨後改成**
- **「不擋發布」＝跟隨**（Shopify 也不擋）⇒ **無需改動**。
- **「落代碼 fallback」＝刻意不跟隨**。🔴 **使用者裁定「URL handle 一律英文，禁止中文」直接排除了 Shopify 的做法**，所以 fallback 維持。要改的只是**論述**：62 §F.3 現在寫的是「V-119 結案，對齊問題消失」，實際上**對齊問題沒有消失，是被裁定覆蓋了**——這兩件事在日後回頭看時意義完全不同，必須寫清楚 Shopify 的真實行為是「保留 CJK」。

**要改哪些檔案**
- `docs/specs/62-seo-geo.md` §F.3（把「V-119 結案＝問題消失」改成「Shopify 實際保留 CJK，我方**明知偏離**，依據＝使用者裁定」，並補本檔出處）
- `docs/specs/67-multilingual.md` §D.2（同上；選項評估表補一列「E. 照 Shopify 保留 CJK ⇒ 被裁定排除」）
- `docs/specs/13-spec-products-inventory-media.md` L187–192（現行寫「允許 unicode handle（URL encode）」＋「fallback `product-{n}`」——**前半正是 Shopify 的真實行為**，後半與 67 §D.2 的 `{resource}-{token8}` 不一致，兩者要對齊到裁定後的單一答案）
- `config/limits.yml` `handle:` 區塊（`ascii_only` 的註釋補「Shopify 實際不是這樣，本鍵依裁定」）

**查不到**
Shopify 沒有任何官方文檔敘述非拉丁字集的處置規則（社群 80006 的原 po 就是在要求官方文件化，至今無回應）。折疊與保留的**確切分界表**（哪些 Unicode block 會折疊）無一手來源 ⇒ **V-180**。

---

### B-2 未經人工覆核的機器翻譯，對前台可見嗎？

**Shopify 實際做法**（`help`：`help.shopify.com/en/manual/international/translate-adapt-app`）

- Translate & Adapt 的自動翻譯執行後，**譯文在數分鐘內直接出現在前台**。
- **沒有審核狀態、沒有草稿、沒有發布閘門**——整個 app 沒有 approve/publish 這個動作。
- 自動翻譯的作用域是「尚未翻譯的內容」＋「**已過期的自動翻譯內容**」；🔴 **不會覆蓋商家手動新增或編輯過的譯文**。
- 自動翻譯語言數上限 **2 種**。
- 官方文檔**沒有**說明 UI 上如何區分「機翻」與「人工」——但「不覆蓋人工譯文」這條行為證明**系統內部有來源標記**。

**我方原本的決定**
可見；譯文帶 `value_source`（human／machine／…），後台可篩、可批次送審（`i18n.machine_translation.value_source_marked: machine`）。

**跟隨後改成**
方向一致，**不需改政策**。要補的是 Shopify 已有、我方尚未明文的兩條行為：
1. 🔴 **重跑自動翻譯必須跳過 `value_source = human` 的列**（Shopify 明文如此；我方目前只有「標記」，沒有「重跑保護」）。
2. 「已過期的自動翻譯」是自動翻譯的**主動作用域**（不只是被動提示）——我方 67 §C.5 的過期偵測要接上批次翻譯的入口。
3. 自動翻譯語言數上限：Shopify 是 2。這是它的商業限制，我方**不必照抄數字**，但應該有一個對應鍵，否則大租戶一鍵翻 20 種語言的成本無處收斂。

**要改哪些檔案**
- `config/limits.yml` `i18n.machine_translation`（新增 `rerun_skips_human_edited: true`、`auto_translate_max_languages_per_run`）
- `docs/specs/67-multilingual.md` §E.5（批次翻譯）、§C.5（過期偵測與批次入口的連線）

**查不到**
無。本條由官方 help 直接回答。

---

### B-3 翻譯 CSV 的「空白」語義

**Shopify 實際做法**

- **Shopify 原生的 Translate & Adapt 是否提供 CSV 匯出／匯入，本輪無法確認。** help 頁面提到可匯出後批次回匯，但社群長期有「怎麼把 Translate & Adapt 的翻譯匯出成 CSV」這類提問（`press`，community 209362），且各家翻譯 app（langify、Matrixify、DataEase、Altera）都把「翻譯匯入匯出」當成自己的賣點 ⇒ 研判**原生能力薄弱或不存在** ⇒ **V-182**。
- **生態內的事實標準是 Matrixify**（`press`：`matrixify.app/documentation/translations/`）：翻譯匯入時，Translation Value 欄留空 ＝ **刪除該語言該欄的既有譯文**。
- **商品 CSV**（`help`，已記於 61 §6.1）：勾選「以相同 handle 覆寫商品」時，**CSV 裡有的欄位一律覆寫，空白儲存格會把既有資料洗掉**；CSV 裡**沒有的欄位**保持不變。

**⇒ 兩者語義是「同向」的：空白＝清空，欄位缺席＝不變更。** 我方設計的「翻譯 CSV 空白＝不變更」在 Shopify 生態裡**沒有對應**。

**我方原本的決定**
`i18n.import_export.blank_means_unchanged: true`（67 §E.6），理由是「翻譯檔常常只填部分語言，空白＝清空會造成大規模誤刪」。

**跟隨後改成**
🔴 **翻面成「空白＝清空」**，與商品 CSV 一致。
但我方原本擔心的誤刪風險是真的，Shopify 生態的解法**不是把空白解釋成不變更**，而是**用「欄位／語言的選擇性匯出」讓「不變更」以「欄位缺席」表達**。所以跟隨的完整形態是三件事一起：
1. `blank_means_unchanged: false`（空白＝清空）
2. 匯出時可**選擇要匯出哪些語言與哪些欄位**（不想動的就不要出現在檔案裡）
3. 匯入預覽必須把「將被清空的儲存格數」單獨列成一個數字（這是 Shopify 沒有、但把它翻面之後**必須**要有的護欄——否則第 1 條就是一個誤刪產生器）

**要改哪些檔案**
- `config/limits.yml` `i18n.import_export`（`blank_means_unchanged: true → false`，新增欄位／語言選擇性匯出鍵、新增匯入預覽的清空計數鍵）
- `docs/specs/67-multilingual.md` §E.6（整節改寫；「與商品 CSV 相反」這個標題本身要拿掉）
- `docs/handoff/2026-08-12-open-decisions.md` B-3 條（結論反轉）

**查不到**
Shopify 原生翻譯匯出／匯入是否存在、格式為何、空白語義為何 ⇒ **V-182**。本條的「跟隨」目前建立在 **Matrixify 這個第三方事實標準**上，等級只有 `press`，**不是 Shopify 官方語義**。若 V-182 查出官方原生行為與 Matrixify 不同，本條要重判。

---

### B-4 來源語言的粒度

**Shopify 實際做法**（`help`：`help.shopify.com/en/manual/international/localization-and-translation`）

- 預設／主要語言是**店級單一值**（Settings → Languages），**不能 per-resource**。
- **可以更改**。
- 🔴 **更改的代價**：把 X 語言設為新的預設語言，會**刪除該語言既有的全部翻譯**（因為那些內容從「譯文」升格為「本體」）。官方明確建議改之前先匯出。原本的預設語言若還要保留，必須**手動再加回**成次要語言。
- 未翻譯的內容一律以主要語言顯示。

**我方原本的決定**
`i18n.source_locale_per_shop: 1`、`source_locale_per_resource: false`、`source_locale_change_requires_migration: true`、`source_locale_change_missing_translation: keep_source_text`。

**跟隨後改成**
**粒度完全一致，不需改。** 要改的是**變更語義的描述**：
- 我方寫的是「遷移時目標語言缺譯 ⇒ base 保留原文並落 gap 記錄」——這是**缺譯**的處置，正確且比 Shopify 安全（Shopify 沒說缺譯怎麼辦）。
- 但我方**沒有**寫「**有譯文**的那些列會怎樣」。Shopify 的答案是：**該語言的譯文列消失**（升格為 base）。我方若實作成「base 換掉 ＋ 舊譯文列保留」，就會出現**同一語言同時是 base 又有一份譯文**的雙寫狀態。
- ⇒ 要補一條：`source_locale_change_promotes_translations: true`（目標語言的譯文升格為 base，該語言的 `translations` 列刪除；舊來源語言**不自動**加入次要語言清單——Shopify 也不自動，要商家手動加）。

**要改哪些檔案**
- `config/limits.yml` `i18n.source_locale_*`（新增升格語義與「舊來源語言不自動保留」兩鍵）
- `docs/specs/67-multilingual.md` §C.3（來源語言：誰是、能不能改）

**查不到**
無。本條由官方 help 直接回答。

---

### B-5 SKU 要不要提供「強制唯一」設定

**Shopify 實際做法**（`help`：`help.shopify.com/en/manual/products/details/sku`）

- 官方**建議**：同一 admin 內 SKU 應唯一，不應有兩個變體共用同一個 SKU。
- 偵測到重複時：在庫存區塊顯示**警告訊息**。
- 🔴 **不阻擋儲存**。商家可以忽略警告（官方也承認組合包等情境會合理重複）。
- 🔴 **沒有任何「強制唯一」的設定、開關或 app 級能力。** 商家層級、店鋪層級、API 層級都沒有。第三方 app（Cin7、Whiplash、GoDataFeed 等）的文檔一致把「Shopify 允許重複 SKU」當成**要自己處理的前提**，而不是可以在 Shopify 裡關掉的行為。

**我方原本的決定**
軟唯一已照做（`product.sku_unique_per_shop: false`、`sku_duplicate_action: warn_not_block`）。額外問題是要不要給有 WMS 整合的商家一個硬唯一開關（`verify_sku_strict_mode_option: true` 就是這個未決問題的殘留鍵）。

**跟隨後改成**
- **軟唯一 ＝ 已完全一致，不改。**
- 🔴 **硬唯一開關：Shopify 無此功能。** 「全部跟隨 Shopify」的字面結論是**不做**。
- 但這條與 B-1 不同——它不是被裁定排除，而是**Shopify 根本沒有**。所以要問使用者：
  **仍然要做嗎？** 我方的評估是「值得做，且不破壞 1:1 對齊」——理由是**預設關閉時行為與 Shopify 完全相同**，開關只是給有 WMS 的商家一個自我約束；不做的代價是 SKU 重複會直接打壞倉庫對接，而那類商家沒有別的自救手段（Shopify 上他們是靠第三方 app 補的，等於承認這是個真實缺口）。
  **這是使用者的產品範圍決定，本檔不代決。**

**要改哪些檔案**（僅在使用者同意「仍然要做」時）
- `config/limits.yml` `product.verify_sku_strict_mode_option`（改成明確的 `sku_hard_unique_optional: {enabled_default: false}`，並在註釋標明「🔴 Shopify 無此功能，ours」）
- `docs/specs/13-spec-products-inventory-media.md`（SKU 節）
若使用者決定不做：把該鍵刪掉，並在 13 註明「Shopify 無此能力，我方不補」。

**查不到**
無。官方 help 明文，且第三方生態的行為一致佐證。

---

### B-6 變體要不要有獨立 URL

**Shopify 實際做法**（三層，必須分開看）

**(a) 預設：變體沒有獨立 URL。** 只有 `/products/{handle}?variant={id}`。

**(b) `?variant=` 的 canonical ＝ 去參數的基底 URL。** 🔴 **本輪一手實測確認**（`test`）：
| 受測 URL | canonical 輸出 |
|---|---|
| `thesill.com/products/monstera?variant=39538230984781` | `https://www.thesill.com/products/monstera-deliciosa` |
| `otherland.com/products/fallen-fir-3-wick-candle?variant=41234567890123` | `https://www.otherland.com/products/fallen-fir-3-wick-candle` |

兩店主題不同，輸出形態一致 ⇒ Shopify 的 `canonical_url` 在 `?variant=` 下**不含該參數**。
⇒ 🔴 **這一併把 62 §B.2 的 V-110 結掉**（原記載為「只有主題商／代理商的二手描述（`press`），未取得官方文檔或實測」）。我方原本「按 Google 規則實作（去參數），不對齊傳聞」的處置，**現在證實與 Shopify 一致**。

**(c) 真的要「每個變體一個獨立可索引 URL」，Shopify 的官方答案是 Combined Listings（合併商品）**（`help`：`help.shopify.com/en/manual/products/combined-listings-app`）：
- 形態不是「給變體加 URL」，而是**把數個真實商品串成一個前台商品列表**。每個子商品**保有自己的 title／description／URL／圖片／價格／庫存**，在 feed 裡是獨立項目。
- 限制：**Plus／enterprise 方案**；需要 Online Store 通路；免費主題 15.0.0+ 支援，其他主題要改碼；商品必須已存在且**同時只能屬於一個 combined listing**。
- 上限：每個 combined listing 最多 **60 個商品**、**3 個自訂選項**、**2000 個選項值**。

**我方原本的決定**
不開放變體獨立 URL；例外情形（每變體真有各異標題／描述／主圖）可通過檢查後開啟（規格已寫成可切換，62 §B.2 模式 B）。

**跟隨後改成**
- **(a)(b) 預設行為 ＝ 已完全一致，不改**；V-110 標結案並補實測出處。
- 🔴 **(c) 是我方的缺口。** 我方的「模式 B」是「同一個商品的變體各自有 URL」——那正是 Shopify **刻意不做**的形態（會產生近似頁面）。Shopify 的做法是**在資料模型層就讓它們是不同商品**，於是不存在重複內容問題。
  ⇒ 跟隨後應**廢掉「模式 B ＝ 變體加 URL」**，改成**Combined Listings 等價物**：多商品合併展示、子商品各自 self-canonical、以 plan／能力閘門控制。這在架構上是不同的東西，不是一個開關。

**要改哪些檔案**
- `docs/specs/62-seo-geo.md` §B.2（V-110 標 ✅ 結案＋補 `test` 出處；模式 B 改寫成 Combined Listings 形態）、L204 的「每變體一個可索引 URL」那列
- `docs/specs/13-spec-products-inventory-media.md`（combined listing 的資料模型：parent／child 關係、單一歸屬約束）
- `config/limits.yml`（新增 `combined_listing.max_products: 60`、`max_custom_options: 3`、`max_option_values: 2000`，出處標 help）
- `docs/research/60-product-area-full-teardown.md`（商品區功能盤點補這一項）

**查不到**
Combined Listings 的**子商品 canonical 實際輸出**（self-canonical 還是指向 parent）——官方 help 未述，第三方文章只講「Google 分別索引」，未給 canonical ⇒ **V-187**。

---

### B-7 UCP（代理商務協定）要不要進路線圖

**Shopify 實際做法**

- UCP 由 **Shopify 與 Google 共同發起**（`press`：`shopify.engineering/UCP`），規格站 `ucp.dev`。
- **2026-01-11** 的官方公告（`press`：`shopify.com/news/ai-commerce-at-scale`）：
  - 20+ 零售商／平台背書；技術標準已可用。
  - **Google 通路**（AI Mode／Gemini 內原生購物）**"rolling out soon"**，商家在 Shopify admin 管理。
  - **Microsoft Copilot** 整合更新中，含新的嵌入式結帳。
  - **Agentic plan**：非 Shopify 商家也能接 Shopify Catalog，在 AI 通路上賣。
  - admin 內以 **Agentic Storefronts** 集中管理各 AI 通路。
- ⇒ **分階段推出中，不是一次到位**；且形態是**「後台的一個通路」＋「協定端點」兩件事**，不只是端點。

**我方原本的決定**
列 M7 之後，分兩階段（唯讀／可交易）；現在不做，但**不要輸出指向 404 的 `ucp_discovery_url`**。

**跟隨後改成**
- **節奏相容，路線圖位置不改。**
- 「不輸出指向 404 的 discovery URL」🔴 **這條要保留**——它不是 Shopify 的規定，是我方的正確判斷（代理在買家面前失敗比沒有更糟），Shopify 也沒有反例。
- 要補的是**形態**：我方 62 §H.3 目前只規劃了 `/agents.md`、`/llms.txt`、`/.well-known/ucp` 三條端點，**缺「Agentic Storefronts 這種後台通路」的對應**。跟隨 Shopify 的話，第二階段（可交易）的入口應該是**通路清單裡的一個 channel**（可啟用／可看訂單歸因），而不是一個設定頁的開關。這會影響 §H.3 的資料模型（channel 表要能容納 AI 通路）。

**要改哪些檔案**
- `docs/specs/62-seo-geo.md` §H.3（補 Agentic Storefronts 的通路形態；`ucp_*` 欄位未實作時不輸出的規定保留）
- `docs/research/43-platform-ecosystem-and-wiring.md`（通路模型補一類 `agentic`）
- `config/limits.yml` `seo` 的 agents／ucp 區塊（`ucp_discovery_url` 未實作時不輸出的鍵）

**查不到**
商家端是否 default-on、`/.well-known/ucp` 是否由平台自動輸出、Catalog 的資料完整度要求 ⇒ **V-186**。

---

## C. 低風險預設（6 條）

### C-1 `llms-full.txt`：Shopify 預設開還是關？

**Shopify 實際做法**（`dev`：`shopify.dev/changelog/customize-llmstxt-llms-fulltxt-and-agentsmd`，2026-05-28）

- 每個店鋪**預設就有** `/agents.md`。
- 🔴 **`/llms.txt` 與 `/llms-full.txt` 預設也指向同一份 `agents.md` 內容** —— 也就是**三條路徑預設全開，且內容相同**。
- 三個可覆寫模板：`templates/agents.md.liquid`（同時是 fallback）、`templates/llms.txt.liquid`、`templates/llms-full.txt.liquid`。
- fallback 鏈：專屬模板 → `agents.md.liquid` → 平台預設生成器。

**我方原本的決定**
`seo.llms_txt_enabled: true`（別名，照做）但 🔴 `seo.llms_full_txt_enabled: false`（預設關），理由三條：①沒有引擎官方宣稱消費它（V-117）；②它等於把商家全站內容做成一鍵可抓的封包；③生成成本隨商品數線性成長。

**跟隨後改成**
🔴 **改成 `true`。**
關鍵在於我方的三條理由**針對的是 `llms-full.txt` 的原始語義（整站 markdown 打包）**，而 **Shopify 的實作根本不是打包**——它就是 `agents.md` 的第三個別名。前提換了，理由 ②③ 直接消失（沒有第二份內容、沒有第二套快取、成本不隨商品數成長），理由 ① 對 `/llms.txt` 同樣成立而我方已經接受了。
⇒ **這是我方誤讀 Shopify 實作造成的分歧，不是價值觀分歧。** 62 §H.2 的推理本身沒錯，錯在它假設 Shopify 的 `llms-full.txt` 是打包。
- `llms_full_txt_max_bytes: 5242880` 在別名形態下用不到，但**保留**——商家一旦自訂 `llms-full.txt.liquid`，原始語義（整站打包）就回來了，那時這個護欄是必要的。
- 驗收條目 62 §O GEN-4「`llms-full.txt` 預設關 ⇒ 預設回 404」**必須反轉**成「預設回 `agents.md` 內容」，否則 CI 會把正確行為判成失敗。

**要改哪些檔案**
- `config/limits.yml` `seo.llms_full_txt_enabled: false → true`（註釋整段重寫，出處改指 2026-05-28 changelog）
- `docs/specs/62-seo-geo.md` §H.2（第 3 點「`llms-full.txt` 是另一回事，要拒絕」整段作廢，改記為「Shopify 的 llms-full 不是打包，是別名」）、§H.3 的三條路由圖（拿掉「預設關閉」字樣）、§O 驗收 **GEN-4**、§K 的預設值表

**查不到**
無。changelog 明文。

---

### C-2 多市場網域：新建市場的預設是什麼？

**Shopify 實際做法**

- 可選四種（`help`：`help.shopify.com/en/manual/international/managing-international-domains`）：**只用主網域**／獨立 ccTLD／子網域／子資料夾。
- **建議值**：首次設定國際銷售建議用**子資料夾**（設定簡單、有 SEO 好處）。
- 🔴 **但預設值不是子資料夾**。`changelog.shopify.com/posts/subfolders-are-no-longer-created-by-default-for-new-markets`（**2023-05-23**）：在此之前，新的單國市場會**自動建立語言／國家子資料夾**；此後**新的單國市場預設沿用 primary market 的 URL 結構**，子資料夾改為商家自行設定。
- ⇒ **「建議＝子資料夾」與「預設＝沿用主網域」是兩件事，Shopify 刻意把它們拆開。**

**我方原本的決定**
C-2「多市場網域＝**子資料夾**」（理由：集中權重、好維護）。

**跟隨後改成**
- **作為 UI 建議值 ⇒ 一致，維持。**
- 🔴 **作為新建市場的預設值 ⇒ 要改**：新市場預設**繼承 primary web presence 的網域與 URL 結構，不自動配子資料夾**。
- **為什麼這條不是雞毛蒜皮**：自動配子資料夾＝新增一批可索引 URL、一批 hreflang 條目、一批 sitemap 列。Shopify 在 2023 專門為此發 changelog 把它關掉，方向很明確——**多市場的 URL 增生必須是商家的明示動作**。我方若沿用「預設子資料夾」，商家每開一個市場就靜默多一份站點。

**要改哪些檔案**
- `config/limits.yml` markets／web presence 區塊（新增 `default_web_presence: inherit_primary`；子資料夾降為 UI 建議值）
- `docs/research/29-markets-i18n.md` §1（`MarketWebPresence` 的 `domain` XOR `subfolderSuffix` 已記載，但**缺「新市場預設 inherit」**這條）
- `docs/specs/62-seo-geo.md` §I（URL 矩陣的預設分支）

**查不到**
`help` 頁面本身**沒有**一句話明說預設值（本條的答案來自 changelog）。Shopify 官方 help 對「新建市場時到底發生什麼」是沉默的 ⇒ 若日後要逐字對照 UI，需 dev store 實測。不另開 V（changelog 已足夠可用）。

---

### C-3 地區自動重導：Shopify 預設是哪個？

**Shopify 實際做法**（`help`：`help.shopify.com/en/manual/markets/getting-started/localization`）

🔴 **官方明文：新店預設「啟用」自動重導，預設「停用」自動語言偵測。**（原文為一句陳述句，此處為語義轉述）

補充事實：
- 自動重導的判斷依據是瀏覽器語言 ＋ 地理位置（`help`：`.../international/automatic-redirection`）；`geoip` 已被併入自動重導（`changelog.shopify.com/posts/geoip-is-now-a-part-of-automatic-redirection`）。
- 🔴 **EU 例外（法遵）**：使用 EU ccTLD 的在地化體驗，EU 客戶**不會**在 EU 內被自動重導；官方要商家改用第三方 app 提供**「建議」**而不是重導。若市場用的是非國別網域（`.com`／`.shop`），EU 客戶照常重導。
- Shopify **自己沒有內建 recommendation banner**——「建議」這個形態官方是推給第三方 app 的。

**我方原本的決定**
`seo.redirect_geo.enabled_default: false`（預設關），理由是 Google 明文建議避免自動重導、IP 判斷不可靠。
另有 `i18n…auto_redirect_on_language: false`（語言自動重導不做）。

**跟隨後改成**
- 🔴 **地區重導：`enabled_default: false → true`。**
- ✅ **語言自動偵測：維持 `false`** —— 這一條**本來就與 Shopify 一致**（Shopify 也預設停用），我方之前沒意識到自己在這一半上已經對齊了。
- 🔴 **這一條是「跟隨 Shopify」與「外部權威（Google）」的直接衝突，不是與使用者裁定衝突。** 使用者裁定「全部跟隨 Shopify」⇒ 開。但必須把代價寫進規格：
  - 62 §K 引用的 Google 多地區網站指南**仍然成立**。Shopify 之所以敢預設開，是靠**爬蟲不重導 ＋ hreflang 完整**這兩件事把 Google 的疑慮擋掉。
  - ⇒ 我方一旦把預設翻成 `true`，`exclude_verified_crawlers: true`、`crawler_verification: reverse_dns`、`hreflang_urls_must_return_200: true` 這三條**從「開啟時的選配護欄」升格成「不可關閉的不變量」**。少了它們，預設開就是真的傷索引。
  - **V-116**（「排除爬蟲是否被 Google 視為可接受」）原本的處置是「未取得官方表態 ⇒ 預設維持關閉」——這個處置的前提沒了 ⇒ V-116 要重寫成「預設開，護欄不可關，風險登記」。
- **EU 例外必須照做**：ccTLD ＋ EU 來源 ⇒ 不重導。這是法遵，不是偏好。我方的 jurisdiction pack（鐵律 11）正好是承接它的地方。

**要改哪些檔案**
- `config/limits.yml` `seo.redirect_geo.enabled_default: false → true`；三條護欄改標為不可關；新增 `eu_cctld_no_redirect: true`
- `docs/specs/62-seo-geo.md` §K（整節翻面）、V-116 條目重寫
- `docs/specs/56-jurisdiction-architecture.md`（EU 例外掛進 pack 介面）
- `docs/research/29-markets-i18n.md` L156 市場判定鏈

**查不到**
無。官方 help 明文給出預設值。

---

### C-4／C-5／C-6 handle 生成的完整規則

**Shopify 實際做法**（`dev` 官方規則 ＋ 本輪 `test` 實測補完）

| 面向 | Shopify 行為 | 出處 |
|---|---|---|
| 大小寫 | 一律轉小寫 | `dev` liquid/basics |
| 空白 | → 分隔符 `-` | `dev` |
| 連續分隔 | 收斂成單一 `-` | `dev` |
| 開頭分隔 | **移除**（`&Kin Fall 2024 → kin-fall-2024`、`#HKSTYLE → hkstyle`） | `dev` ＋ `test` kith／god |
| 結尾分隔 | **修剪**（`A.P.C. → a-p-c`） | `test` kith（官方文檔只提開頭，未提結尾） |
| `.` | → 分隔符（`A.P.C. → a-p-c`、`B.M.B BREWERY → b-m-b-brewery`） | `test` kith／kurand |
| `/` | → 分隔符（`#AU/NZ → au-nz`） | `test` hardware.shopify.com |
| 🔴 `&` | **→ 分隔符，不展開成 `and`** | `test` ×5：`Carroll&Chan → carroll-chan`（god）／`Bags & Wallets → bags-wallets`（god）／`Herbs & Grow Kits → herbs-grow-kits`（thesill）／`Plant Duos & Trios → plant-duos-trios`（thesill）／`8th St … Clarks Originals & the New York Yankees → …-clarks-originals-the-new-york-yankees`（kith） |
| `%` | → 分隔符（`Clearance 50% Off → clearance-50-off`） | `test` god |
| `$` | → 分隔符（`Only HK$88 → only-hk-88`） | `test` god |
| `'` `"` | **刪除**（`Women's → womens`、`Men's → mens`、`16" Cash Drawer → 16-cash-drawer`） | `test` allbirds／god／hardware |
| `®` | 消失（`Trino® Sprinters → trino-sprinters`、`Tyvek® Zip → tyvek-zip`） | `test` allbirds／god |
| `#` `(` `)` | → 分隔後收斂（`… (DS2278) #AU/NZ → …-ds2278-au-nz`） | `test` hardware |
| 變音符號 | **折疊**（`Créature → creature`、`Décor → decor`） | `test` god |
| 全形 | **未查證** | ⇒ **V-181** |
| `_` | handle 中**允許存在**（`…sausage_regular`、`f7j9mb5i_manual`）；自動生成是否保留未證 | `test` kurand ⇒ **V-181** |
| 非拉丁（CJK 等） | **保留**（見 B-1(b)） | `press` ×4 |
| 長度上限 | **255**（第三方記載「超過會被截斷」）；官方文檔未見 | `press` matrixify ⇒ **V-183** |
| 🔴 重複 | **自動加數字尾碼，自 `-1` 起算** | `dev`（官方例 `potion`／`potion-1`）＋ `test`：`ceiling-fans` ／ `ceiling-fans-1`（同店兩個同名系列）、`home-decor-accessories-1`、`nathan-road-collection-1`、`denim-collection-2` |
| 改標題 | **不自動改 handle** | `dev` |

**我方原本的決定 vs 跟隨後**

| 條目 | 對照結果 |
|---|---|
| **C-6 `&` `%` 不做詞彙展開** | ✅ 🔴 **與 Shopify 完全一致，實測 5 次確認。** 我方 `expand_symbol_words: false` 不改。這是本輪 17 條裡對得最乾淨的一條 |
| 大小寫／空白／收斂／首尾修剪／`.`／`/`／`%`／`$` 轉分隔／`'`／`"` 刪除／變音折疊／改標題不動 handle | ✅ **逐條一致**。特別是 67 §D.1 觀察 4「`125ml/4.2oz → 125ml-4-2oz`，`.` 與 `/` 都轉分隔不是刪除」被 `A.P.C. → a-p-c` 與 `#AU/NZ → au-nz` 獨立佐證 |
| **C-4 品質閘門（拉丁字母 ≥3、丟棄比 ≤0.5）** | Shopify **無此概念**（它不需要，因為它保留 CJK）。我方獨有，是「一律 ASCII」裁定的必然衍生物 ⇒ **維持** |
| **C-5 中英混排保留英文片段** | 同上，Shopify 無此概念 ⇒ **維持** |
| ASCII-only vs 保留非拉丁 | 🔴 **不一致 ⇒ 使用者裁定 > Shopify**，維持我方（見 B-1） |
| 🔴 **重複尾碼起算值** | 🔴 **不一致，且沒有任何理由偏離** ⇒ **要改**：`numeric_suffix_from_2 → numeric_suffix_from_1`。順帶把 67 §M-1 登記的「13 §F2-2 寫 `-1`、67 寫 `-2`」這個內部不一致**反向解決：13 是對的，67 要改** |
| 手填重複 handle 的處置 | 我方 reject，Shopify 疑似自動加尾碼——但官方描述講的是「duplicate **title**」不是「手填 handle」，**沒有一手證據** ⇒ **V-184**；結案前**維持 reject**（保守失效） |
| `max_chars: 255` | 我方原本標「未查證（V-160）」，現在有 `press` 級佐證且**數值恰好相同** ⇒ V-160 可從「未查證」降為「二手佐證」，改由 **V-183** 承接「取得官方出處」 |

**要改哪些檔案**
- `config/limits.yml` `handle.collision_strategy_generated`（`from_2 → from_1`）、`handle.max_chars` 註釋（補 `press` 出處、V-160 → V-183）、`handle.expand_symbol_words` 註釋（補「實測 5 次確認 Shopify 亦不展開」）、`handle.charset`／`delete_chars`（補 `test` 出處）
- `docs/specs/67-multilingual.md` §D.1（驗證樣本表補 Shopify 實測對照列）、§D.4(b)（尾碼起算改 `-1`）、§M-1（不一致反向結案）、§L（V-160 改指 V-183）
- `docs/specs/13-spec-products-inventory-media.md` L188（`-1` `-2` 後綴——**這句是對的**，改的是 67 不是 13）
- `docs/specs/62-seo-geo.md` §F.3（handleize 九步管線的出處行）

**查不到**
全形字元與 `_` 的自動生成處置 ⇒ **V-181**；官方字元上限 ⇒ **V-183**；手填重複的處置 ⇒ **V-184**。

---

## D. 工程範圍授權（3 條）

### D-1 `61 §9` 剩餘上限值搬進 `limits.yml`

**Shopify 實際做法**：不適用（純內部工程）。
**我方原本的決定**：只搬了商品變體與商品系列兩節；媒體／庫存／CSV／SEO／禮品卡尚未搬。
**跟隨後改成**：**照做。** 鐵律 6 已經要求「上限值一律引用 `config/limits.yml`，不得硬編碼」，這只是把既有規則執行完。
**要改哪些檔案**：`config/limits.yml`、`docs/research/61-shopify-docs-products.md` §9（搬移後標註已落鍵）。
**查不到**：不適用。

### D-2 `collection.max_smart_collections_per_shop` 改名

**Shopify 實際做法**：官方語義已變成「含任何條件的系列」，`smart collection` 一詞被標 legacy（61 §9 已記）。
**我方原本的決定**：改名，但要全庫換引用。
**跟隨後改成**：**照做。** 建議新名 `collection.max_conditional_collections_per_shop`，並在舊鍵位置留一行 deprecation 註釋（不是別名——別名會讓兩個鍵同時存在）。
**要改哪些檔案**：`config/limits.yml`、`docs/specs/13`、`docs/research/61`、`docs/research/22`（凡引用該鍵處）。
**查不到**：不適用。

### D-3 `exponent=3` 幣別（KWD／BHD／JOD）

**Shopify 實際做法**

| 層面 | Shopify 的實際處置 | 出處 |
|---|---|---|
| **幣別代碼** | **支援**。`CurrencyCode` enum 含 **KWD／BHD／JOD／OMR／TND** | `dev` `shopify.dev/docs/api/admin-graphql/latest/enums/CurrencyCode` |
| **金額精度** | 🔴 **四捨五入到 2 位**。商家實測以 API 送 `3.004`，Shopify 存成 `3.00` | `press` community 147003 |
| **顯示** | 不一致：BHD 店家回報首頁／分類頁顯示 3 位（`BD 2.900`），**商品頁只顯示 2 位** ⇒ 官方沒有把 3 位小數做通 | `press` community 197071 |
| **收款** | Shopify Payments **不支援** Kuwait／Bahrain／Oman 開店（社群回報，官方無否認） | `press` community 1069509 |

**⇒ Shopify 的實質做法是「幣別代碼開放，金額當 2 位小數處理，精度損失不處理」，而不是「擋掉這些幣別」。**

**我方原本的決定**
「儲存 ×100 表達不了 milli-unit ⇒ **首發擋掉**；要支援＝全庫 migration」。

**跟隨後改成**
🔴 **不要把 KWD／BHD／JOD 從幣別清單擋掉**（那會讓 1:1 對齊出現一個 Shopify 沒有的缺口），改成三條明文：
1. **顯示與儲存一律 2 位小數** —— 這與 2026-08-12 裁定二（所有國家一律兩位小數）**天然吻合**，不需要例外邏輯。
2. **明文記錄精度損失**：KWD 的 `2.905` 存不進 ×100 的尺度，會落成 `2.90`。**Shopify 也是這樣**，所以這不是我方的缺陷，是跟隨的結果——但**必須寫進 65 號，不能靠沉默**。
3. 🔴 **PSP 邊界不放鬆**：鐵律 3 的「PSP 未宣告 minor unit 一律 reject」原封不動。ISO 4217 的 KWD exponent=3，若某 PSP pack 宣告 3，`Money::PspMinor` 的基數就是 1000，而我方儲存是 ×100 ⇒ **儲存尺度與 PSP 單位在此幣別下不同源**。這是一個**真實且未解**的問題，跟隨 Shopify **不解決它，只是允許幣別存在**。⇒ 結論：**幣別可選、收款要等 PSP pack 明文宣告，且該 pack 必須同時宣告如何處理儲存精度不足**。

> 🔴 **不要把本條讀成「鐵律 3 放寬了」。** 跟隨 Shopify 改的是「幣別清單」，不是「金額邊界」。

**要改哪些檔案**
- `docs/specs/65-money-unit-boundary.md`（新增 exponent=3 的明文處置：允許幣別、2 位小數、精度損失登記、PSP 仍 reject）
- `config/limits.yml` `currency_display` 區塊、jurisdictions 的幣別清單
- `docs/specs/55-money-tax-event-inventory.md`（金額測試矩陣：**exponent=3 幣別要進矩陣**，斷言「送 PSP 時若 pack 未宣告 ⇒ reject」）
- `docs/handoff/2026-08-12-open-decisions.md` D-3 條（結論反轉：不擋幣別）

**查不到**
Shopify 對 exponent=3 幣別**有無官方立場**（是否明文不支援 3 位小數，或只是 money 欄位限制 2 位）——官方文檔通篇沉默，本條全靠社群回報 ⇒ **V-188**。

---

## E. 需要法務而非工程（1 條）

### E-1 顯示價 ≠ 結帳價

**Shopify 實際做法**

- 🔴 **沒有任何價格鎖定機制。** 購物車不是報價單：商家改價後，cart line 的 merchandise 價格會反映**當前**價格；cart 的 `cost` 合計有快取／延遲，要一次 cart 更新才刷新；**結帳一律以當前價格重算**（`press`：community 194928、2736191、80607）。
- 官方與 moderator 對「購物車價 ≠ 結帳價」的回應方向是**排錯**（懷疑 app、自動折扣），**不是合規**。本輪**找不到任何 Shopify 官方文件**把「標示價與實收不符」當成價格標示的法遵議題來處理。
- 唯一接近「價格鎖定」的官方機制是 **draft order／invoice**（草稿訂單把價格固定在建立當下）；abandoned checkout 的復原連結**不保證原價**，一樣重算。
- 商家社群的實務共識是「以結帳頁看到的為準」——也就是**把責任推給結帳頁的顯示**。

**⇒ Shopify 對這個問題的做法是：技術上不鎖價、法遵上不表態、責任留給商家。**

**我方原本的決定**
帳務不會錯（server 端重算）；但「標示價格與實收不符」在香港是價格標示的法遵問題，具體條文未查證；建議投入法務查核。

**跟隨後改成**
- **技術面 ＝ 已完全一致**：不做價格鎖定、結帳重算。我方 server 端重算本來就是這個形態 ⇒ **不改**。
- 🔴 **法遵面：Shopify 給不出答案。** 這一條**不是「跟隨 Shopify」能結案的條目** —— 因為 Shopify 的做法是「不表態」，跟隨「不表態」等於什麼都沒決定。**是否投入法務查核，仍然要使用者決定。**
- **可以先做、且不需要法務意見的兩條工程護欄**（把法務問題縮小成可執行的東西）：
  1. 任何會改變已顯示價格的操作（改價、改匯率、改市場、改 price list）在 admin 送出前顯示明確提示：**此變更會即時影響已在購物車中的訂單**。這是「有權限的人日常操作就可能觸發」的實際入口。
  2. 結帳頁在金額與加入購物車時不同時，**明示變更**（顯示「價格已更新」而不是靜默套用新價）。Shopify 沒有這一條，但它正是「標示與實收不符」的實際觸發點，而且成本很低。
  > 這兩條是 `ours`，**不是跟隨 Shopify**，要照鐵律標清楚。第 2 條是**刻意超出 Shopify** 的合規保守處置。

**要改哪些檔案**
- `docs/specs/15-spec-cart-checkout-payments.md`（結帳重算的明文＋價格變動明示提示）
- `docs/specs/13-spec-products-inventory-media.md`（改價操作的影響提示）
- `docs/specs/11-production-baseline.md` §0 合規維度（把「價格標示」列為需法域 pack 承接的能力）
- `docs/specs/56-jurisdiction-architecture.md`（HK 價格標示規則掛進 pack 介面）
- `docs/handoff/2026-08-12-open-decisions.md` E-1 條（標明「Shopify 無對應處置，本條無法由對齊結案」）

**查不到**
Shopify 對「顯示價 ≠ 結帳價」有無任何官方合規說明或價格鎖定選項 ⇒ **V-185**。香港價格標示的具體條文**本檔未查**（那是法務範疇，不在「查 Shopify 怎麼做」的任務範圍內）。

---

## F. 附帶重大發現（不在 17 條內，但影響既有裁定）

### F-1 🔴 Shopify 的 handle **是可翻譯欄位**——我方 D-67-H2 是明知的偏離

`shopify.dev/changelog/resource-url-handles-are-now-translatable`（**2023-06-26**，API 2023-04）：**product／collection／article／blog／page 的 URL handle 可透過 `translationsRegister` 註冊翻譯**，以產生在地化的線上商店 URL（官方例：`/products/red-shoes` 與 `/products/…/zapatos-rojos`）。
實務佐證（`press`）：啟用多語言後，同一商品在各語言下**就是不同的 handle**；AJAX API `/products/{handle}.js` 必須用**該語言的 handle**，用預設語言的 handle 在其他語言下取不到；社群把它稱為 Shopify 架構的既知限制。
我方 `docs/research/29-markets-i18n.md` §2.1 **早就記載** PRODUCT 的可翻欄位含 `handle`。

- **我方的決定**：67 §D.3 決策 **D-67-H2**「handle 是 per-shop-per-resource 的單一值，語言走 URL 前綴」，`handle.per_locale_enabled: false`、`handle.translatable: false`。
- **在「全部跟隨 Shopify」之下，這是一條比 17 條裡任何一條都大的分歧**，而它**沒有被列進待裁決清單**。
- **本檔的立場**：🔴 **建議維持我方偏離，但要把它的標籤改掉。** 理由：使用者已裁定 handle 一律英文 ⇒ per-locale 的三個 handle 都會是英文 ⇒ 那不是在地化，是同義詞增生，在地化收益為零，卻要付三倍的 301、唯一性與 N+1 成本。**也就是說：這條偏離同樣是「裁定 > Shopify」的下游後果，不是獨立的技術偏好。**
- 但目前 67 §D.3 把它寫成「我方決策」，讀起來像是我方自己選的。**應改標為「🔴 明知偏離 Shopify 的決策，唯一依據＝handle 一律英文的裁定；裁定若改，本決策必須連帶重審」**，並保留既有的 `per_locale_schema_reserved: true` 逃生口。
- **要使用者確認的一句話**：`handle 一律英文` 這條裁定，是否**同時**意味著放棄 Shopify 的 per-locale handle 能力？（我方推定是，但這是推定。）

**要改哪些檔案**：`docs/specs/67-multilingual.md` §D.3、§M；`config/limits.yml` `handle.per_locale_enabled` / `handle.translatable` 註釋；`docs/research/29-markets-i18n.md` §2.1（標註「handle 可翻，我方刻意不做」）。

### F-2 ✅ V-110 結案（`?variant=` 的 canonical）

見 B-6(b)。一手實測兩店，Shopify 的 `canonical_url` **不含 `?variant=`**，與我方「按 Google 規則去參數」的實作一致。
**要改哪些檔案**：`docs/specs/62-seo-geo.md` §B.2 與 §L 的 V-110 條目（標 ✅ 結案，出處改 `test`）。

### F-3 Liquid `handleize` filter 對非 ASCII 的行為（V-161 的部分答案）

`community.shopify.dev/t/unicode-in-handleize-output/1060`（2024-10，Shopify staff 已復現）：`{{ 'Abc 123-D--E 🔪 ŭ' | handleize }}` 的**實際輸出保留 emoji、把 `ŭ` 折成 `u`**，與文檔描述不符（staff 承認並轉產品團隊，無結論）。
⇒ **filter 對非拉丁字元是「保留」，不是「落空」。** 這正面回答了 67 §D.5 / V-161 最擔心的情境：`{{ '顏色' | handleize }}` 在 Shopify **不會**回空字串，而是回 `顏色`。
⇒ 我方 filter 端的 `h-{sha1}` fallback **在 Shopify 上永遠不會被觸發**（因為 Shopify 不會產生空結果）。若主題把 handleize 的輸出寫死進 CSS（Ella 有 91 處用量），我方的 fallback 會與本尊**輸出不同字串**。
**跟隨後改成**：filter 端**保留非 ASCII 原樣**（我方 `liquid_filter_ascii_only: false` 已對）；`h-{sha1}` fallback 只在**輸入本身為空或全為分隔符**時觸發，**不得**因為「結果非 ASCII」而觸發。V-161 可從「行為未知」縮小成「僅剩全形／空輸入的邊界未證」（併入 V-181）。
**要改哪些檔案**：`docs/specs/67-multilingual.md` §D.5、§L 的 V-161；`config/limits.yml` `handle` 區塊末段 filter 說明。

---

## G. 🔴 與使用者既有裁定衝突的條目（不得默默改掉）

| # | Shopify 的做法 | 使用者既有裁定 | 本檔處置 |
|---|---|---|---|
| **B-1／C-4／C-5** | handle **保留 CJK**，中文標題直接得到中文 URL，從不落代碼，也不擋發布 | 「URL handle **一律英文，禁止中文**」（open-decisions §F） | 🔴 **裁定 > Shopify。** 維持 ASCII-only ＋ 代碼 fallback ＋ 品質閘門。只改論述（承認這是明知偏離），不改行為 |
| **F-1**（附帶） | handle **可 per-locale 翻譯**（2023-06-26 起） | 同上（一律英文 ⇒ per-locale 收益為零） | 🔴 **裁定的下游後果。** 維持單一 handle，但要改標成「明知偏離」，並請使用者確認這個推定 |
| **C-3** | 地區自動重導**預設開** | 無直接裁定；我方依據的是 **Google** 的多地區指南 | ⚠ **不是與裁定衝突，是與外部權威衝突。** 「全部跟隨 Shopify」⇒ 改成預設開，但三條爬蟲／hreflang 護欄**升格為不可關閉的不變量**，V-116 重寫 |
| **D-3** | 幣別代碼開放、金額 2 位小數、精度損失不處理 | 裁定二「所有國家一律兩位小數」；鐵律 3「PSP 未宣告 minor unit 一律 reject」 | ✅ **不衝突。** 跟隨改的是幣別清單，鐵律 3 原封不動。**不得讀成鐵律 3 放寬** |

---

## H. Shopify 沒有對應功能的條目

| # | 事項 | Shopify 的狀態 | 要問使用者的 |
|---|---|---|---|
| **B-5** | SKU 強制唯一 | 🔴 **完全無此功能**。只警告、不阻擋、無開關、無 app 級能力；第三方 WMS app 一律把「Shopify 允許重複 SKU」當成要自己吃下的前提 | **仍然要做嗎？** 我方評估：值得做且不破壞對齊（預設關＝行為與 Shopify 相同）。**但這是產品範圍決定，本檔不代決** |
| **C-4／C-5** | handle 品質閘門、中英混排保留英文片段 | Shopify **無此概念**（保留 CJK 就不需要） | 無需再問——它們是「一律英文」裁定的必然衍生物，裁定在就必須有 |
| **E-1** | 顯示價 ≠ 結帳價的法遵處置 | 🔴 **無價格鎖定、無官方合規說明**，只當排錯問題處理 | **是否投入法務查核？** 跟隨「不表態」等於什麼都沒決定，這條**無法由對齊結案**。另建議先做兩條不需法務的工程護欄（見 E-1） |
| **B-6** | 「變體加獨立 URL」這個形態 | Shopify **刻意不做**；官方等價物是 **Combined Listings**（把數個真實商品合併展示，Plus 限定） | 我方要不要做 Combined Listings 等價物、要不要照 Shopify 做成方案閘門？ |
| **C-3** | 內建的 recommendation banner | Shopify **自己沒有**，官方把「建議」推給第三方 app | 我方要不要**超出 Shopify** 內建一個（EU ccTLD 情境下 Shopify 商家只能裝 app，這是真實缺口）？ |

---

## I. 待查證（V-180 起）

| # | 未知 | 怎麼查 | 在查明前怎麼處置 | 相關節 |
|---|---|---|---|---|
| **V-180** | Shopify 自動生成 handle 對**非拉丁字集**的**官方**規則（本輪 4 個 `press` 來源一致指向「保留」，但**無任何官方文檔**；且有 1 則反例：goodsofdesire.com `8折 → 8`，研判商家手改） | dev store 實測（建純中文標題商品，看 admin 產生的 handle）；或 Shopify 官方文件化該行為 | 我方**行為不受影響**（裁定已定死 ASCII-only）。本 V 只影響「我方文檔如何描述 Shopify」——描述時必須標 `press` 而不是 `dev` | B-1、C-4 |
| **V-181** | handle 生成對 **全形字元** 與 **`_`** 的處置；以及 Liquid `handleize` 對**空輸入／全分隔符輸入**的輸出 | dev store 實測 ＋ Liquid 沙箱 | 我方維持 NFKC 正規化（全形→半形）與 `_ → -`；filter 端 `h-{sha1}` fallback **只在空輸入時觸發** | C-4、F-3 |
| **V-182** | Shopify **原生**是否提供翻譯 CSV 匯出／匯入，以及其**空白語義** | help 中心逐頁查 Translate & Adapt 的匯出功能；或 dev store 實測 | B-3 的「跟隨」目前建立在 **Matrixify 這個第三方事實標準**上（`press`）。若官方原生行為不同，B-3 要重判 | B-3 |
| **V-183** | Shopify handle 的**官方**字元上限（255 目前只有 Matrixify 這個 `press` 出處） | shopify.dev API 參考的欄位限制；或以超長標題實測 | 維持 `handle.max_chars: 255`（數值已有二手佐證且與我方相同）。**取代原 V-160 的「未查證」狀態** | C-4 |
| **V-184** | 商家**手填**重複 handle 時，Shopify 是**拒絕**還是**自動加尾碼**（官方講的自動加尾碼是針對「duplicate **title**」，不是手填 handle） | dev store 實測 | 維持我方 `collision_strategy_explicit: reject`（保守失效：不靜默改掉商家明確輸入的值） | C-4 |
| **V-185** | Shopify 對「顯示價 ≠ 結帳價」有無**任何**官方合規說明或價格鎖定選項 | help 中心的價格／結帳章節逐頁；Shopify 法遵頁 | 技術面照 Shopify（不鎖價、結帳重算）；合規面**懸置**，等使用者對「是否投法務」的決定 | E-1 |
| **V-186** | UCP 在商家端是否 **default-on**、`/.well-known/ucp` 是否由平台自動輸出、Catalog 的資料完整度要求 | `shopify.dev/docs/agents`、`ucp.dev` 規格站逐節 | 維持「現在不做，且不輸出指向 404 的 `ucp_discovery_url`」 | B-7 |
| **V-187** | **Combined Listings 子商品的 canonical 實際輸出**（self-canonical 還是指向 parent） | 找一個已啟用 combined listing 的 Plus 店實測 | 我方若做等價物，預設 **child self-canonical**（與 62 §B.4「一律 self-canonical」一致），不猜 Shopify | B-6 |
| **V-188** | Shopify 對 **exponent=3 幣別**的官方立場（是否明文不支援 3 位小數，或僅是 money 欄位限制 2 位） | shopify.dev 的 Money／MoneyV2 型別定義、International pricing 章節 | 幣別可選、**顯示與儲存 2 位**、PSP 未宣告 minor unit **一律 reject**（鐵律 3 不放鬆） | D-3 |

---

## J. 出處清單（查證日 2026-08-12）

**`dev`（shopify.dev／changelog）**
`shopify.dev/docs/api/liquid/basics`（handle 生成四條規則＋重複 `-1` 起算＋改標題不動 handle）｜`shopify.dev/docs/api/liquid/filters/handleize`（filter 定義，範例僅 `Health potion → health-potion`）｜`shopify.dev/changelog/customize-llmstxt-llms-fulltxt-and-agentsmd`（2026-05-28；三路徑預設全開、三模板、fallback 鏈）｜`shopify.dev/changelog/resource-url-handles-are-now-translatable`（2023-06-26；product／collection／article／blog／page 的 handle 可翻譯）｜`shopify.dev/docs/api/admin-graphql/latest/enums/CurrencyCode`（含 KWD／BHD／JOD／OMR／TND）｜`changelog.shopify.com/posts/subfolders-are-no-longer-created-by-default-for-new-markets`（2023-05-23）｜`changelog.shopify.com/posts/geoip-is-now-a-part-of-automatic-redirection`

**`help`（help.shopify.com）**
`/en/manual/international/translate-adapt-app`（自動翻譯直接上線、不覆蓋人工譯文、上限 2 語言）｜`/en/manual/international/localization-and-translation`（預設語言店級、可改、改了刪目標語言譯文）｜`/en/manual/products/details/sku`（SKU 應唯一、只警告不阻擋）｜`/en/manual/products/combined-listings-app`（Plus 限定、60／3／2000 上限、子商品各自 URL）｜`/en/manual/markets/getting-started/localization`（🔴 **新店預設啟用自動重導、停用自動語言偵測**）｜`/en/manual/international/automatic-redirection`（EU ccTLD 例外、建議走第三方 app）｜`/en/manual/international/managing-international-domains`（四種網域策略、首次設定建議子資料夾）｜`/zh-TW/manual/international/managing-international-domains`（zh-TW 版內容一致，未見落差）

**`test`（本輪一手實測，公開 JSON 端點與 canonical 抓取）**
`kith.com/collections.json`（`A.P.C. → a-p-c`、`&Kin … → kin-…`、`… Originals & the New York Yankees → …-originals-the-new-york-yankees`）｜`thesill.com/collections.json`（`Ficus & Fig Plants → ficus-fig-plants`、`Herbs & Grow Kits → herbs-grow-kits`、`Plant Duos & Trios → plant-duos-trios`）｜`goodsofdesire.com/collections.json`（`Carroll&Chan → carroll-chan`、`Clearance 50% Off → clearance-50-off`、`Only HK$88 → only-hk-88`、`Créature de Keis → creature-de-keis`、`Home Furnishing & Décor → home-furnishing-decor`、`ceiling-fans` / `ceiling-fans-1`、`home-decor-accessories-1`、**反例** `8折 → 8`）｜`hardware.shopify.com/products.json`（`(DS2278) #AU/NZ → ds2278-au-nz`、`16" Cash Drawer → 16-cash-drawer`）｜`allbirds.com/products.json`（`Women's → womens`、`Trino® → trino`）｜`kurand.jp/collections.json`／`products.json`（日文店：`B.M.B BREWERY → b-m-b-brewery`；handle 中出現 `_`；日文標題的 handle 大量被商家改成羅馬字或代碼）｜`thesill.com/products/monstera?variant=…` 與 `otherland.com/products/…?variant=…` 的 `rel=canonical`（**皆不含 `?variant=`**）

**`press`（Shopify Community／Shopify Engineering／第三方）**
community.shopify.com `/t/product-handles-with-international-characters-are-transliterated-for-some-languages/80006`（2021-11-22；中文與西里爾原樣、Baltic 折疊）｜`/t/cannot-update-product-handle-with-unicode-characters/239594`（admin UI 生成 unicode handle，staff Liam 承認、無後續）｜`/t/url/223998`（日文；日文標題產生長日文 URL）｜community.shopify.dev `/t/unicode-in-handleize-output/1060`（2024-10；staff 復現 `… 🔪 ŭ → …-🔪-u`）｜`/t/resource-url-handles-are-now-translatable/30530`｜community.shopify.com `/t/fetch-a-product-using-ajax-api-that-has-his-handle-translated/347763`｜`/t/product-identification-issues-with-shopify-i18n-…/570416`｜`/t/change-currency-decimal-3-digits/197071`（BHD 顯示 3 位／2 位不一致）｜`/t/update-shopify-product-price-upto-3-decimal/147003`（`3.004 → 3.00`）｜`/c/international-commerce/kuwaiti-dinar-is-not-supported-under-shopify-multi-currencies/td-p/1069509`｜`/t/why-i-use-storefrontapi-query-cart-when-product-price-change-cartcost-do-not-change/194928`、`/c/shopify-discussions/cart-page-item-price-does-not-update-to-new-price-on-refresh/m-p/2736191`、`/t/price-in-add-to-cart-and-at-checkout-are-different/80607`（購物車價格快取與結帳重算）｜`shopify.engineering/UCP`｜`shopify.com/news/ai-commerce-at-scale`（2026-01-11）｜`matrixify.app/documentation/translations/`（翻譯匯入空白＝刪除）｜`matrixify.app/documentation/shopify-limits/`（handle 255）｜`matrixify.app/tutorials/import-shopify-handles-with-non-english-characters/`（**Shopify 自己不轉寫**，轉寫是 Matrixify 的功能）｜`5-bit.jp/blogs/shopify/page-url-change`（日文頁面 URL 的 percent-encoding 實例）

---

## K. 本檔的可重跑驗證

任何人要覆核 §C-4 的實測表，執行下列即可（不需帳號，公開端點）：

```
1. 取 title→handle 對照：GET https://{store}/collections.json?limit=250
                          GET https://{store}/products.json?limit=250
   受測店見 §0.1。判讀規則：title→handle 若與生成規則吻合即視為自動生成；
   明顯被改寫者（增刪語義字詞）一律標「商家手改」不採信。
2. 取 canonical：GET https://{store}/products/{handle}?variant={任意數字}
                 讀 <link rel="canonical"> 的 href
3. 判 `&` 是否展開：任找 title 含 `&` 且 handle 其餘部分逐字對應的一列。
   本輪 5 例全部為 `&` → 分隔符收斂，0 例為 `and`。
```

> ⚠ 這些是**真實商家店鋪**，handle 可被商家覆寫。單一樣本不足為證，**本檔的每條字元規則都要求 ≥2 個獨立店鋪的一致樣本**，`&` 一條要求 ≥5。
