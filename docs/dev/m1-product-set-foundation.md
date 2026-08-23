# M1 — productSet 地基（claim/replay ＋ 第一支 mutation）

> 2026-08-23。本篇是 mutation root 掛載那一批的裁定與對接文檔（鐵律 12.4 ④：
> 後續開發只讀本篇就該知道改哪裡會影響誰）。規格出處：63 §B.4（寫入映射）、
> 11 §2.1（冪等）、65 §B X12（金額入向，本批新增）、limits `handle:` 區塊。

## 1. 這是什麼

- **`productSet`**：admin 商品頁 SaveBar 的唯一寫入映射（`catalog_flow.
  product_write_entry_mutation`）。宣告式全樹 upsert，建立與更新同一支，
  差別只在有無 `id`。**v1 射程＝建立態＋隱含變體**；`id`／多變體回 `INVALID`。
- **`Idempotency::Guard`**：11 §2.1 claim/replay 狀態機的唯一入口。
- **`Catalog::SaveProduct`**：normalize→validate→commit（單一 transaction 寫
  products／product_variants／event_outbox 三表）。
- **`Catalog::HandleGenerator`**：limits `handle:` 區塊的可執行形（六個裁定
  範例逐字元通過，含 kerastase 86 字元例）。

## 2. 本批裁定（六條）

| # | 裁定 | 依據與理由 |
|---|---|---|
| D-PS1 | **三段式交易邊界**（對抗審查後修訂）：claim INSERT 在外（獨立 commit）；**succeeded 落款在業務 transaction 內**（同 commit）；failed 落款在外 | claim 在外＝立即 CONCURRENT 而非 lock wait；succeeded 在內＝消滅「業務已 commit、落款前死掉 ⇒ TTL 後同 key 重建重複商品」窗口（審查 confirmed #5）；failed 在外＝rollback 後存活。殘餘窗口＝failed 落款前死掉 ⇒ 列卡 processing 到 TTL（防重複優先，登記）。未決點 2 結案 |
| D-PS2 | 業務失敗（非空 userErrors）⇒ claim 記 `failed` | 什麼都沒 commit ⇒ 依 (b) 表「視為未執行、同 key 可重試」；succeeded 必有 result_ref 可重建，業務失敗沒有結果物件可指。未決點 5 結案 |
| D-PS3 | failed 分流在指紋比對**之前**，指紋隨新嘗試重置 | 「同 key 重試」重試的正是**修正後參數**；先比指紋會把每次修正判成 MISMATCH，(b) 的語義形同虛設 |
| D-PS4 | `IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED` 商品線**不發** | 11 §2.1(b) 與 90 藍圖矛盾（91 §3.7 第 1 條）；遵循生產基線 11 |
| D-PS5 | productSet **建立態（無 id）強制 idempotencyKey** | `required_for_catalog_create` 判準逐字適用（無業務唯一鍵兜底）；「宣告式刻意不列入」只對更新態成立。名單表達不了條件強制 ⇒ resolver 內落地（91 §3.7 第 2 條） |
| D-PS6 | 建立未帶 status ⇒ `DRAFT` | 91 §3.7 第 3 條 |

另兩個既有缺口以本批結案：隱含變體 DB `title` 直接存
`catalog_flow.default_variant_liquid_title`（"Default Title"——Liquid 硬相容契約
與 DB 同源）；admin 金額入向補 65 §B **X12** 列（封閉條款要求先改表，已改）。

## 3. 怎麼做出來的（實作要點）

- **冪等流**：`resolve` → `enforce_idempotency_contract!`（清單制，現對 productSet
  no-op）→ `enforce_creation_key!`（D-PS5 條件強制）→ 無 key（更新態）直跑；
  有 key → `Idempotency::Guard.with`。指紋＝`input.to_h`（snake_case）
  deep_stringify 後 `CanonicalJson.fingerprint`——**測試端照 GraphQL 線上格式
  （camelCase）算指紋會 MISMATCH**，mutation_name＝類別 graphql_name
  `"ProductSet"`（不是欄位名 productSet）。
- **回放**：succeeded ⇒ 依 resource_type/resource_id 重載（tenant scope 內）
  重跑 serializer；物件已刪 ⇒ userError `NOT_FOUND`（原請求成功、資料隨後被刪）。
- **金額**：`ProductSetVariantInput.price` 等收 R4 十進位字串（恆兩位小數），
  `Money::Decimal.from_string → to_storage` ⇒ integer cents；格式錯 `INVALID`、
  負數 `GREATER_THAN_OR_EQUAL_TO`，皆 userErrors。**input 不收 Float**（鐵律 3）。
- **handle**：手填 ⇒ 格式＋保留字驗證＋衝突 reject `HANDLE_TAKEN`（model :taken
  特判）；未填 ⇒ HandleGenerator，生成衝突 `-1` 起算尾碼（保留字視同已占用）；
  DB 唯一索引兜底時**手填/生成分流**——手填 `HANDLE_TAKEN`、生成重試 ≤3 次後
  `CREATION_FAILED`（63 §A.1 ④ 不得漏成 500）。
- **sanitize**：白名單 p/br/strong/em/ul/ol/li/a/img；a[href] http(s)、
  img[src] https（**自家 CDN 白名單待媒體包**）。

## 4. 跨功能／跨頁影響（預先對接）

| 誰 | 什麼時候會撞到 | 要知道什麼 |
|---|---|---|
| 新 mutation 作者 | 每一支 | ①resolve 開頭呼叫 `enforce_idempotency_contract!`（`spec/graphql/mutation_idempotency_call_spec.rb` 靜態掃描擋）②建立型進 limits 清單 ③專屬 code enum＋error type |
| 前端新增商品頁（PR B） | 送 SaveBar | 送**完整樹**（B.4 規則 1）；建立態必帶 uuid idempotencyKey；金額送兩位小數字串；status 顯式送 `DRAFT`；分三層接錯誤（userErrors／top-level THROTTLED 等／非 200） |
| 更新態實作者 | productSet v2 | 解掉 `reject_unsupported!` 的 id 分支；lockVersion 全樹比對（63 §A.4）＋ B.5 變體身分保持；`STALE_OBJECT` 轉譯 |
| 庫存線 | claim/replay 復用 | 先解 91 §3.7 的 11-vs-90 矛盾（PREVIOUS_ATTEMPT_FAILED）；初始庫存量走 `initial_quantity_allowed_on_create_only`（同 transaction、冪等鍵由父請求派生）——**本批未做** |
| 發布線 | 88 §5 #2 | `auto_publish` 的 after_create 行為本批未做：v1 建立的 ACTIVE 商品**不會**自動進 online_store 管道（M2 前無實害，前台未存在） |
| 多語言線 | 67 §E.2 | 建立時的 translation base row 本批未寫；handle 來源優先序的 `en_title` 步待多語言表 |

## 5. 對抗審查輪（2026-08-23，發 PR 前）

45-agent 工作流（5 鏡頭 × 每條 finding 2 個獨立反駁者）：**17 條確認、3 條被反駁**。
四條紅色全數修復並各配回歸釘：

| 紅色 | 修法 | 回歸釘 |
|---|---|---|
| 金額尾隨換行穿 regex → 500 | limits `decimal_string_regex` 錨點 `^$`→`\A\z`＋parse_money 補 rescue ExcessPrecision（雙防線） | request spec「尾隨換行 ⇒ INVALID」 |
| failed→processing 非原子（雙贏雙建） | 帶狀態條件的 `update_all` CAS，輸家回 CONCURRENT | 併發 spec 兩執行緒 CAS 恰一贏 |
| succeeded 落款與 commit 不原子 | 落款移進業務 transaction（D-PS1 修訂） | guard_spec 例外/失敗路徑 |
| （自查）外層 transaction 讓部分寫入變孤兒 | userErrors ⇒ `raise ActiveRecord::Rollback`＋`requires_new: true`（joined 巢狀下 Rollback 會被靜默吞掉） | guard_spec「不留孤兒列」 |

黃色已修：replay 釘 shop 參數 tenant（不信 ambient）；expired 讓位原子化＋
retrying 旗標；HandleGenerator 撇號刪除移到 NFKC 前（U+00B4 分解事故）；
保留字（all/new/index）手填 reject、生成走尾碼；letters_dropped 結構化日誌；
生成衝突併發重試（≤3 次）與手填 reject 分流；靜態掃描 glob 遞迴化；
HandleGenerator 專屬 spec（裁定範例全數釘住）；v1 射程守門三測試；
回放已刪 NOT_FOUND 測試。

黃色登記不修（各有依賴）：`reserved_first_segments` 全表檢查（storefront 路由
包）；letters_dropped 落庫欄位（SEO health 包）；payload 的 variants selection
（需 ProductVariant GraphQL type，更新態包一併做）。

## 6. Pending（誠實清單）

- 更新態／具名選項／多變體（B.5）；初始庫存量通道；auto_publish callback；
  translation base row；img src 的 CDN 白名單；`orderCreate` 類清單合併
  （未決點 4，catalog_create_merge_pending 照舊）。
- 未決點 3（IDEMPOTENCY_KEY_REQUIRED 的 enum 歸屬）照舊：仍走 top-level 暫行。
- §5 的三條登記不修黃色；D-PS1 殘餘窗口（failed 落款前死掉 ⇒ TTL 內同 key 被擋）。
