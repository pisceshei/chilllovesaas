# 排程發布的接線（M2 · S6b-2b）

## 概述

把 S6b-2a 交付的三個原語（`Popover` / `Calendar` / `SchedulePopover`）接進 S6b 的發布編輯
modal，讓「排程發布」真的能設定、能送出、能在卡片上看見。

S6b-2a 交的是**能單獨測的零件**，本包交的是**它們與發布狀態機的接縫**——
接縫才是出事的地方：排程要不要另存一份狀態、`Done` 的啟用條件怎麼比、
送出時 `publishDate` 帶不帶、樂觀更新要不要含排程。

## 規格出處

| 主題 | 出處 |
|---|---|
| 排程入口的位置與顯示條件 | `docs/research/82` §12.3、§15.10 |
| 排程送出的 payload 形態 | `docs/research/82` §15.8（抓包，鐵律 14） |
| `Remove schedule` 的終態 | `docs/research/82` §15.7 |
| 卡標題列的排程計數 badge | `docs/research/82` §15.9 |
| 按 `Done` 後卡片樂觀更新 | `docs/research/82` §13.1 |
| 時區來源＝店鋪設定 | `docs/dev/m2-schedule-popover.md`（S6b-2a） |

## 🔴 四個設計決定，每個都有一個「不這樣做會怎樣」

### 1. 排程不另存狀態，它是 `publish` 的一個欄位

`PublicationDelta.publish` 從 `string[]` 改成 `PublishEntry[] = { publicationId, at }`。

**為什麼不開一份 `schedule: Map<id, at>`**：兩份狀態會產生
「`schedule` 有 id 但 `publish` 沒有」的不可能組合，而那個組合送出去就是**一筆沒有目標的排程**。
本尊也沒有獨立的 schedule mutation——「排程」＝帶未來 `publishDate` 的 `publishablePublish`（§15.8）。

`at === null` ＝立即發布。

### 2. `at` 為 null 時 payload **不帶 `publishDate` 這個 key**

```ts
entry.at === null
  ? { publicationId: entry.publicationId }
  : { publicationId: entry.publicationId, publishDate: new Date(entry.at).toISOString() }
```

**不能傳 `publishDate: null`**：後端對明確 null 一律 reject。官方文檔對「傳 null 代表什麼」
完全沉默（R10），我方不得自行定義成「取消排程」——省略才是「立即」。

### 3. 「伺服器上有排程」的判準是 `isPublished === false`，不是 `publishDate` 非空

```ts
if (!row || row.isPublished || !row.publishDate) return null;
```

V2 的 `isPublished: false` 就是「已排程未到點（staged）」。
**每一列都有 `publishDate`**——已發布的列存的是「當初發布的時刻」，是過去值。
只看 `publishDate` 非空會把**所有已發布管道**都當成排程中。

⚠️ 這條在測資裡很容易漏測：只要 fixture 沒有同時出現
「`supportsFuturePublishing` ∧ `isPublished: true`」的管道，錯的判準也全綠。
本包的 `MW2` 突變一開始殺不掉任何測試，就是這個原因；補了第三個 publication 才轉紅。

### 4. `sameDelta` 要比 `(id, at)` 兩個欄位

```ts
const key = (entry: PublishEntry) => `${entry.publicationId}@${entry.at ?? "now"}`;
```

只比 id 的話，「同一個管道改了排程時間」會被判成沒變 ⇒ `Done` 停在 disabled，
**商家改不了已暫存的排程**。

## 逐個控件（鐵律 12.4 的四件事）

### `ChannelScheduleButton`（管道列右側的日曆 icon）

| | |
|---|---|
| ①**是什麼** | 一顆 `cl-icon-button` ＋ 它開出的 `SchedulePopover`，位在發布 modal 每一列的行尾 |
| ②**功能** | 顯示條件＝該 publication 的 **`supportsFuturePublishing`**。已排程時 `aria-label` 變成「發布於：{時刻}」並加 `--on` 高亮；未排程時 label 是「排程發布」 |
| ③**怎麼做到** | 條件渲染而非 `open` prop——`SchedulePopover` 的 state 靠 unmount 清空（本尊每次重開彈層完全重置，§15.10）。`scheduledAt` ＝待送 delta 優先、否則伺服器值 |
| ④**跨功能影響** | 寫入 `values.publicationDelta` 的 `at` 欄 → 決定送出的 `publishDate` → 決定發布卡的 badge 與卡標題的計數 |

🔴 **顯示條件不是「目前已發布」**：§15.10 實測，toggle 關掉時 icon 仍在、彈層仍可開。

⚠️ **刻意偏離登記**：本尊未排程時是 **hover 才出現**這顆 icon，我方**一律顯示**。
理由——hover-only 在觸控裝置上沒有對應手勢，而它是唯一的排程入口。

### 發布卡的排程 badge

`pendingAt !== null` 時顯示 `排程於 {at}（待儲存）`，優先於「已發布／待發布」兩態。
商家剛在彈層設好時間按了 `Done`，卡片必須立刻反映（§13.1 的樂觀更新），
否則看起來像沒生效。

### 卡標題列的排程計數

`scheduledCount` ＝伺服器現值**套上待送 delta**：
`at === null` 的 entry 要把該 id **移除**（改成立即發布 ⇒ 不再是排程），
`unpublish` 的 id 也要移除。只數伺服器的話，剛設好的排程不會計入。

## 兩個時間基準

| 值 | 取法 | 為什麼 |
|---|---|---|
| `shopTimezone` | `Query.shop.ianaTimezone`，與商品同一次往返 | 排程一律用**店鋪時區**，不是瀏覽器。載入前預設 `UTC`——此時齒輪還不可按，不會用錯的時區算 |
| `publishingOpenedAt` | 開啟 modal **那一刻**取一次 | 排程彈層用它算下限（今天之前灰掉、過去時間夾到 now）。每次 render 取的話，下限會在使用者填表期間一直往前爬，**剛選好的時間下一秒就變成「過去」** |

## 一個順手修掉的既有缺陷

`setLockVersion(product.lockVersion)` 原本在 publishing mutation **之後**才呼叫。
發布 mutation 失敗時 `lockVersion` 不會更新，而 `productSet` 已經成功寫入並遞增了伺服器端版本
⇒ 之後每一次儲存都撞 `STALE_OBJECT`，**永久卡住**，只能重新整理。

改成 `productSet` 成功後**立即**更新。

## 測試

`ProductDetailPage.test.tsx` 75 格全綠（本包新增的在 `S6b-2b 排程接線` describe）。

突變覆蓋（每格都實跑確認轉紅）：

| 突變 | 預期轉紅 | 實際 |
|---|---|---|
| `MW1` 排程入口改用「目前已發布」當條件 | ✅ | 轉紅 |
| `MW2` `serverScheduleOf` 改成只看 `publishDate` 非空 | ✅ | **一開始沒轉紅**——fixture 缺「已發布 ∧ 可排程」的組合。補第三個 publication 後殺掉 4 格 |
| `MW3` `sameDelta` 只比 id | ✅ | 轉紅 |
| `MW4` payload 改成明確傳 `publishDate: null` | ✅ | 轉紅 |
| `MW5` `scheduledCount` 只數伺服器 | ✅ | 轉紅 |

## 已知限制與 TODO

### 射程外（天然邊界）

- **本尊在「已有暫存排程」時按 `Cancel` 的行為**＝§14.10 未取得（需要在測試店造出該狀態並抓包）。
  我方沿用 S6b 的處置：`Cancel` 丟棄整份 draft。
- **多個管道同時排程不同時刻**：資料結構支援，但本尊測試店只有 Online Store
  一個 `supportsFuturePublishing` 的管道 ⇒ **無法實測本尊的呈現形態**，我方形態未經對照。

### 未取得（鐵律 19）

- 本尊排程 badge 的**確切文案**：§15.9 只取到 tooltip 的 `Publish on: …`，
  卡片上的呈現未取得（該店沒有已排程的商品，且造一個會影響 fixture）。
  我方文案「排程於 {at}（待儲存）」是**我方措辭**，非本尊原文。

### 待補（層④）

本包的三個新畫面（排程入口 icon／排程彈層／卡標題計數）**尚無本尊 CSS 量測**，
由**另一個工作包**（本尊 CSS 量測涵蓋排查）統一登記，不在本包射程。

## 變更記錄

| 日期 | 變更 |
|---|---|
| 2026-08-28 | S6b-2b 初版：排程接線、`PublishEntry` 型別、四個設計決定、`lockVersion` 缺陷修復 |
