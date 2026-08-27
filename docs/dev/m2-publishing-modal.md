# 逐商品發布編輯 modal（M2 · S6b）

## 概述

商品詳情頁 `Publishing` 卡右上齒輪開啟的模態，讓商家**逐管道**開關這個商品的發布狀態。
本尊對位＝`Manage publishing for <商品標題>`（`docs/research/82` §12.1）。

🔴 **`Done` 不寫入任何東西**——它把 modal 內的草稿提交到頁面的未儲存變更，
真正的寫入在頁面層級的 `Save`，且走**獨立的 mutation document**，不併進 `productSet`。

## 規格出處

| 主題 | 出處 |
|---|---|
| modal 結構、左欄四節、群組半選態 | `docs/research/82` §12.1／§12.2（2026-08-26 實測） |
| `Done` 零寫入、發布是獨立 mutation | `82` §13.1／§13.2（2026-08-27 抓包） |
| 群組開關行為、搜尋比對法、暫存兩層、錯誤態、`@include` 開關 | `82` §14（2026-08-27 實測＋抓包） |
| 三層 AND 發布模型 | `docs/specs/88-publication-model.md` |
| 寫入語義（R1–R10 狀態矩陣、硬刪列、all-or-nothing） | `docs/dev/m2-publishable-write.md`、`Publications::Write` 檔頭 |
| V2 投影的三態語義 | `docs/dev/m2-resource-publication-semantics.md` |
| `switch` 不支援 `aria-checked="mixed"` | MDN《ARIA: switch role》（取證 2026-08-27） |
| 原生 `indeterminate` → `mixed` 的 AX 映射 | W3C html-aam 1.0（取證 2026-08-27） |
| 「owned property window」的 OK／Cancel 語義 | Microsoft Win32 UX Guide《Property Windows》（取證 2026-08-27） |

## 架構與資料流

```
Publishing 卡（齒輪）
  └→ PublishingModal（草稿 = local state，條件渲染 ⇒ 每次開啟都新鮮）
       ├ 群組總開關 GroupToggle（三態，值由各列導出）
       ├ 逐管道 SwitchRow（二態）
       └ Done → values.publicationDelta（頁面 dirty）／Cancel → 丟棄草稿
                    ↓
                 SaveBar『儲存』
                    ↓
          productSet（既有）→ 成功後 → PUBLISHING_MUTATION
                    ↓
             reloadPublications（重讀伺服器現值）
```

三個資料來源，職責不重疊：

| 來源 | 內容 | 誰寫 |
|---|---|---|
| `publicationRows` | 伺服器現況（已發布／已排程的列） | 載入與 `reloadPublications` |
| `publications` | **本店全部管道**（modal 的骨架） | 載入（與商品同一次往返） |
| `values.publicationDelta` | 待送出的增量 | modal 的 `Done` |

### 🔴 為什麼 delta 進 `values`

`dirty` 是 `JSON.stringify(values) !== snapshot`。delta 在 `values` 裡才會讓 SaveBar
自動亮起，這正是本尊的行為（§13.1：`Done` 後出現 `Unsaved changes`）。

**額外收益**：`applyDiscard` 走 `setValues(snapshot)` ⇒ 捨棄**自動**撤銷 modal 內的變更。
這正好滿足 Microsoft 對 owned property window 的逐字要求
"make sure users can cancel changes made in an owned property window by clicking Cancel"。
若當初把它另存成獨立 state，捨棄會漏掉它，症狀是「按了捨棄，發布卡卻還顯示待儲存」。

### 🔴 為什麼是 delta 不是完整期望狀態

後端就是 publish／unpublish 兩個方向的兩支 mutation。存完整期望狀態的話：
①它會**重複** `publicationRows` 的資訊，兩者可能矛盾（別的分頁改過之後）；
②送出前還要再對現況做一次差集，而那份現況可能已經不是計算時的那一份。

⚠️ 外部研究（關卡④）曾建議相反（存完整狀態、送出前 diff），理由是 React 官方
「Avoid contradictions in state」。**我方採 delta 正是為了同一條原則**——在有伺服器現況的
情況下，完整狀態才是那個會與現況矛盾的第二份真相。該研究自己也標明
「前端該存哪一種＝無第一方推薦」，故此為 ours 裁定。

## 控件逐個（鐵律 12.4 的四件事）

### 齒輪按鈕

①`Publishing` 卡標題列右上的 icon 鈕（`aria-haspopup="dialog"`，Lucide `Settings`），
形態沿用 SEO 卡的既有 `.cl-card__head-action`。
②開啟 modal。**建立態不渲染**——商品尚不存在，沒有可傳給 `publishablePublish` 的 GID，
且該態下管道清單根本沒查（`PRODUCT_QUERY` 只在編輯態跑）。
③`setPublishingOpen(true)`；`ref` 供 Modal 的焦點還原鏈使用。
④影響：Modal 原語（`#admin-root` 加 `inert`）。

### 逐管道開關（`SwitchRow`，`role="switch"`）

①每個管道一列，左側管道名、右側 toggle。清單骨架＝**本店全部管道**（`publications`），
不是 `resourcePublicationsV2`（後者沒有「未發布」的管道的列）。
②開＝發布、關＝取消發布。**這是狀態編輯器語義**，與批次 modal 的累加語義相反（§12.2）
——兩者**不得共用元件**。
③🔴 **值＝該管道的列是否存在**（`channelIsOn`），不是 `isPublished`。
V2 的 `isPublished=false` 是「已排程未到點（staged）」；綁錯會讓已排程的管道顯示成關閉，
商家一存就把它取消發布了，**而這個 bug 在沒有任何排程的環境下 100% 測綠**。
④影響：`values.publicationDelta` → `dirty` → SaveBar → 兩支 mutation。

### 群組總開關（`GroupToggle`，`role="checkbox"`）

①管道清單上方一列，左側群組名、右側三態 toggle。
②全開／全關／半選。**半選一律 → 全開**（§14.1 實測，含少數態複驗，**不是多數決**）；
全開 → 全關；全關 → 全開。作用域＝**目前可見（篩選後）的子集**（§14.2）。
③🔴 **不是 `role="switch"`**：`switch` 規範上不支援 `aria-checked="mixed"`，指定 mixed 會被
UA 降級成 `false` ⇒ 半選態會被螢幕閱讀器讀成「關」，而畫面完全正常、視覺測試不會紅。
值由各列於 render 期導出，**不另存 state**。`aria-controls` 指向各列 switch 的 id。
④影響：一次改動多個管道的 delta；被篩掉的管道**不得**波及。

### 搜尋框

①`type="search"`，placeholder 可見、label 只給輔助科技（本尊同形態）。
②即時篩選（本尊有 debounce，⚠️ 毫秒數未取得；我方不做 debounce——清單是個位數）。
🔴 **詞首前綴比對**，不是子字串（§14.3 四格實測）。大小寫不敏感、前後 trim。
③不符的列整個從 DOM 移除（本尊同形態，非 `display:none`）。
④影響：群組開關的作用域（見上）。

### `Cancel`／`Done`

①頁尾兩顆。②`Cancel` 丟棄草稿；`Done` 提交草稿到 `values.publicationDelta`，
**無變更時 disabled**。
③🔴 **`Cancel` 的作用域是 modal session，不是整頁 dirty**（§14.4d：已有暫存值時再開再
`Cancel`，先前暫存值**保留**）。我方靠條件渲染達成：`Cancel` 只 unmount 草稿，
不碰 `values`。
④`Done` 之後發布卡樂觀顯示「待儲存」badge，SaveBar 出現。

## API

```graphql
mutation productPublishing(
  $id: ID!
  $publicationsToPublish: [PublicationInput!]!
  $publicationsToUnpublish: [PublicationInput!]!
  $shouldPublish: Boolean!
  $shouldUnpublish: Boolean!
) {
  publishablePublish(id: $id, input: $publicationsToPublish) @include(if: $shouldPublish) { … }
  publishableUnpublish(id: $id, input: $publicationsToUnpublish) @include(if: $shouldUnpublish) { … }
}
```

🔴 **變數名與 `@include` 開關名都對齊本尊**（§14.7 抓包逐字）。三條理由：

1. 本尊的 `ProductSaveUpdate` **也帶同樣那兩個陣列**，但 `shouldPublish`／`shouldUnpublish`
   皆為 `false` ⇒ 兩支 document 共用變數、靠 `@include` 決定誰執行，不重複寫入。
2. 空的那一邊**整個 field 不執行**——送空陣列會讓 `Publications::Write` 白跑一次
   transaction 並多 bump 一次 stamp。
3. **`publish` 排在 `unpublish` 前面是刻意的**：GraphQL 對 mutation 的 top-level field
   是依序執行；順序相反且 publish 那半失敗的話，商品會落在「舊管道已移除、新管道沒加上」
   ＝**意外全下架**。反過來最壞只是多發布一個管道。

⇒ 回應形狀是**可選的**：被 skip 的 field 在 `data` 裡不存在，消費端一律用可選鏈。

## 測試

`app/frontend/admin/pages/ProductDetailPage.test.tsx` 的 `S6b 發布編輯 modal`，21 格。
本包全套 176 examples / 0 failures（本包前 155）。

**突變全部實跑轉紅**：

| 突變 | 轉紅的格 |
|---|---|
| M1 判準改綁 `isPublished` | 已排程顯示為開 |
| M2 撥回現況時不歸零 delta | 撥開再撥回 |
| M3 只看 publish 那半的 userErrors | unpublish 錯誤 |
| M4 不判 delta 是否為空，一律送 | 沒改發布就不送（另殺 6 格既有測試） |
| **M5 快照不歸零 delta** | **儲存後 delta 歸零**（🔴 見下） |
| M6 modal 以 `rows` 為骨架 | 列出全部管道（另殺 4 格） |
| M7 捨棄時保留 delta | owned property window |
| M8 卡片不看 `delta.publish` | 完成鍵樂觀更新 |
| M9 publish／unpublish 兩組互換 | 儲存送出兩組 |
| M10 群組改用 `role="switch"` | 群組 ARIA（另殺 3 格） |
| **M11 群組作用於全部管道** | **搜尋篩選時的作用域**（🔴 見下） |
| M13 搜尋改回子字串 | 詞首前綴 |
| M14 `@include` 開關恆真 | 只有 publish 方向 |

🔴 **M5 第一次沒轉紅，開出一個真缺口**，且證明我原本的註釋寫錯了機制。
移除 `savedValues` 的 `publicationDelta: EMPTY_DELTA` 之後 45 格全綠——因為快照與 `values`
**雙雙**停在非空 delta、彼此相等，SaveBar 照樣消失。真正的症狀只有一個且完全無聲：
**下次儲存重送同一份 delta**。
⚠️ 這與 `mediaOrder` 的 C8/C20 **不是同一個失效形態**——那邊有 `reloadMedia` 會把
`values.mediaOrder` 清成 `[]`，才會造成「永遠不相等」。照抄那句話會寫出一個斷言 SaveBar
的測試，而那個斷言在 M5 下是綠的。已補格並複驗轉紅。

🔴 **M11 第一次也沒轉紅**，但原因不同：是**測試選錯初始狀態**。第一版篩出關著的 `Shop`
再全開，而另外兩個管道本來就開著 ⇒ 不論群組作用於誰，斷言都通過。改寫成「篩出**開著**的
管道再全關」後才能區分。已複驗轉紅。

🔴 **M12（`channelSwitchId` 不轉義）沒轉紅，而那是預期內的**：GID 不含空白，
`aria-controls` 的空白分隔解析在不轉義時也不會壞。轉義是**防禦性的**（防日後有人拿它餵
`querySelector('#…')`，`/` 與 `:` 在 CSS 選擇器裡要跳脫），現有測試證明不了它必要
——已在程式碼註釋誠實登記。本尊在這裡是**直接用裸 GID 當 host id**。

## 已知限制與 TODO

### 射程外（天然邊界，非自行縮小）

本尊 modal 有四節，我方只做 `Sales Channels` 一節，因為另外三節的資料層都不存在：

| 本尊的節 | 我方現況（複驗指令） |
|---|---|
| `Agentic` | 無資料層（`grep -ril agentic app/models app/graphql` 只命中註釋） |
| `Catalogs` › `Regions` | 無 (publishable × catalog) 成員表（schema 只有 `sales_catalogs` 容器）⇒ 屬 **S10** |
| 排程（日曆 icon） | 無日期時間選擇器原語，且需要店鋪時區 ⇒ 屬 **S6b-2** |

⇒ 只有一節時**不渲染左欄導航**（單項導航是噪音）。登記為 V，S10 落地時回頭補。

### 刻意偏離本尊（逐條登記）

1. **`Discard` 走確認框**——本尊點下即生效、無二次確認（§14.4）。我方是包 4 的既有裁定，
   不在 S6b 射程內改動。
2. **零管道時顯示空態文案**——本尊是「銷售管道那一列整列消失」（§14.5）。我方卡片結構不同
   （沒有本尊那個 `All catalogs` 列），顯示空態較合理，且 S6a 已定。
3. **`Done` 標籤**——Microsoft 逐字 "Don't use Done, because it isn't an imperative construction."、
   GNOME 逐字 "This is clearer than a generic label like _OK_ or _Done_."（皆取證 2026-08-27）。
   鐵律 12（Shopify 1:1）優先 ⇒ 維持 `Done`，登記此已知偏離，避免日後 review 重開。
4. **不做 debounce**——本尊有（§14.3）。我方管道清單是個位數，debounce 只會讓輸入變鈍。
5. **顯式 `aria-checked="mixed"`**——本尊用原生 `indeterminate`（AX 上等價，見 §14.1）。
   我方這條路可測，且避開「React 官方沒有記載 `indeterminate`」的無依據區。
6. **只改發布時我方仍送 `productSet`**——本尊只送發布那一支（§14.7 結論 3）。
   我方 `productSet` 是宣告式全量、同值 no-op，差異僅多一次寫入與 bump 一次 `lockVersion`，
   無正確性問題。不在本包改既有 `save()` 的送出策略（鐵律 20.5）。

### 未落地的實測發現

- 🔴 **中文管道名的搜尋退化**：詞首前綴規則套到無空白書寫系統 ⇒「線上商店」搜「商店」
  不命中，只有整串前綴才行。這是照抄本尊的必然代價，已在測試中明文釘住。
  若日後要改善，須先裁定「偏離本尊的搜尋語義」，不得靜默改成子字串。
- ⚠️ **本尊的琥珀警示（`Channel Pill Button`）我方沒有**：它的觸發條件是
  `Active` ∧ 發布到 Shop ∧ 未發布到 Online Store（§14.6），依賴 Shop 管道的業務規則，
  而我方**沒有 feedback 概念**（`Types::Interfaces::Publishable` 檔頭已登記）。屬未來包。
- ⚠️ **`supportsPublicationForUnlistedProducts` 我方不用**：該欄位存在於 `PublicationType`，
  但**寫入層完全不讀它**（`grep -rn supports_publication_for_unlisted app/ --include=*.rb`
  只命中型別宣告）⇒ 後端不擋，UI 也不得自行發明閘門（S6a-2 的教訓：可購買性一律問伺服器）。
- ⚠️ **兩支 mutation 不在同一個 transaction**：graphql-ruby 的 mutation 各自開 transaction
  ⇒ 第二支失敗時第一支已提交。本尊那份 document 內部是否原子＝**不可觀測**（鐵律 14.3）。
  我方的收斂辦法是儲存後一律重讀，不做樂觀翻轉。
- ⚠️ **部分成功時 delta 一律清空**（`mediaOrder` C13 同構）：留著會讓之後每次儲存都重送同一份
  失敗清單。使用者靠重讀後的卡片看到真實狀態。

### 未取得（鐵律 19）

`82` §14.10 的 S6b-U1…U6，其中對本包最相關的是 **U3：存檔時的驗證錯誤形態**
——三種嘗試（Draft 發布、全管道關閉、Draft+Shop）在本尊**皆正常存檔**，未能觸發。
⇒ 我方的 `userErrors` 測試用的是**我方後端的契約**（`Publications::Write` 確實會回
`userErrors`），不宣稱它對應本尊的任何已觀測形態。

## 變更記錄

- 2026-08-27 S6b 初版：Sales Channels 節的編輯面。
