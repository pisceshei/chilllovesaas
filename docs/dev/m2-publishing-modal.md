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
🔴 **accessible name 必須含可見文字「銷售管道」**（WCAG 2.5.3 Label in Name，Level A，
逐字 "the name contains the text that is presented visually"）——只給狀態動詞的話，
語音輸入使用者照畫面唸「點擊 銷售管道」找不到任何控件。本尊有同樣落差（§14.1），
我方此處刻意偏離，理由與 mixed 態用顯式 `aria-checked` 相同。
④影響：一次改動多個管道的 delta；被篩掉的管道**不得**波及。

### 搜尋框

①`type="search"`，placeholder 可見、label 只給輔助科技。
🔴 **這三個屬性是 ours，不是實測結論**——§12.2 對這個控件的全部逐字只有「`Search channels`
輸入框」，§14.3 補的是行為；type／placeholder 可見性／label 可見性**皆未取得**
（已列入 §14.10 的 U7）。附帶已知偏離：清除鈕靠 `type=search` 的瀏覽器原生實作，
Firefox 預設不渲染（本尊實測右側有 `⊗`，U8）。
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
④`Done` 之後發布卡樂觀顯示「待儲存」badge（新增方向）並**移除**被取消的管道（移除方向），
SaveBar 出現。
🔴 **`Done` 是否可按的判準＝「draft ≠ 開場暫存」，不是「draft 兩邊皆空」**——差別只在
「開場就已有暫存」的 session 顯現，而後者會讓撤銷變成按不下去（見 `sameDelta` 檔頭）。

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

`app/frontend/admin/pages/ProductDetailPage.test.tsx` 的 `S6b 發布編輯 modal`，34 格
（初版 21 格 ＋ 對抗性審查後補 13 格）。全套 189 examples / 0 failures（本包前 155）。

**突變 M1–M27 逐個實跑**，只有兩個沒轉紅且兩個都已誠實登記（M12 預期內、M25 是防線缺口）：

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
| M15 `changed` 改回「draft 兩邊皆空」 | 重開 modal 撤回暫存 |
| M16 `setLockVersion` 移回發布 mutation 之後 | 發布失敗後重試的 lockVersion |
| M17 齒輪拿掉 `disabled` | 儲存中／變體超過 250 時齒輪 |
| M18 `salesChannelsOf` 改成恆真 | catalog 不得混進銷售管道 |
| M19 不呼叫 `reloadPublications` | 儲存後真的重讀 |
| M20 `shouldPublish` 硬編 `true` | 只取消發布時 `shouldPublish=false` |
| M21 刪掉卡片的 unpublish 濾鏡 | 樂觀**移除**被取消的管道 |
| M22 拿掉 `toLowerCase()` | 搜尋大小寫不敏感 |
| M23 群組 label 拿掉可見文字前綴 | Label in Name |
| M24 刪掉 `role="status"` | 搜尋結果的 status message |
| M26 重讀失敗不標 stale | 不冒充伺服器真相 |
| M27 modal 標題改成不帶商品名 | 標題逐字對位 |

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

🔴 **M25（`.cl-switch--mixed` 的 knob 幾何改回錯的）沒轉紅，而這是一個真實的防線缺口**：
把橫線改回「寬 4px、無 height 覆寫」（＝直立短棒）之後**全套 189 格仍然全綠**。
⇒ **CSS 幾何在本倉庫目前沒有任何機械防線**。鐵律 13.3 要求的量測腳本
`scripts/rwd-check.mjs` 尚未建立（屬 PR-C0），而新增 `scripts/` 屬 18.3 人工合併射程、
且鐵律 20.4 要求先登記候選與代價再取得裁定 ⇒ **本包不自行新增判準**，
候選已登記於 `docs/specs/91-pit-register.md` §2。

## 對抗性審查（2026-08-27，PR #160）

初始候選推出後對本包做了一次五維度對抗性審查（正確性／對齊本尊／無障礙／測試充分性／
跨模組影響），每條 finding 再由兩個獨立 lens 嘗試推翻（一個實際讀碼推演、一個查是否已登記）。
32 條 finding，**23 條通過雙 lens**，去重後 9 個真問題，本輪全部修復：

| # | 級別 | 問題 | 修法 |
|---|---|---|---|
| 1 | 🔴 | `changed` 判準是「draft 非空」而非「draft ≠ 開場暫存」⇒ 重開 modal 撤回先前暫存時 `Done` **鎖死**，使用者撤銷不了，一存就真的下架 | `sameDelta` 集合比較 |
| 2 | 🔴 | 儲存後的 `reloadPublications` **完全不可觀測**（重讀路由回同一份 fixture、零呼叫斷言）——刪掉那一行測試全綠 | 重讀路由改回不同的一份＋呼叫斷言＋兩維斷言 |
| 3 | 🟡 | 發布 mutation 拋例外時 `lockVersion` 沒吸收 ⇒ 此後**每次**儲存都撞 `STALE_OBJECT`，連標題都存不回去 | `productSet` 成功當下就吸收 |
| 4 | 🟡 | `variantOverflow` 連坐：發布變更可暫存但永遠存不進去 | 齒輪 disabled＋說明；更正被推翻的登記 |
| 5 | 🟡 | `Query.publications` 含 catalog publication ⇒ 混進「銷售管道」節、被群組總開關一併寫入 | `salesChannelsOf` 依 `handle` 過濾（fail-closed） |
| 6 | 🟡 | `.cl-switch--mixed` 只覆寫 `width` 未覆寫 `height` ⇒ 渲染成**直立短棒**而非實測的橫線 | `width:14 height:4 top:7 translate:7px` |
| 7 | 🟡 | 齒輪沒有 `disabled={saving}` ⇒ 儲存中可重開 modal，之後的錯誤 toast 落在 `inert` 樹內、對輔助科技**完全靜默** | 齒輪 disabled＋儲存時關閉 modal |
| 8 | 🟡 | 搜尋結果無 status message（WCAG 2.2 SC 4.1.3）／群組開關 accname 不含可見文字（SC 2.5.3） | 固定位置 live region＋accname 加前綴 |
| 9 | 🟡 | 搜尋框把三個**未量測**的屬性寫成「本尊形態（§12.2）」 | 改標 ours＋新增 §14.10 的 U7／U8 |

另修三條較輕的：卡片在重讀失敗時冒充伺服器真相（加 `stale` 第三態）、字面 `1px` 違反
`tokens.css` 的「全站邊框一律 `var(--hairline)`」、群組列 en 文案大小寫（`Sales Channels`）。

🔴 **審查也推翻了本文件原本的一句登記**（「只改發布仍送 productSet…無正確性問題」），
更正見下方「刻意偏離本尊」第 6 條。

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
   我方 `productSet` 是宣告式全量、同值 no-op，代價是多一次寫入與 bump 一次 `lockVersion`。
   不在本包改既有 `save()` 的送出策略（鐵律 20.5）。

   🔴 **2026-08-27 更正（對抗性審查推翻）**：本條原文結尾是「**無正確性問題**」，那句是錯的。
   `save()` 開頭有 `if (variantOverflow) { … return; }`（審查 C0：變體超過 250 時整頁封鎖），
   而發布寫入被這個閘門**連坐**——變體超過 250 的商品，發布變更可以撥、可以按完成、
   卡片會掛「待儲存」badge、SaveBar 會亮，但按儲存**一個請求都不送**，使用者只看到一句
   與發布無關的「變體太多」。審查以實跑複驗（fixture 加 `pageInfo.hasNextPage=true`）
   得到 `PUBCALLS = 0 | SaveBar still = true`。
   ⇒ 本輪處置：**齒輪在 `variantOverflow` 時 disabled 並帶說明**（見下方「刻意偏離」第 7 條），
   讓使用者不會暫存出一個存不進去的變更。真正解除要等 variantOverflow 本身解除（變體子頁）。

7. **`variantOverflow` 時齒輪 disabled**（ours）——本尊沒有這個狀態（它不封鎖整頁儲存）。
   理由見上一條的更正。**代價誠實登記：超過 250 變體的商品目前無法從詳情頁改發布狀態。**

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
