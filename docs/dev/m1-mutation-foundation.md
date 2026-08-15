# Mutation 寫入地基（M1）

## 概述

Admin GraphQL 的**寫入路徑地基**：`BaseMutation`、`DisplayableError` interface、
錯誤碼池、`userErrors.field` 的路徑組裝、冪等清單讀取器與參數指紋。

🔴 **本層不出任何一支真 mutation**，而且 `Types::MutationType` 建了但**刻意沒有掛上
`ChillloveSchema`**。理由見「關鍵取捨」。

對應本尊：`docs/research/28` §0.3（2026-08-15 依 Admin API **2026-07** 逐頁考掘後改寫）。

## 規格出處

- `docs/research/28` §0.3.1–§0.3.6（本輪改寫）｜`docs/DECISIONS.md` **D14**
- `CLAUDE.md` 鐵律 4（本輪修正「HTTP 恆 200」的措辭）、鐵律 5
- `docs/specs/11` §2.1（冪等完整規格）

## 架構與資料流

```
POST /admin/api/2026-08/graphql.json
  └─ Admin::Api::V202608::GraphqlController#execute
       ├─ authorize :admin_api（Pundit）
       ├─ normalized_variables → InvalidVariables（🔴 專屬例外，見取捨）
       ├─ GraphqlRequestCost.calculate（mutation 另加 base cost）
       └─ ChillloveSchema.execute
            └─ Mutations::XxxCreate < Mutations::BaseMutation
                 ├─ enforce_idempotency_contract!（只檢查有沒有帶 key）
                 ├─ resolve → { <resource…>, user_errors: [...] }
                 └─ userErrors 用 UserErrors::Path.build 組 field 路徑
```

## API

**本層不出任何操作。** 它定義的是所有 mutation 共用的 payload 形狀：

```graphql
type XxxPayload {
  # resource 欄位 0..N —— 🔴 下限是 0（純副作用 mutation 只有 userErrors）
  userErrors: [XxxUserError!]!    # 唯一必備欄位；成功時 []，絕不是 null
}

type XxxUserError implements DisplayableError {
  field: [String!]                # list 可 null、元素非 null；無法歸屬時整個為 null
  message: String!
  code: XxxUserErrorCode          # 🔴 ours：本尊泛用 UserError 無此欄
}
```

## 資料表

**不新增任何表。** 使用既有的 `idempotency_keys`（M0 建）。

🔴 **該表的形狀與 `docs/specs/11` §2.1(a) 不一致**（本輪未改，登記為待清）：
狀態欄叫 `state`（規格寫 `status`）、指紋欄叫 `request_digest`（規格寫
`params_fingerprint`）、仍帶被明文廢棄的 `response_body`(longtext)／`response_digest`／
`status_code`、**完全沒有 `mutation_name` 欄**（⇒ 目前無法區分「同一把 key 用在不同 mutation」）。

## 關鍵取捨

### 🔴 為什麼繼承 `GraphQL::Schema::Mutation` 而不是 `RelayClassicMutation`

本尊的 Admin GraphQL **沒有 `clientMutationId`**（payload 與 input object 兩側都沒有）。
`RelayClassicMutation` 會自動注入它 ⇒ 用它就是偏離本尊的 schema 形狀。

⚠️ 連帶後果：`GraphQL::Schema::Mutation` **沒有** `input_object_class`
（它定義在 `HasSingleInputArgument`，只被 `RelayClassicMutation` include）
——在 BaseMutation 裡呼叫它會在**類別定義期**就 `NoMethodError`，
Zeitwerk eager load 一跑整個 app 載入失敗。

### 🔴 為什麼不提供泛型的 `resource` 欄位

本尊 payload 的 resource 欄位**數量下限是 0**，上限是 N。
把「一個 resource ＋ userErrors」寫死成契約，第一支純副作用或多資源的 mutation
就得繞過基底。⇒ `user_errors_type` DSL 只加 `userErrors`，resource 由各 mutation 自己宣告。

### 🔴 為什麼建了 `MutationType` 卻不掛上 schema

`enforce_idempotency_contract!` **只檢查 key 有沒有帶，不做去重**——
不 claim、不查重、不回放。**本 PR 一支 mutation 都不出，所以沒有任何東西獲得
虛假的安全感**；掛上 root 的那一刻這個保護就沒了。

`spec/graphql/mutation_root_guard_spec.rb` 把解鎖條件**寫進斷言**
（斷言 `mutation_type.rb` 的原始碼含「claim/replay」與「虛假的安全感」兩個字串），
讓要掛上去的人一定會讀到理由。

### 🔴 controller 的 `rescue TypeError` 必須收窄

原本是**方法層 rescue**（`rescue JSON::ParserError, TypeError`），
而 `ChillloveSchema.execute` 就在方法體裡面 ⇒ **任何 resolver 內部拋出的 `TypeError`
都會被渲染成 `BAD_USER_INPUT`**。

鐵律 3 的金額型別閘門（65 §C L3）正是靠 `raise TypeError` 擋住「把儲存值直接送 PSP」
——那是 **P1 級送款事故**，卻會顯示成「variables 必須是有效的 JSON 物件」，
而真正的訊息一個字都不會出現在 log 以外的地方。
⇒ 改為專屬例外 `GraphqlController::InvalidVariables`。

### 錯誤碼：形狀照抄本尊，值域是 ours

本尊是「一個 UserError object type 對應一個專屬 enum」，**沒有全域 base enum**
（`/enums/UserErrorCode` 回 404），而且值名並未貫徹（`PRESENT`／`PRESENCE` 語義甚至相反）。
⇒ **GraphQL 形狀照抄**（每支一個獨立 enum type），**偏離的只有值域紀律**
（各 enum 的值從 `CodePools` 取）。

🔴 **`CONFLICT` 不在共用池裡，而且永遠不會在**：本尊的 `CONFLICT` 只存在於
`DiscountErrorCode`，語義是「折扣屬性選擇互相衝突」的**輸入驗證**。
樂觀鎖用 `STALE_OBJECT`、庫存 CAS 用 `CHANGE_FROM_QUANTITY_STALE`
——兩者進本輪新開的 `CONCURRENCY` 池（`COMMON` 那 24 個全是欄位級輸入驗證，
**結構上容不下併發語義**）。

### 指紋：規則⑤ 只在頂層生效

第一版把 `idempotencyKey` 在**每一層**都排除，而規格說的是「不含 `idempotencyKey`
**本身**」＝頂層那把。巢狀同名欄位被靜默丟掉 ⇒ 兩個不同請求算出同一指紋，
**參數不符永遠偵測不到**——這機制要防的東西在機制自己身上重演。

## 🔴 跨功能／跨頁／前端影響（鐵律 12.4 ④）

| 影響對象 | 什麼時候會碰到 | 要注意什麼 |
|---|---|---|
| **每一支新 mutation** | 一律 | 繼承 `BaseMutation`；用 `user_errors_type` 宣告 error type；**`resolve` 開頭要主動呼叫 `enforce_idempotency_contract!`**（graphql-ruby 沒有 around hook） |
| **每一個新 error type** | 一律 | `implements Types::Interfaces::DisplayableError`；code enum 繼承 `BaseCodeEnum` 並 `from_pools` |
| **admin SPA 的錯誤處理** | 接第一支 mutation 時 | 🔴 **三層都要檢查**（鐵律 4 本輪修正）：`res.ok` → `data.errors`（THROTTLED／MAX_COST_EXCEEDED／ACCESS_DENIED） → `data.<mutation>.userErrors`。只檢查後兩層的 client 會把 401／423 當成「沒有錯誤的空回應」 |
| **前端表單欄位對應** | 同上 | `field` 是**平鋪的一維陣列**，陣列索引是十進位裸字串段（`["variants","0","price"]`）；`field` 為 `null` ⇒ 送 form-level banner |
| **`Types::MutationType`** | 第一支真 mutation | 掛上 root **必須同批處理 claim/replay**（guard spec 會擋） |
| **`config/limits.yml` 的冪等清單** | 新增金流 mutation | 判準：凡金流寫入一律強制冪等；**新增的一律進 ours 段**（本尊只強制 17 支） |
| **`idempotency_keys` 表** | 做 claim/replay 時 | 🔴 表形狀要先改（缺 `mutation_name`、留著三個廢棄欄） |
| **rate limit／cost** | 加新 mutation | `GraphqlRequestCost` 對 mutation 加 base cost；⚠ `mutation?` 是低精度實作（寧可高估） |
| **`docs/research/28`** | 契約有變時 | §0.3.1–§0.3.6 是本層的正典；改實作要同批改它 |

## 測試

- `spec/graphql/base_mutation_spec.rb`（18）：**真的 execute**。
  五支 fixture mutation 各證明一件事（一般形態／純副作用／陣列索引／
  `TypeError` 不被偽裝／冪等契約）。
- `spec/graphql/user_errors_path_spec.rb`（12）：每條對得上一條官方依據。
- `spec/graphql/mutation_root_guard_spec.rb`（4）：把「刻意沒做」釘住。
- `spec/models/idempotency/canonical_json_spec.rb`（19）：五條規則各配反向斷言。
- `spec/graphql/products_contract_spec.rb`：+3 條 rescue 收窄的回歸斷言。

**負面驗證**（改壞之後必須紅）：
| 改動 | 結果 |
|---|---|
| 繼承 `RelayClassicMutation` | 9 條紅 |
| `field` 改成 `[String]` | 1 條紅 |
| rescue 放寬回 `TypeError` | 1 條紅 |

## 已知限制與 TODO

- 🔴 **claim/replay 完全沒做**，五個未決點（表形狀／transaction 邊界／缺 key 的 code／
  兩份清單待合併／業務失敗算不算成功而被快取）見
  `docs/worklog/2026-08-15-冪等指紋.md`。
- 🔴 **`enforce_idempotency_contract!` 要由子類主動呼叫**——忘記就等於沒有檢查，
  **而沒有任何機制會發現**。第一支真 mutation 落地時要補一條 CI 斷言。
- 🔴 **指紋沒有納入 `mutation_name`**：同一把 key 用在兩支不同 mutation、
  參數又剛好相同時偵測不到。要等表補欄位。
- 🔴 **`UserError` 是否 `implements DisplayableError` 未確認**（shopify.dev 對它不印
  Implements 區塊）⇒ **不得假設**所有 userErrors 都能用 `... on DisplayableError` 取用。
- ⚠️ **具名參數形下的多段 path 是假設**（只剝逐字等於 `input` 的參數）。
- ⚠️ **`DISCOUNT_ONLY`（`CONFLICT`）沒有 CI 斷言守住**——「只准出現在折扣線的 enum 裡」
  還停在紀律層。折扣線落地時要補。
- ⚠️ **28 §6 的「20 個泛用碼」與清單對不上**（表列 26 值、退貨專屬只有 2 個 ⇒ 24 才對）。
  `CodePools::COMMON` 以清單為準，規格那句話待修。
- ⚠️ **`warnings`（成功但要提醒）尚未實作**：形狀已定（照抄 Storefront `CartWarning`），
  但第一個需求（重複 SKU 提醒）要等變體 mutation。

## 變更記錄

- 2026-08-15 PR-1：建立（BaseMutation／DisplayableError／CodePools／
  UserErrors::Path／冪等清單與指紋／controller rescue 收窄）
