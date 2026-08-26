# 2026-08-26 S1：Publication 的生命週期 API

> 分步方案 `docs/plans/2026-08-26-發布與可見性-分步執行方案.md` 的 **S1**，走完六道關卡
> （①官方文檔 ②後台逐控件實測 ③抓包 ④外部參考 ⑤關聯與 DB 推理 ⑥開發收口）。
> 前置＝S0（PR #146／#147，皆已合併並部署驗證）。
> 研究全文＝`docs/plans/2026-08-26-S1-規格草案.md`；dev doc＝`docs/dev/m2-publication-lifecycle.md`。

---

## 已完成的工作 (Done)

### 0. 六道關卡的產出

| 關卡 | 產出 |
|---|---|
| ①官方文檔 | 三支 mutation ＋ `Publication` object ＋ `ResourceOperation` ＋ `PublicationUserErrorCode` 的逐欄位契約，全部帶 URL、取證日期與英文原文逐字 |
| ②後台實測 | `docs/research/82-admin-channels.md` **§11**（新增）：sales channels 設定頁、app installation 詳情頁八個分區、商品批次 `⋯` 選單值域窮舉、發布 modal 形態 |
| ③抓包 | 同 §11：`SalesChannelsBulkModal` → `ProductBulkPublish` → `JobPoller` → `ProductIndex` 的完整序列，含 GET 的 variables |
| ④外部參考 | Saleor（BSD-3）的 channel 生命週期與 `channelDelete` 遷移語義、Medusa（MIT）的 `dismiss` vs `delete` 區分。🔴 GPLv3 專案（Vendure／WooCommerce 原始碼）全程未讀 |
| ⑤關聯推理 | 倉庫全量影響面掃描（見下方 C-12）＋ limits／28 契約／88 規格的既有規定盤點 |
| ⑥開發 | 見下 |

### 1. 🔴 研究階段推翻了 S1 的預設框架（C-12）

分步方案原本把 S1 定義成「`Publication.operation` 的狀態機與進行中的鎖」。
倉庫掃描發現一件更根本的事：

> `resource_publications.published_at` **只在建立時**被寫入
> （`Publications::Materialize` 兩條路徑 ＋ 兩支 migration 的原生 SQL），
> 全倉**零 UPDATE、零 DELETE、零 publish／unpublish 入口**。

⇒ 「進行中的鎖」在這個狀態下是**空掛的**：沒有可被鎖住的動作。
射程因此改成「**先交付那個動作**」，鎖屬後續。

複驗：`grep -rn "resource_publications\|ResourcePublication" app/ --include=*.rb`

### 2. 交付：publication 生命週期 API

- 讀取面：`Types::PublicationType` ＋ `QueryType#publications`
- 寫入面：`publicationCreate`／`publicationUpdate`／`publicationDelete` 三支 mutation
- 規則層：`Publications::Write`（唯一寫入入口）＋ `Publications::Lookup`（GID 解析）
- 契約：`PublicationUserErrorCode`／`PublicationUserErrorType`／兩個 input／`PublicationDefaultState` enum
- 五個語系的 `errors.publication.*` 文案（五檔 key 集合必須一致，有 spec 擋）

🔴 **`publicationUpdate` 是本倉庫第一條 `resource_publications` 的非建立寫入路徑。**

### 3. 🔴 四條實測驅動的規則（照直覺做會全錯）

| # | 規則 | 照直覺做會怎樣 |
|---|---|---|
| 1 | `publishablesToAdd/Remove` 是**累加／扣除** | 本倉庫的 `productSet`／`collectionSet` 是宣告式全量（未列出＝移除）。照那個習慣做，商家一次勾選會**清空整個管道** |
| 2 | 重複 add 是 **no-op success** | 回 `ALREADY_EXISTS` 會讓批次操作在正常情況下失敗 |
| 3 | 逐列 `find_or_create_by!`，**不用 `insert_all`** | `insert_all` 繞過唯一那道租戶守衛（多型側無外鍵）⇒ 寫出跨租戶的列**而不拋錯** |
| 4 | 批次上限取**合計**不是各自 | 官方兩句措辭不同且都未指明切分 ⇒ fail-closed 取較嚴側，登記為 ours 加嚴 |

規則 1 的實測依據＝`docs/research/82` §11.5：本尊的發布 modal **一律以「全部未勾」開場**，
即使選取的商品已經在某些管道上。

### 4. 刪除的三條裁定（全部 ours——官方對副作用完全沉默）

`publicationDelete` 官方全文只有 `Deletes a publication.` 一句（同一 URL 抓兩次字串完全相同）。

1. **綁著 channel 的 publication 不可刪** → `CANNOT_MODIFY_APP_CATALOG_PUBLICATION`
   （本尊逐字 `Can't modify a publication that belongs to an app catalog.`）。
   沒有這條守衛，刪線上商店 publication 會讓 `Publication.online_store` 回 nil，
   後果是**整店商品前台不可見且不拋任何錯**（與 S0 修掉的 C-9 同一個症狀）。
2. **級聯刪 `resource_publications`**（配置類可刪，交易類才需遷移——Saleor 旁證）。
3. 🔴 **絕不連帶刪 publishable 本體**，有反向 fixture 鎖死。

🔴 **刪除前必須 bump cache stamp**：`dependent: :destroy` 不會 bump，而順序不可倒
——刪完就查不到受影響的是哪些商品了。

### 5. 六個突變複驗（本輪實跑，逐字輸出）

| 突變 | 結果 |
|---|---|
| update 改成宣告式全量（未列出＝移除） | `29 examples, 1 failure` |
| 批次上限改成各自計算（不是合計） | `29 examples, 1 failure` |
| 解析 publishable 時不帶租戶條件 | `29 examples, 1 failure` |
| 拿掉刪除的 channel 守衛 | `29 examples, 1 failure` |
| 刪除路徑不 bump cache stamp | `29 examples, 1 failure` |
| cache stamp 改用 `update_all` 的 hash 形式（會推 `lock_version`） | `29 examples, 1 failure` |
| 還原後 | `29 examples, 0 failures` |

🔴 **每個突變恰好一格失敗**——守衛與測試一對一，不是一個突變打翻一片
（那種形態通常代表測試在測共同前置而不是測那條規則）。

### 6. 實作當下被 CI 判準當場擋下的一次（處置：改自己不改判準）

第一版把 `PublicationLookup` 放在 `app/graphql/mutations/` 底下，被
`spec/graphql/mutation_idempotency_call_spec.rb` 擋下：

```
publication_lookup.rb：找不到 resolve 方法
```

該斷言的判準是「`mutations/` 下非 `base_*` 的檔案一律是帶 `resolve` 的具體 mutation」，
且檔內明文「不逐檔白名單」。🔴 **那個判準是對的，錯的是「一個 lookup 不是 mutation」**
⇒ 移到 `app/services/publications/lookup.rb`。**不得為了遷就放錯的檔案去放寬判準。**

---

## 修改的檔案與核心邏輯 (Changes)

| 檔案 | 內容 |
|---|---|
| `app/services/publications/write.rb` | 新增。唯一寫入入口：create／update／delete ＋ 批次上限 ＋ 租戶解析 ＋ cache stamp |
| `app/services/publications/lookup.rb` | 新增。publication GID 解析與 not-found 錯誤（兩支 mutation 共用，避免 `field` path 分岔） |
| `app/graphql/mutations/publication_{create,update,delete}.rb` | 新增。三支薄殼 |
| `app/graphql/types/publication_type.rb` | 新增。🔴 `title` 取自 catalog、`handle` 取自 channel、`catalogId` 用本尊的 GID Type `AppCatalog` |
| `app/graphql/types/publication_default_state_enum.rb` | 新增。恰兩值 |
| `app/graphql/types/inputs/publication_{create,update}_input.rb` | 新增 |
| `app/graphql/types/errors/publication_user_error_{code,type}.rb` | 新增 |
| `app/graphql/types/mutation_type.rb` | 掛三支 mutation |
| `app/graphql/types/query_type.rb` | 新增 `publications` 欄位與 resolver（preload catalog／channel） |
| `config/locales/{en,zh-Hant,zh-Hans,ja,fr}.yml` | `errors.publication.*` 六個 key × 五語系 |
| `spec/requests/publication_lifecycle_spec.rb` | 新增，29 格 |
| `docs/dev/m2-publication-lifecycle.md` | 新增。dev doc |
| `docs/plans/2026-08-26-S1-規格草案.md` | 新增。研究工作流的合成產出（自帶證據地位聲明） |
| `docs/research/82-admin-channels.md` | 新增 §11（實測 ＋ 抓包） |
| `docs/research/28-api-contract.md` | §2 補三支 mutation ＋ 三條契約細節 |
| `docs/specs/88-publication-model.md` | §5 結案 #6；§2.1 的外鍵更正註 |
| `docs/dev/m2-publication-model.md` | P12-B11 撤回（cache stamp 的寫入者已交付） |
| `docs/plans/2026-08-26-發布與可見性-分步執行方案.md` | S1 節兩處過期陳述就地更正 |
| `docs/specs/91-pit-register.md` | §3.20（七條範圍外觀察） |

---

## 尚未完成或需注意的風險 (Pending / TODO)

| # | 內容 |
|---|---|
| S1-P1 | 🔴 **`defaultState: ALL_PRODUCTS` 誠實拒絕**（回 `FEATURE_NOT_ENABLED`）。本尊那條路是非同步的 `AddAllProductsOperation`，我方沒有 `processedRowCount`／`rowCount` 的落點。⚠️ **不得**改成「同步跑一遍假裝是它」 |
| S1-P2 | **`operation_status` 仍然零寫入者、恆為 null**。type 上有這個欄位**不代表鎖已生效** |
| S1-P3 | **`sales_catalog_id` 未轉 NOT NULL**（`docs/specs/88` §2.1 指派給 S1，但語義獨立 ⇒ 另包） |
| S1-P4 | **`publications.name`／`channel_handle` 欄位未刪**（已降級 legacy／快照；刪欄要改所有讀取端） |
| S1-P5 | **逐資源的 `publishablePublish`／`publishableUnpublish` 未做**（分步方案劃給 S5） |
| S1-P6 | **`publications` query 不做 connection 分頁**。S10 的 catalog publication 大量出現時要改 |
| S1-P7 | **不進 `idempotency.required_for`**（本輪裁定）。⚠️ 若日後 publication 牽動計費，必須重新裁定 |
| S1-P8 | 六條未取得（S1-U1～U6）逐條列在 dev doc §7，其中 U-2（`Publication.operation` 實地形態）需安裝管道 app，使用者已裁定不安裝 |
| S1-P9 | ⚪ 七條範圍外觀察登記 `91` §3.20，其中「`insert_all` 繞過租戶守衛」的**全域**缺口仍在——下一個批次寫入者（匯入器）會再遇到 |
| S1-P10 | **前端未動**：admin SPA 沒有管道管理介面。本步只交付 API |
