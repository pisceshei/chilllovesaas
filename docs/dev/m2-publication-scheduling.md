# 排程發布的到點副作用（M2／PR-C）

> 交付＝`app/services/publications/scheduled_publication_consumer.rb`
> ＋`app/services/publications/backfill_scheduled_stamps.rb`
> ＋`app/services/events/consumers.rb` 的註冊表一行＋`lib/tasks/publications.rake`。
> 裁定＝`docs/DECISIONS.md` **D53**；取證與依據全文＝`docs/plans/2026-08-27-PR-C-五格裁定書.md`
> （🔴 該檔 §0.3 列出 20 條**被推翻**的斷言，一律不得引用）。

---

## §1 這是什麼

S5（`publishablePublish`）讓商家把發布時刻設在未來，寫入時同一 transaction 補一筆
`event_outbox`，`available_at` **精確等於** `published_at`。到點那一刻該做什麼，
官方**全面沉默** ⇒ 由 D53 以 ours 裁定定案，本包是它的執行面。

**到點的唯一載荷是 cache stamp**（`products.publications_updated_at`），
不是「執行一個發布動作」——發布時刻早在寫入當刻就已落在 `resource_publications.published_at`，
可見性是**查詢時判定**（`Product.purchasable` 的 `published_on` 條件）。
⇒ 到點消費者不需要、也不得改任何發布狀態。

### §1.1 🔴 為什麼判準不是 `== ACTIVE`

`ProductStatus` 自 2025-10 起有第四值 `UNLISTED`，官方逐字：

> The product is active but you need a direct link to view it.
> （<https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductStatus>，取證 2026-08-27）

我方 `Product::PURCHASABLE_STATUSES` ＝ `{active, unlisted}`（`config/limits.yml:912`）。

寫 `!= ACTIVE` 的**具體事故形態**：UNLISTED 商品到點時 `Product.purchasable` 已放行、
`published_at` 已是過去 ⇒ **前台實際上已可購買**，但因非 ACTIVE 而未 bump stamp
⇒ **前台快取繼續供舊內容、無錯誤、無日誌**。這是 spec `T02` 釘住的那一格，
突變 M1（判準改 `== "active"`）會讓它轉紅。

⚠️ `config/limits.yml` 的 `sales_channels.future_publishing_requires_active_status`
登記的是**本尊規則**（射程僅 product），**不是我方生效判準**——見該鍵的行內註釋與 D53 F1。

---

## §2 到點那一刻做什麼（**只有五項，沒有第六項**）

| # | 動作 | 不合格時 |
|---|---|---|
| 1 | 重讀 `resource_publications` 該列（**payload 只作定位，DB 現值為權威**） | — |
| 2 | 列不存在 ⇒ no-op success | `decision: :row_gone` |
| 3 | `published_at` ≠ payload 的值 ⇒ no-op success | `decision: :superseded` |
| 4 | 依 `publishable_type` 分流取 status：`Product` 讀自己／`ProductVariant` 讀**父商品**／`Collection` 本規則不適用 | `decision: :no_stamp_target`（Collection） |
| 5 | `status ∈ PURCHASABLE_STATUSES` ⇒ `Product.bump_publications_stamp!` | `decision: :not_purchasable` |

**明確不做**（D53 §3.2）：不 UPDATE `published_at`／不翻 `products.status`／
不建或刪任何發布列／不新增掃描 due 列的常駐 sweeper／不對 `event_outbox` 加 stale 或
max-age 判斷／**不改 `app/services/events/relay.rb`**（掛載縫契約：接消費者只動註冊表）。

### §2.1 🔴 同一 topic 有**兩種** payload 形狀

`product.publication.changed` 有兩個真實生產者，形狀不同：

| 生產者 | payload | `available_at` |
|---|---|---|
| `Publications::Write#enqueue_scheduled_event!`（S5） | `{publication_id, publishable_type, publishable_id, published_at, scheduled: true}` | 未來的 `published_at` |
| `Catalog::StatusTransition` | `{product_id, resource_version, status_transition: {from, to}}` ——**沒有 `publication_id`** | `Time.current` |

假設一定有 `publication_id` 的事故形態：**每一次商品狀態變更都 KeyError** ⇒ 燒 8 次重試 ⇒
dead 表每天增長，而**測試若只用自捏 fixture 會全綠**（這正是 `Collections::ResyncConsumer`
H3 事故的逐字根因）。⇒ 分流在消費者內，spec `T09` 釘住，突變 M4 轉紅。

`status_transition` 型走**商品級 bump、無資格閘**——狀態轉移**兩個方向**都改變可見性
（`active→draft` 也必須讓前台快取失效）。且**不得重放任何 per-channel 副作用**（無 `publication_id`）。

### §2.2 🔴 不合格分支一律 `return`，**禁止 `raise`**

`Events::Relay#deliver` 只有兩條出口：正常返回 ⇒ delivery done；拋 `StandardError` ⇒
`available_at = now + 2^attempts` 秒退避（序列 2/4/8/16/32/64/128），
達 `events.outbox_dead_letter_attempts` ⇒ `status=dead`。

用 raise 表達「條件不合」的後果：每一筆不合格排程燒掉約 254 秒重試、在
`event_outbox.last_error` 留下**假錯誤**、最終進 dead 表被營運當真事故追查。
⇒ spec `T03`／`T04` 釘住，突變 M2（改 raise）會讓它們連同 `T21` 一起轉紅。

### §2.3 🔴 `superseded` 的比對必須到**秒**

payload 走 `row.published_at.utc.iso8601`（**秒級**），DB 欄位是 `datetime(6)`（微秒）。
直接 `==` 會把**每一筆合法事件**都誤判成 superseded ⇒ 到點永遠不 bump，而
`T01` 這種「排程後不動它」的快樂路徑仍可能因為 usec 恰為 0 而假綠。
⇒ `same_second?` 兩邊都取 `to_i`。任一邊缺值＝不可比 ⇒ 視為已改期（fail-closed）。

---

## §3 catch-up：**不自動補發布**（D53 F2，三層射程）

| 層 | 裁定 |
|---|---|
| **可見性層** | 不做也不需要做——查詢時判定，改回 ACTIVE 的那一刻自然可見 |
| **事件補送層** | 既有 relay **必然補送**（`available_at <= now` 無上界），本裁定不改變它、**不加 max-age 丟棄** |
| **補發布動作層** | 不存在也不新增（承接 `m2-resource-publication-semantics.md` §6 既有禁令） |

⚠️ 反直覺點的正確表述是「**改回 ACTIVE 的那一刻**自然可見」，
不是「錯過時點之後前台其實已經可見了」——DRAFT 情境下 status 層先擋住
（`PURCHASABLE_STATUSES` 不含 draft）。spec `T13` 把兩件事分別釘住。

業界術語＝Quartz `MISFIRE_INSTRUCTION_DO_NOTHING`。
🔴 **不是** Airflow catchup——後者關閉後仍為最新 interval 建 run，照字面搬會帶進相反語義
（裁定書 §0.3 R10）。

---

## §4 一次性 backfill（PR-C 必須額外交付）

S5 自 PR #151 起就在投排程事件，而 `Events::Consumers::REGISTRY` 在本包之前**沒有**
`PRODUCT_PUBLICATION_CHANGED` ⇒ `deliver_to_consumers!` 開頭 `return if consumers.empty?`
⇒ 這些事件到點被 relay 取走、派給**零個**消費者、直接標成 `published`
⇒ 接上消費者也**重放不到**（delivery 帳從未建立、事件已終態）。

`Publications::BackfillScheduledStamps` 掃 `resource_publications` 中
`publishable_type = "Product"`、`published_at <= now`、且商品 stamp 落後者，補一次。

🔴 **冪等靠 `at: row.published_at`**（不是 `Time.current`）：補完 stamp ≥ published_at，
重跑時「落後」不再成立 ⇒ 不再前進。用 `Time.current` 就**不冪等**（每跑一次前進一次），
spec `T22` 的第二次呼叫斷言 `bumped == 0` 正是釘這個，突變 M7 轉紅。

資格閘與消費者**同一條**（`PURCHASABLE_STATUSES`）——現值不合格者不補，
等它改回 ACTIVE 時由 `status_transition` 事件路徑 bump。

🔴 **跑完即結案，不是常駐 sweeper**。入口＝`bin/rails publications:backfill_scheduled_stamps`。
**不得掛到 `catalog:resync:publications`**——該 task 零實作（`91` §3.23）。

---

## §5 測試矩陣與突變驗證

spec＝`spec/services/publications/scheduled_publication_consumer_spec.rb`（24 examples）。

🔴 **T26 地基紀律：全部事件一律由真實生產者產生**（`Publications::Write.publish` ／
`Catalog::SaveProduct.call`），投遞一律走 `Events::Relay.drain!`，不直呼消費者
——到點語義與 delivery 帳都在 relay 裡，直呼會把兩層一起跳過。

**唯一例外是 `T08b`**，且在 spec 內明文標註：變體排程**在寫入層就被 reject**
（`validate_publish_date` 的 R12，官方 help 逐字
`You can't set a future publishing date for individual product variants.`）
⇒ 變體排程事件**沒有真實生產者**，該格只能直呼。`T08a` 用真實生產者證明這條路確實封死
（`INVALID_STATE` ＋ 零排程事件）。消費者仍保留變體分支——D53 §3.1 第 4 項明文
「實務上不會出現，但必須有分支不得炸」。

### 突變表（七個突變，全部實跑轉紅）

| 突變 | 改法 | 轉紅的格 |
|---|---|---|
| M1 | 判準改 `status == "active"` | `T02` |
| M2 | 不合格分支 `return` → `raise` | `T03`／`T04`／`T21` |
| M3 | 刪 `superseded` 守衛 | `T06` |
| M4 | 刪 `status_transition` 分支 | `T09`／`T11` |
| M5 | 變體不讀父商品 | `T08b` |
| M6 | 刪 `row_gone` 守衛 | `T05` |
| M7 | backfill 的 `at:` 改 `Time.current` | `T22` |

基線 24 examples / 0 failures。

---

## §6 跨功能影響與**目前還是斷的**環節

**上游**：`Publications::Write`（S5，排程事件的生產者）、`Catalog::StatusTransition`
（狀態轉移事件的生產者）——兩者契約本包**不動**。
**掛載點**：`Events::Consumers::REGISTRY` 一行。
**唯一副作用**：`products.publications_updated_at`。

🔴 **誠實登記（鐵律 19）**：本包把 stamp bump 起來了，但
**`publications_updated_at` 目前還沒有前台快取真的讀它** ⇒ bump 在端到端意義上仍是
半掛的。把它接成真正的快取失效屬 **S7（事件與快取失效）**；前台契約屬 **S9**；
第三層 catalog 過濾屬 **S10**。本包不越界，但不得把「stamp 已 bump」講成「快取已失效」。

---

## §7 關卡①複驗（help.shopify.com，2026-08-27 本輪重新取證）

D53 的依據在本輪被**獨立重跑一次**（不引用 `五格裁定書` §0.3 已推翻的 20 條）。
結論：**無一條與本包實作牴觸**，另補三條 D53 未涵蓋的事實。

### §7.1 正面補強我方判準的兩條

**① UNLISTED 的商家面定義**（`## Product status` 段，逐字）：

> **Unlisted**: the product details are complete and the product is available to be sold,
> but customers can't discover it.

⇒ 「可以被賣、但顧客無法發現」＝**可購買但不可發現**，與 Draft（details 未完成、不可賣）
**完全不同側**。這是 A 層 enum 逐字（`The product is active but you need a direct link to view it.`）
之外的**第二個獨立錨**，共同證實「非 ACTIVE 當單一分支」不成立。

**② 變體不可排程有兩處獨立官方錨**：
`## Limitations for future publishing` 的
`You can't set a future publishing date for individual product variants.`
與商品可用性頁 `Considerations` 的
`You can't set a publishing date for individual product variants.`
⇒ 證實 `validate_publish_date` 的 R12 是對的，spec `T08a` 的形態正確。

### §7.2 🔴 本輪新取得、D53 未涵蓋的三條（登記，不改本包）

| # | 事實（逐字） | 對本包的意義 |
|---|---|---|
| N1 | `You can't publish unlisted products to any third-party sales channels.` 且 UNLISTED 不進 contextual product feeds／Shopify Catalog／sitemap，並加 `noindex`／`nofollow` | ⇒ 到點時商品為 UNLISTED，「發布到 online store」與「發布到第三方管道」在官方語義上**已是兩種不同結果**。本包不受影響（載荷是**商品級** cache stamp，不是 per-channel 發布動作），但**第三層 catalog 過濾（S10）必須處理這個分歧** |
| N2 | 官方有**兩個平台側管理的 status**：`Suspended`（不可販售且商品細節不可修改）與 `Pending suspension`（維持當前 status），由智財申訴流程觸發、商家不可設 | ⇒ 「商家面 status 值域」與「admin 可能顯示的 status 標籤集合」**不是同一個集合**。我方 `Product::STATUSES` 目前無對位物，登記為未來觀察 |
| N3 | `If you use channel markets, then for a product to be made available in a sales channel, the product must be included in any catalogs that you assign to that channel market, and the product must be published to that sales channel.` | ⇒ 「已發布」只是**必要條件之一**，catalog 是第二道閘門。與 `docs/specs/88` 的三層 AND 一致，屬 **S10** |

### §7.3 官方沉默面（D 級缺席，**不得反向斷言**）

本輪對 future-publishing 全頁原始 markdown 逐字通讀（取得兩份互相對照），
全頁**不存在** notification／notify／email／alert／banner／warning／retry／catch up／
missed／skip／republish 等詞。逐條登記為未取得：

- 到點時商家端的**任何**回饋形態（banner／email／通知中心／activity log）
- 到點不合格後**排程值本身的去留**（是否被清除、是否保留）
- 錯過時點後把 status 改回 Active **是否會補做發布**（兩個方向皆無陳述）
- 到點時商品為 **ARCHIVED** 或 **UNLISTED** 的處置（Caution **只點名 Draft**）
- 多管道排程之間的原子性／執行順序／部分失敗處置
- 完整的「支援 future publishing 的 sales channel 清單」（help 只給 Shop app 一個反例）

🔴 這正是 D53 之所以是 **ours 裁定**而非「照抄本尊」的原因，也是本包每個 no-op 分支
**必須寫結構化 log** 的原因——官方不給回饋形態，我方至少要有營運可見性。

### §7.4 兩條與 S6（Admin UI）直接相關的形態（本包不做，先登記）

- **時區依店鋪層級**：`Settings → General` 的 **Store defaults** 區塊（店級單一值，
  官方以 Note 要求商家自行核對，措辭 `Verify that…` ⇒ 平台不保證商家設對）。
  我方 `published_at` 存 UTC，商家面呈現必須按店鋪時區換算——這是 S6 的契約。
- **輸入粒度＝日期＋時分（分鐘級）**，預設值是當日下一個 `:00` 或 `:30`，但可手打任意時分
  （官方例 `1:23 p.m.`）。product／collection／blog post·page 三處逐字相同。
- ⚠️ **help 內部不一致（登記）**：collection 排程的 UI 路徑，future-publishing 頁寫
  「Publishing 區塊 → Online Store 旁日曆 icon」，collection settings 頁寫
  「Channels → Sales channels 下拉的 Online Store 列 → 日曆 icon」。兩頁不互相引用。

---

## §8 🔴 關卡②③（後台實測＋抓包）＝**未取得**，需使用者解除

本輪嘗試三次導航至測試店（`/products` 兩次、store 根一次，各等 8/8/10 秒），
**全部 302 到 `accounts.shopify.com/lookup`**，第二次起出現 hCaptcha
（`document.title` ＝「登入：Shopify」，兩個 `newassets.hcaptcha.com` iframe，body 含 Password 欄位）。

⇒ 依鐵律 12.0 的載入紀律逐條排除後，確認**是認證牆，不是載入未完成、不是 404、不是空白頁**。
登入需要 ①完成 hCaptcha ②輸入密碼／密碼金鑰或第三方 OAuth——**三者都是執行方被明文禁止的動作**。

**兩組 fixture 完全未觸及**（`Product/9907126370539`、`Product/9911273160939`），測試店資料未被本輪改動。

**解除方法**：使用者本人在同一 Chrome（Browser 1）手動登入 `admin.shopify.com` 的
`chill-love-u5q5mnzq`，確認 `/products` 可直接開啟後重跑本路。

**對本包的影響**：本包的實作依據是 D53（其 M 層證據來自前一輪已完成的實測），
本輪的 help 複驗未推翻任何一條 ⇒ **不阻塞本包合併**；但 §7.4 的 S6 形態與
「到點後商家面到底看到什麼」仍為未取得，**S6 動工前必須補做**。
