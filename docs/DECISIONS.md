# 專案決策紀錄（DECISIONS）

## 2026-08-10 — 第二階段開工前三決策

### D1. 技術棧：Rails + React（本尊同款）

- 選擇：跟 Shopify 相同形態——**Ruby on Rails**（modular monolith）+ **MySQL** + **React + TypeScript 後台**（自建 Polaris 風格元件庫）+ 伺服器端渲染的買家前台。
- 對應研究：08（Shopify 用 Rails Core 單體 + MySQL Pods + React 後台 + Liquid 前台）。
- 實務註記：
  - 開發與展示在雲端工作區進行；Windows 本機要跑的話建議 WSL2 或 Docker（Rails 在原生 Windows 體驗較差）。
  - demo 階段資料庫用 MySQL（與本尊一致）；所有表帶 shop_id（06 的多租戶原則）。
  - 後台 React 以 Vite 構建、掛在 Rails 之上；買家前台走 Rails 伺服器渲染（對應 Storefront Renderer 的讀路徑思路）。

### D2. 路線：A → B → C（全都要，按此順序）

1. **A 成交閉環**（M0 地基 → M1 商品 → M2 前台 → M3 結帳/Stripe test）
2. **B 後台深化**（M4 訂單出貨退款/顧客 → M5 折扣/報表/設定）
3. **C 主題編輯器**（M6 三欄編輯器 + section 庫）

### D3. 品牌名：**CHILL LOVE**

- 平台（SaaS 本體）品牌名，用於 logo 文字、後台左上角、登入頁、通知信署名與網域規劃。
- 全部做成單一變數/設定，之後可一行改名。
- demo 內不出現 Shopify 字樣與其品牌資產（07 §10 的紅線）。

## 2026-08-10（同日晚間）— 前台引擎重大修訂

### D4. 前台改走 Liquid 相容主題引擎（第三方 Shopify 主題可直接匯入）

- 選擇：買家前台的渲染引擎從「Rails ViewComponent 自有 section 系統」改為 **Shopify/liquid gem（MIT）＋ 自行實作平台層（138 objects / 9 tags / 94 filters）＋ 主題 JS 硬依賴端點（/cart/*.js、Section Rendering API 等）1:1 實作**。
- 動機：使用者明確要求「Shopify 本身的第三方主題可以直接套用」。
- 影響範圍：**取代** 07 號 §與 10 號中「前台用 ViewComponent 簡化」的舊方案；M2/M6 里程碑內容修訂（見 25 號 §9、HANDOFF §5）；14 號 spec 的 theme JSON/編輯器規格仍有效。
- 法律基礎：liquid gem、theme-check（TS 版）、theme-liquid-docs 皆標準 MIT；**但 Dawn/Horizon 授權含「僅限與 Shopify 互通」限制（非純 MIT）、Theme Store 主題授權限單一 Shopify 商店**——平台不預載/散布任何 Shopify 主題或其衍生物，第一方預設主題從零自寫，商家匯入第三方主題須過授權聲明 gate（詳見 25 號 §8，含 2026-06 Shopify v. SHOPLINE 和解先例）。
- 規格文件：24（編輯器/結帳 teardown）、25（相容層架構）、26（API 全量 checklist）、27（Ella golden theme）、31（完整補齊計畫）。

## 2026-08-11 — 全面 API 化與國際化三決策

### D5. API-first：admin 與服務端只經 GraphQL Admin API 對話

- 選擇：**1:1 仿 Shopify GraphQL Admin API 工程慣例**（官方文檔查證）——版本化 URL `/admin/api/{YYYY-MM}/graphql.json`、GID `gid://chilllove/{Type}/{id}`＋Node、cursor 分頁（≤250）＋pageInfo、mutation `resourceVerb`＋`userErrors{field,message,code}`（HTTP 恆 200）、MoneyV2/MoneyBag、cost 制限流＋`extensions.cost` 回報、webhooks（topic `資源/動詞`＋HMAC-SHA256＋5 秒 2xx）、bulk operations 契約保留（demo 同步分批）。
- 三端對接：admin React SPA→GraphQL；買家前台→Liquid SSR＋Ajax/SRA 面；外部整合→token＋webhooks；編輯器高頻操作走內部 REST（draft/render_section）。
- 契約文件：**28 號**（§0 慣例＋§1–14 逐模組操作表＋§15 webhooks＋§16 前台面＋§17 對接矩陣）。

### D6. 基建對映：全面走 Shopify 路線（demo 形態 → 生產路線）

| Shopify 生產 | 我們 demo | 我們生產路線 |
|---|---|---|
| Rails modular monolith | Rails 8.1 單體 | 同（Packwerk 模組化） |
| MySQL + Vitess Pods | MySQL 8 | MySQL → Vitess/PlanetScale 分片（shop_id 鍵） |
| Memcached + Redis | Solid Cache | + Redis（session/限流桶） |
| Kafka 事件流 | Solid Queue + outbox 表 | + Kafka（webhooks/分析管線） |
| Elasticsearch | MySQL ngram | OpenSearch（商品/訂單搜尋） |
| 自建圖片 CDN | imgproxy + S3 相容存儲 | 同 + CDN 邊緣 |
| Storefront Renderer（獨立讀路徑） | 同進程 ThemeRuntime | 抽獨立 renderer 服務（無狀態、可水平擴） |
| GraphQL Admin API | 同（D5） | 同 |

### D7. Markets/i18n 一級公民＋SEO/feed 內建

- 多語言/多貨幣/多市場按 29 號 P0（M2 隨行：locales＋translations＋多幣顯示）→ P1（M5/M6：markets 全模型＋市場定價＋hreflang 全量＋Adapt）→ P2（price lists/duties/B2B）。
- SEO 合規（30 號 §1–5/§9）內建於 storefront 渲染層（M2）：self-canonical 引擎、JSON-LD 注入分工、sitemap 分片、robots.txt.liquid、410 紀律、CWV 預算。
- 商品 feed（30 號 §6–8）：以 GMC 規格為 canonical schema 的生成器＋per-channel 轉換（M5+）；**Google 側直接實作 Merchant API**（Content API 2026-08-18 落日）；IndexNow 事件 ping；Simprosys 走「自建底座＋connector 加值」雙軌（30 §10.3），不做 Shopify 偽裝。

## 2026-08-14 — parity R11–R13 收口四裁定

> 背景：parity sweep 跑到 R13，§F 累積 86 條未結案，而實作仍停在 M0（PR #12 未合）。
> 這四條是「擋住地基或會讓後續輪次反覆重提」的部分，先裁定再往下走。
> 保護清單條目：`docs/specs/71` §A **G24–G27**（凡在 §A 者，任何對比輪不得建議改回與 Shopify 一致）。

### D8. 身分與權限表豁免鐵律 2 的 `shop_id`（G24）

- **問題**：R13 實測證實本尊 2026 已改 RBAC，且**身分與權限掛在組織層**（使用者↔群組↔角色↔權限，
  角色可跨店）。這與鐵律 2「全表帶 `shop_id`」正面衝突，而 PR #12 的 schema 正是地基。
- **選擇：窄範圍豁免**，而非硬套 shop_id（做不出跨店角色）或全面放寬（失去隔離保證）。
- **理由不是「本尊這樣所以照抄」，而是分層本來就不同**：鐵律 2 保護的是**業務資料的租戶隔離**；
  身分與權限是**授予租戶存取權的那一層**，邏輯上位於租戶之上。這也正是本尊把「使用者」
  放在組織區塊而非商店區塊的原因。
- **白名單（逐表列舉，不得口頭擴充）**：`organizations`／`users`／`roles`／`role_permissions`／
  `user_roles`／`user_groups`／`user_group_roles`／`user_store_assignments`。白名單以外一律照舊。
- **三條配套約束**（缺一條這個豁免就變成隔離漏洞）：
  1. 白名單表**不得**存放任何業務資料欄位（只放身分、角色、指派關係）；
  2. 🔴 **豁免的是「表有沒有 `shop_id` 欄」，不是「查詢可不可以不帶 `shop_id`」**——
     跨店存取一律先由 `user_store_assignments` 解析出可及 shop_id 集合，查詢層仍逐表帶條件；
  3. 新增白名單表必須同步改 `CLAUDE.md` 鐵律 2 與 `71` §A G24，且 PR 描述標明。
- **影響**：`CLAUDE.md` 鐵律 2 與 `AGENTS.md` §技術鐵律 2 已加註；71-R12-STRUCT1 結案。
- 🔴 **2026-08-14 當日更正**：本條原寫「RBAC 資料表本體的實作仍在 M1（＝白名單表還沒建）」——
  **那是錯的**。M0 已建 `roles`／`role_permissions`／`staff_members`／`sessions` 四張表
  （命名用 `staff_members` 不是 `users`，我只查了 `users` 就下結論），
  全部 `shop_id NOT NULL` ＋ **複合外鍵** ＋ `acts_as_tenant` fail-closed。
  ⇒ 當時 **D8 與現有 schema 直接衝突**。兩案影響評估＝**`docs/specs/85`**。
- ✅ **2026-08-14 使用者裁定：採 A 案（改 schema）＋把安全網補回去，已落地**。
  - migration `20260814000000_identity_tables_to_organization_level`：四張身分表拆 shop_id 與
    複合外鍵、新建 `user_store_assignments`（回填既有列）、email 唯一性改全平台、
    順帶補 `staff_members.timezone`/`locale`（R12-V3 結案）。
  - 🔴 **安全網兩道**（缺一則 G24 就是漏洞）：
    ①`Current.accessible_shop_ids` / `can_access_shop?` / `role_for_current_shop`——fail-closed，
      無法證明有權限一律回空集合；②`scripts/check-tenant-isolation.rb` 進 CI，
      守住「白名單以外的表一律帶 shop_id」與「身分 model 不得再宣告 acts_as_tenant」。
  - **業務資料表完全未動**（products/orders/inventory 的 shop_id 與複合外鍵照舊）。
  - 驗證：rspec **52/52**（比原本多一條——新增孤兒帳號的 fail-closed 測試）；
    兩道安全網皆做過反向測試（注入違規確實 exit 1）。

### D9. AOV 不與 `net_sales` 同源——鐵律 7 的具名例外（G25）

- **問題**：本尊的 AOV 分子**刻意排除 post-order adjustments**，因此 `AOV ≠ net_sales / orders`。
  照鐵律 7「同指標同一份 rollup」的直覺實作，數字會與本尊對不上。
- **選擇：照抄本尊的例外**——AOV 有自己的 rollup 分子。專案前提是 1:1，且官方公式寫得很清楚。
- **配套兩條**：①**總銷售額允許負值**（撤銷 > 銷售的日子，官方明列）⇒ 金額元件與 badge 要支援負值；
  ②`any_click` 歸因各通路加總會超過 metric 本身（設計如此）⇒「小計＝總計」一致性測試須白名單。
- **影響**：`CLAUDE.md` 鐵律 7 已加註（主文不改，例外以註釋掛在條文下）；71-R11-V13 結案。

### D10. 不實作 POS，但資料模型保留 POS 活口（G26）

- **問題**：R13 取得 POS Lite/Pro 完整對照與 9 群組權限；範圍需裁定。
- **選擇：不做 POS**。理由：POS 是**第二個產品不是一個模組**——牽涉硬體、離線、裝置管理、
  店員 PIN、班次、現金抽屜，且**權限模型與後台完全不同**（organization role・只能指派角色不可逐權限・
  以裝置所在地點為軸）。以目前規模，把 POS Lite 做「對」的成本遠大於價值。
- **保留活口**：訂單來源標記、地點、員工歸屬三個欄位面現在就留著，之後要加不用改表。
- 🔴 **任何輪次不得因「本尊有 POS」而建議補做**——要翻案須推翻本裁定。
- **影響**：71-R13-V1 結案；R13 已建的 POS 管道殼保留為展示層。

### D11. UCP 延後至 M6 後評估，但受限 render context 現在就吃進主題引擎（G27）

- **問題**：R13 查明 UCP 是 Shopify 與 Google 共同開發的開放標準（規格在 ucp.dev），
  五個 MCP 端點、能力協商、checkout 四態都有官方文檔——技術面不再是未知，剩產品決策。
- **選擇：UCP 相容層延後**（在有商店有商品之前實作沒有意義）。
- 🔴 **但有一條現在就要吃**：`agents.md.liquid` 是**受限 render context**——
  只有 `request` 與 `agents` 兩個物件可用，且 `agents.md`／`llms.txt`／`llms-full.txt`
  **不可為 JSON template**。這是**架構約束不是功能**，M2 設計 render context 時沒算進去，之後補會很痛。
- **影響**：71-R13-V7 結案；71-R13-V3（主題引擎支援受限 context）**維持 M2 前必答**。

### D12. 變體×選項用 join 表 ＋ `option_values_digest` 物化欄（M1 前裁定）

- **問題**：`HANDOFF` §5 的 M1 第二項是「**變體 diff 更新**」，而 diff 的 match key 就是選項組合。
  但 55 張表裡**沒有 variant × option_value 的關聯**，`product_variants` 也沒有 digest 欄。
  `docs/specs/13` §F1-2 要求唯一索引 `(product_id, option_values_digest)`，
  🔴 **卻從沒定義 digest 的來源資料存哪**——這是全倉庫唯一一個「查了確實沒有規格」的洞。
- 🔴 **為什麼 84 號沒抓到**：84 只分流了 `71` §F 的 parity 條目，
  **從未做「spec 要求 vs 現行 schema」的對帳**。⇒「A 桶五條全結案」**不等於**「M1 無閘門」。
  同型的漏網另有 SKU 唯一索引（見 D13 註）。
- **選擇：`product_variant_option_values` join 表 ＋ `product_variants.option_values_digest`**
  （digest ＝ 排序後 join 的 SHA1，唯一索引 `(shop_id, product_id, option_values_digest)` 兜底）。
- **為什麼不選 `option1/2/3` 冗餘欄**：`docs/research/26` 明載 `variant.option1/2/3` 在 Liquid 是
  **DEP（已淘汰）屬性** ⇒ 等於把本尊已標記淘汰的形態焊進 M2 主題引擎；且天生只支援 3 個選項。
- **為什麼不選「只存 digest」**：無法反查「這個變體在某個選項上的值是什麼」，
  `docs/research/63` §B.5 的變體身分保持演算法（補上新選項的第一個值）跑不了，商品表單也畫不出選項矩陣。
- **影響**：擋 `productCreate` 的 input shape，必須在第一支商品 mutation 之前落地。

### D13. 系列採 61/13 的 sources 模型，`84` §2 B-4 作廢

- **問題**：兩份內部裁定互相矛盾——`84` §2 B-4 判「collections 表兩種都撐得住、可延後」，
  而 `docs/research/61` §10 C-4 與 `docs/specs/13` §F4.1 判「資料模型層級 P0」，
  且 13 §F4.1 **已經寫成五張表**。
- **選擇：採 61/13 的 sources 模型**（本尊 2026 改為「來源」卡：新增條件與新增商品同卡混用
  ＋排除 negative 條件＋多來源組），**`84` §2 B-4 作廢**。
- **理由**：鐵律 12 是最高強制（1:1 對齊本尊），而 B-4 把它當成 UI 問題判斷是錯的分類——
  「手動/智慧二分不可互轉」與「多來源組可混用」是**兩種不同的表結構**，不是同一張表的兩種畫法。
- **影響**：71-R8-V4 結案方向確定；M1 建 collections 相關表或 mutation **前**要先改 schema
  （現行 `collections`／`collection_products`／`collection_rules` 三張是 legacy 形態）。

### D14. userErrors 契約全面對齊本尊（2026-08-15，Admin API 2026-07 逐頁考掘）

- **問題**：`docs/research/28` §0.3 的 mutation 契約有四處與本尊不符，而第一支 mutation
  定下的形態會被全專案抄。使用者裁定：「深度分析和研究 shopify 的架構，然後我們和 shopify 一樣」。
- **方法**：四路平行考掘 shopify.dev（field 路徑／code enum／金額正負／payload 慣例）
  ＋ 三路對抗式覆核（找反例／查版本差異／檢查我方誤讀）。覆核逐頁複核 24 條 load-bearing 事實。

**照抄本尊的（無偏離）**：

| # | 裁定 | 依據 |
|---|---|---|
| 1 | `userErrors.field` 型別＝**`[String!]`**（list 可 null、元素非 null），不是 `[String]` | `/interfaces/DisplayableError` 的 SDL 逐字 |
| 2 | **`input:` 這層外殼要剝掉**：`productDelete(input:{id})` 的錯誤回 `["id"]` 不是 `["input","id"]` ⇒ 63 §A.4 的 `["lockVersion"]` **本來就對** | `/mutations/productDelete` 官方錯誤範例 |
| 3 | 陣列索引＝**十進位裸字串段**平鋪（`["variants","0","optionValues","0"]`），不用括號／JSONPath | 兩個官方 payload 實例 |
| 4 | 無法歸屬 ⇒ `field` 回 **`null`** 不是 `[]` | `/mutations/draftOrderComplete` 官方範例 |
| 5 | **沒有 `clientMutationId`** ⇒ BaseMutation 繼承 `GraphQL::Schema::Mutation`，**不得**用 `RelayClassicMutation` | schema 抽樣 ＋ 404 |
| 6 | payload 的 **resource 欄位 0..N**，唯一必備是 `userErrors: [X!]!` ⇒ 不得寫死「一個 resource ＋ userErrors」 | 多個官方 payload |
| 7 | **`CONFLICT` 只屬折扣線**（語義＝折扣屬性互斥的輸入驗證）⇒ 樂觀鎖改 **`STALE_OBJECT`**、庫存 CAS 改 **`CHANGE_FROM_QUANTITY_STALE`**。63 §L-3 以**相反方向**結案 | `DiscountErrorCode` 頁 |
| 8 | 金額**型別層一律不驗正負**；退款在交易層是**正數**、方向由 `kind` 承載；送 PSP 正數；訂單編輯減項用**獨立型別 ＋ 正 delta**。唯一負數例外是 tender 層 | `Decimal` scalar signed ＋ Stripe「A positive integer」 |
| 9 | `compareQuantity` **自 2026-04 已移除**，改 `changeFromQuantity`（型別 `Int` **nullable**——「必填」是行為層要求，做成 `Int!` 會拿掉官方明文的「傳 null＝關閉 CAS」逃生門） | schema diff |
| 10 | input object 命名規則 `{Mutation}Input` **已落後兩年**：本尊 2024-10 起拆成 `ProductCreateInput`／`ProductUpdateInput`，參數改具名 | `/mutations/productCreate` |
| 11 | 對齊基準版＝**2026-07**（Spring '26 發布日 2026-06-17），不是 2026-04 | 版本頁 |

**刻意偏離（每條都標 ours）**：

| # | 偏離 | 型態 | 為什麼非偏不可 |
|---|---|---|---|
| A | **所有 mutation 的 userErrors 一律帶 `code`** | 加嚴 | 本尊泛用 `UserError` **沒有 code**（`/enums/UserErrorCode` 回 404，無共用 base enum）。我方 admin SPA 是唯一客戶端，錯誤分支必須機器可判別；本尊留著無 code 的舊型別是**相容包袱**，它自己也在逐支遷往 typed error ⇒ 這是「往本尊正在走的方向走完」 |
| B | **各 enum 的值從共用池取** | 加嚴 | GraphQL **形狀照抄**（一個 UserError type 一個專屬 enum，`PageDeleteUserErrorCode` 只有 1 值、`PageCreate` 8 值、`PageUpdate` 9 值）；偏離的只有值域紀律。本尊自己就有 `PRESENT`／`PRESENCE`（語義相反）、`NOT_FOUND`／`RECORD_NOT_FOUND`／`*_DOES_NOT_EXIST` 三種拼法——那是二十年演進的產物，我方沒有相容包袱 |
| C | **不採用 `elementIndex`** | 收斂 | 本尊對陣列元素錯誤有**兩種**做法，而它自己沒把任一種做成全域鐵律（`ProductSetUserError` 就沒有）。`elementIndex` 與 `field` 的並存語義官方**從未定義** ⇒ 照抄等於抄一個語義未定的欄位。此偏離**只減不加**，客戶端照本尊的另一種寫一律相容 |
| D | **Admin 側新增 `warnings`** | 新增 | Admin GraphQL 沒有 warnings（`/objects/CartWarning` 在 Admin 命名空間 404），唯一先例在 Storefront Cart。63 §L-9 的「重複 SKU 放行但提醒」在本尊是**靜默行為**，我方判定靜默合併是可用性缺陷。形狀 **100% 照抄 Storefront**（`{code, target, message}` 三欄全非空），所以不是自創語義 |
| E | **冪等擴充到 33 支** | 加嚴 | 本尊 2026-04 起強制的是 **17 支**，全部是 refund／inventory／location——**Shopify 自己的金流寫入點**，不涵蓋我方自有的。`orderCreate` 至 unstable 都**沒有任何冪等機制**。判準沿用 NP1-D「凡金流寫入一律強制冪等」。🔴 **不會因升版變成 parity**，升版時不得併進官方段 |
| F | **冪等用 mutation 參數而非 directive** | 形態不同 | 本尊主流是 `@idempotent(key:)` **directive**（少數走 input 欄位）。⚠ 該 directive 的 SDL 定義 shopify.dev **沒有獨立頁面**（無 directives 索引），我方寫的 `directive @idempotent(key: String!) on FIELD` 是從用法反推 ⇒ 登記為假設 |

- **同批修正的檔案**：`CLAUDE.md` 鐵律 4（「HTTP 恆 200」改成三層）、`docs/research/28`
  §0.1／§0.3.1–§0.3.6、`docs/specs/63` §A.4／§E.5／§L-3／驗收清單、
  `docs/specs/65` §A.7 ＋ 五處「無符號」措辭、`config/limits.yml` 冪等區塊。
- 🔴 **仍未查到、不得硬寫的**：具名參數形下的多段 path（只有單段官方範例）；
  `UserError` 是否 `implements DisplayableError`；`OrderAdjustment.amountSet` 個別項的正負；
  ShopifyQL MONEY measure 的 **API 回傳**符號（報表 UI 明文「reversal 顯示為負」，
  但沒有頁面把 UI 符號與 API 符號連起來）⇒ **鐵律 7 的一致性測試不得斷言 `sales_reversals` 的符號**。

### D15. PR-1 落地時的實作級裁定（2026-08-15）

D14 定的是**契約**（與本尊對齊），本條記的是**實作時必須自己決定、而規格沒寫**的部分。
每一條都附「為什麼不能不決定」。

| # | 裁定 | 為什麼規格沒寫也得決定 |
|---|---|---|
| 1 | **`Data` 的 `.[]`／`#with`／`allocate` 三條後門全關** | `65` §C L2 只說關 `.new`。**`allocate` 產出的物件 `is_a?` 為真、欄位全 nil ⇒ 直接穿過 L3 的 adapter 斷言**，而只斷言 `.new` 的測試會全綠交付 |
| 2 | **`__build` 是 public，靠命名 ＋ CI C5 守** | Ruby 表達不了「friend class」——`Money::Storage` 與 `Money::PspMinor` 是兩個類別。**這是四層防線裡唯一一處型別擋不住的地方**，必須明說而不是假裝完整 |
| 3 | **`Money.fixed_string` 不用 `format("%.2f", …)`** | `Kernel#format` 的 `%f` 內部轉 Float，BIGINT max 上失真 2 分錢。**只在極大值現形**，一般測試全綠 |
| 4 | **型別層不驗正負** | `65` 從頭到尾沒提負數。在值物件上驗非負會讓退款差額與撤銷整條卡死；正負是**業務規則**不是**單位規則** |
| 5 | **`Money::Storage` 不定義算術** | `65` §F.3 只講 SQL rollup。現在猜一個實作，第一個使用者就會繞過它寫 `a.cents + b.cents` ⇒ 留給第一個需要小計／折扣的 PR |
| 6 | **`Psp::Registry` 入口統一鍵型別** | 生產 Symbol／fixture String，而「空表 ≠ 缺鍵」逼實作用 `Hash#key?`。不收斂 ⇒ **整份 §H 矩陣證明不了生產路徑** |
| 7 | **幣別鍵 upcase 收在 `Pack` 不是 `Registry`** | 後者是泛型的、不知道哪些鍵是幣別（做了會把 `amount_format` 變成 `:AMOUNT_FORMAT`） |
| 8 | **`config/iso4217_minor_units.yml` 的 TWD 刻意缺席** | `65` §H.3：本專案至今沒有 TWD minor unit 的一手出處。`limits` 裡兩個看起來像 exponent 的 TWD 數字**都不是 PSP 該用的那個**，填進底表就是從它們推導 |
| 9 | **`divisibility_scope` 目前被忽略（一律檢查）** | V-206 未結案；`65` §L 的當前處置是「最嚴格解讀」。scope 只進錯誤訊息 |
| 10 | **`enforce_idempotency_contract!` 不做去重** | claim/replay 有**五個**未決點（表形狀缺 `mutation_name`／transaction 邊界／缺 key 的 code／兩份清單待合併／業務失敗算不算成功而被快取）。五個未決點 × 零支真 mutation ＝ 五次盲猜 |
| 11 | **`Types::MutationType` 建了但不掛 schema** | 承上：**本 PR 一支 mutation 都不出，所以沒有任何東西獲得虛假的安全感**；掛上 root 的那一刻這個保護就沒了。guard spec 把解鎖條件寫進斷言 |
| 12 | **不交付 `purchasable`／`discoverable` 具名 scope** | `13` §F1.2(d) 的 SQL 指向兩張不存在的表。照做 ⇒ 全站商品靜默不可購買；省略變體層 ⇒ **名字在說謊** |
| 13 | **回填 migration 不補 `resource_publications`** | `published_at` 欄位已被上一支 migration 移除，「原樣搬」無值可搬。填 `NOW()` ＝實作 `auto_publish`（`88` §5 #2，明確延後）；填 `NULL` 與該 publication 的 `auto_publish: true` 自相矛盾 |
| 14 | **`Shop` 的 `publications` 用 `dependent: :destroy`** | 本 model 另外三個關聯都用 `restrict_with_error`，照抄會讓**每一間店（含空店）永遠刪不掉**，而沒有任何既有測試會紅 |
| 15 | **`around_destroy :within_own_tenant, prepend: true`** | 沒有它時，在別間店的租戶 context 下刪店會把 publication 過濾成 0 列、**一列沒刪卻回報成功**。`prepend` 不可省——`has_many dependent` 是在關聯宣告當下註冊成 `before_destroy` 的 |
| 16 | **CI 檢查跳過整行註釋、不跳行尾註釋** | 不跳整行 ⇒ **唯一正確實作 C4 的檔案被 C4 判違規**；要精確剝行尾就得處理字串內的 `#` 與 `#{}`，那正是 `lint-prototype.py` 踩過六次「漏看」的解析。取捨方向是**寧可誤擋** |
| 17 | **「0 examples 不是通過」守衛，判準＝ARGV 沒有路徑也沒有 `-e`／`--tag`** | fixture 曾讓整個套件從 233 變 0。判準改過兩次：無條件檢查會誤擋單跑一個檔；「載入檔數 < 5 ⇒ 跳過」**判斷反了**（那正是要抓的 bug 的症狀） |
| 18 | **「金額路徑的測試檔」用具名常數 `MONEY_TEST_GLOBS`** | `65` §H.1 以它為判準卻沒有定義它。**它的失效方向是「少掃」** ⇒ 新增金額 spec 時要記得加進去 |

🔴 **本 PR 全層沒有生產呼叫端**（`app/` 的 `Money::` 只出現在自己、`Psp::BaseAdapter`
沒有子類、`ProductType` 連價格欄位都沒有）。正確性靠三件事：規格逐行寫死的欄位形狀、
六幣別 × 兩種格式的測試矩陣、六條帶「故意違反 fixture」的 CI 檢查。
**這一點必須在 PR 描述誠實揭露，不得假裝已被使用。**

---

## 2026-08-15 — PR #29 驗收發現的送款缺口

### D16. `decimal_string` 位數下限：拒絕 sub-2 位，不發明湊整規則

> 來源：PR #29 的 Claude 驗收（🔴 必須修 第 1 條）。**規格全文＝`docs/specs/65` §D.2 A6b ／ §D.5。**

**缺口**：A6 原本只擋位數**上限**（> 2 ⇒ 精度謊報）。宣告 `decimal_places: 0` 或 `1`
**是完全合法的 pack**，而 `Money::Storage#to_psp_decimal` 走
`Money.fixed_string(major, pack.decimal_places)`，內部 `value.round(digits)`
**靜默四捨五入**：

| pack 宣告 | 帳上（儲存 cents） | 送出 | 差額 |
|---|---|---|---|
| `decimal_places: 1` | HKD 14.85（`1485`） | `"14.9"` | **0.05，沒有任何一張表記得住** |
| `decimal_places: 0` | HKD 1480.00（`148000`） | `"1480.0"` | 格式本身就不符它自己宣告的 0 位 |

🔴 **三件事讓這個缺口特別難發現**：
1. **與 `minor_units` 側不對稱**——那一側有 A3 的餘數 `raise` 順手擋住 float 與非整除，
   `decimal_string` 側**沒有等價物**（A3 是 minor_units 專用）；
2. **在 HKD 這個基準法域上就會發生**，不像 A1／A2 只在 zero-decimal 幣別現形；
3. **§H 矩陣證明不了它**——矩陣裡每個 pack 都宣告 2 位，那條路徑從沒被走過。

**裁定＝(a) fail-closed**：`psp_decimal_min_places: 2`，`validate_decimal_string!`
一併 reject `< min`。

**為什麼不選 (b) 補齊語義**（加 A3 等價檢查 ＋ §H 補 0／1 位案例）：
要「支援」sub-2 位就得先發明湊整規則——**誰決定進位方向？差額記到哪張表？**
`65` §D.4 的四家 PSP 實證表裡沒有任何一家這樣要求（Airwallex 是 2 位），
本規格全篇沒有出處可依 ⇒ 那是憑空造規則，而且很可能在第一次接真 PSP 時就是錯的。
🔴 **語義刻意留白**，等第一家真的這樣要求的 PSP 出現時再裁定；到時要改的是
`65` §D.5 ＋ `psp_decimal_min_places`，**不是繞過閘門**。

**配套（獨立的一個 bug，一併修）**：`Money.fixed_string` 在 `digits = 0` 時輸出 `"1480.0"`
——`"0".rjust(0, "0")` 回 `"0"`，而小數點是無條件接上去的。
🔴 **分層刻意如此**：格式化器管「怎麼 render」（對任意 `digits` 都要正確，因此修的是
格式化邏輯而不是在裡面加政策），政策層（A6／A6b）管「准不准 render」。
把政策塞進格式化器會讓 `Money::Decimal`（恆 2 位、與 PSP 無關）也被 PSP 規則綁住。

**負面驗證**（兩道防線各拆一次，確認測試真的會紅）：
- 拆掉 A6b 的下限檢查 ⇒ `registry_spec` 的兩條（`decimal_places` 1／0）紅；
- 還原 `fixed_string` 的 `digits=0` bug ⇒ `money_spec` 的位數契約那條紅。

---

## 2026-08-17–19 — 階段 0 收口與接手制度裁定

### D17. 修復只處理被點名處，查證不得等同擴修

- 2026-08-17 裁定：修復只動驗收方明確點名的問題；同型但未點名者只登記
  `docs/specs/91-pit-register.md` §3，不得主動 sweep、順手修或宣稱全族清零。
- 2026-08-18 升格為鐵律 16：修法方向必須先查證；外部語義帶官方 URL、取證日期與英文原文，
  純內部一致性以 `git log -p` 追沿革。查證可能否掉驗收方建議，但不擴大可動範圍。

### D18. 全自動化授權有明確停止線

- 2026-08-17 裁定：正常計畫內步驟免逐步確認，驗收清後可自動推進後續無依賴工作。
- 例外仍須停問：憑證紅線、破壞性操作、不可逆 schema、真實費用與計畫外新裁定。
- 鐵律 18.4 啟用前所有 PR 仍人工合併；自動合併與部署不是本裁定下的現行啟用狀態。

### D19. Ella fixture 可留在 public repo

- 2026-08-17／19 裁定：Ella fixture 留倉視為無授權問題；不得散布或隨平台出貨的產品義務不變。
- Codex／Claude bot 對這個已裁事項一律跳過，不再重開授權警告。

### D20. 取消熔斷，驗收循環不限輪數

- 2026-08-19 裁定逐字：「取消熔断机制，所有的必须循环到双清为止。不限次数」。
- `MAX_FIX_ROUNDS`、`review:需人工裁定` 與超輪分支已隨 PR #59 移除；不得以輪數為由停止。
- 雙清＝Claude bot 無 🔴／🟡，且 Codex 對當前 head 零未清意見；使用者明文棄單仍可覆蓋流程。

### D21. 紀律優先，不再自行新增機制化

- 2026-08-19 裁定：不因反覆意見自行改 CI、把 R4／R5 升級或增設 push 前腳本。
- 既有機械閘門保留；新機制只能先登記候選、代價與射程，取得使用者裁定後再做。
- 執行者仍須逐項履行鐵律 15，不能把責任推給 checker。

### D22. P-1 採乙案，不擴包遷移既有行號引用

- 只在 P-1 原定交付 `scripts/check-pit-register.rb` 增加新條目「⑦ 複驗指令不得只由 `檔:行` 構成」斷言。
- `91` §0.1 schema 與既有引用遷移不納入 P-1；既有立場仍是內容錨點正確、`91` 日後應改，
  不是撤回禁行號判準。

### D23. Shopify 負責交互取證；SHOPLINE 只作輔助參考

- 2026-08-19 裁定：建立訂單及建立／修改／刪除等交互邏輯使用獲授權的 Shopify 測試店取證。
- SHOPLINE 只作輔助參考，用來增強促銷、會員／點數／購物金、Builder 與報表功能；不建立訂單，
  不做可能產生費用的寫入，因此 2% 試用期交易費不是 R-9 驗收條件。
- R-9 不插隊、不購買方案；參考店到期由使用者更新。若日後確有 SHOPLINE 付費操作必要，須另案說明並取得授權。

### D24. R29 七條未處置意見全部交由接手者清理

- 清單＝D 組兩條機械／終態修復、A 組三條需使用者選案、B 組兩條可直接修。
- 「轉交」不是驗收意見的清法；修復、證偽，或裁定不修且落在 PR 描述／本檔，才算清除。
- A 組涉及真實費用或改變已批准方案結構，接手者不得自行選案。
- 接手輪已取得使用者對 A1–A3 的裁定並落於 D23、D26、D27；D／B 組採最小修復，七條均已有倉庫落點。

### D25. 互動式 Codex 可實作；workflow 自動派修維持廢止

- 2026-08-19 裁定：**僅本次互動式 Codex 工作階段**獲准實作、commit、push 並送 GitHub 驗收；
  本授權隨本次 PR #58 接手任務結束，**不可由後續工作階段沿用或視為制度改制**。
- `AGENTS.md` 的常態分工仍有效：未取得使用者另一次明文授權時，Codex 只驗收、不實作。
  本次裁定澄清的是 workflow 禁令不等於禁止使用者手動交辦一次性實作；workflow 內的自動
  `@codex` 派修乒乓仍維持廢止，不得加回。
- 修法含裁定時仍以本輪對話為準，尤其 A 組一律回問。Codex 自審不算獨立驗收；實作後獨立驗收方
  只剩 `claude-review.yml`，故查證與「全收」計數必須提高一級。

### D26. CD-1／CD-2／CD-3 各自使用可達成的驗收條件

- CD-1 驗部署基礎、伺服器初始化、備份啟用與最小還原演練。
- CD-2 驗 workflow 語法、觸發條件與 secrets 介面，依鐵律 18.3 人工合併。
- CD-3 驗真實部署、`/up` 與故障回滾，並作為 CD 階段總收口；前兩包不得被要求提供只有 CD-3 才能產生的證據。

### D27. 首批研究與規格工作全部拆成獨立 PR

- R-6、R-9、`121` 各自一個研究 PR；Q-1、S-1 各自一個階段 PR。
- 不以減少 PR 數為由綁定無共同依賴、無單一驗收標準的工作；每包各自 worklog、commit
  與驗收。handoff 依 D36 於每個工作單位結束時在 Git 倉庫外本地保存，不與 commit 綁定。

---

## 2026-08-20 — 階段一' 開工裁定

### D28. 伺服器到位，CD-1／CD-2／CD-3 解凍

- 2026-08-20 使用者裁定伺服器已到位，總方案中「伺服器到位後才執行」的等待條件已成就。
- CD-1 開工時再由使用者提供 SSH 位址與使用者、OS 規格、網域及 registry 選擇；SSH 私鑰與
  `RAILS_MASTER_KEY` 只放 GitHub Actions secrets，不進對話與倉庫。
- CD 各包仍分別遵守 D26 的可達成驗收條件與鐵律 18.3 的人工合併邊界。

### D29. Playwright 依賴獲准進倉

- 2026-08-20 使用者裁定 Playwright 作為 P-6 的 devDependency 進倉，解除
  `scripts/rwd-check.mjs` 與 C 軌的前置阻塞。
- 響應式輸出快照的實際路徑由 P-6 同包定義並納入倉庫，以符合鐵律 13.3 的可重跑憑證要求。

### D30. 本階段射程為整個階段一'與 CD

- 2026-08-20 使用者裁定本階段涵蓋 P-1～P-7、Q-1～Q-6、A–F 六軌及 CD-1～CD-3；
  執行細則見 `docs/plans/2026-08-20-階段一執行方案.md`。
- 無未完成依賴的包可並行；有依賴者須等上游合併進 main，18.3 人工合併點只暫停其依賴鏈。

### D31. 階段一'全自動化與代行合併授權

> 🔴 **2026-08-21 D38 現值**：下文的舊 `1111`／「階段 B」只保留 2026-08-20 授權沿革；
> 0e／0f 合併前不具代行效力。現行入口只有 D38 的 0e → 0f → 0g，且 `AUTO_MERGE=false`。

- 2026-08-20 使用者明文授權本次互動式 Codex 工作階段執行整個階段一'：實作、測試、commit、
  push、監視 GitHub 驗收、依結果修復並循環至雙清，以及在合規條件下代行合併；本條是取代
  D25 已到期授權的本階段新授權，不恢復 workflow 自動 `@codex` 派修。
- 代行合併僅限鐵律 18.1 四條件齊：Codex 對當前 head 完成且零未清、Claude bot 通過且
  零未清、非空機械 CI check 集合全部綠、0e／0f 現行 evaluator 已對 exact head 證明 C1–C4
  全通過；合併須使用
  `gh pr merge <N> --squash --match-head-commit <head>`，成功後刪除遠端 `pr{N}-last-push` tag。
- 鐵律 18.3 清單與 17.3 例外不在代行授權內，雙零後仍停下等使用者人工合併或裁定；
  本授權不翻 `AUTO_MERGE`，0g 只作現行 evaluator／接線的常規 PR canary。
- 2026-08-21 D38 過渡期補正：能實作新 C1 的獨立 evaluator 與 workflow 接線各自合併前，舊
  evaluator 不得啟動本條代行權，故全部 PR 暫由使用者人工合併；兩包完成後，本條只對原具名射程
  恢復，不外推到其他工作階段。

### D32. 互動式 Codex 實作與過渡期代行合併的鐵律補正

> 🔴 **2026-08-21 D38 現值**：本條授權主體仍有效，但任何舊 evaluator 結果均不得啟動代行；
> 只有 0e／0f 已合併且現行 evaluator 對 exact head 證明四條件全通過時，非 18.3 PR 才可代行。

- 2026-08-20 使用者在 PR #61 首輪驗收後選案「1」，並明文批准修改 `CLAUDE.md`／
  `AGENTS.md`：取得完整對話脈絡及具名射程授權的互動式 Codex 可以實作；workflow 自動
  `@codex` 派修仍維持廢止，GitHub Codex bot 仍只負責獨立驗收。
- 在鐵律 18.4 workflow 自動合併尚未啟用期間，D31 所授權的互動式工作階段可對
  **未命中 18.3**的 PR，在 18.1 四條件齊時以
  `gh pr merge <N> --squash --match-head-commit <head>` 代行合併；這是使用者授權的 CLI
  操作，不翻 `AUTO_MERGE`，也不把權限交給 workflow。
- PR #61 因本裁定修改兩份鐵律本文，已命中 18.3，必須在雙清後由使用者人工合併；
  D31 的代行路徑從其後第一個符合資格的常規 PR 才開始實測。
- 2026-08-21 D38 進一步凍結上述「其後第一個」：必須先讓新 C1 evaluator 與 workflow 接線各自
  合併，再由其後第一個符合資格的常規 PR canary；過渡期不因 PR 非 18.3 而恢復舊 evaluator 代行。

### D33. 全項目零假設發布

- 2026-08-20 使用者明文裁定：「所有一切項目內容禁止假設，必須取得證據，才能發佈」。本裁定
  升格為鐵律 19，自裁定時點起適用於全部倉庫內容、PR／review／commit／release／部署與驗收聲明。
- 外部語義須有官方／第一方 URL、取證日期與支持原句的英文原文；內部事實須有可重跑命令輸出
  或精確檔案、commit、diff、`git log -p`；CI／GitHub／執行期／部署狀態須綁當前 head／版本、
  時間及 run／check／review／API 證據。使用者裁定只證明專案選擇與授權，不替代外部事實證據。
- 未取得證據時只能發布「未取得」及缺少的證據、取得方法或阻塞，不得用推論作為事實、實作輸入、
  驗收基準或發布結論。舊制允許「標〔推論〕＋驗證法」的發布路徑至此撤銷；既存標記只代表證據
  缺口，不能被引用為已證實內容。
- 發布前採 fail-closed 逐項證據稽核；發現已發布假設時，依文檔分層保留應保留的歷史原文、追加
  日期更正並撤回錯誤聲明。PR #61 因修改規範本文仍命中 18.3，雙清後由使用者人工合併。

### D34. 重犯問題按已定型處理法一次斷根

> 🔴 **2026-08-21 D37 射程補正**：下文「同型未點名只登記」只適用於**不在已點名根因影響圖**
> 的既有問題；同一 producer／consumer／元件內可列舉的狀態矩陣屬同一被點名根因，必須同批封閉。
> 這是現行 17.2／20.5 射程；不得再以本條舊絕對句拒絕做根因閉合。

- 2026-08-20 使用者要求深度整理所有已處理問題類型，將「重複犯錯且已有固定處理方式」者寫入
  鐵律，避免再用後續驗收輪發現同型問題、浪費時間與 token；本裁定升格為鐵律 20。
- 升格門檻是同一系統性根因有兩個獨立可追事故，或在宣稱修復後復發，且已有固定處理與反向
  複驗；單次事故、仍待裁定或只有症狀相似者不立法，留在 `docs/specs/91-pit-register.md`。
- 截至本裁定的完整證據帳、F1–F12 判定與固定處理矩陣落在
  `docs/dev/m0-review-convergence.md`「重犯根因收斂稽核」。鐵律 20 要求送驗前一次掃完適用類型，
  再犯時記錄防線失效與反向複驗，不接受只補眼前一行或「下次小心」。
- 本裁定不覆寫鐵律 17.2：同型但未被點名的既有問題仍只登記 `91` §3；若斷根需要新增／擴張
  checker、workflow 或 CI 判準，先登記 §2 的候選與代價，另取得裁定並走 18.3 人工 PR。

### D35. 每一個執行步驟都必須留下詳細 handoff

> 🔴 **2026-08-20 更正：本條把使用者的「每次寫 handoff」錯誤擴張成每個小步驟都要
> handoff／commit；已由 D36 覆寫，不再是現行規則。下文保留當時錯誤落籍，供追溯事故。**

- 2026-08-20 使用者明文裁定：「你做的每一個步驟都必須寫 handoff。詳細介紹有什麼問題，
  做了什麼，需要注意什麼。」本裁定升格為鐵律 21，不再只在整次工作結束前交接。
- 「步驟」＝方案／任務／驗收清單中的具名或編號節點，以及會改變下一步決策的研究、實作、
  測試、commit／push、驗收、修復、合併、部署、rollback、逾時或阻塞；完成、失敗、純讀取、
  沒有改碼或證據未取得都要在進下一步前新增獨立 handoff 並 commit。
- handoff 沿用四段，但 §①必須具體記問題與證據、逐項動作／命令、產物與驗證；§②記理由、
  被推翻假設與未採方向；§③非空記未解、風險及下游；§④記下一步入口、前置、紅線與不得外推
  範圍。同一步內的命令收在同一份文件，handoff 的收尾不遞迴再造 handoff。
- push 成功、當前 head 驗收完成、合併、deploy／healthcheck／rollback 等結果只能在遠端動作後
  取得；若為了補倉庫 handoff 再 commit，會改掉剛被證明的 head。這類遠端終態改在對應 PR／
  deployment 留相同四段的 remote handoff，綁定 head／base、run／review／comment id 與時間；
  其後若有修復 commit，由下一份倉庫 handoff 引用。此例外只改載體，不放寬內容與證據要求。
- 本裁定不取代 worklog 三段、三件套、終態回寫、附錄 A 對帳與鐵律 19 證據稽核。PR #61
  因修改規範本文仍命中鐵律 18.3，最後由使用者人工審核與合併。

### D36. handoff 恢復原有工作單位節奏並改為本地保存

> 2026-08-21 D38 覆寫：本條「handoff 只存本地」仍有效；下文「一次驗收修復輪另觸發 handoff」
> 與「一份 handoff 可列多份 worklog」只保存 2026-08-20 沿革，現行檔案粒度一律讀 D38。

- 2026-08-20 使用者先後明文裁定：「handoff不需要commit只需要保留在本地」、
  「未來停commit到github，只保留本地」，並澄清：「我說的每次寫handoff都是按照以前那種形式，
  而不是要你每一個小步驟都commit到github」及「按照以前的來做handoff」。
- PR #61 前的可重跑證據是 `git show d9e6a458:CLAUDE.md`：worklog 按「可獨立驗收單位」產生；
  handoff 則在「每次工作結束前」用四段記錄「這一輪的判斷與教訓」。原文沒有要求純讀取、
  命令、等待、commit 或 push 各自建立 handoff。D35 對「步驟」的展開與 handoff-only commit
  是執行者自行增加的解釋，不是使用者裁定。
- 現行觸發點恢復為一個工作包／PR 初始交付、一次驗收修復輪、正式阻塞／rollback，或整次
  工作結束的交接點；同一單位內的研究、實作、測試、commit、push、等待、驗收與遠端終態
  收進同一份四段 handoff，不按小步驟拆檔。
- 自本裁定起 handoff 只存 Git 倉庫外的本地工作區，不新增或修改 `docs/handoff/`，不做
  handoff-only commit，不 commit／push，也不在 PR／deployment 另留 remote handoff。既有
  `docs/handoff/` 保留為歷史唯讀資料。
- worklog 規則不變：仍按可獨立驗收單位三段入庫並與產物一起 commit；一份本地 handoff 可以
  列出同一工作單位的多份 worklog。附錄 A 只登記實際入庫的 worklog，不登記本地 handoff。

### D37. 驗收改採 Convergence Protocol v2，廢止會自行增殖的循環

> 2026-08-21 後續裁定：本條的「產物頻率留第二包」、PR #66 一次性例外，以及下文把 clean
> completion 限定為 REST review／禁止 body ref 的舊 C1 均已由 D38 取代；以下保留為改制沿革，
> 現行產物頻率、C1 與 P-8 序列一律讀 D38。

- 2026-08-21 使用者裁定：廢除不必要、不合理且會讓驗收問題自行增加的機制；其餘採本輪
  根因審計提出的收斂方案。目標服務水準是每個可獨立驗收單元通常只發布「初始候選＋一次
  整合修復」兩個受驗 head；這是流程設計目標，不得冒充「任何缺陷必然兩輪內全被發現」的
  技術保證。
- 取證快照（2026-08-21，來源為 GitHub 三個 paginated REST 集合、review body、PR metadata
  與 git 歷史）：PR #61–#65 的修復循環已產生大量新 commit 與 review surface；PR #65 的
  current diff 另含多份逐輪 worklog，而 exact-head Codex 意見中有一組直接指向這些新生成的
  worklog／證據散文。重跑入口：
  `gh api --paginate repos/pisceshei/chilllovesaas/issues/65/comments`、
  `gh api --paginate repos/pisceshei/chilllovesaas/pulls/65/comments`、
  `gh api --paginate repos/pisceshei/chilllovesaas/pulls/65/reviews`、
  `git fetch -f origin tag pr65-last-push`、
  `git -c core.quotepath=false diff --name-only origin/main...pr65-last-push`。reviews 集合須逐則讀
  `.body`；`pr65-last-push` 是為該 exact head 保持可達的遠端基準 tag。
- 本第一語義包先廢止六項驗收控制流：①第一個 reviewer 回覆後即開始修、未等另一方完成；
  ②把同一 head 的歷史 inline 總數當未清數；③把「只修點名處」解讀成禁止封閉被點名根因在
  同一元件內可列舉的狀態空間；④每次本地微小編輯都跑全套閘門；⑤無限小修小推而不切換成
  根因審計／拆包模式；⑥Claude 判詞只有格式失敗時仍靠改檔換 head 或無界 rerun。
  worklog／handoff 的**檔案產生頻率與聚合方式**屬第二語義包；在該包連
  `docs/worklog/README.md` 等 consumers 一起合併前，D36／鐵律 21 的現行粒度維持不變。
  本第一包只禁止「唯一目的為刷新受驗 head／C1」的 unrelated、evidence、worklog、handoff 或
  空白 commit；這是驗收狀態機邊界，不裁定一般工程何時另建 worklog／handoff。PR #66 本身是
  D37 制度採用的一個可獨立驗收單元，當時的全部 bot 回應屬同一單元迭代，具名維護同一份 worklog；
  此過渡裁定只清本 PR，不外推成通用粒度規則。
- 新流程：一個候選 head 推送後，CI、Claude、Codex 三方未全部對 exact head 完成以前不得改檔；
  完成後一次全量拉 conversation、review body、inline 與 GraphQL threads，去重成凍結 finding
  ledger，再按根因批次修復。修復射程可涵蓋被點名根因在同一 producer／consumer／元件內的
  完整狀態矩陣與反向 fixture；無關元件仍只登記 `91` §3。
- 驗證採兩層：本地編輯時只跑受影響的 targeted gate；候選 head 凍結、整合修復 head 凍結及
  合併前 base 有變時，各跑一次完整正典閘門。任何 tracked file 在完整閘門後再變動，該候選
  證據失效；但純查詢、PR body、本地 handoff 與 thread resolve 不改 Git tree，不產生新 head。
- exact-head 原則保留於**實際 Git tree 變更**：新內容必須由兩方驗當前 head。Codex finding
  固定為 exact-head REST review body 或以 review ID 關聯的 inline／thread；處置不抹除時間。
  乾淨 completion 的 REST author、review `.commit_id`、body envelope 與無關聯 finding 四格均由
  fixture 鎖定，且須晚於最後 finding；不得用 comment `.commit_id` 或 body SHA 猜測。三個 REST
  集合、每則 review body 與 GraphQL threads 全取＋未解 threads 為零仍是必要條件，不再用 REST
  inline 歷史總數。GitHub 官方允許 PR 作者或具 write 權限者 resolve conversation，故 `isResolved=true`
  只是必要的工作流狀態，不足以單獨證明獨立驗收；官方證據見 `docs/dev/external-facts.md` A9。
  OpenAI 官方要求 Codex reaction 後仍 post review；reaction-only 沒有 exact-head review，故只作
  觸發／排隊訊號，C1 fail-closed 並轉人工，不得把 reaction 當乾淨 completion（外部證據 A10）。
  finding 處置未改 tree 時只送一次 same-head review 請求；第一方資料未保證同 SHA 重複請求必定
  產生新 review，故 deadline 前沒有更晚 exact-head completion（含平台去重）時 C1 保持 0，保存
  請求與水位後轉獨立人工審核／人工合併，不再重試、造 head 或啟用代行／自動合併。
  現有 `await-verdict.sh` 只等待兩個 reviewer，不構成機械 CI 證據；0e 接手前在同一有界 deadline
  另以 `gh pr checks --json name,bucket,link` 間隔輪詢；每輪查詢前後與凍結 ledger 前都須重取
  `headRefOid` 並等於候選 SHA，否則丟棄結果、非零終止。`pending` 等待；終態 `fail` 進 ledger
  授權修復；API／deadline 才是未取得；合併時仍確認全部 bucket 為 `pass` 並重驗 head（A11）。
  在新 evaluator 與 workflow 接線分別合併前，舊 `1111` 不得作代行合併依據；過渡期全部 PR
  視同 18.3 走使用者人工合併，避免舊 C1 假死或假綠。
- 收斂模式：初始候選有意見時只做一次整合修復；第二個 finding-bearing head 仍有同根因時，
  不得再小修小推，須在本地重建狀態矩陣、mutation 與影響圖，必要時自動把過大的單元拆成
  語義獨立 PR。這不是棄單熔斷，任務仍持續；它是禁止第三輪沿用已證失敗的點修方法。
- Claude 只有判詞格式失敗時，最多對同一 exact head 整體 rerun 一次；第二次仍畸形即保留兩次
  run 轉獨立人工審核，不為格式 push 新 head、不建立第三次 attempt。格式驗證仍 fail-closed，
  本款廢止的是無界重試與「改檔刷新」，不是允許畸形判詞自動通過。
- 仍保留：18.3 人工合併、GitHub CI 對每個 pushed head 全跑、tracked tree 變更後的 exact-head
  雙方最終驗收、三端點＋review body＋GraphQL 全量攝取、外部語義官方取證、合併前 base 更新
  與最終完整驗證。被廢止的是重複且不增加這些安全保證的手續，不是品質門檻。

### D38. 舊驗收制度整域退役，不再保留第二個產物頻率包

- 2026-08-21 使用者明文要求：「一次性修復好，不要再這樣不停的修復好幾輪，舊制度全部
  一次性剔除」，並要求深度分析、排查完成後才 commit。據此撤銷 D37 的「產物頻率留到第二
  語義包」過渡切法；D36 的「handoff 只存本地」保留，但檔案頻率由本條覆寫。
- 一個可獨立合併的 PR／原子工作包只維護一份 tracked worklog：初始候選與產物同 commit；
  finding 真正改 tracked tree 時，在一次整合修復 commit 更新同一份 worklog 與終態文件；純
  disposition、等待、resolve、PR body、run 與遠端終態不改 worklog、不造 head。umbrella 只有
  實際拆成可獨立合併 PR 才各建一份。`docs/worklog/README.md`、鐵律 21 與 AGENTS 同批同步。
- 一個工作包／PR 從研究到 merge／rollback／正式阻塞只維護一份倉庫外本地 handoff，不按
  驗收輪、命令、查詢、等待、commit 或 push 拆檔。只有正式轉交、rollback 後另起恢復包，或
  真正拆成獨立 PR 才另建；handoff 永不 commit／push。
- C1 採本倉庫實測的雙載體狀態機：finding 以 exact-head REST review `.commit_id`＋review ID
  關聯 body／inline／thread；clean completion 可由 connector issue comment 的受控 envelope 加
  獨立 `Reviewed commit:` 欄位證明，該欄只接受 10–40 位十六進位、且須為當前完整 head 的前綴。
  已觀測 envelope 有 A 型首行精確前綴 `Codex Review: Didn't find any major issues.`（句點後同一行
  自由尾句不參與分類），以及 B 型前兩個非空行 `## 驗收結論`／
  `**未發現需要新增 inline 意見的重大問題。**`。A 型固定 About-Codex details 與 B 型確認敘述／
  checks 屬同一 completion 說明，不用未定義的 prose NLP 重分類；可由同一 ref grammar 綁 current
  head、且第一個非空行為 `## 驗收結論：需修改` 的留言是 issue-comment finding，第二個頂層
  verdict marker 則 ambiguous／C1=0。
  PR #61／#64 的
  paginated issue comments 證明兩型存在；這是倉庫觀察，不冒充平台永久保證。PR #61 comment
  `5352954268` 後又有較晚 finding review `4980284182`，故該 clean 事件不能作終態；0e 必須以此
  fixture 證明「先 clean、後 finding」令 C1 回到 0。缺 ref、多 ref、錯 ref、未知 envelope、一般
  散文 SHA 或只有 reaction 一律 C1=0。
- 載體間先後只比較 UTC event time：已提交 review 用 `submitted_at`，issue comment 用
  `created_at`；clean 必須嚴格晚於最後 finding。缺值、解析失敗或相等都 fail-closed，數字 ID
  只作 endpoint-local 身分／去重，不跨端點排序（官方欄位證據＝external-facts A12）。
- current-head finding 集合為空時，時間下界定義為負無限；合法 exact-head clean completion 可滿足
  時序，但沒有 completion 仍 C1=0。0e 要以「零 finding＋clean／零 finding＋無 completion」正反格
  鎖定，不得把不存在的最後 finding 誤歸欄位缺失。
- CI 零 check 集合＝尚未執行，不是 all-pass：deadline 內等待，deadline 後 C3=0／證據未取得。
  `gh pr checks` 在 pending 時的退出碼 8 不是 API failure，必須先解析 JSON bucket 再分流；JSON
  未取得／不可解析才屬 API failure。非空集合全部 bucket 為 `pass` 才可合併；pending 繼續等，
  terminal fail 進凍結 ledger；skip／cancel 先對同一 head 重跑 owning check 一次，仍非乾淨才保存
  兩次證據轉人工。API failure 與 head drift 非零終止。
- C2 必須改成 run-specific exact-head 證據：0f 由受信任 workflow 產生 `run_id`／`run_attempt`／
  candidate＝`github.event.pull_request.head.sha`／verdict comment id 或 hash；0e 依 run id 複驗
  `event=pull_request`、目標 PR 的 `pull_requests[].head.sha`，並要求 run／job／check-run
  `head_sha == candidate` 作本倉庫具名 canary。官方未給該 response 欄位的 pull_request 永久語義，
  故任一缺失／不等即 C2=0，單看 `head_sha` 或舊時間窗都不能綁 run/head。C3 只排除 workflow jobs
  `check_run_url` 指出的 evaluator 精確
  check-run ID；self ID 缺失／多重、排除後 only-self、其他 pending 或錯 head 都是 C3=0（A13）。
- C4 的 0e fixture／mutation 必須覆蓋合法通過、合法需修改＋非空理由、判詞缺失、標記不在首行、
  重複標記、通過／需修改互斥、空白理由（含全形空白／CR）與未知結構；first-line、唯一標記、
  互斥與非空理由任一守衛被刪都必須使 regression 轉紅。
- P-8 當前唯一執行序列改為 0e 獨立 evaluator＋fixtures／mutation（人工合併）→ 0f
  workflow-only 接線**完整 C1–C4**並實查 validation-skip（人工合併）→ 0g 常規 PR canary。
  Codex 晚到只再調用 evaluator；whole-run rerun 只保留 Claude 判詞格式畸形的同 head 一次例外。
  #59 的舊
  `1111` evaluator 與 `await-verdict.sh` 只作已部署歷史／排隊訊號，**不得再作 C1、C3、雙清或
  代行合併證據**；0e／0f 完成前全部 PR 人工合併。總方案 P-8 舊合包契約、兩單元尾包與階段
  A／B 舊敘述移入歷史註，不再與現行序列並列。
- Markdown 表格驗證新增內容級反向斷言：除 pipe 與 cell 數外，改動表格要選末欄 sentinel，
  確認 GitHub 渲染後該列末欄保留 sentinel 全文；只數 `<td>` 不能證明超額 cell 沒被 GFM 丟棄。
