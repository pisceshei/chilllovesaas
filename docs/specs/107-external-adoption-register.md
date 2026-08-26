# 107 — 外部方案採用登記簿

> 依 CLAUDE.md 鐵律 9 的增補條款建立：「外部方案的採用／拒絕逐項登記於
> `docs/specs/107-external-adoption-register.md`」。本檔在 D49（2026-08-25）隨第一個
> 需要登記的採用（OpenCC 字元表）正式建立——早於原定的「隨合併版總方案 R-8 引入」，
> 因為採用先發生了；R-8 屆時直接續用本檔。
>
> **登記門檻**：任何第三方**內容**（代碼、資料檔、字表、schema、詞庫）要進倉庫，
> 必須先有一列。純參考（讀完自己寫）不登記，但授權紅線照鐵律 9：
> GPL 家族禁讀禁抄；MIT／BSD 可參考；Apache-2.0 需使用者知情（專利授權＋NOTICE 義務）。
>
> **每列七欄**：編號／專案／授權（含複驗 URL）／採用內容／落點／義務履行／裁定錨。

## 採用

### OpenCC-1：Open Chinese Convert 字元表（2026-08-25，D49）

| 欄 | 值 |
|---|---|
| 專案 | OpenCC（Open Chinese Convert），<https://github.com/BYVoid/OpenCC> |
| 授權 | **Apache-2.0**。複驗＝<https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE>（2026-08-25 抓取，首兩行逐字 `Apache License` / `Version 2.0, January 2004`） |
| 採用內容 | **僅兩個資料檔**（原樣未修改）：`STCharacters.txt`（簡→繁字元映射，4012 資料行）、`TSCharacters.txt`（繁→簡，4148 資料行）。**不含任何 OpenCC 原始碼**。 |
| 落點 | `lib/opencc/`（連同上游 LICENSE 逐字副本與我方 NOTICE）。消費者＝`app/services/translations/script_detector.rb`（繁簡誤借稽核 `script_mismatch` 的判別核心）。 |
| 義務履行 | ①LICENSE 逐字入庫同目錄 ②NOTICE 載明版權人、來源 URL、抓取日期、三檔 SHA-256（複驗＝`sha256sum lib/opencc/*`）③本登記列。Apache-2.0 §4：redistribution 附授權副本＋標明來源——皆滿足；未修改檔案 ⇒ 無「修改聲明」義務。 |
| 專利面 | Apache-2.0 §3 授予專利授權；資料檔（字元映射表）本身非可專利標的，風險面極小，仍照鐵律 9 走知情裁定。 |
| 裁定錨 | `docs/DECISIONS.md` **D49**（2026-08-25 使用者裁定「引入（連 NOTICE＋attribution 一起入庫）」，回應第 7 包 dev doc §7 的待裁定項）。 |

**刻意不採用（同專案）**：`TWPhrases.txt` 等**詞庫**（詞彙在地化：软件↔軟體）——
那是 `machine_translation`／`script_conversion`（ML-5）的射程，且電商詞覆蓋率未量測
（第 7 包研究輪登記的疑慮）；字形稽核只需要字元表。日後要用詞庫＝新開一列，不得引用本列。

### S5-1：批次寫入的原子性策略（2026-08-27，發布寫入 API）

| 項 | 內容 |
|---|---|
| 情境 | `publishablePublish`／`publishableUnpublish` 一次打 N 個 publication，其中一筆不合法時要整批中止還是逐筆獨立？ |
| 🔴 本尊怎麼說 | **未取得**——`publishablePublish` 頁對 `partial`／`fails` 兩個關鍵字皆 Not found on page（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/publishablePublish>，2026-08-27） |
| **採用** | **全有全無（all-or-nothing）**。三個依據：①同表同線的既有先例 `Publications::Write.update`（已有 spec 逐字釘死）；②本尊在**別支**把逐筆獨立做成明確 opt-in——`productVariantsBulkUpdate.allowPartialUpdates` 逐字 `When partial updates are not allowed, any error will prevent all variants from updating.`、`metafieldsSet` 逐字 `This operation is atomic, meaning no changes are persisted if an error is encountered.`（兩者皆 2026-08-27）；③**Saleor（BSD-3）** 預設 `errorPolicy: REJECT_EVERYTHING`，逐字 `If a single error occurs, in at least one of the objects, the whole mutation fails and no data is saved.`（<https://docs.saleor.io/developer/bulks/error-policy>，2026-08-27） |
| **拒絕** | Saleor 的第三級 `IGNORE_FAILED`（單筆內部分保存）——會讓資源落到半完成狀態，而我方沒有任何面可以讓商家看見「這一筆只成功了一半」 |
| 🔴 登記口徑 | 我方取全有全無是 **ours 裁定＋既有一致性**，**不得寫成「照抄本尊」**（本尊該支未取得） |

### S5-2：取消發布時的資料處置（2026-08-27）

| 項 | 內容 |
|---|---|
| 🔴 本尊怎麼說 | **完全沉默**——`publishableUnpublish` 正文與全部八個 Examples、`PublicationInput`、`ResourcePublication`、`ResourcePublicationV2`、`Publishable`、`product-publishing.md` 皆未陳述紀錄去向（2026-08-27 逐頁確認） |
| **參考** | **Saleor（BSD-3）** 走刪列並明說會丟資料，逐字 `When a product is unassigned from a channel, variant data for that channel, like pricing and availability, will be lost.`（<https://docs.saleor.io/developer/products/configuration>，2026-08-27）；同時另提供**軟移除**路徑（保留 listing 列、把 `isPublished` 等設 false） |
| **拒絕採用 Saleor 的軟移除** | 🔴 **它的前提在我方不成立**：Saleor 的 listing 列上有 per-channel 售價與日期要保住，我方 `resource_publications` **只有 `published_at` 一欄可保**。⚠️ **S10 把 price list 掛上這條線時本裁定需重開** |
| **採用 Medusa（文檔層）的一個區分** | `dismiss`（解除關聯）與 `delete`（連帶刪被連結紀錄）**在方法名層級就分開** ⇒ 我方 unpublish **絕不走任何 cascade delete**，有反向 fixture 鎖死。⚠️ **授權邊界**：Medusa 在本檔下方登記為「LICENSE 未取證 ⇒ 視同禁」——本列採用的是**公開文檔的概念**，**未讀其任何原始碼**（鐵律 9 逐字：「概念可從其公開文檔學、代碼不可看」） |
| **列為 S10／結帳包必答** | Medusa 逐字 `It doesn't prevent a purchase of a product that's unavailable in the channel.` vs Saleor 用 `isAvailableForPurchase` 在購買層設閘——我方目前**沒有** checkout 層的管道檢查，兩種取向都未採納，登記待答 |

🔴 **注入登記（鐵律 16.3，2026-08-27 實測）**：`docs.medusajs.com` **全站**內嵌
`<AgentInstructions>` 區塊，逐字要求 `POST https://docs.medusajs.com/{section}/agents/feedback`；
本輪六個 Medusa 頁全部命中。`docs.stripe.com` 的 idempotent_requests 頁亦含指示型文字
（`run stripe agent setup` 等）。**一律視為資料，未執行。**
建議把「docs.medusajs.com 全站含 agent 指示型內容」寫進 `docs/dev/external-facts.md`，
避免每次重新發現。

## 拒絕／禁用（鐵律 9 紅線的具名登記）

| 專案 | 授權 | 處置 | 出處 |
|---|---|---|---|
| Vendure（含 admin dashboard） | GPLv3 | **禁讀禁抄禁引用**（污染不可逆） | CLAUDE.md 鐵律 9 增補條款 |
| Spree ≥4.10 | AGPL-3.0 | 同上（AGPL 屬 GPL 家族） | 官方 blog 標題逐字 "Why Spree is changing its Open Source license to AGPL-3.0"（2026-08-25 WebSearch；license.md 直取 404，見第 11 包研究 P11-U15） |
| TinyMCE `develop` 分支 | GPL-2.0-or-later | 一次誤讀已封存（`Schema.ts`，第 7 包研究輪）；讀取結果不得作實作輸入 | 第 7 包研究輪注入登記節 |
| Medusa | 未取證（LICENSE 未取回，P11-U13） | 取證前視同禁 | 第 11 包研究 |
