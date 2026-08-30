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
  <!-- 🔴 2026-08-24 更正（接手面稽核發現）：上面這一行是**被 2026-08-14 當日更正推翻的舊版**，
       卻一直留在本條開頭沒有標記——CLAUDE.md 鐵律 2 與 71 §A G24 都已更正、唯獨這裡沒有，
       正是「規則多落點、各落點各自腐化」的形態。現行白名單（以 CLAUDE.md 鐵律 2 為準）：
       用**我方實際表名**——已建：staff_members／roles／role_permissions／sessions；
       未建（M5 再加）：organizations／user_roles／user_groups／user_group_roles。
       🔴 `user_store_assignments` **不在豁免內、必須帶 shop_id**（上行把它列進豁免是反的）。
       本條下方「2026-08-14 當日更正」段的內容為準；此註只是把過期行就地標記。 -->
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
  evaluator 不得啟動本條代行權，故全部 PR 暫由使用者人工合併；
  🔴 **唯一解凍條件（全倉同文，不得另立變體）＝0e 與 0f 各自合併、且 0g 完成 merge-boundary guard 的 production canary 後**，
  且僅對 0g 之後的 PR、只對原具名射程恢復，不外推到其他工作階段。
  <!-- 🔴 2026-08-22 更正（來源＝PR #66 Codex inline `3835736708`）：本則原寫「兩包完成後，
       本條只對原具名射程恢復」——**漏掉 0g**。0e／0f 合併到 0g 完成之間有一段區間，
       照原文讀會在該區間內恢復代行，而那正好**繞過最後一道 bootstrap 安全檢查**。
       全倉不變量的逐字在本檔的 merge-boundary guard 段（內容錨＝
       `grep -n '唯一解凍條件' docs/DECISIONS.md`），該段明寫「**全倉同文，不得另立變體**」
       ⇒ 本則與 D32 現值段同批補齊。 -->

### D32. 互動式 Codex 實作與過渡期代行合併的鐵律補正

> 🔴 **2026-08-21 D38 現值（2026-08-22 補 0g 條件）**：本條授權主體仍有效，但任何舊 evaluator
> 結果均不得啟動代行；**唯一解凍條件（全倉同文，不得另立變體）＝
> 0e 與 0f 各自合併、且 0g 完成 merge-boundary guard 的 production canary 後**，且現行 evaluator 對 exact head 證明
> 四條件全通過時，非 18.3 PR 才可代行，且僅適用於 0g 之後的 PR。
> <!-- 🔴 2026-08-22 更正（來源＝PR #66 Codex inline `3835736708`）：本段原寫「只有 0e／0f
>      已合併且現行 evaluator 對 exact head 證明四條件全通過時，非 18.3 PR 才可代行」
>      ——**漏掉 0g 完成這個前置**。在 0e／0f 合併後、0g 完成前的區間裡，照原文讀
>      「evaluator 一通過就可代行」，於是**最後一道 bootstrap 安全檢查被繞過**。
>      與 D31 同批補齊；逐字以本檔 merge-boundary guard 段的「唯一解凍條件」為準
>      （該段自述「全倉同文，不得另立變體」）。 -->

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
  🔴 **「一份 worklog（不另建「第 M 輪」）」這一條對規則生效前已開的 PR 不追溯；其餘條文（分層、更正註、閘門、ledger）照舊不豁免**：判準與射程邊界見 `docs/DECISIONS.md` **D39**（2026-08-22 使用者裁定）。
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
  `created_at`；**曾被編輯的 issue comment（`updated_at` 晚於 `created_at`）改以 `updated_at`
  為排序時點，缺失或不可解析即 fail-closed**——否則 connector 在 clean 之後編輯既有留言補
  finding，該 finding 會帶較舊的 `created_at` 而讓 clean 誤判為較晚（可編輯性官方證據＝A14）。
  clean 必須嚴格晚於最後 finding，且 clean 時點前的每筆 finding 都須有**機器可讀、以 finding
  身分為鍵**的 disposition（值域 `fixed`／`disproved`／`no-fix-ruled`；後兩者帶可存取的證據或
  裁定條目引用），不得由事件排序或 thread 狀態推定；缺鍵、值域外或缺證據引用即 C1=0。
  缺值、解析失敗或相等都 fail-closed，數字 ID
  只作 endpoint-local 身分／去重，不跨端點排序（官方欄位證據＝external-facts A12）。
- current-head finding 集合為空時，時間下界定義為負無限；合法 exact-head clean completion 可滿足
  時序，但沒有 completion 仍 C1=0。0e 要以「零 finding＋clean／零 finding＋無 completion」正反格
  鎖定，不得把不存在的最後 finding 誤歸欄位缺失。
- 四個驗收集合（issues comments、reviews body、inline comments、GraphQL threads）**本專案不
  假定其為原子讀取**。🔴 這是**專案安全裁定**，不是平台語義：GitHub 官方頁只定義各端點與分頁，
  本輪查不到跨端點交易 snapshot 契約，也查不到一致性視窗數值或 SLA——「查不到」依鐵律 19.3
  記為未取得，既不反向斷言平台沒有 snapshot，也不作為實作輸入；採雙掃的理由是本專案選擇對
  未知邊界 fail-closed（外部可查原文只留在 external-facts A14）。
  **0e 合併後**：每次完整掃描前後都須確認 candidate `headRefOid`，再由該包已提交的版本化
  canonical serializer 對排序後、含判定欄位與 body／版本欄位的四集合各算 SHA-256；只有兩次連續
  完整掃描在已校準的 `SETTLE_INTERVAL_S` 前後得到相同 digest vector 才可凍結 ledger。
  `SETTLE_INTERVAL_S` **由 0e 以受控 live calibration 產生並在該包落值**（提交量測程序、原始觀測、
  採值理由與 interval 退化 mutation）；在此之前任何人不得自行填值或區間，「非零 interval」是待
  交付契約而非已生效判準。
  **0e 合併前的過渡期沒有 serializer、也沒有已校準 interval**：CLI 三端點＋reviews body＋GraphQL
  全量拉取只供獨立人工審核與修法 ledger，**不得輸出合規 digest、不得令 C1／四條件成立、不得
  代行或自動合併**；此時的穩定雙掃只是診斷輔助，不是機械證據。
  插入 finding、原地改 body、thread 狀態變化、分頁失敗或兩掃不等均 fail-closed；0e fixture 必測
  review 與 issue 端點讀取間插入 finding、兩掃間改 body、刪除穩定守衛，以及 interval 退化的
  mutation（可查原文邊界見 A14）。🔴 **另含四格**：clean 後編輯既有留言補 finding ⇒ C1 回到 0、
  移除 `updated_at` 排序守衛的 mutation（`updated_at` 不前進時須由 disposition 接住）、全部
  finding 有合規 disposition ⇒ 通過、其中一筆缺 disposition ⇒ C1=0；disposition 的載體／schema／
  責任方由 0e 同包定義並落地，落地前是待交付契約而非已生效判準。
- ⚪ 登記不得成為 exact-head 增殖器：只要本批另有 tree 修復，仍在同一 commit 搬入 `91` §3；
  exact-head 終態若只新增 ⚪，改在 PR body 寫唯一 grammar
  `DEFERRED_WHITE head=<40hex> comment=<decimal> item=<decimal>`，不改 tree。下一個本來就會改
  tree 的 PR，在首個候選前全量讀 merged PR bodies，把尚未存在於 `91` 的 deferred pair 批量
  入籍。錯 head、重複或無法在完整判詞集合複驗的 machine line 不算登記；任意 PR 散文不復活
  PR #55 前已廢止的過渡辦法。
- CI 零 check 集合＝尚未執行，不是 all-pass：deadline 內等待，deadline 後 C3=0／證據未取得。
  `gh pr checks` 在 pending 時的退出碼 8 不是 API failure，必須先解析 JSON bucket 再分流；JSON
  未取得／不可解析才屬 API failure。非空集合全部 bucket 為 `pass` 才可合併；pending 繼續等，
  terminal fail 進凍結 ledger；skip／cancel 先對同一 head 重跑 owning check 一次，仍非乾淨才保存
  兩次證據轉人工。API failure 與 head drift 非零終止。
- C2 必須改成 run-specific exact-head 且內容不可變的證據：0f 由受信任 workflow 同時產生
  `run_id`／`run_attempt`／candidate＝`github.event.pull_request.head.sha`／
  `verdict_comment_id`／`verdict_body_sha256`。0f 完成最終貼文或更新後，必須按 ID 從 GitHub
  回讀 `.body`，對不作任何正規化的 UTF-8 bytes 計算 SHA-256；0e 按同一 ID 重取、重算並要求
  hash 相等。ID 不替代 hash；缺／錯 hash、同 ID body 被原地編輯或內容不等均 C2=0。0e 再依
  run id 複驗 `event=pull_request`、**`run_attempt` 與 evidence 精確相等**、目標 PR 的
  `pull_requests[].head.sha`，並要求 run／job／check-run `head_sha == candidate` 作本倉庫具名
  canary；**job 只能取自官方 attempt-specific 端點
  `/actions/runs/{run_id}/attempts/{run_attempt}/jobs`，check-run 只能沿該 job 回應的
  `check_run_url` 取得**——同一 run 重跑時 `run_id` 不變而 `run_attempt` 遞增，只比 run id 會把
  attempt-1 的判詞配到 attempt-2 的執行證據。一般 run jobs 集合、另一 attempt 的 job／check-run
  或只比 run id 一律 C2=0，fixture 另須含 attempt mismatch 與 cross-attempt job／check-run
  （官方端點原文與本倉庫 canary＝A15）。官方未給該 response 欄位的 pull_request
  永久語義，故任一缺失／不等即 C2=0，單看 `head_sha`、comment ID、`updated_at` 或舊時間窗
  都不能綁 run/head/body；fixture 必測 same-ID body edit 與缺／錯 hash（A13／A14）。C3 只排除 workflow jobs
  `check_run_url` 指出的 evaluator 精確
  check-run ID；self ID 缺失／多重、排除後 only-self、其他 pending 或錯 head 都是 C3=0（A13）。
- C4 的 0e fixture／mutation 必須覆蓋合法通過、合法需修改＋非空理由、判詞缺失、標記不在首行、
  重複標記、通過／需修改互斥、空白理由（含全形空白／CR）與未知結構；first-line、唯一標記、
  互斥與非空理由任一守衛被刪都必須使 regression 轉紅。
- P-8 當前唯一執行序列改為 0e 獨立 evaluator＋fixtures／mutation（人工合併）→ 0f
  workflow-only 接線**完整 C1–C4**並實查 validation-skip（人工合併）→ 0g 常規 PR canary。
  0e 另須交付 **merge-boundary mode**：合併 consumer 必須在呼叫 merge 的**同一控制流**重新取得
  current head、新的 stable digest vector、四集合 watermarks 與 C1–C4，任何晚於該結果的
  review／comment／thread 變化或 watermark／vector 不等都中止合併。`gh pr merge` 的
  `--match-head-commit` 官方逐字只是 "Commit SHA that the pull request head must match to allow
  merge"（<https://cli.github.com/manual/gh_pr_merge>，取證 2026-08-21）⇒ 它**只鎖 Git head、不會
  使既有 review state 失效**，同 head 新增的 finding 不會觸發它。在 merge-boundary guard 的
  production canary 證成前，D31／D32 代行授權與 18.4 自動合併都保持凍結。🔴 **唯一解凍條件
  （全倉同文，不得另立變體）＝0e 與 0f 各自合併、且 0g 完成 merge-boundary guard 的 production canary 後**，且僅對 0g 之後的非 18.3 PR 生效；
  最後一次重驗到 merge 之間的殘餘窗是已登記、被接受的風險（GitHub 是否有服務端 review-state
  前置條件＝未取得，不反向斷言），**不另立為第二條解凍前置**。
  Codex 晚到只再調用 evaluator；whole-run rerun 只保留 Claude 判詞格式畸形的同 head 一次例外。
  #59 的舊
  `1111` evaluator 與 `await-verdict.sh` 只作已部署歷史／排隊訊號，**不得再作 C1、C3、雙清或
  代行合併證據**；0e／0f 完成前全部 PR 人工合併。總方案 P-8 舊合包契約、兩單元尾包與階段
  A／B 舊敘述移入歷史註，不再與現行序列並列。
- Markdown 表格驗證新增內容級反向斷言：除 pipe 與 cell 數外，改動表格要選末欄 sentinel，
  確認 GitHub 渲染後該列末欄保留 sentinel 全文；只數 `<td>` 不能證明超額 cell 沒被 GFM 丟棄。

---

### D39. 「一個工作包一份 worklog」對規則生效前已開的 PR 不追溯

- **2026-08-22 使用者裁定（選項 A）**。起因：Convergence Protocol v2（PR #66，merge commit
  `bbf5f3b73971b35d23c253a68bb2554d14eff1bc`）把 `AGENTS.md` §6「一個可獨立合併的 PR／
  原子工作包只維護一份 worklog⋯**不另建「第 M 輪」worklog**」變成硬性要求。
  而 PR #64 在該規則存在之前就已開始，並依當時的體例逐輪各建一份 worklog。
- **裁定**：該要求**不追溯**。規則生效前已開的 PR，其既有逐輪 worklog **維持原樣**，
  不要求整併、不因此判為違規；**生效後新建的 worklog 一律照規則**。
- **判準（單一權威訊號＝PR 的建立時間，不看 commit 譜系）**：

  ```bash
  set -u
  N=64                       # ← 要判定的 PR 編號；沒有這一行，下面整段跑不起來
  # 🔴 值域也要卡（月 01-12、日 01-31、時 00-23、分秒 00-59）——
  #    只卡形狀的話 `0000-00-00T00:00:00Z` 會通過然後被判成「很早」⇒ 誤給豁免。
  # 🔴 年份也要有下界：`[0-9]{4}` 讓 `0000-01-01T00:00:00Z` 形狀與日曆都合法，
  #    它會被判成「非常早」而拿到豁免。GitHub 時戳不可能早於 2008 ⇒ 收到 20xx。
  #    ⚠️ 這條下界在 2100 年後要改；它是**刻意的窄射程**，不是筆誤。
  ISO='^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$'
  RULE_AT=$(gh pr view 66 --repo pisceshei/chilllovesaas --json mergedAt --jq .mergedAt) || { echo "EVIDENCE_NOT_OBTAINED: gh 取 #66 mergedAt 失敗" >&2; exit 2; }
  PR_AT=$(gh pr view "$N" --repo pisceshei/chilllovesaas --json createdAt --jq .createdAt)  || { echo "EVIDENCE_NOT_OBTAINED: gh 取 PR createdAt 失敗" >&2; exit 2; }
  # 🔴 fail-closed：兩值都必須是**整串**合法的 ISO8601。
  #    空字串（`gh` 對未合併 PR 的 `--jq .mergedAt` 實回**空值**；逐字證據＝`docs/dev/external-facts.md` **B15**）、多行、
  #    權限不足、PR 不存在 —— 一律非零終止，**不得落到 APPLIES**。
  for v in "$RULE_AT" "$PR_AT"; do
    # 🔴 `grep` 是**逐行**比對：多行值只要有一行合法就會過。先擋掉換行。
    [ "$(printf '%s' "$v" | wc -l)" -eq 0 ] || { echo "EVIDENCE_NOT_OBTAINED: 值含換行" >&2; exit 2; }
    printf '%s' "$v" | grep -Eq "$ISO" || { echo "EVIDENCE_NOT_OBTAINED: 非 ISO8601: [$v]" >&2; exit 2; }
  done
  # 🔴 regex 只認**形狀**，收不掉**不存在的日曆日期**：
  #    `2026-02-31` / `2026-04-31` / 非閏年的 `2026-02-29` 三者形狀全合法。
  #    再做一次日曆回吐：正規化後必須逐字等於原值。
  for v in "$RULE_AT" "$PR_AT"; do
    [ "$(date -u -d "$v" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" = "$v" ] \
      || { echo "EVIDENCE_NOT_OBTAINED: 不存在的日曆日期: [$v]" >&2; exit 2; }
  done
  [ "$PR_AT" \< "$RULE_AT" ] && echo APPLIES || echo NOT_APPLIES
  ```

  🔴 **下列每一格都必須實跑過，這條判準才算成立**（20.2.5 逐字要求「正常、違規、輸入缺失／工具失敗**與零掃描 canary**」）：

  | 輸入 | `RULE_AT` | `PR_AT` | 期望 |
  |---|---|---|---|
  | 正常·適用 | `2026-08-22T14:21:47Z` | `2026-08-20T15:48:34Z` | `APPLIES`、rc 0 |
  | 正常·不適用 | `2026-08-22T14:21:47Z` | `2026-08-25T00:00:00Z` | `NOT_APPLIES`、rc 0 |
  | 輸入缺失（`gh` 回空） | 任意 | 空字串 | rc 2、`EVIDENCE_NOT_OBTAINED` |
  | 工具失敗（#66 未合併 ⇒ `gh` 回空值，見 `external-facts` **B15**） | 空字串 | 任意 | rc 2、`EVIDENCE_NOT_OBTAINED` |
  | 多行汙染 | `2026-08-22T14:21:47Z` | `x` ＋換行＋合法值 | rc 2（`grep` 逐行比對，不先擋換行就會過） |
  | 值域荒謬 | `2026-08-22T14:21:47Z` | `0000-00-00T00:00:00Z` | rc 2（月／日為 00）|
  | 不存在的日期（非閏年 2/29） | `2026-08-22T14:21:47Z` | `2026-02-29T00:00:00Z` | rc 2（regex 過、日曆回吐擋）|
  | 不存在的日期（4/31） | `2026-08-22T14:21:47Z` | `2026-04-31T00:00:00Z` | rc 2（同上）|
  | 閏年真日期不得誤擋 | `2026-08-22T14:21:47Z` | `2024-02-29T00:00:00Z` | `APPLIES`、rc 0（2024 早於規則生效點，本來就該適用；重點是**不得被日曆檢查誤擋**）|
  | 年份無下界（`0000`） | `2026-08-22T14:21:47Z` | `0000-01-01T00:00:00Z` | rc 2（日曆合法但年份被 `20xx` 擋）|
  | 年份早於 GitHub（`1999`） | `2026-08-22T14:21:47Z` | `1999-01-01T00:00:00Z` | rc 2（同上）|
  | **零掃描 canary** | 把上面**兩個 `for` 迴圈都**刪掉，再跑「輸入缺失」那格 | 空字串 | 必須翻回 `APPLIES` ——沒翻代表斷言根本沒被執行，這張表全部作廢 |
  | canary 補充（只刪其中一個） | 只刪 ISO 迴圈／只刪日曆迴圈 | 空字串 | **仍 rc 2**——兩道斷言互為備援，這是預期行為，不代表 canary 失效 |

  <!-- 🔴 2026-08-23 更正（來源＝本輪 push 前實跑，非驗收方點名）：
       canary 那列初稿寫的是「刪掉迴圈再跑**工具失敗**那格」，實跑回 `NOT_APPLIES` 而不是 `APPLIES`。
       原因：「工具失敗」那格空的是 `RULE_AT`，而 `[ "$PR_AT" \< "$RULE_AT" ]` 在 `RULE_AT` 為空時
       恰好落在**安全側**（任何非空字串都不小於空字串）⇒ 它證不出「斷言有沒有在跑」。
       真正會誤放行的是 **`PR_AT` 為空**那一格（空字串小於任何值 ⇒ `APPLIES`）。
       🔴 這說明 canary **選錯格等於沒做**：一個永遠回安全值的輸入，拿掉防線也不會變色。
       ⇒ canary 一律選「拿掉防線後會翻成危險側」的那一格。
       ---- 2026-08-23 二次更正（來源＝本輪 push 前對抗式複驗）：
            上一版 canary 逐字寫「把上面**那個** `for` 迴圈整段刪掉」。同一個 commit 把驗證迴圈從 1 個增為 2 個
            （ISO 形狀 ＋ 日曆回吐）之後，「那個」失去唯一解，而**兩種單刪法實跑都仍是 rc 2**（兩道斷言互為備援）
            ⇒ 照該列文字跑不出它宣稱的翻轉，依它自己的收尾句「這張表全部作廢」。
            🔴 這是 20.2.2 的 producer／consumer 不同步：我改了被 canary 指涉的對象，沒改 canary。
            ⇒ 改成「兩個都刪」，並另立一格記錄「只刪其一仍 rc 2」是預期行為。 ----
       ---- 2026-08-23 三次更正（來源＝PR #64 Codex inline `3836905824`）：
            本註**原本沒有結束標記**，而下一行又開了一則新註。GFM 的 HTML block 結束條件是
            「該行含結束序列」，於是兩則註釋合成一大塊，把夾在中間的 **D39 現行指引**
            （PR #64 的實跑結果、GNU／BSD 可攜性邊界）一併吞成不可見。
            🔴 這是本 PR 第二次因為「註釋沒各自關閉」而讓正文消失（前一次是第 0 欄殘骸行）。
            ⇒ 每一則 dated 更正註都必須自己閉合，不得靠後面那則的結束標記。 ----
  -->
  <!-- 🔴 2026-08-23 補正（來源＝PR #64 Claude issue comment `5381492053` 🔴-3）：
       上一版判準逐字＝`[ "$PR_AT" \< "$RULE_AT" ] && echo APPLIES || echo NOT_APPLIES`，
       **沒有失敗分支**。驗收方直接跑 shell 實測：`test "" "<" "2026-08-22T14:21:47Z"` ⇒ `APPLIES`；
       `test "2026-08-20T15:48:34Z" "<" "null"` ⇒ `APPLIES`。
       ⇒ `gh` 失敗、PR 不存在、權限不足、或 #66 尚未合併時**一律給豁免**。
       ---- 本行第二次更正（2026-08-23，來源＝PR #64 Claude issue comment `5381930022` 🟡-1）：
            上一版逐字寫「#66 尚未合併（`--jq .mergedAt` 得**字面 `null`**）」，**該描述為假**。
            實測結論：對 OPEN 的 PR 走同一條路徑，stdout 只有一個換行；命令替換後是**空字串**，
            不是四個字元的 `null`。
            🔴 **本處不再複製任何量測輸出**——逐字命令、逐字輸出、`gh` 版本與取證日期
            一律以 `docs/dev/external-facts.md` **B15** 為唯一來源。
            ---- 2026-08-23 更正（來源＝PR #64 Claude issue comment `5382552421` 🔴-1）：
                 本處原本自帶一份量測輸出，逐字寫「stdout 經 `od -c` 得 `0000000` 後接兩個空白與一個 LF（`0a`）」。
                 🔴 **兩處都錯**：`od -c` 對 LF 印的是反斜線 n、輸出裡不存在 `0a`（那是 `od -tx1` 的形態）；
                 且真實輸出有**兩行**，第二行被整個省略。
                 🔴 更難看的是：同一則更正註三行之下就宣告「外部行為的權威記錄改放 B15」，
                 而 B15 自己逐字寫著「初稿寫成 `0000000  0a`⋯那是 `od -An -tx1` 的形態」——
                 **一邊指定 B15 為權威、一邊在同一則註裡發布與 B15 不符的量測**。
                 ⇒ 本處只留結論與指標，不複製輸出。同一份量測**只能有一個發布點**。 ----
            🔴 這句的來源是驗收方上一輪的措辭，我沒有實測就落進裁定文件——**轉述不是證據**。
            外部行為的權威記錄改放 `docs/dev/external-facts.md` **B15**（帶實測命令、版本與取證日期）。 ----
       🔴 **20.4 四欄**：
       ① 復發錨：與觸發改判準的 Codex `3836378178` **同一個方向**（誤給豁免）——換了訊號、沒換防呆姿勢，第 2 次。
       ② 既有防線為何沒攔住：本倉庫沒有任何閘門會執行文件裡的 shell；20.2.5 是規則、不是機制。
       ③ 固定處理哪一步被漏掉：20.2.5 要求「同時證明正常、違規、**輸入缺失／工具失敗**與零掃描 canary」——
         我只證了前兩格（PR #64 適用／生效後開的不適用），第三格連想都沒想，因為**判準看起來只是一個比較**。
         🔴 判別法：凡是把外部指令的 stdout 直接餵進條件式，就必然存在「stdout 不是預期形狀」這一格。
       ④ 可重跑的反向複驗＝**上表每一列**（含後續補的日曆三格與 canary 兩格），任何一列不符即本判準無效。
          🔴 不寫列數——該表已隨每輪新發現的失敗形態擴充過兩次，寫死列數下一次就過期。
       ---- 2026-08-23 追記（來源＝PR #64 Codex inline `3836378178`／`3836685420`）：
            本區塊 ① 原寫「第 2 次」。到本輪為止，**同一個方向（誤給豁免）已經是第 3 次**：
            ①`3836378178` 譜系訊號錯 ②本註原記的 fail-open 無失敗分支 ③`3836685420` regex 只認形狀、
            收不掉不存在的日曆日期。三次的共同形態是**「我證明了正常路徑，就當作判準成立」**——
            每一次補的都是**失敗路徑**，而失敗路徑的集合我從來沒有一次性列全。
            🔴 因此本判準的驗證表改為「**每新發現一種失敗輸入就進表**」，不宣稱它已經完整。 ---- ----
  -->

  PR #64 實跑：`PR_AT=2026-08-20T15:48:34Z`、`RULE_AT=2026-08-22T14:21:47Z` ⇒ **APPLIES**。

  ⚠️ **可攜性邊界**：日曆回吐用 **GNU `date`** 的 `-d`（本機 Git Bash 與 CI ubuntu 皆為 GNU coreutils）。
  🔴 **BSD／macOS 的實際行為＝未取得**（本機無該平台，亦未取得官方 `date(1)` 逐字）。
  以下是**條件推論**，不是實測：*若* 該平台的 `date` 不接受 `-d` 而使該格解析失敗、stdout 為空，
  *則* 對非空值會被擋下（方向 fail-closed，但誤擋合法輸入）。
  🔴 **但對空字串是反例**：兩邊皆空 ⇒ 相等 ⇒ **不擋**。空字串由前面那個 ISO 迴圈承接，
  所以現行雙迴圈版**不是** fail-open；但「兩道斷言互為備援」這句話**在非 GNU `date` 上對空字串不成立**。
  在該平台可能要改 `date -j -f`（**同樣未取得**）。
  🔴 **已驗證的只有 GNU 側**：本機 Git Bash 與 CI ubuntu 皆為 GNU coreutils，本輪矩陣**每一格**全部實跑於此（逐格輸出見 PR #64 第十七輪 worklog 的「D39 判準輸入矩陣實跑」段）。
  🔴 **空字串那個反例不依賴平台**——它只用到 shell 字串比較（兩邊皆空 ⇒ 相等 ⇒ 不擋），
  所以「兩道斷言互為備援」這句話在**任何** `date` 失效的平台上，對空字串都不成立；
  空字串實際由前面的 ISO 迴圈承接，現行雙迴圈版**不是** fail-open。
  <!-- 2026-08-23 更正（來源＝PR #64 Claude issue comment `5382552421` 🟡-1）：上一版把
       「BSD 無 `-d`」寫成事實並緊接著宣告「這是已知邊界，不是未標示假設」，而下一行又寫「實際行為未取得」
       ⇒ 同一件事三行內同時被宣告為「已知」與「未取得」，與 19.3 互斥。⇒ 平台行為降為未取得，
       「已知邊界」限縮到 GNU 側，並把不依賴平台的那半（空字串反例）與依賴平台的那半分開。 -->
  <!-- 🔴 2026-08-23 改判準（來源＝PR #64 Codex inline `3836378178`）：
       本條原本用 commit 譜系判斷（`git log --first-parent` 取第一個 commit，再與規則生效
       commit 比祖先關係）。**那個訊號答的不是本條要問的問題**——它答「這條分支的第一個 commit
       多早」，而本條要問的是「**這個 PR 何時被開**」。
       🔴 漏洞：一個**規則生效後**才開、但從**過期 checkout** 長出來的 PR，其第一個 commit
       仍早於 RULE ⇒ `merge-base --is-ancestor` 回 1 ⇒ **不該適用的 PR 拿到豁免**。
       （更早一次的修正加了 `--first-parent`，堵的是「併入側枝」那個變體；
        本次是同一個根因的更上游——**譜系根本不是正確的訊號**。）
       ⇒ 改用 GitHub 的 `createdAt`：它是「PR 何時被開」的權威記錄，不受 checkout 新舊影響。
       ⚠️ 對 PR #64 兩種判準同值（皆適用），這是**把判準換成對的那一個**，不是改結論。 -->
- **理由，逐條**：
  ① **規則不能約束它存在之前完成的工作**——共同基底 `0fbe520` 上
  `grep -c '不另建「第 M 輪」' AGENTS.md` ⇒ **0**，main 上 ⇒ **1**，該條確由 #66 引入。
  本 PR 的逐輪 worklog 份數複驗：
  `git -c core.quotepath=false diff --name-only --diff-filter=A origin/main...HEAD -- 'docs/worklog/*.md' | wc -l`
  （2026-08-22 於 `df506749` 實跑 ⇒ **19**；該數會隨後續輪次增加，判準不依賴它）。
  ② **整併的代價是銷毀稽核軌跡**。逐輪 worklog 記的是「那一輪當時說了什麼」，而本倉庫的
  20.4 復發紀錄、19.5 逐字撤回、歷史層不回改**全部建立在這個軌跡上**；把它們壓成一份，
  會把「同一個錯誤第幾次出現」抹平——那正是這批 PR 一路在保護的東西。
  ③ **要解決的問題（按輪次增殖文件）在新 PR 上已由規則本身解決**，追溯不會多解決任何事。
- **射程邊界（不得外推）**：
  ① 只豁免「一份 worklog」這一條，**不豁免**其他任何條文（分層、更正註、閘門、ledger 照舊）；
  ② 只對規則生效前已開的 PR，**不對**其後新開的；
  ③ 這些 PR 若在生效後**新建** worklog，那一份仍受規則約束。
- 落點同步：🔴 **規則的每一個落點**都就地加指標，**不只加 `AGENTS.md`**。
  指標有**兩種合法形態**，不是一種：
  ① **規則本體所在的那一處**（`AGENTS.md` §6）用「本節「一份 worklog」⋯」的**就地限定寫法**——
     在規則自己的段落裡說「本節」是精確的，把規則名再抄一次反而累贅；
  ② **其餘所有落點**用逐字相同、機器複製的那一串（開頭為「「一份 worklog（不另建⋯」）。
  <!-- 🔴 2026-08-23 更正（來源＝本輪 push 前對抗式複驗，非驗收方點名）：
       本行原逐字寫「都就地加**同一串**指標（**逐字相同**、機器複製）」。
       🔴 那句話與倉庫現況矛盾：`AGENTS.md` §6 的指標是第 18 輪 🟡-2 **刻意**改成的限定寫法，
       不是那一串。照原文拿下面的雙 grep 去複驗，§6 這個落點會在右式零命中 ⇒ **假 FAIL**。
       ⇒ 明文承認兩種形態。判準不是「字串相同」，是「**每個規則陳述句的相鄰處，讀者都拿得到射程限定**」。 -->
  複驗（不寫死數字，因為落點會隨文件成長）：
  ```bash
  # 左：規則陳述句全集；右：已帶指標者。逐筆看左邊每一個**規則陳述**（非引用、非 worklog 敍事）相鄰處是否有右邊那一行。
  grep -rn '不另建「第 M 輪」\|一份 worklog\|不按驗收輪增殖\|只維護一份' --include=*.md docs/ AGENTS.md CLAUDE.md
  grep -rn '判準與射程邊界見\|本節「一份 worklog」' --include=*.md docs/ AGENTS.md CLAUDE.md
  ```
  <!-- 🔴 2026-08-23 更正（來源＝PR #64 Claude issue comment `5381302078` 🔴-5）：
       本行原寫「落點同步：`AGENTS.md` §6 就地加一句指向本條。」
       🔴 兩個問題：①實際加了五處，本行只寫一處；②更要命的是，即使加了五處仍有
       **D38 本文、Convergence Protocol v2 正典表、`AGENTS.md` §工作單位交接、總方案鐵律 17** 四處沒有 ——
       讀到那四處的人拿到的是**未豁免版**，等於裁定沒生效。
       → 本輪四處都補上；並把本行改成**導出指令**而不是數字，因為寫死的落點數下一次新增文件就又錯一次。 -->

### D40. 廢止雙 bot 驗收制；開發模式改為「直接開發＋CI 兩測」（2026-08-23 使用者裁定）

- **裁定原文**：「從現在開始你直接開發，取消 github 的 claude 和 codex 驗收。只保留 ci 兩個測試」。
- **改制內容**：
  ① `.github/workflows/claude-review.yml` 刪除——Claude bot 判詞不再產生、不再是任何合併前提。
  ② Codex（`chatgpt-codex-connector`）的 review **不再是驗收方**：其意見自本裁定起視同一般旁註，
     不進逐條處置義務、不擋合併。⚠️ 其自動觸發設定在 OpenAI 側
     （chatgpt.com/codex/cloud/settings），倉庫內無從關閉——**需使用者自行到該設定頁停用**；
     停用前它仍可能對 PR 發 review，一律不構成義務。
  ③ 合併前提收斂為 **CI 的 `quality` 與 `test` 兩個 job 綠**。
  ④ 開發模式：Claude Code 工作階段直接開發；分支→PR→CI 綠→逕行合併（使用者本裁定
     即為概括授權，18.3 的人工合併要求對此後的 PR 由本裁定承接；使用者可隨時收回）。
- **不隨之廢止的**：鐵律 1–14（技術鐵律）、金額/租戶/冪等等實質規範、文檔分層、
  worklog 紀律（D38 一包一份）照舊；15–21 中**專為雙 bot 循環設計的程序**（逐輪判詞攝取、
  雙零、exact-head 等待、20.3 送驗前稽核表）自本裁定起**停用**，其教訓保留於 91 §3 與
  memory，供日後恢復驗收制時參考。
- **背景**：PR #64 經 34 輪雙驗收不收斂（🔴 集中於驗收記錄自身），
  使用者裁定合併後進一步裁定改制。

### D41. 冪等 failed 語義：11 §2.1(b) 勝出，`IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED` 我方不發（2026-08-24，排程第 15 包）

- **問題**：91 §3.7 登記的矛盾——11 §2.1(b) 逐字「failed＝視為未執行，允許以同一把 key 重試」；
  本尊庫存三支 mutation 的 enum 描述逐字「A previous request with this idempotency key failed.
  **Retry with a new idempotency key.**」（三支同文，docs/research/95 §4 取證 2026-08-24）。
  兩者不可同真，而 91 明文「庫存線落地前必須先解此矛盾」。
- **選擇：11 勝出（同 key 重試），全平台單一語義；該 code 從我方庫存錯誤 enum 移除、永不發出。**
- **理由**：①productSet 線已依 11 落地（`Idempotency::Guard` 的 failed→同 key 重試是**已上線行為**），
  庫存線若改走換鍵語義，就是 91 警告的「兩線對同一個 code 觸發條件不一致」；
  ②同 key 重試是嚴格更友善的語義——客戶端失敗後不需要新鍵管理邏輯；
  ③我方錯誤 enum 本來就是刻意重造的（G-code 前例），不背未發出的死碼。
- **影響**：第 17 包的庫存 mutation 錯誤 enum **不含** `IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED`；
  CONCURRENCY 池若列有此碼，掛「商品線／庫存線皆不發」註記。與本尊的機器可見差異
  屬 enum 重造的既有範圍（71 §A G28 同案脈絡），非新增豁免。

### D42. 庫存權限鍵＝獨立的 `inventory.view`／`inventory.edit`，不沿用 `products.edit`（2026-08-24，排程第 15 包）

- **問題**：12 號規格的 permission key 清單 grep `inventory` 零命中——庫存三支 mutation
  落地時要嘛沒有授權檢查、要嘛靜默沿用 `products.edit`，兩者都是排程文件點名的缺口。
- **選擇：新增 `inventory.view`／`inventory.edit` 兩鍵**，命名照 12 §2 的 `資源.動詞` 慣例；
  已寫入 12 §2 的 key 清單。
- **理由**：本尊在 API scope 層就把庫存與商品分開（`read_inventory`／`write_inventory` 獨立於
  `read_products`；webhook topic 逐條標注所需 scope——2026-08-24 研究）。倉管改庫存數量
  不應自動獲得改價格與文案的權力，反之亦然。
- **影響**：第 16 包的 `totalInventory` 欄位**沿用 products.view**（它是商品讀取面的欄位，
  本尊同樣以 read_products 讀 `Product.totalInventory`）；`inventory.*` 兩鍵的第一個強制點
  是第 17 包的 mutation 與第 18 包的 /admin/inventory 頁。M1 全員 owner ⇒ `can?` 恆 true，
  但 policy 縫現在就分開，M5 RBAC 展開時不必回頭拆。

### D43. 批量編輯器與庫存 CSV 明文延後；第 17 包的禁直寫 cop 不留豁免口（2026-08-24，排程第 15 包）

- **問題**：①本尊 bulk editor 明文不留庫存移動紀錄（help 逐字「a record of your inventory
  movements isn't tracked when you use the bulk editor」，94 §2b④）——與 13 §F5「ledger 唯一入口」
  正面衝突，第 17 包的 rubocop cop 要不要為它留豁免口？②庫存 CSV 匯入與批量編輯器
  在不在本階段？
- **選擇**：①cop **不留豁免口**——M1 沒有 bulk editor，豁免口是為不存在的東西開洞；
  日後 bulk editor 落地時**一律走 `Inventory::Adjust`**（即：我方批量路徑也寫 ledger，
  是對本尊的行為超集）。⚠️ 該超集屬與本尊的刻意差異，**落地前需使用者批准入 71 §A**——
  本條先定 cop 形狀，不預支 §A。②庫存 CSV 匯入器與批量編輯器**明文延後**（不入 M1 排程；
  71 §F 既有 R8-V5／R8-V2 兩條 V 繼續持有此缺口，不靜默丟掉）。
- **理由**：豁免口的成本不是現在的代碼，是它教會下一個人「繞過入口是選項之一」；
  而「批量也寫 ledger」在資料上嚴格多於本尊，商家看到的是**更完整**的歷程，不是行為差。
- **影響**：第 17 包 cop 全域生效無例外；R8-V2／R8-V5 的結案責任移交 bulk editor／CSV 落地輪。

### D44. 冪等鍵 TTL 過期後重用＝userError，不靜默 replay（2026-08-24，第 17 包對抗審查的解）

- **問題**：Guard 的 24h TTL（11 §2.1：過期＝同 key 視為全新操作）與
  `inventory_adjustment_groups` 的**永久**唯一索引互撞——過期讓位重跑時 group create
  撞舊列，未接住＝該 key 毒化成永久 5xx（對抗審查以實跑 repro 證實）。
- **選擇**：接住撞索引，回 `IDEMPOTENCY_KEY_ALREADY_USED` userError（200），
  **不**靜默 replay 舊 group。
- **理由**：TTL 過期後指紋列已刪，無從驗證新請求參數與原請求相同——回舊結果是冒充成功。
  fail-closed 讓客戶端顯式換新鍵，語義誠實且一行不改 Guard。
- **影響**：group 的永久唯一索引成為庫存線的「第二層冪等」；11 §2.1 的「過期＝全新操作」
  對庫存線的實效＝「過期＝必須換鍵」。錯誤碼入 InventoryAdjustUserErrorCode（own_value）。

### D45

**on_hand 調整免附 `ledgerDocumentUri`（ours，2026-08-24 使用者裁定）**

- **背景**：對抗式複查（第 18 包出貨後）實測發現，庫存後台的「On hand／總計」行內調整
  **100% 失敗**——bt3 實跑回 `INVALID_QUANTITY_DOCUMENT`。成因是 `Inventory::Adjust`
  照 `docs/research/95` §4 的本尊語義實作了「除 `available` 外 `ledgerDocumentUri` 全部必填」，
  而手動盤點的 UI 沒有任何文件 URI 可附。
- **裁定**：**放寬 `on_hand`**，其餘四個 name（`reserved`／`damaged`／`safety_stock`／
  `quality_control`）維持必填。落點＝`Inventory::Adjust::LEDGER_DOCUMENT_OPTIONAL_NAMES`。
- **理由**（兩條，缺一則這個放寬就只是便宜行事）：
  ① **在我方模型裡 `on_hand` 不是獨立變數**——`LEAF_COLUMN` 明文把它翻譯成 `available` leaf。
     實際寫的是 available 這條 leaf，卻要求它附一份 available 自己**不准**附的文件，
     規則自相矛盾。
  ② **手動盤點沒有文件**。On hand 儲存格是商家數完架上數量直接改的，
     不存在對應的轉移單／收貨單。必填的實效是「這個入口不存在」。
- **🔴 這是與本尊的刻意差異（ours），不是照抄**。與鐵律 4 的
  「`code` 一律有值是我方刻意加嚴」同一性質：登記在案、寫進註釋、有測試守著
  （`spec/requests/inventory_read_spec.rb` 同時測「on_hand 免附放行」與
  「damaged 未附仍回 `INVALID_QUANTITY_DOCUMENT`」——後者防止放寬被擴大成橡皮圖章）。
- **影響**：`docs/research/95` §4 的本尊語義**不改**（那是外部事實）；差異記在本條與
  `docs/dev/m1-inventory-ui.md`。日後若本尊也放寬，本條可降級為「與本尊一致」。

### D46

**第一道租戶閘接線：`user_store_assignments` 成為登入與 session 恢復的前提（2026-08-24）**

- **背景**：D8 把身分表（`staff_members`／`roles`／`sessions`）升為組織層、拿掉 `shop_id`，
  並明文要求由 `Current#accessible_shop_ids`／`#can_access_shop?` 這道 fail-closed 安全網
  在應用層補回「這個人屬於這間店嗎」。**但那道閘從未接線**——對抗式複查（2026-08-24）
  `grep` 證實 `can_access_shop?` 只有定義、註釋與 spec，**零 production 呼叫點**。
- **後果（已重現）**：`SessionsController#create` 用 `StaffMember.find_by(email:)`
  **全平台**查，成功即發 session；`Session.authenticate` 只比對 token digest；
  `StaffMember#can?` 第一行 `return true if owner?`。
  ⇒ **A 店的 owner 在 B 店的 host 用自己的帳密登入，即可讀寫 B 店資料**。
  曝險面是整個 admin（products／collections／inventory 全部），不只複查發現它的庫存面。
- **裁定**：接上**兩側**的閘，判定依據一律 `user_store_assignments`：
  - **登入側**（`SessionsController#create`）：發 session 前要求本店指派，
    失敗走**與帳密錯誤完全相同**的訊息（否則登入表單成為帳號／租戶枚舉側通道）。
  - **恢復側**（`ApplicationController#resume_admin_session`）：每個 request 驗一次，
    失敗當作**未登入**（不是 403——403 等於承認「這間店存在、你只是沒權限」）。
    `Admin::BaseController` 與 GraphQL controller 都繼承它，**一處覆蓋整個 admin**。
- **🔴 不改 `can?` 的 owner 短路**：兩層是 AND，第一層＝能不能進來、第二層＝進來能做什麼。
  owner 在**自己有指派的店**裡本來就該無所不能。缺的是第一層就補第一層，
  把租戶歸屬塞進第二層只會讓兩層語義糊在一起。
- **配套（少一個就是把所有人鎖在門外）**：
  ① `db/migrate/20260824130000_backfill_user_store_assignments.rb`——正式站實測
     `assignments=0`，不先鋪路，接閘當天所有帳號都進不去。
     恰好一間店才推斷補齊；**多於一間店一列都不建**（猜錯的代價正是這個漏洞本身）。
  ② `db/seeds.rb` 建立指派，否則新裝的 owner 會被自己的安全閘擋掉，
     而錯誤訊息（刻意地）不會說出原因。
- **影響**：新增商店的 onboarding 流程**必須**同時建立 owner 的指派——
  目前沒有 production 的建店路徑（只有 seeds／console），做 onboarding 時這是硬前提。

### D47

**handoff 回歸入庫：推翻鐵律 21.3（2026-08-24 使用者裁定）**

- **背景**：鐵律 21.3（2026-08-21）規定 handoff 只保存在 Git 倉庫外的本地工作區、
  `docs/handoff/` 唯讀不再增長。但 2026-08-23 起十個 PR（#75、#78、#79、#81、#83、#85、
  #86、#97、#110、#112）全部把 handoff commit 入庫——成因是各 session 載入的
  工作目錄 `CLAUDE.md` 是 2026-08-16 的過期複本（只有鐵律 1–12，21.3 對它們不可見），
  照著舊條文「一律寫 docs/handoff/ 並一起 commit」執行。**條文與實踐各跑各的**，
  而且沒有任何一方是誰刻意選的。
- **裁定**：**改條文、承認實踐**——handoff 一律入庫 `docs/handoff/`，與該工作單位的
  產物同 commit。已誤入庫的十份不回頭改（歷史照舊）。
- **理由**：接手者的形態已改變。「另一個 Claude clone 倉庫接手」是常態，
  倉庫外的本地檔案對它**根本不存在**；handoff 的目的就是讓接手者拿得到，
  放在拿不到的地方等於沒寫。
- **仍然成立**：21.1（一個工作包一份，不按驗收輪增殖）、21.2（四段結構，能直接接手）、
  21.4（一個 Git 驗收單位一份 worklog）、21.5（交接內容受零假設發布約束）。
- **配套**：CLAUDE.md 21.3 已就地改寫並引本條；AGENTS.md 歷史層表與 §6 同步；
  🔴 **工作目錄的過期 CLAUDE.md 複本已同步為現行版**（漂移的根因），
  同步方式與提醒見 `docs/handoff/2026-08-24-總交接.md`。
- **影響**：D36／D38 中與「handoff 不入庫」相關的部分由本條取代；
  AGENTS §9.3 歷史層的「既有份唯讀」不變（新增份恢復增長）。

### D48

**alt 權威遷回檔案層；並確立「有分歧一律跟本尊」的通則（2026-08-25 使用者裁定）**

- **裁定原文**：「所有的都跟Shopify」——回應第 28 包 PR 提出的 alt 分層抉擇。
- **直接效果（推翻 D-無編號的第 26／27 包實作裁定）**：alt 的權威從 `media.alt_text`
  改為 **`files.alt_text`，全店一份**。同一張圖掛在 30 個商品上就是同一份 alt，
  在檔案庫或任何商品頁改它，處處跟著改。`media.alt_text` 欄位**停用但不刪**
  （不刪欄＝schema drift 最小，同 B4 的 `product_variants.sku` 先例）。
- **被推翻的理由**（記下來，免得日後有人以為當初沒想過）：第 26／27 包選 per-product
  的論據是「同一張圖用在洋裝和外套上，各寫各的說明比較貼近實際用途」。那個論據**本身
  沒有錯**，但它不是我們的取捨——本專案的目標是與本尊 1:1 對齊（鐵律 12），
  「我們覺得比較好用」不構成偏離理由；偏離只有兩種合法形態（71 §A 保護清單或 §F 的 V），
  而這一條沒有進 §A 的理由。
- **證據層級（誠實登記，鐵律 19）**：本尊 alt 在檔案層有**兩項官方佐證**——
  ①`MediaImage` 同時 implements `File` 與 `Media`，**只曝露一個 `alt` 欄位**
  （<https://shopify.dev/docs/api/admin-graphql/latest/objects/MediaImage>）
  ②help 逐字 "Accepting suggested alt text in the media editor saves the alt text to
  **the file**."（<https://help.shopify.com/en/manual/products/product-media/add-alt-text>）
  ⚠️ 「在 Files 改 alt 會傳播到全部商品」這一句**沒有官方逐字**，是由 ①的型別結構
  推導出來的。⇒ 實作依本裁定進行，但該句在文檔中一律標明是推論；
  複驗法＝測試店把同一檔掛兩個商品、從 Content › Files 改 alt、再讀兩個商品。
- **通則**：「所有的都跟 Shopify」同時是對**其餘已登記缺口**的裁定——
  第 28 包 `91` §3.10 登記的三項（檔案庫排序、選檔器內上傳、列表載入更多）
  一律補到與本尊一致；`used_in` 值域涵蓋 Metaobjects／Brand Settings 那一項
  **維持登記**，因為那兩個功能我方尚未實作，不是選擇不做而是還沒到。
- **不受影響**：§A 保護清單的 27 條仍然有效。本裁定推翻的是「未經裁定就形成的實作
  偏離」，不是已經明文裁定過的偏離——兩者不同，不得混為一談。

### D49

**OpenCC 字元表（Apache-2.0）准予入庫；繁簡誤借稽核轉為實際執行（2026-08-25 使用者裁定）**

- **裁定**：對「第 7 包的繁簡誤借稽核需要 OpenCC 字表（Apache-2.0——帶專利授權與
  NOTICE 保留義務）。要引入嗎？」使用者選「**引入（連 NOTICE＋attribution 一起入庫）**」。
- **射程**：僅 `STCharacters.txt`／`TSCharacters.txt` 兩個**資料檔**（未修改），
  不含 OpenCC 原始碼；詞庫（TWPhrases 等）**不在本裁定內**（要用另行裁定）。
- **落地**：`lib/opencc/`（LICENSE 逐字＋NOTICE）＋`Translations::ScriptDetector`＋
  `Translations::Audit` 的 `script_mismatch` 規則由「明文棄權」轉實際執行（僅登記不自動修）。
  採用登記＝`docs/specs/107-external-adoption-register.md` OpenCC-1（本檔隨本裁定建立）。

### D50

**第 11 包（智慧系列引擎）採案 A：連最小地基一起交付（2026-08-25 使用者裁定）**

- **背景**：W5 整合規格把 sources schema（包 10）與 product_tags（包 9）列「不回補」，
  但包 11 的引擎沒有表可寫；舊 `collection_rules.condition_value` 用字串存金額
  （`'148.00'`）＝鐵律 3 禁止的十進位字串入口，不能沿用（三方向 :86 已登記）。
  第 11 包研究輪（P11-U16／§9-9）依 90 §7「未裁定不得動工」呈裁定。
- **裁定**：**案 A**——包 11 自帶三張必要表：`collection_memberships`（物化成員，
  含 13:369 的 `variant_key` 產生欄 NULL 陷阱解）、typed-value 規則儲存（金額走
  `value_cents`）、`product_tags` 正規化表（tag EXISTS 的載體，13 §F4.3）。
  照 D13「建表前先改 schema」與 spec 13 正典一次建對；包 11 由 M 升 L。
- **不採**：案 B（沿用字串規則表——違鐵律 3，除非改鐵律本文）；案 C（先另開包 9/10
  回補——多兩輪 PR 無實質差別）。
- **配套**：spec 13 §F4.1 的過時 schema 塊（13:337-347）隨包 11 契約 PR 回寫；
  `collections` 補 `rebuild_status`/`rebuilt_at`（13:335）。


### D51

**商品建立的多語言形態走 SHOPLINE，不得改回 Shopify（2026-08-26 使用者裁定）**

- **裁定原文（逐字）**：「**商品建立那個多語言參考的是 shopline，所以你必須禁止改回和 shopify
  完全一樣的。這點你要參考之前的文檔。**」
- **背景**：2026-08-26 使用者要求把第 12 包（發布模型）從第一步重做一次、逐項對齊本尊。
  在那個對齊射程裡，「商品建立頁的多語言輸入形態」會被誤判成「與 Shopify 不一致的缺口」
  而被修掉——但它是 2026-08-23 已裁定的**刻意偏離**。本條把該裁定**補登**成 D 編號。
- **為什麼要補登**：2026-08-23 的 C1–C7 裁定只寫在
  `docs/plans/2026-08-23-多語言方案.md` §10，**從未回寫 `DECISIONS.md`**
  ⇒ 只讀本檔的人完全看不到「建立態多語＝SHOPLINE 形態」這條裁定，
  於是每一輪 Shopify 對齊都會重新把它當缺口。這正是 D48「所有的都跟 Shopify」
  必須保留 71 §A 保護清單的同一個理由。
- **保護射程**（逐條，出處在括號內）：
  - **建立態即可填多語**（C1；`config/limits.yml` 的 `create_only_in_source_locale: false`）
    ——推翻 `docs/specs/67-multilingual.md` §E.2 原本的「一律在 source locale 下建立、
    建立態停用語言切換」。**該原文已作廢，不得據以判缺口。**
  - **編輯頁內嵌形態**：標題＝**堆疊式**（各語言並列、各標 endonym）；
    說明與 SEO＝**分頁式**（一個編輯器實例＋N 個 tab）（多語言方案 §2.4）
  - **刪語言保留譯文、加回即復原**（採 SHOPLINE 的承諾；`app/models/shop_locale.rb`）
  - **CSV 匯入認 SHOPLINE 欄名方言**（`[en]`／`(English)` 等；70 §D.1；輸出**不**抄）
- **明文不採 SHOPLINE 的部分**（同樣不得被「對齊 SHOPLINE」反向推翻）：
  資料層的 `*_translations[lang]` 欄位 map（承載不了六個稽核欄）；
  URL 的「預設語言無前綴＋裸 `/en/`」（違 2026-08-13 恆帶地區裁定）；
  「English 恆預設不可移除＋最少 2 語」；渲染期機器翻譯；市場級內容覆寫。
- **與發布模型的邊界**（本輪勘查結論）：兩者**目前零程式碼耦合**。唯一交集是宣告層——
  `status`／`publications`／`variant_publications` 被 `docs/specs/67` §E.3 與
  `config/limits.yml` 的 `readonly_fields_in_non_source_locale` 定義為
  **「全語言共用的可見性、非來源語言唯讀」**。
  🔴 ⇒ **發布模型只要維持「發布是全語言共用的單一值」就不會踩到本保護區；
  一旦引入任何 per-locale 發布概念，就與 67 §E.3 直接衝突。**
  （語言自己的 `shop_locales.published` 是**另一個軸**，作用在路由層 404 與
  `Translations::Resolve` 的 scope，不在商品可見性計算內。）

### D52

**S0 管道身分模型走方案 D（本尊全形），`platform_apps` 建成平台字典表（2026-08-26 使用者裁定）**

- **裁定原文（逐字，兩次選擇）**：
  - 方案選擇：「**D：C 再加 catalogs 一級表（本尊全形）**」
  - `apps` 的形態：「**建 `platform_apps` 平台字典表（忠於本尊）**」
- **背景**：2026-08-14 的 **R13-V2**（`docs/specs/71` §A）逐字寫過「資料模型應是 `App` 之下的
  `Channel`（帶 channel capability），不是兩張平行表」，**至今無人動過**。
  我方把整個「銷售管道」概念壓成 `publications` 一張表的一個字串欄；
  `publications.catalog_id` 自 `20260814200000` 起存在但**無外鍵、無寫入者、恆為 NULL**。
  決策文件列了 C-1～C-13 十三條代價與四個方案（A／B／C／D），我方建議是 **B**；
  使用者選了 **D**（射程最大的那個）。
- **本裁定明文接受的鐵律變更**：`platform_apps` 是**第三類「平台字典表」**（無 `shop_id`），
  依鐵律 2 配套條款③必須同步改三處，本裁定即該變更的授權：
  ① CLAUDE.md 鐵律 2 的平台字典表段（改為逐表列舉）
  ② `docs/specs/71` §A G24 的第三類登記註
  ③ `scripts/check-tenant-isolation.rb` 的 `NON_TENANT_TABLES`
  ⇒ 該 PR 同時落入 **鐵律 18.3**（改 `scripts/` 與規範本文）⇒ **人工合併**。
- **判準是滿足的**：鐵律 2 逐字「表裡**一列都不屬於任何一家店**才算平台字典表」。
  本尊的 `App` 是 App Store 的目錄、全域共用（官方 `App.shopifyDeveloped`／`developerName`
  都是 app 自身屬性，與商店無關）；每店的部分是 `AppInstallation`
  ——後者**帶 `shop_id`、是業務資料**，與 `user_store_assignments` 必須帶 `shop_id` 同一個判斷。
- **落地拆兩個 PR**：
  - **PR A**（#146，已合併，main `2a91b5c`）：`sales_catalogs` ＋ 五能力旗標 ＋ `operation_status`。
    零鐵律變更 ⇒ D40 自合併。
  - **PR B**：`platform_apps` ＋ `app_installations` ＋ `channels` ＋ 上述三處規則變更
    ⇒ 鐵律 18.3 人工合併。
- **本裁定**不**涵蓋的部分**（實作時仍受未取得約束，逐條登記於
  `docs/plans/2026-08-26-S0-管道身分模型-決策文件.md` §7）：安裝管道時平台自動建立什麼（U-2）、
  卸載後 publication 與發布列的去向（U-3）、新增管道後既有商品是否立刻可見（U-4）。
  三條都需要**安裝一個管道 app** 才測得到，而使用者 2026-08-26 已裁定不安裝
  ⇒ `app_installations` 的 `installed_at`／`uninstalled_at` 兩欄是**我方定義的語義**，
  官方 `AppInstallation` 沒有任何時間戳、也沒有卸載狀態欄（取證 2026-08-26）。
  ⚠️ 下一輪 parity **不得**把那兩欄當成「與本尊不一致的缺口」修掉——要改須推翻本條。

  🔴 **2026-08-26 稍晚更正（S1 實測，`docs/research/82` §11.1）**：上一段「官方 `AppInstallation`
  沒有任何時間戳」**本身沒錯**（公開 GraphQL 型別確實沒有），但由它推出的
  「⇒ 兩欄是我方定義的語義」**過窄**。實測 app installation 詳情頁
  （`/settings/sales_channels/app_installations/app/<handle>`）逐字顯示 `Installed July 14`，
  且有 `App history` 時間軸逐字顯示 `App installed by KEN LEE` ＋ 時間
  ⇒ **平台有存安裝時間與帶操作者的事件歷史，只是不在公開 API 面上**。
  ⇒ 正確的分界是：**`installed_at` 與本尊實質對齊**；**卸載的語義**（`uninstalled_at` 代表什麼、
  卸載後發布列去向）才是我方定義的、且仍受 U-3 未取得約束。
  本條的保護射程不變（下一輪 parity 仍不得刪那兩欄），改的是**理由的準確性**。
  同批發現：本尊保留安裝／卸載**歷史**，我方每店每 app 恆一列的設計是**已證實的缺口**
  （登記於 S0 PR B worklog 的 S0B-3），不是假設。

### D53

**排程發布到點的補償語義（ours，2026-08-27 使用者裁定；F1–F5 五格）**

- **裁定原文（逐字）**：「**先把五格定下來，然後做好詳細的handoff，我要交給另外一個claude繼續開發，
  然後給我寫給另外一個claude的指令，讓他接受繼續下去**」
  （2026-08-27。此前的脈絡是執行方回報「S2 §4.F 五格補償語義卡住 PR-C，那節明文
  『送使用者裁定，不得由執行方自定』」，使用者以此句授權把五格定案。）
- **取證與依據全文**＝`docs/plans/2026-08-27-PR-C-五格裁定書.md`
  （七路研究＋對抗複驗；🔴 **該檔 §0.3 列出 20 條被推翻的斷言，一律不得引用**）。
- **背景**：S5（`publishablePublish`／`publishableUnpublish`，main `f86d76b`）已交付排程列的
  outbox 生產者（topic `product.publication.changed`，`available_at` 精確等於 `published_at`），
  消費者屬 PR-C。官方對到點的**補償語義**全面沉默。
  🔴 **本條是 ours 裁定，不是照本尊；也不得反向斷言本尊沒有補償機制**
  （形態同 `docs/specs/91-pit-register.md` §3 第 28 包 staged 保留期先例）。

- 🔴 **2026-08-27 更正（本尊實測；使用者裁定「按照 shopify 的處理方式做」）**：
  本裁定原文有兩處與本尊實際行為牴觸，依使用者指示改為照抄本尊。逐字證據與取證步驟＝
  `docs/dev/m2-publication-scheduling.md` §11（測試店三個商品、逐時點 API 取樣）。
  **原文保留不改**（歷史層），生效判準以本更正為準：
  - **更正一｜到點的 `published_at` 處置**：原文 §3.2 列「不 UPDATE
    `resource_publications.published_at`」。實測本尊採 **consume-and-drop**——
    到點**合格** ⇒ `publishDate` **覆寫成實際發布時間**（實測 `05:58:00 → 05:58:02`，
    晚約 2 秒）；到點**不合格**（DRAFT）⇒ `publishDate` **清成 null**（排程物件消滅，
    列本身不刪）。⇒ 我方改為同樣處置。
  - **更正二｜轉回可購買狀態時補發布**：實測本尊在錯過排程後把 status 改回 Active 存檔，
    **三個通路的 publishDate 同時寫成存檔當下時間**（不是回填錯過的排定時間）——機制是
    「Active ＋ 通路 toggle ON ⇒ 立即發布」，**不是排程補跑**。我方對位：
    `resource_publications` 列存在＝toggle ON、`published_at IS NULL`＝在通路上但未發布
    ⇒ status 轉為 `PURCHASABLE_STATUSES` 時把該類列的 `published_at` 寫成當下。
    ⚠️ 差異：本尊同步發生，我方經 outbox 非同步（延遲上界≈一個 relay 輪詢間隔）。
  - **更正三｜業界術語錨由 Quartz 換成 K8s**（2026-08-27 使用者裁定）：原文 F2 寫
    「業界術語＝Quartz `MISFIRE_INSTRUCTION_DO_NOTHING`」。本輪直取 Quartz 官方文檔複驗，
    該術語的官方逐字射程**只涵蓋兩種情形**——scheduler 關機期間、thread pool 無可用執行緒
    ——**不涵蓋「業務前置條件在到點時不成立」**。而我方架構下事件**永遠準時觸發**
    （`available_at <= now`，relay 必然取件），失敗的是業務條件而非觸發本身
    ⇒ 嚴格說 F1／F2 **兩者都不是 misfire**。
    🔴 **改用 K8s `concurrencyPolicy: Forbid`** 作為術語錨——其官方三句
    （逐字 `skipping next run`／`future occurrences are still scheduled`／只發 **Normal** 級事件）
    與 F1 三句（不執行副作用／不清排程／不報錯但留痕）**逐句同側**。
    ⚠️ 原文「🔴 **不是** Airflow catchup」那半句**仍然成立且不得刪**（R10 的論證未被推翻）。

  - 🔴 **被實測正面證實、維持不變的兩格**：①F1 的判準集合＝`{ACTIVE, UNLISTED}`
    （實測 UNLISTED 商品排程**照常發布**、status 不被改動 ⇒ 不合格集合**只有 DRAFT**）；
    ②F2「不自動補發布」（實測排程值不復活、不回填原排定時間）。
  - ⚠️ **未取得**：`ARCHIVED` 到點行為本輪未測（避免對測試商品做不可逆歸檔）
    ⇒ 我方 fail-closed，與 DRAFT 同處置並登記為 ours。

- **裁定（逐格）**：
  - **F1｜到點時 status 不合格**：到點消費者以 **DB 現值**重新評估——列不存在或 `published_at`
    已改期 ⇒ no-op；`status ∉ Product::PURCHASABLE_STATUSES`（＝{ACTIVE, UNLISTED}）⇒
    **不 bump cache stamp、不改 `published_at`、不刪列、不 raise**；`Collection` 本規則不適用。
    **全部 no-op 分支必須寫一行結構化 log。**
    🔴 判準取 `Product::PURCHASABLE_STATUSES`（可見性軸），**不是** `== ACTIVE`——
    官方逐字 `The product is active but you need a direct link to view it.`（`UNLISTED`，
    <https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductStatus>，取證 2026-08-27）
    ⇒ 寫 `!= ACTIVE` 會讓 UNLISTED 商品「前台已可購買但快取未失效」。
    🔴 S2 建議值寫的是「**不投遞事件**」，本輪改成「**到點消費者不執行副作用**」——
    事件在 S5 建列時就已投出，到點必然被 relay 取出（`available_at <= now`，無上界），
    「不投遞」在我方架構上做不到。
  - **F2｜catch-up**：**不自動補發布**，射程分三層，缺一層就與機制實況矛盾——
    ①**可見性層**不做也不需要做（查詢時判定，改回 ACTIVE 即自然可見）；
    ②**事件補送層**既有 relay 必然補送，本裁定不改變它、不加 max-age 丟棄；
    ③**補發布動作層**不存在也不新增（承接 `docs/dev/m2-resource-publication-semantics.md` §6 的既有禁令）。
    業界術語＝Quartz `MISFIRE_INSTRUCTION_DO_NOTHING`（🔴 **不是** Airflow catchup——
    後者關閉後仍跑最新一格，照字面搬會帶進相反語義）。
    ⚠️ S2 把反直覺點寫成「錯過時點之後前台其實已經可見了」，**在 DRAFT 情境下是錯的**：
    status 層先擋住（`PURCHASABLE_STATUSES` 不含 draft）⇒ 正確表述是
    「**改回 ACTIVE 的那一刻自然可見**」。
  - **F3｜到點事件的失敗重試**：沿用 `Events::Relay` 既有機制（`available_at = now + 2^attempts` 秒，
    序列 2/4/8/16/32/64/128；`events.outbox_dead_letter_attempts` ⇒ `status=dead` ＋ `last_error`）。
    🔴 **不得引用** `catalog_flow.publication_retry_*`——該兩鍵**已存在**（S2 說「不新增」與現況不符）、
    零消費者，且其出處註釋自陳是**反推**，依鐵律 19.3 不得驅動實作。
    🔴 重試期間不得改寫 payload 或 DB 的 `published_at`。
  - **F4｜到點延遲的可接受窗**：**導出 SLO，不落新 limits 鍵**。正常路徑 ≈
    `events.outbox_poll_interval_s`（牆鐘對齊 ⇒ 0–該值均勻分布）＋ worker `polling_interval`
    ＋ drain 時間；含一次退避 ≈ 再加首次退避 2 秒＋一個輪詢間隔。
    🔴 **ours 導出值、非官方 SLA、只在 `production` 成立、是 SLO 不是不變量**。
    🔴 **寫成參數式不寫死數字**（`config/recurring.yml` 與 `events.outbox_poll_interval_s` 是雙寫點）。
    🔴 **不設 max-age 丟棄**：我方事件的唯一載荷是 cache stamp bump，晚到仍正確且冪等。
  - **F5｜不合格時的商家可見回饋**：**不做**，登記 `docs/specs/91-pit-register.md` §3.23 為 ⚪。
    🔴 S2 的原理由（「本尊有、我方尚無」）**整個換掉**——本尊確有，且測試店實測到逐通路的
    三層 channel error UI。正確的三條理由是：①官方唯一把 `ResourceFeedback` 與排程綁在一起的
    句子落在**到點之前的驗證**，不是到點失敗回報；②我方是單體 SaaS、無管道 app 身分 ⇒ 缺 producer；
    ③我方無三個排程生命週期事件 ⇒ 缺前置觸發點，做出來只能退化成本尊沒有的事後回報形態。
    🔴 **可觀測性不隨之取消**：消費者每次 no-op 必寫結構化 log（營運可見，不是商家可見）。

- **理由**（逐格一句）：
  1. F1 取可見性軸：到點事件的唯一載荷是 cache stamp（可見性設施），不是發布動作。
  2. F2 不補發布：可見性是查詢時判定，沒有「發布動作」可補；補發布會製造第二個事實來源（鐵律 7）
     並抹掉商家設定的排程時刻。
  3. F3 沿用：本尊平台層對所有 topic 用同一份重試政策，無 per-topic 參數；我方 outbox 四件事已備。
  4. F4 不落鍵：倉庫已有多個零消費者死鍵；且該值是雙寫點，硬編會靜默失真。
  5. F5 不做：缺 producer 與前置觸發點，做出來只能是空掛件或自創形態。

- **🔴 這是與本尊的刻意差異（ours），不是照抄**：
  - 重試放棄語義：本尊是**刪訂閱＋寄警告信**，我方是 dead-letter。
  - 排程列去留：本尊行為**未取得**，我方選「不清除」。
  - 發布計數：本尊有 `availablePublicationsCount`（排除 feedback error）與
    `resourcePublicationsCount` 兩個數，我方無 feedback 維度 ⇒ 單一計數（已登記 `91` §3.23）。

- **程序口徑（本條順帶定死，結掉 S2 規格草案 §5-C 的 C-7）**：
  🔴 **改 `config/limits.yml` 不落鐵律 18.3**。判準寫在 `scripts/check-limits-keys.rb` 內
  （規則＝「每一層 mapping 的鍵都必須解析成 String」），`config/limits.yml` 是它**被檢查的輸入**
  ——與 `app/` 的 Ruby 檔被 rubocop 檢查同構，改它不可能讓 CI 由被改的檔自己定義。
  複驗：`grep -n "limits" .github/workflows/ci.yml`（只有兩個 `run: ruby scripts/...`）與
  `grep -n "limits" config/ci.rb`（同）。
  ⚠️ `app/services/publications/write.rb` 內 S5 寫的「不改 `config/limits.yml`（判準面，鐵律 18.3）」
  **是錯的口徑**，已於本批同步更正。

### D54. 視覺 1:1：token 表換成本尊量測值，推翻「色值改用自有調色」（2026-08-28 使用者裁定）

- **裁定原文**：「整體 ui 你必須和 shopify 完全 1：1，完全跟隨他的 css」。
  隨後於選項中明選「**改裁定：token 表換成本尊量測值**」。
- **推翻了什麼**：`docs/design/47` §6 逐字「只採用『中性階的層級關係』…**色值改用 CHILL LOVE
  自有調色**。層級關係是資訊設計事實，色值是品牌資產」；同檔 §H2-1「只取結構與關係，
  **不引用其色值**」；§8 第 89 條「中性色只取層級關係，色值用自有調色」；
  以及 `docs/research/80` §5 表尾「只做映射…**不得取用本尊色值**」。**四處一併作廢。**
- **新處置**：**視覺結果對到 1:1，實作仍走我方 token**（鐵律 8 不變——CSS 由我方撰寫，
  不複製 Shopify 樣式表原始碼，鐵律 9 的法律紅線不動）。換的是 token 的**值**，不是機制。
- **射程與邊界**：
  ① **多語言面不在射程**（2026-08-28 同日裁定）：「shopify 本尊是沒有多語言欄位，參考的是
     shopline」⇒ `LocalizedField`／`SettingsLanguagesPage`／`TranslationCsvCard` 三面對標
     SHOPLINE（`docs/research/109`），不納入本尊量測。
  ② **有量測值才換**：未取得的維持現值並登記，不得用推導公式補（鐵律 19.3）。
     逐項差異與可換／不可換的邊界＝`docs/design/110` §7。
  ③ **本尊有兩套設計系統世代並存**（`docs/design/111` §17.1），同名元件在兩層值不同。
     **我方只取新層**（`s-*` web component），不照抄兩套。
  ④ **本尊自身的不一致不照抄**（同一 popover 兩種邊框實作、focus 環只在表單控件、
     hover 比 selected 深且 token 名與用途對調）——我方統一，逐條登記於 `111` §17。
- **待辦（不在本裁定的落地包內）**：
  - `CLAUDE.md` 開頭「視覺用自有設計語言」一句需改寫 ⇒ **命中鐵律 18.3，另開 PR**。
  - `docs/design/23` §1 我方 token 表與 `app/assets/tokens.css` 的換值 ⇒ 另一個工作包。
  - `47` §6／§H2-1／§8-89 與 `80` §5 表尾的原文**保留**（文檔分層：不抹除歷史），
    由 `110` §2 逐條登記其被推翻，並在各處加註指向本條。
- **為什麼不是「照抄 Shopify」**：鐵律 9 禁的是**複製其樣式表原始碼、圖片、文案、商標**；
  量測值（computed style 的數值）是**觀察到的事實**，記錄與對標一直是鐵律 12.3 層④的要求。
  本裁定改變的只是「量到之後要不要採用」，不是「可不可以量」。

### D55. 照用 Polaris（授權風險轉交專責團隊）＋ 欄寬換成本尊 s-grid 常數（2026-08-28 使用者裁定）

**兩件事同日裁定，合併一條記錄，因為第二件是第一件解鎖後才做成的。**

#### ① 使用者裁定：照用 Polaris，版權問題由另一團隊處理

使用者原文：「你給我照用 polaris。版權問題我另外有額外的團隊會解決」。

**在此之前已向使用者完整攤開的四條事實**（取證 2026-08-28，全文＝該輪對話與
`docs/dev/external-facts.md`；本條只記結論與出處）：

| # | 事實 | 出處 |
|---|---|---|
| 1 | Polaris 的 `LICENSE.md` 是 **MIT 加一條 Shopify 自訂用途限制**，逐字含「dissimilar and visually distinct from Shopify products and services (**including the internal administration page of a Shopify merchant store**), as determined by Shopify in its sole discretion」 | `raw.githubusercontent.com/Shopify/polaris/main/LICENSE.md` |
| 2 | 該限制屬 **field-of-endeavor**，不符 OSI Open Source Definition **第 6 條**（「The license must not restrict anyone from making use of the program in a specific field of endeavor.」）⇒ **source-available，非 open source** | `opensource.org/osd` |
| 3 | npm metadata 的 `license` 欄是 **`"SEE LICENSE IN LICENSE.md"`**，**不是 `"MIT"`** | `registry.npmjs.org/@shopify/polaris/latest` |
| 4 | GitHub 授權偵測器回 `key:"other"`／`name:"Other"`／`spdx_id:"NOASSERTION"` | `api.github.com/repos/Shopify/polaris` |

🔴 **鐵律 9 的文本射程（精確，不是放寬）**：對 Polaris 只寫「**不用**」「**不抄**」，
**沒有「禁讀」**——「禁讀」只寫給 GPLv3（2026-08-18 增補款）。
⇒ **為研究而讀 Polaris 源碼本來就不在鐵律 9 的射程內**，本裁定沒有改變鐵律 9，
先前把它當「禁讀」處理是執行方自己加嚴的。

**仍然違反鐵律 9、本裁定未放行的兩件事**：
- 安裝 `@shopify/polaris` 當依賴（違「不用」，另撞鐵律 1）
- 把其 CSS 複製進我方倉庫（違「不抄」）

要放行那兩件，依驗收基準「🔴 不適用②，**要放行先改鐵律本文**」，須先開 18.3 PR 改 `CLAUDE.md`。

**產出約束（本裁定下仍然成立）**：讀源碼取得的是**事實與結構對照**
（「X token = green ramp 第 12 階」），**不得大段複製其原始碼進倉庫**。

#### ② 欄寬：換成本尊新層 s-grid 的常數

**推翻** `docs/design/111` §16.1 的「本尊內容區沒有 max-width，內容欄是流體寬度」——
那是**量錯層**：`main.page` 的 `max-width: none` 是真的，但上限在再下一層 shadow root 的
`<s-grid>` → `<span class="grid">`，由元素屬性生成 per-instance `<style>`。

| 項 | 舊層（polaris-react，已封存） | 新層（s-grid，實測） | 我方（本裁定前 → 後） |
|---|---|---|---|
| 主欄上限 | 662（`41.375rem`） | **638** | 633 → **638** |
| 主欄下限 | 480 | **480**（相同） | **無** → **480** |
| 次欄上限 | 320（`20rem`） | **312** | 317 → **312** |
| 次欄下限 | 240 | **240**（相同） | **無** → **240** |
| 內容合計 | 998 = 662+320+16 | **966** = 638+312+16 | — → `--col-content:966` |
| 外框 | `.Polaris-Page` 998 | 966 + 2×16 = **998** | 998／1030 兩個打架 → **998** |
| 列表頁上限 | — | **無**（`max(100%)`） | 1200 → **none** |

🔴 **總寬沒變**：`633 + 16 + 317 = 966 = 638 + 16 + 312`。只是內部分配各挪 5px。
🔴 **降幅不同**（−24 / −8）⇒ 新層不是統一縮放舊層，是各自重訂。

**四項配套**：
1. `.cl-page` 水平內距 **32 → 16**（本尊 `main.page` 是 `padding:16px 0`，16/側加在其內的 grid 上）。
   改完 `.cl-page--detail` 的 998 才第一次是對的（966+32）；
   `.cl-product-detail` 的 1030 是為補償雙倍內距而存在的第二個上限，**同批刪除**。
2. **收合門檻改容器查詢** `@container cl-page (width < 752px)`（本尊 `784` 的 border-box
   扣掉 band 的 16/側內距）。🔴 **門檻值刻意不做成 token**——`@container` 條件不能用 `var()`，
   Chrome 151 實測會**解析成功但永遠不匹配**（fail-open）。本尊自己也踩同一條限制：
   `--p-breakpoints-*` 五顆全站零消費。
3. **列表頁上限改 `none`** ——本包唯一真正改變產品形態的一項（寬螢幕下列表變滿版）。
   量測支持；若日後要恢復，須走 `docs/specs/71` §A 保護清單登記。
4. **順帶封閉一個既有缺陷**：`VariantDetailPage` 的 `<aside>` 放在第一個子節點，
   卻套主欄先的 `.cl-od-grid`（且無 `.cl-vd-grid`、無 `order:` 覆寫）⇒ **兩欄左右顛倒**。
   原型早有反向 template 的 `.vd-grid`，React 端一直沒有對應 class。
   新增 `.cl-vd-grid` 並改用之。屬本包所改的同一張 grid，依鐵律 17.2 一併封閉。

**未取得**：`s-page` 的 `inlinesize` 三個值各自對應的寬度（官方文檔無數字）；
`s-internal-page` 與公開 `s-page` 是否同一（**無任何證據，不得互推**）；
Firefox／Safari 的容器查詢行為（只在 Chrome 151 量過）。

### D56. 決定 A：語義色換成本尊值，並補上兩個缺失的槽位（2026-08-28）

D54「視覺 1:1」的第二個落地包（第一個＝D55 欄寬）。

#### 根因不是色值，是**槽位缺失導致的模型塌縮**

我方每族只有 surface／fill／border／icon／text 五槽，**沒有「填色上的前景色」這個槽**
⇒ 消費端只能硬編白字（原型 `.b-fill-*` 五處 `color: var(--text-inverse)`）
⇒ fill 被反推成**必須夠深才能配白字**
⇒ 產生器把每個色相壓暗到白字剛好過 4.5:1 就停
⇒ **五族 fill 亮度全擠在 0.166–0.177（跨度 0.010）**，而本尊是 0.125–0.779（跨度 0.654，**65 倍**）。

代價是 warning／caution／info 的**色相身分被毀**：亮琥珀 `#ffb800` → 深褐 `#af5c1d`、
亮黃 `#ffe600` → 深橄欖 `#847115`、淺天藍 `#91d0ff` → 深藍 `#1e78b8`。

#### 本尊的規則：兩個彼此獨立的配色系統，元件只綁一個

| 系統 | 層 | 規則 |
|---|---|---|
| **① 淺層** | `surface`／`fill-secondary`／`border`／`icon`／`text` | 一律「同族深字配同族淺底」。text 在 surface 上 CR **8.09–10.77** |
| **② 填色** | `fill` ＋ `on-fill` | **成對定義、成對消費**。前景依 WCAG 黑白對比交叉點 **L≈0.17913** 翻面 |

**fill 的明度逐族不同不是失誤**——黃色只有在亮處才是黃色。
**每一組的相反模型都失敗**：淺 fill 配白字 1.73／1.27／1.66；深 fill 配深字 2.51／2.20。

#### 處置

| 類 | 顆數 | 動作 |
|---|---:|---|
| 有本尊對應、值不同 | **52** | 逐格採用本尊 live computed 值 |
| **本尊無此槽 ＋ 零消費** | **25** | **刪除** |
| **本尊有、我方缺** | **10** | 新增 `-fill-secondary`／`-on-fill` × 5 族 |

⇒ 77 − 25 + 10 = **62 顆**。另改原型 `.b-fill-*` 五處：`--text-inverse` → `--sem-{族}-on-fill`。

**刪除的 25 顆**：5 族 × `border-hover`／`border-active`／`icon-hover`／`icon-active`（20）、
`caution-text-hover`／`-active`、`info-text-active`（3）、
`critical-button-fill`／`-button-gradient-fill`（2）。

- 本尊只有 **`highlight`** 族有 icon／border 的 hover／active，其餘六族該格全空。
- **按鈕那兩顆**：本尊 primary destructive ＝ `bg-fill-critical` ＋ `text-critical-on-bg-fill`
  （⇒ 我方 `--sem-critical-fill` ＋ `--sem-critical-on-fill`，已存在）；
  secondary destructive ＝ `button-bg-fill-critical` **`#fff`** ＋ `text-critical`。
  我方原本那兩顆（紅底 `#c11f35` ＋漸層）是**相反模型**且零消費 ⇒ 不保留。

#### 🔴 照實複製本尊自己的三處不一致（修正它就不是 1:1）

1. **`info-text-hover` 與 `info-text` 同值** `#003a5a` ⇒ info 語氣連結 hover 無顏色變化。
   七族中唯一相等者；已實測被 `s-text`／`s-paragraph`／`s-internal-text`／`s-internal-paragraph`／
   `s-internal-number` 五個 shadow adopted sheet 綁為 `--s-link-color-hover`。
2. **`border-caution` 與 `fill-secondary-caution` 同值** `#ffeb78` ⇒ 兩者同時用邊框隱形。
   **本尊實際不會發生**（11169 條規則掃描，同時消費這兩顆的規則交集為空），但我方若同時用就會。
3. **`icon` 在同族 surface 上只有 2.49–5.48**，五族在 WCAG 1.4.11 的 3:1 線上下擦邊
   ⇒ **icon 不得作為承載語義的唯一線索**，必須伴隨文字。

#### 明確不跟的一項

本尊 **avatar 族有 4 組配對不過 AA**（`avatar` 2.05／`five` 3.00／`seven` 3.18／`one` 4.11，
源碼與 live 量測逐一相同、互為交叉驗證）。判準：226 個 token 有 187 個帶 `description`，
**16 個 avatar token 一個都沒有**；`light-high-contrast-experimental` 主題覆寫 8 個 token、
**沒有一個是 avatar** ⇒ 本尊沒把它當待修問題。**我方不跟。**

#### 未取得（照實留空，不用公式補）

`caution` 的 `text-hover`／`text-active`、`info` 的 `text-active`——本尊 `:root` 上沒有這三顆。
`.p-partial-theme-admin-next`（把 7 族 fill 全改成淺彩）**目前零元素在用**，只登記不實作。

### D57. 決定 C（包 C-1）：字體系統改成三層，字重全部回到本尊值域（2026-08-28）

D54「視覺 1:1」的第三個落地包（前兩個＝D55 欄寬、D56 語義色）。

#### 為什麼要分層——不是整潔問題，是**舊結構表達不了實測**

本尊在 **12px 這一個字級上同時有三種字重**：表格儲存格 **450**、欄位標題鈕／badge／
按鈕標籤 **550**、`heading-small` **600**。13px 上同樣有 450／550／600
（側欄二級／一級／卡片標題）。

我方 `--t-xs ↔ --fw-xs` 的一對一配對只能表達其中一種。**而我方自己的程式碼早就在違反它**：
`--t-xs` 被消費 **265** 處、`--fw-xs` 只有 **1** 處、`--fw-sm` **0** 處
⇒ **配對只活在註釋裡**。這正是 G12b 量到「一格塞兩個值」的成因。

#### 🔴 而且不能靠改 size token 的值來對齊

| size token | 消費 | 它同時服務的用途 |
|---|---:|---|
| `--t-lg`（16px） | 13 | SERP 模擬標題（**模仿 Google，不是 admin 元素**）／modal 標題／setup 卡 h4／帳目數字／統計數字／logo 預覽 |
| `--t-2xl`（20px） | 7 | h1 頁面標題／圖表大數字／方案價格／統計值 |

本尊卡片標題是 **13px**、頁面標題是 **18px**——但把 `--t-lg` 改成 13 會**一起縮掉 SERP 模擬**，
而那個 16px 本來就是對的（它模仿的是 Google 的搜尋結果標題，不是 Shopify）。
⇒ **必須由元件指到「角色」，不是指到「尺寸」。**

#### 三層結構

| 層 | 內容 | 本包狀態 |
|---|---|---|
| **L1 原語** | 字級 13 階（`--t-275`…`--t-1000`）／行高 8 階（`--lh-300`…`--lh-1200`，**獨立編號、不與字級對齊**）／字重 4 抽象階（450/550/600/650）／字距 4 抽象階 | ✅ 新增 |
| **L2 角色階** | **16 個**，與本尊 1:1。**軸集也 1:1——沒有的軸就不建 token** | ✅ 新增 |
| **L3 過渡階** | 舊的 `--t-{2xs..3xl}`，265+ 消費點 | 值指回 L1；逐元件遷移到 L2 ＝ 包 C-2 |

**L2 的四種形狀**（本尊如此）：unary（只 size）2 個｜size+lh+ls（**無 weight**）4 個｜
size+lh+weight（**無 ls**）4 個｜四軸齊 6 個。

#### 修掉的四個值域外字重

本尊字重域**只有 450／550／600／650**（非整百，可變字重軸）。

| token | 前 | 後 | 消費 | 依據 |
|---|---|---|---:|---|
| `--fw-control` | **500** | **550** | **14** | 本尊 `.button{font-weight:var(--p-font-weight-button-label,550)}`，且枚舉全部 `.button*` 字型規則**只有這一條**、無 variant 覆蓋 |
| `--fw-md` | **500** | **550** | 3 | 消費者＝變體表 `thead th`／`tbody th`／刪檔警告；本尊 `.Polaris-Table-TableHeadingCell` = 550 |
| `--fw-xs` | **500** | **550** | 1 | 唯一消費者＝`.idx th`（表格欄位標題），同上 |
| `--fw-xl` | **500** | **600** | 1 | 唯一消費者＝原型 `.modal-head`；本尊 modal 標題走 `display-small` = 600 |

**複驗**：25 顆字重 token 解析後**全部落在 {450,550,600,650}，值域外 0 顆**（換值前 4 顆）。
字級 13 個值全中。行高只有 `--lh-2xs: 14px` 在域外——**我方自有值**（11px 微標籤，47 未量到），
本尊行高階沒有 14，**保留並標明，不硬套最接近的 12 或 16**。

#### 兩件實作時會撞到的反直覺事實

1. **本尊的 size class 也發字重，而且是 reset 不是繼承**——`.Polaris-Text--bodyXs/Sm/Md/Lg`
   四個 class 都顯式宣告 `font-weight: var(--p-font-weight-regular)`（抽象 token，不是 body 語義
   token，因為 `--p-font-weight-body-*` **不存在**）。live control 證實：父層 750 → bodyMd 子元素 450。
   ⇒ 我方元件用 `body-*` 角色時**必須同時寫 `--fw-regular`**，否則放進粗體容器會被繼承污染。
2. **字重 class 靠 source order 恆勝**，與 class 屬性書寫順序無關
   （本尊同一份 sheet：尺寸 class 索引 70–80、字重 class 81–84；兩種書寫順序實測同值）。

#### 未取得／不跟

- **6 個角色只被新 `s-*` 元件消費**（`button-label`／`details-text`／`input-label(-small)`／
  `avatar-initials(-long)`），舊 Polaris CSS 一次都沒用過 ⇒ 只看 `.Polaris-Text--*` 只會看到 10 個。
- **字體 token 不隨 dark provider 變**（實測 diff = 0）⇒ 本決定不受 theme-scope 污染影響。
  只有 `.p-partial-theme-admin-next` 會整組改寫（字重域變 400/500/600/600、body/heading 全加負字距），
  而該 scope **零元素在用**。
- `--lh-2xs: 14px`：本尊無此行高，我方保留（見上）。

### D58. 決定 C（包 C-2）：元件層遷移到角色階（2026-08-28）

D57 建好角色階之後，**真正改變畫面**的那一步。射程＝逐元件量本尊對應物，指到對的角色。

依據＝**66 列逐元件實測對應表**（49 要改／8 無對應-維持現值／6 未取得／3 已對應），
三族各經兩面對抗性反駁，**主結論全部成立**，三面反駁各抓到一個真問題（見下「反駁抓到的三件事」）。

#### 主要視覺變更

| 元件 | 我方（前） | 本尊實測 | 改成 |
|---|---|---|---|
| `.cl-page__header h1` | 20px / **1.45（無單位＝29px）** / **700** | **18 / 24 / 600 / dense** | display-sm |
| `.cl-detail-head h1` | 20 / 24 / **450** | 同上（🔴 **索引與詳情同值**，`has-breadcrumbs` 只改版面） | display-sm |
| `.cl-modal__title` | **16** / 20 / 600 | **13 / 20 / 600**（新層 17 個實例） | heading-md |
| `.cl-button` | **13px / 1（無單位）/ 600** | **12 / 16 / 550**（新層 19 顆全同值，跨全部 variant） | button-label |
| `.cl-button--small` | 另設 12px | 本尊 size-base 與 size-large **字型軸完全相同** | **刪掉字級覆蓋**，只留幾何 |
| `.cl-badge` | 12 / **500** | **12 / 16 / 550**（products 51 + orders 25 全同值） | body-sm ＋ `--fw-medium` |
| `.cl-index-table th` | **12 / 600** | **12 / 16 / 550** | body-sm ＋ `--fw-medium` |
| `.cl-field__label` | **600** | **13 / 20 / 450**（新舊兩層 8 個實例） | input-label |
| `.cl-nav-item` | 13 / **500** | 13 / 20 / **550** | body-md ＋ `--fw-medium` |
| `.cl-nav-sub` | 13 / 繼承 | 13 / 20 / **450** | body-md ＋ `--fw-regular`（顯式） |
| `.cl-store-chip__avatar` | **11px / 700** | **16 / 20 / 450** | avatar-initials ＋ `--fw-regular` |
| `.cl-empty-state h2` | 14 / 1.45 / **700（UA 粗體）** | **14 / 20 / 600** | heading-lg |
| `.cl-serp__title` | 16 / **1.3（無單位）** | **18 / 24 / 450 / dense** | display-sm 三軸 ＋ `--fw-regular` |

🔴 **`.cl-serp__*` 原本被我判成「Google 模擬、不該動」——那是錯的。**
本尊商品編輯頁就有「Search engine listing」預覽，版式與我方 1:1（站名／URL／藍標題／描述／價格），
逐項實測：標題 18/24/450/dense、站名 14/20/450、URL 12/16/450、描述與價格 13/20/450。

#### 🔴 反駁抓到的三件事（都不是細節）

1. **漏掉 5 個完全沒有 CSS 規則的 `<h3>`**（`SettingsLanguagesPage` ×3、`TranslationCsvCard`、
   `CollectionDetailPage` 的 notFound 態）。它們在 `<Card padded>` 內但祖鏈上沒有
   `.cl-product-detail`，**沒有任何規則命中** ⇒ 吃 Chrome UA 的 `h3{font-size:1.17em;font-weight:bold}`
   ＋ body 的 `line-height:1.5`，在 `html{font-size:13px}` 下算出 **15.21px / 22.815px / 700**
   ——**三軸同時落在兩邊值域外**，比清單裡任何一列都嚴重。
   ⇒ 選擇器 `.cl-product-detail .cl-card h3` **放寬為 `.cl-card h3`**。
   本尊有對應：Settings → Languages 卡標題 `h2.Polaris-Text--headingSm` = 13/20/600。

2. **`.cl-product-title` 存在**（`admin.css:728`，`font-weight: 500`，4 個呼叫點：
   ProductsPage／InventoryPage／CollectionsPage／FilesPage）。對應表原本寫「我方無專用 class」。
   本尊：`<a>` 本身 12/16/450，**真正繪製文字的 span 是 12/16/550**
   ——「rect 相同不代表同一節點」的典型。⇒ 一行：`500 → var(--fw-medium)`。

3. 🔴 **日曆的 today 與 selected 字重綁反了**。本尊 `s-date-picker`：
   `.is-today` **只有一個 box-shadow 環、字重仍 450**；`.selected` 才是 **600**。
   實測 `button.day-button.is-today`（8/28）= 13/20/450 且有 box-shadow；
   `…selected`（8/27）= 13/20/600；57 顆普通日 13/20/450。
   我方剛好相反（`--today` 加粗、`--on` 完全不設字重）⇒ 兩者對調。

#### 🔴 更正 D57 的一句話

D57 的 `--fw-xl` 註釋寫「本尊 modal 標題走 `display-small` = 600」——**那是錯的**。
逐頁實測 20 個 modal 標題（新層 17／舊層 3），**沒有一個是 18px**：
新層 `s-internal-modal` 的 `h2.heading` = **13/20/600**（heading-md）、舊層 = 14/20/600；
`size="large"` 只改寬度不改字型。字重 600 的結論仍成立（兩者皆 600），**錯的是「哪一階」**。

#### 原型端的兩件系統性問題

1. **`body` 帶 `letter-spacing: .01em`**，多處元素繼承而未 reset。本尊 body 是 `normal`。
   ⇒ 改成 `var(--ls-normal)`。
2. **兩個元件的字級無對應階，照實登記不硬套**：
   - `.setup-card h4` 的 **16px/20px** 在 L2 十六階裡不存在（16px 只有 `avatar-initials`，unary 無 lh/fw 軸）
     ⇒ 從 L1 組，並標明是**我方自有組合**。
   - `.hero-hello h2`：本尊對應物量到 **26px**，而 26 **不在本尊自己的 13 階字級表裡**
     ⇒ 字級維持 24，只對齊有證據的三軸（lh 32、fw 550、ls denser）。

#### 量化

| | 前 | 後 |
|---|---:|---:|
| `admin.css` 硬編 `font-weight` | 18 | **5**（域外 3） |
| `admin.css` 硬編 `font-size` px | 22 | **8** |
| `admin.css` 消費角色階 `--type-*` | 0 | **116** |

原型仍有 93 處硬編字重（32 域外）、11 處硬編字級、26 處無單位行高 ⇒ **包 C-3**。

### D59. 中性階換成本尊值，並拆開一顆服務多角色的 token（2026-08-28）

D54 的第五個落地包。這是「整體 UI 不協調」三層診斷裡**最後一層**，也是影響面最大的一包
（**591 個消費點**）。

#### 換值前的指紋：我方中性階帶藍色偏，本尊一律純灰

| 項 | 我方（前） | 飽和 | 本尊 | 飽和 |
|---|---|---:|---|---:|
| `--text` | `#1a1c1e` | **13.3%** | `#303030` | 0.0% |
| `--surface-inverse` | `#1a1b1d` | **10.3%** | `#1a1a1a` | 0.0% |
| `--text-3` | `#67696e` | 6.4% | `#616161` | 0.0% |
| `--text-2` | `#6b6d71` | 5.3% | `#616161` | 0.0% |
| `--border-strong` | `#c9cace` | 2.4% | `#ccc` | 0.0% |
| `--border` / `--border-2` | `#e3e3e6` / `#ececef` | 1.3% | `#e3e3e3` / `#ebebeb` | 0.0% |

**換值後我方中性階的飽和度最大值 ＝ 0.0%。**

主文字對白底的對比也從 **17.09** 降到 **13.20**（＝本尊值）——我方原本的字更黑更硬。
次文字反而從 5.18 升到 **6.19**。

#### 兩項計畫表漏掉的

`docs/design/112` §2.1 列了 16 項，但系統性掃描整個中性區塊後另外找到兩顆：

- **`--link`**：`#2a5bd7` → **`#005bd3`**（本尊 `text-link`，111 §14.8）。
  與 `--focus` 同值不是巧合——本尊兩者都是 `#005bd3`。
- **`--text-inverse`**：`#fff` → **`#e3e3e3`**，並**拆成兩顆**（見下）。

#### 🔴 `--text-inverse` 一顆服務三種角色（與 `--t-lg` 同型）

本尊有**兩顆不同的 token**，我方只有一顆：

| 角色 | 本尊 token | 值 | 我方（前） |
|---|---|---|---|
| 深色**中性面板**上的字（toast／tooltip／savebar／bulkbar／doc-pop） | `text-inverse` | **`#e3e3e3`** | `#fff` |
| **brand 填色**上的字（primary 按鈕、chip、選中段） | `text-brand-on-bg-fill` | **`#fff`** | `#fff` |
| **critical 填色**上的字 | `text-critical-on-bg-fill` | **`#fffafb`** | `#fff` |

⇒ 拆成 `--text-inverse: #e3e3e3`（深中性面板，12 個消費點）
＋ **`--text-on-brand: #fff`**（飽和填色，10 個消費點）；
`.btn-danger` 改指 D56 已建的 `--sem-critical-on-fill`。

複驗：`--text-inverse` 的 12 個消費點**全部在 `--surface-inverse` 或近黑 rgba 上**，
非深中性面板的殘留 **0**。對比：`#e3e3e3` 於 `#1a1a1a` = 13.56（本尊配對）、
`#fff` 於 `#303030` = 13.20（本尊配對）。

#### 視覺變化最大的一項

**`--surface-selected`：品牌藍 `#f0f5ff` → 中性 `#f1f1f1`。本尊的選取態不用品牌色。**
表格選取列會從藍變灰。

⚠️ `--surface-hover` 與 `--surface-selected` 在本尊是**兩個不同來源**
（`nav-bg-surface-hover` 與 `bg-surface-selected`）**但恰好同值** `#f1f1f1`——同值不代表同源。

⚠️ **設定區導覽的 hover／selected 是對調的**（`81` §8.4 實測：selected `#f3f3f3`、hover `#f1f1f1`，
即 hover 比 selected 深）⇒ **換值後必須逐畫面複驗，不能只信 token 名。**

#### 一項不改的「AA 失敗」

`--text-disabled: #b5b5b5` 於白卡對比 **2.05**。那是**本尊自己的值**（111 §14.8），
且 WCAG 1.4.3 明文豁免停用控件（"inactive user interface component… no contrast requirement"）。
**照抄，不修正。**

#### `--scrim` 的來源更正

原值 `rgba(0,0,0,.5)` 出自 `82` §16.2，但那量的是**舊 Polaris React modal**；
新層遮罩是 **`#000000b5`**（≈71% 黑）。兩層各有自己的遮罩色（111 §17.1）。

### D60. 決定 C 包 C-2b：原型端補齊角色階遷移 ＋ **第一次真正的三寬度實測**（2026-08-28）

#### ① C-2 只遷移了 `admin.css`，原型端 13 個元件被留下

D58（C-2）改了 `admin.css` **39 條**規則與原型的**標題族 7 條**，
但原型的**控件／表格／導航**整批沒跟 ⇒ **設計端與實作端對 13 個元件互相矛盾**。

**這個缺口是 live 量測抓到的，靜態分析沒抓到**：在 1280 量 `.btn` 得到 **13/20/550**，
而 `admin.css` 的 `.cl-button` 已經是 12/16/550。

補齊 12 條（`.btn`／`.btn-sm`／`.badge`／`.nav-group`／`.nav-item`／`.nav-sub`／`.pill`／
`.input`／`.idx th`／`.toast`／`.serp .s-t`／`.avatar`），全部用「錨定字串 ＋ 斷言唯一 ＋
**全部驗證通過才動手**」的原子寫法（D59 那個偏移漂移 bug 的固定處理）。

#### ② 🔴 第一次真正的三寬度實測（鐵律 13.1）

**先前登記的「1280 不可得」原因是錯的。**

| | 先前的解釋 | 本輪實測 |
|---|---|---|
| `screenX` | −32000（視窗離屏、渲染面凍結） | **0**（視窗在螢幕上） |
| `resize_window` 回報 | 「Successfully resized」 | **一樣回報成功** |
| `innerWidth` | 不變 | **一樣不變（2560）** |

⇒ **不是離屏造成的，是 `resize_window` 本身就不生效。** 原歸因作廢。

✅ **可行的做法＝同源 iframe**：把原型載進指定寬度的 iframe，
media query 與 container query 在 iframe 內都按 **iframe 寬度**求值。
🔴 **必須用本地 Chrome**（使用者 2026-08-28 明示：所有實測不得用內嵌瀏覽器）
——內嵌瀏覽器的行動模擬會扭曲值：`html` 回報 14px（**掃遍樣式表沒有任何規則設它**）、
`devicePixelRatio` 回報 2.0000000596、`innerWidth` 與 `clientWidth` 差 4px。

**結果**（污染源已停用，量畢複驗還原）：

| | 1280 | 768 | 390 |
|---|---|---|---|
| **溢出元素** | **0** | **0** | **0** |
| **橫向捲動** | 無 | 無 | 無 |
| `h1` | 18/24/600/−0.14994 | 18/24/600/−0.14994 | 🔴 **17.94**/24/600/−0.14944 |
| `.card h3` | 13/20/600 | 13/20/600 | 13/20/600 |
| `.btn`／`.badge`／`.idx th`／`.nav-group` | 12/16/550 | 12/16/550 | 12/16/550 |
| `.avatar` | 16/20/450 | 16/20/450 | 16/20/450 |
| `html` | 13px | 13px | 14px |
| 側欄 | 240 | 272 | 272 |

**1280 逐項與本尊實測值相符**（h1 18/24/600/dense、卡標題 13/20/600、按鈕與 badge 與表頭
12/16/550、頭像 16/20/450、側欄 240）。

#### ③ 三寬度驗證抓到的唯一分歧

390 的 `h1` 是 **17.94** 不是 18，`html` 是 14 不是 13。成因是**既有規則**：

```
@media (max-width:47.9975em){ html{font-size:var(--t-md)} }        /* 13 → 14 */
@media (max-width:47.9975em){ h1{font-size:clamp(17px,4.6vw,20px)} }  /* 390×4.6vw = 17.94 */
```

決定性證據：同一個 iframe 內，字面 `18px`、`var(--type-display-sm-size)`、
inline 強制 18px **三個探針全部渲染成 18px** ⇒ token 解析正確，是那條 clamp 蓋過角色階。

🔴 **這條規則對不對＝未取得。** 本尊確實有 mobile 覆蓋機制
（`--p-when-mobile`，閘門是 `@media (pointer: coarse) and (max-width: 47.9975em)`，
**比我方多一個 `pointer: coarse` 條件**），但**本尊的 `display-small` 在該閘門下是否縮小、縮到多少，本輪未取得**。
⇒ **本輪不動那條 clamp**，登記 `91` §3.36。

#### ④ 順帶記錄兩個工具陷阱

- **MCP 回傳的鍵名含 `token` 會被安全過濾器吞成 `[BLOCKED: Sensitive key]`**，
  且**不報錯**——很容易誤以為量到空值。改鍵名即可（本輪把 `tokenT450` 改成 `v450`）。
- `resize_window` 在本地 Chrome **回報成功但不生效**（見 ②）。

### D61. 刪除視口相對字級，響應式字體對齊本尊（2026-08-28）

D54 的第七個落地包。射程＝原型裡**兩條**用視口相對單位（`vw`）做字級的規則。

#### ① `h1` 的 `clamp(17px,4.6vw,20px)` — **刪除**

**本尊的頁面標題沒有 mobile 覆蓋。** 全表只有 **29 條** `*-when-mobile-p1s0`
（25 字型 ＋ 4 圓角），**`display-small` 與所有 `font-weight` 一條都沒有**。
六個頁面實測（Products／Orders 列表／Orders 詳情／Discounts／Metaobjects／Themes）
在非 toolbar 頁首形態下一律 **18/24/600/dense**。

⚠️ **射程限定（對抗性反駁的更正）**：原研究宣稱「本尊頁面標題在**任何**寬度、
**任何**指標型別下都是死的 18px」——那是**全稱句，證據是狀態相依的單點取樣**。
反駁方用消融證明 `s-internal-page` 的 shadow sheet 對 `.heading` **有 3 條規則**，
其中 `.toolbar .heading` 走 **body-medium**，而 body-medium **有** mobile 覆蓋（13→16）。
加 `toolbar` class 後 h1 變 13px、強制開閘門後變 16px。
⇒ 正確表述＝「**在目前實測到的所有非 toolbar 頁首形態下**恆 18px」。
我方 h1 是一般頁首形態，不適用 toolbar 那一支。

**刪除為何安全**（逐項驗證）：
- `line-height` 半條本來就是 **no-op**：`--lh-2xl` → `--lh-600` = **24px**，
  與 `--type-display-sm-lh` → `--lh-600` = **24px** 逐值相同。
- `letter-spacing` 與 `font-weight` 該規則**根本沒設**，一直由基底 `h1` 規則提供。
- `--lh-2xl` 另有 2 個消費者（`.chart-head .big`／`.plan .pp`），刪除不會變死 token。

🔴 **保留的真實代價不是 390 的 0.06px，是 435–768 寬會差 +2px**（4.6vw 在 435 觸頂 20px）
——那落在鐵律 13.1 的 768 對比點附近。

#### ② `.hero-hello h2` 的 `clamp(19px,5.4vw,24px)` — **改用容器查詢**

本尊 `._TitleLine_,._SubtitleLine_`：base **26/32/550/−0.4316px**（＝26×−0.0166em），
`@container (max-width: 768px)` 分支 **20/24**（`1.25rem` ＋ `--p-font-line-height-600`）。

🔴 **它量的是容器寬不是視口寬**——我方原本寫在視口斷點區塊內的 clamp，
**機制與值都不對**。改成 `@container cl-page (max-width: 768px)`，容器＝`.page`
（D55 已掛 `container-type: inline-size; container-name: cl-page`），值取 `--t-500`／`--lh-600`。

⚠️ **base 的字級仍是 24 不是 26**：26px **不在本尊自己的 13 階字級表裡**
（11/12/13/14/16/18/20/22/24/30/32/36/40），登記 `91` §3.33 W-4 待複驗。
窄版的 **20／24 兩個都在階內**，故可直接對齊。

#### live 驗證（本地 Chrome ＋ 同源 iframe，污染源已停用並複驗還原）

| | 1280 | 768 | 390 |
|---|---|---|---|
| `h1` | 18/24/600/−0.14994 | **18/24/600/−0.14994** | **18/24/600/−0.14994** |
| `.hero-hello h2` | 24/32/550/−0.3984 | **20/24/550/−0.332** | **20/24/550/−0.332** |
| 頁面容器內容寬 | 966 | 736 | 359 |

`h1` 在**量測的三個寬度（1280／768／390）**都是 18/24/600/−0.14994px，與本尊逐值相同；
hero 的容器查詢在 ≤768 正確切換，
字距按 em 重算成 −0.332（＝20×−0.0166）。

#### 🔴 順帶發現：`lint-prototype.py` 有兩條規則不剝註釋

本輪的註釋**兩次觸發假 ERROR**，同一個根因：

1. `r_px_breakpoint` 的 regex 以視口 at-rule 名起頭、中間允許任意非左大括號字元
   ⇒ 從**註釋裡**提到的那個 at-rule 一路掃到下面容器查詢的 `768px`，判「px 寬度斷點」。
   隔離複驗：真違規命中、合規 em 不命中、**註釋提及 at-rule ＋ 後方容器查詢 px ⇒ 命中（假陽性）**、
   註釋不提 at-rule ⇒ 不命中。
2. `<style>` 大括號平衡檢查**同樣不剝註釋**——註釋裡寫一個左大括號就判不平衡。

本輪以**改寫註釋**規避（不寫 at-rule 名、不寫裸左大括號）。
🔴 **修 lint 本身命中鐵律 18.3**（`scripts/` 下），依鐵律 20.4 只登記候選：`91` §3.37。

### D62. 拆掉逼近逾時的測試格，並把純資料輸入換成 `fireEvent`（2026-08-28）

使用者裁定的五項執行順序中的**第 2 項**。🟢 只改測試檔，不觸鐵律 18.3。

#### 做了什麼

`ProductDetailPage.test.tsx` 的「建立態：popover 加尺寸 → 打 S,M,L ⇒ 表即時三列；
儲存 payload…」一格做四件事，拆成兩格並抽出共用 arrange：

- **A 格**「popover 加尺寸 ⇒ 表即時三列」——驗**即時性**
- **B 格**「三列改價改量 ⇒ 儲存 payload」——驗 payload 形狀

純資料輸入（標題「帽T」、價格 128.00／138.00／148.00、數量 7，共 21 次擊鍵）
換成 `fireEvent.change`。

🔴 **`S{Enter}M{Enter}L{Enter}` 刻意不換。** 那一段測的正是「逐鍵輸入 ＋ Enter 提交
⇒ 表即時長列」的互動語義；換成 `fireEvent.change` 會把**被測行為本身**改掉，
屬於「為了讓測試變快而降低測試強度」。

**為什麼 `userEvent` 慢**：它每次擊鍵之間插一個 `setTimeout(0)`，而 Windows 的計時器
最小粒度約 15.5ms ⇒ 21 次擊鍵光排程就 ~300ms（同源教訓見記憶 `race-tests-waitfor-trap`）。

#### 量測（同 session、同機、安靜狀態）

| | 改動前 | A 格 | B 格 |
|---|---:|---:|---:|
| 單檔第 1 次 | 2042ms | 687 | 958 |
| 單檔第 2 次 | 2050ms | 649 | 924 |
| 單檔第 3 次 | 2239ms | 678 | 876 |

**最壞單格 2239 → 958ms（−57%）。**

**全套**：基準 **46.16s**（同 session 重測，非引用先前的 42.94s）→ 改動後 45.61／46.33s
⇒ **在雜訊範圍內，無可量測的變化**。
🔴 研究預測「總時間會增加約 1s」與我單檔量測讀出的「更快」**兩個都不成立**；
正確表述是「**最壞單格砍半，全套不變**」。

#### 🔴 但這一項是**必要而不充分**的

重測基準時第 2 次跑在機器被壓住的狀態下：**10 格紅，其中 8 格是 `Test timed out in 5000ms`**
——不是一格 flaky，是**整個 `ProductDetailPage` 套件在負載下都逼近 5000ms**：

| | 安靜（全套 verbose） | 負載下 |
|---|---:|---:|
| 那批格子 | 1009–1257ms | **5038–5297ms** |

**約 4–5× 的負載放大。** 拆一格只救一格；另外 8 格未動。

⇒ **執行順序第 5 項（`testTimeout`）不是可選的優化，是這個問題的主要解。**
以最壞的安靜值 1257ms 計，`testTimeout: 13000` 給約 **10×** 餘裕，
能吃下實測到的 4–5× 負載放大並留一倍。該項 🔴 觸鐵律 18.3，需使用者裁定後另開人工合併 PR。

---

### D63. 基準字級對齊本尊：`html` 交回 100%，基準搬到 `body`（2026-08-28）

使用者裁定的五項執行順序中的**第 3 項**。🟢 不觸鐵律 18.3。

#### 本尊怎麼寫的（原文取證）

2026-08-28 於 `admin.shopify.com/store/chill-love-u5q5mnzq/products`，
本機 Chrome，`fetch` 取 `…/vite/client/en/assets/main-ec608a075296.css` 原文。
🔴 **這一組規則用 CSSOM 走訪找不到**——45 張表、12077 條規則全走過、
無 `@import`、無 CORS 阻擋，`document.body.matches(selectorText)` 一條都沒命中。
是**逐張 `disabled = true` 二分**才定位到 sheet #4，再 `fetch` 原文才看見。
⚠️ 這代表 **CSSOM 走訪在本尊頁上不可靠**，往後定位規則一律以「消融 ＋ 原文」為準。

本尊三條規則，**順序就是語義**：

| 序 | 選擇器／條件 | 宣告 |
|---|---|---|
| ① | `html,body` | size-400、line-height-600、weight-regular、`letter-spacing: initial` |
| ② | `(hover) and (pointer:fine)` **或** `min-width: 48em` 下的 `html,body` | size-325、line-height-500 |
| ③ | `html` | `position: relative`、**`font-size: 100%`**、字形平滑一組 |

三條同特異度（型別選擇器）⇒ 源序後者勝 ⇒ **①② 的 font-size 實際只作用在 `body`，
`html` 恆 16px**。實測 computed：`html` = 16px / 20px / 450 / normal，
`body` = 13px / 20px / normal。

token 宣告值（同一份原文）：`size-325: .8125rem`、`size-400: 1rem`、
`line-height-500: 1.25rem`、`line-height-600: 1.5rem`。
🔴 **本尊整套字級 token 是 rem**——`.8125rem` 要靠 `html = 16px` 才算得出 13px。
`--p-font-weight-regular` 在這張表宣告 400，但 root 上的 live 值是 **450**
（`:root.p-partial-theme-admin-next-light` 那一塊覆蓋掉），與我方 `--fw-regular: 450` 一致。

#### 我方改了什麼

原型 `chilllove-admin-v2.html` 與 `app/assets/stylesheets/admin.css` 同步改成同一組三條規則，
並刪掉「`@media (max-width: 47.9975em)` 時把 root 推到 14px」那一階（本尊沒有這一階）。

**改動前後（實測，本機 Chrome，同源 iframe 控寬，擴充功能污染已停用）**

`admin.css`（＝使用者實際看到的 React app）：

| | 改動前 | 改動後 | 本尊 |
|---|---|---|---|
| `html` font-size | **13px** | 16px | **16px** |
| `html` line-height | normal | 20px | **20px** |
| `body` font-size | 13px | 13px | 13px |
| `body` line-height | **19.5px** | 20px | **20px** |
| `body` font-weight | **400** | 450 | **450** |
| letter-spacing | normal | normal | normal |

🔴 **實作端有三個真分歧，不是只有 rem 基準**：
①`line-height: 1.5` 在 13px 下是 **19.5px**，本尊 20px——它**繼承到每一個沒自己設行高的元素**；
②`body` 根本沒設 font-weight ⇒ 吃 UA 的 **400**，而原型是 450
⇒ **原型與實作對同一件事給了兩個答案**（C-2 同型：設計與實作各說各話）；
③root 13px 讓 `1rem = 13px`。

#### 三寬度回歸（原型，1280 / 768 / 390）

以 `git show HEAD:` 導出改動前的原型作對照組，兩份同源並排，
走完 `go()` 的 **35 條路由**，逐元素比 15 個 computed 屬性 ＋ bounding rect：

| 寬度 | 比對元素 | 差異種類 |
|---|---:|---:|
| 1280 | 2792 | **0** |
| 768 | 2792 | **0** |
| 390 | 2792 | 44（**全部同一族**：`fontSize: 14px → 13px`） |

390 的差異就是本包要的：舊的 root 14px 那一階被刪掉，改成跟本尊一樣由指標型態決定。
🔴 **桌機 Chrome 恆滿足 `(hover) and (pointer:fine)`**（實測本尊頁 `matchMedia` 回 true），
而 ② 的條件是 **OR** ⇒ 縮到 390 也仍是 13/20，與本尊在同一台機器上的行為一致。

#### 未取得 / 已知限制

- 🔴 **16/24 那一支在本 harness 測不到**（需真觸控裝置，鐵律 13.4）。
  代測法＝在 390 強制 `html,body{font-size:16px;line-height:24px}` 跑溢出稽核：
  7 個已渲染頁**溢出 0**。這證明「基準放大到 16 不會撐破版面」，
  **不等於**證明真機形態與本尊一致。
- **「使用者改瀏覽器預設字級會不會移動 em 斷點」本輪未實測**——它會移，
  那正是 47 §F 選 em 的理由；本輪只證了「root **宣告**字級不影響」。
- px→rem 的 token 改制**不在本包**（見下）。

#### 順帶證實的一條

`@media` 條件式裡的 `em` **不受 root 宣告字級影響**：本機 Chrome、同源 iframe 控寬，
root 依序設 8 / 13 / 16 / 26 / 32px，`(min-width: 48em)` **一律在 768px 翻轉**，
與 `(min-width: 768px)` 同格。`docs/design/48` 「三條硬規則」的第 3 條與原型兩處斷點階梯註釋原本只寫規格推論，已補上這組實測。

#### 明確不做

**px → rem 的 token 改制另案**（`91` §3.38）。本包只對齊三條規則的**結構與門檻**；
把 `--t-*` / `--lh-*` 全改成 rem 是本尊的無障礙決定（使用者調大瀏覽器字級時整個後台等比放大），
射程是整張 token 表 ＋ 所有消費端，且**在預設設定下零視覺差** ⇒ 無法用視覺回歸驗收，
需要另設驗收方法。鐵律 20.5：不借「斷根」包裝跨元件擴修。

---

### D64. 頂欄改成本尊的「暗色主題容器」，內容面板加上圓角（2026-08-28）

使用者裁定的五項執行順序中的**第 4 項**。🟢 不觸鐵律 18.3。

#### 本尊不是「深色頂欄」，是主題容器

2026-08-28 於 `/products`（本機 Chrome）實測：頂欄 `_TopBar_1scp5_1` 只寫
`background: var(--p-color-bg)`——**它自己沒有指定任何深色**。深色來自它的父層
`Polaris-ThemeProvider--themeContainer`，那一層把同一組語意 token 全部換成暗值。

逐項對照（同一組名字，左亮右暗）：

| token | 亮域 | 暗域 |
|---|---|---|
| `bg` | #f1f1f1 | **#0a0a0a** |
| `bg-surface` | #fff | **#1a1a1a** |
| `bg-surface-secondary` | #f7f7f7 | **#282828** |
| `bg-surface-tertiary` | #f3f3f3 | **#2f2f2f** |
| `bg-surface-hover` | #f7f7f7 | **#222** |
| `text` | #303030 | **#eee** |
| `text-secondary` | #616161 | **#aaa** |
| `icon` | #4a4a4a | **#dcdcdc** |
| `icon-secondary` | #8a8a8a | **#aaa** |
| `border` | #e3e3e3 | **#ffffff17** |
| `border-secondary` | #ebebeb | **#ffffff0f** |
| `bg-fill-brand` | #303030 | **#fcfcfc** |
| `bg-fill-brand-hover` | #1a1a1a | **#eee** |

🔴 **`*-inverse` 家族兩邊完全相同**（`bg-inverse` #0a0a0a、`text-inverse` #e3e3e3、
`icon-inverse` #e3e3e3、`border-inverse` #616161、`bg-surface-inverse` #303030）
——它們是**絕對參照**，不隨主題翻。這一點很容易搞混：頂欄背景是**暗域的 `bg`**，
殼層底色是**亮域的 `bg-inverse`**，兩者恰好都是 #0a0a0a 但來源不同、不可互代。

#### 三件事是同一個視覺系統，缺一件就看不出效果

實測 `main` 有 `border-radius: 12px 12px 0 0`，而它的祖鏈是
`_DarkOverlay`（透明）→ **`_Frame` #0a0a0a** → `_AppFrame` #0a0a0a。
⇒ **圓角處露出的就是那層暗底**。

🔴 **我一度判它是 no-op。** `main` 的背景 #f1f1f1 與 `body` 的 #f1f1f1 相同，
我只比到 body 就下了「同色 ⇒ 圓角看不見」的結論。**走完整條祖鏈才看到中間的
`_Frame`**。教訓：問「背後是什麼顏色」時，要走到第一個**不透明**的祖先，不是跳到 body。

同理，側欄實測 `background: rgba(0,0,0,0)`、`border-width: 0`、寬 240
——它直接踩在內容面板上。若我方保留 #f7f7f7 不透明側欄，它會**蓋住面板左上圓角**，
只剩右邊露暗底 ⇒ 不對稱。所以圓角、暗底、透明側欄**必須一起做**。

#### 我方怎麼實作

- **值全部放 `:root`**（`--dk-*` 14 個 ＋ `--bg-inverse`）。理由：
  `scripts/check-tokens-sync.rb` 只同步 `:root`，值寫在別處會在原型與 `admin.css`
  兩邊各自漂移——那正是 C-2 的事故形態。
- **`.cl-scope-dark` 只做語意名重新指向**，不含任何色值。暗域裡的元件
  **一行 CSS 都不用改**：寫 `var(--text)` 就自動拿到 #eee。這就是本尊那個
  ThemeProvider 的等效物。
- `.cl-topbar` 加上 `cl-scope-dark`、背景改 `var(--bg)`、**刪掉 `border-bottom`**
  （本尊實測 `border-bottom-width: 0`、`box-shadow: none`）。
- `.cl-admin-shell` 底色改 `var(--bg-inverse)`；`.cl-app-frame` 加
  `background: var(--bg)` ＋ `border-radius: var(--r-300) var(--r-300) 0 0`。
- `.cl-sidebar` 桌機改透明、無右框；**行動抽屜補上 `background: var(--surface-2)`**
  （桌機那條改透明後，抽屜會透出下面的頁面）。

#### 驗證（本機 Chrome、同源 iframe 控寬、擴充功能污染已停用）

| | 1280 | 768 | 390 | 本尊 |
|---|---|---|---|---|
| `.cl-topbar` bg | rgb(10,10,10) | 同 | 同 | **rgb(10,10,10)** |
| `.cl-topbar` color | rgb(238,238,238) | 同 | 同 | **rgb(238,238,238)** |
| `.cl-topbar` border-bottom | 0px | 0px | 0px | **0px** |
| `.cl-admin-shell` bg | rgb(10,10,10) | 同 | 同 | **rgb(10,10,10)** |
| `.cl-app-frame` bg / radius | rgb(241,241,241) / 12px 12px 0px 0px | 同 | 同 | **同** |
| `.cl-sidebar` bg | 透明 | 透明 | rgb(247,247,247)（抽屜） | 透明（桌機） |
| `.cl-sidebar` 寬 | 240 | 240 | 272（抽屜） | **240**（桌機） |

並以**放大截圖**逐一目視對照本尊同一角落：兩邊都是「暗色頂欄 → 亮色面板左上 12px 圓角
露出暗底 → 導航項目直接坐在亮面板上、無側欄底色也無分隔線」。

#### 未取得

- 🔴 **本尊行動版（<768）的頂欄與抽屜形態量不到**：`resize_window` 不可用、
  admin 不能 iframe。我方抽屜沿用改動前的 `--surface-2`，**不是對齊本尊的結果**。
- 頂欄**內部元件**本輪只量、未實作（搜尋列 640×36 / #282828 / r12、
  圖示鈕 18px 圖示 ＋ 6px 內距 / r12、商店 chip 154×36 / r12、
  快捷鍵標籤 #2f2f2f 底 / #aaa 字 / 10px / 550 / r4）——登記 `91` §3.39。

---

### D65. 前端測試逐格逾時 5000 → 16000（2026-08-28 使用者裁定）

使用者裁定的五項執行順序中的**第 5 項**，也是唯一一項 🔴 **命中鐵律 18.3**
（`vite.config.ts` 定義「`pnpm test` 綠」是什麼意思 ⇒ 判準面）⇒ **人工審閱與人工合併**。

#### 問題不是「某一格慢」

實測（同一台機、同一 session）：

| | 安靜 | 機器被壓住 |
|---|---:|---:|
| `ProductDetailPage` 那批格子 | 1009–1257ms | **5038–5297ms** |

**4–5× 放大**，一次實測到 **10 格紅、其中 8 格是 `Test timed out in 5000ms`**。
⇒ 這是整套在負載下一起逼近上限，不是單一一格寫得慢。
D62 把最肥的那格拆成兩格（最壞單格 2239 → 958ms）**只救了那一格**，其餘 8 格照紅。

#### 16000 的來源

**全套最慢一格的安靜值 1602ms 的 10 倍。**
導出指令：`pnpm vitest run --reporter=verbose`，取最大的毫秒數。

🔴 **這個數字修正了 D62 的建議值。** D62 當時寫「以最壞的安靜值 1257ms 計，
`testTimeout: 13000` 給約 10× 餘裕」——那個 1257 只掃了 `ProductDetailPage`。
全套掃描後最慢是 **1602ms**，13000 對它只有 8.1×，且對推算的最壞負載值
（1602 × 5 = 8010ms）只剩 1.6 倍餘裕。16000 留一倍。
（D62 的 worklog 與 D64 的 handoff 都寫了 13000，**不回頭改**，以本條為準。）

⚠️ **代價誠實登記**：真的卡死的測試會慢 16 秒才失敗（每格一次）。

#### 反向複驗

不入庫的 canary：一格 `await new Promise(r => setTimeout(r, 6000))`。

| 設定 | 結果 |
|---|---|
| 本檔現值（16000） | `Tests 1 passed` |
| `--testTimeout=5000` 覆寫 | `Error: Test timed out in 5000ms.` / `Tests 1 failed` |

⇒ 證明兩件事：①新值**真的生效**（不是寫了沒接上）②canary **真的殺得死**
（不是恆綠的假驗證）。跑完即刪，未入庫。

#### 🔴 明確禁止 `retry`

它跟拉高逾時**不是同一類措施**：拉高逾時只改變「等多久才判失敗」，**失敗還是失敗**；
`retry` 會讓**永久性回歸**（每次都錯、只是偶爾偵測得到）在重試後變綠。
本尊在單元測試裡 **0 次**使用 retry（已以四種查法全組織確認）。

---

### D66. 頂欄內部控件逐項對齊本尊（2026-08-28）

`docs/specs/91` §3.39 W-2 登記的「已量未實作」那一項。🟢 不觸鐵律 18.3（純 CSS，未動 markup）。

#### 取證

2026-08-28 於 `/products`（本機 Chrome，viewport 2560、暗色域內、
`font-bolder-style` 擴充功能已停用）逐控件量測：

| 控件 | 本尊 |
|---|---|
| 搜尋觸發鈕 `_TopBarButton_ir1fb_1 _SearchA…` | 545×36、圓角 12、**邊框寬度 0**；底色來自內層 `_BorderGradient_bw2yn_1` ＝ #282828；文字 13 / 20、color #dcdcdc |
| 快捷鍵標籤 `Polaris-KeyboardKey` | 34×20（CTRL）／20×20（K）、bg #2f2f2f、color #aaa、**邊框 0**、圓角 4、內距 `2px 4px`、**10px / 16 / 550** |
| 圖示鈕 `_TopBarButton_ir1fb_1` | **36×36**、圓角 12、底透明、color #dcdcdc；內距 6，圖示 20×20 或 16×16 |
| 商店 chip `_TopBarButton_ir1fb_1 _Act…` | 154×36、圓角 12、**邊框 0、底透明**、內距 0；店名 12 / 16 / **550** |
| chip 內頭像 | 28×28、圓角求值 8（宣告 `clamp(4px, round(25%, 2px), 8px)`） |

顏色全部對得上暗色域 token（#282828＝surface-2、#2f2f2f＝surface-3、
#dcdcdc＝icon、#aaa＝text-2），所以我方一律寫語意名，不寫色值。

#### 🔴 兩處更正

1. **`91` §3.39 W-2 記的「圖示鈕 18×18」是量錯節點**——那是圖示，不是鈕。
   鈕是 **36×36**（內距 6 ＋ 圖示 20 或 16）。以本條為準。
2. **搜尋鈕寬度 545 不是控件上限**，是「該視口下與『View as』鈕分掉中央 640 槽」的結果。
   我方取**槽寬 640**。

#### 明確不照抄的一項

本尊搜尋標籤的 computed `font-weight` 是 **400**，但那是 **UA button 預設值漏出來的**
——該 span 只設了 font-size／line-height，沒設 weight，於是繼承鈕的 UA `400`
（同一顆鈕的 computed font 讀出 `13.3333px/normal/400/normal`，是典型的 UA button 簡寫）。
400 **不在我方字重值域**（450／550／600／650，D57 定案），也不在本尊自己的 `--p-font-weight-*` 常用值裡。
⇒ 我方用 `--fw-regular`（450），**不引進一個一次性的 400**。理由記在此，不在程式碼裡爭辯。

#### 我方改了什麼

原型與 `admin.css` **同步**改四個控件（搜尋鈕／kbd／圖示鈕／chip ＋ chip 內頭像）。
被刪掉的硬編值：`#c9cace`（hover 邊色，直接硬編色，違反鐵律 8）、
`34px` 高、`9px` 圓角、`11px`、`600` 字重、`24px` 頭像、`7px` 頭像圓角、`600px` 上限。

🔴 **`10px` 保留為字面值**：本尊的 kbd 是 10px，而**兩邊的字級階最小都是 11px**
（本尊 `--p-font-size-275`＝.6875rem＝11px）。這是本尊的**階外值**，
照實記錄、不硬湊到 11；也不建 token（單一用途，建了是死 token）。

🔴 **頭像的 28×28 只加在 chip 內**：`.avatar` 是通用類（原型 markup 內 9 個用點），
直接改它會把列表、顧客卡一起放大。

#### 驗證（本機 Chrome、同源 iframe 控寬、擴充功能污染已停用）

原型與 `admin.css` **各自量一次**，1280 下五個控件九個軸**逐項相同**，且與本尊相符：

| | 我方（兩份一致） | 本尊 |
|---|---|---|
| 搜尋鈕 | 640×36、r12、bd 0、bg rgb(40,40,40)、col rgb(220,220,220)、13/20 | 545×36、r12、bd 0、#282828、#dcdcdc、13/20 |
| kbd | bg rgb(47,47,47)、col rgb(170,170,170)、10/16/550、r4、pad 2px 4px、bd 0 | 同 |
| 圖示鈕 | 36×36、r12、透明、rgb(220,220,220) | 同 |
| chip | 高 36、r12、bd 0、透明、12/16/550 | 同 |
| 頭像 | 28×28、r8 | 同 |

768 與 390：原型與 `admin.css` 皆**溢出 0**，頂欄高 56、底 rgb(10,10,10) 不變。

---

### D67. 頂欄改成本尊的三欄 grid（2026-08-28）

`docs/specs/91` §3.40 W-1。🟢 不觸鐵律 18.3（CSS ＋ 兩處 markup wrapper，未動判準面）。

#### 本尊怎麼做

`_Container_1scp5_26` 實測 `display: grid`、`grid-template-columns: 960px 640px 960px`
（viewport 2560 ⇒ 等效 `1fr 640px 1fr`），三個槽分別是
`_LeftContent_` / `_SlotsContainer_` / `_RightContent_`（後者 `justify-content: flex-end`）。

🔴 **這不是排版偏好，是行為差異**：舊寫法 `flex:1 + margin:0 auto` 讓搜尋框的中線落在
**剩餘空間**的中央；左右內容不等寬時會偏。三欄 grid 的兩側是同一個 `1fr`
⇒ 中欄**恆在視口中央**。

🔴 **中欄同時是存檔列的槽位**：dirty 時 savebar 取代搜尋列（不是疊加），兩者都住在中欄
⇒ 換手時中線不動。實測原型：savebar `.show` 時 `position: static`、盒 320w640、
**中線 640 ＝ 視口中線**，同時 `.searchbox` 的 `display` 變 `none`。

⚠️ 本尊中央槽另有 `padding: 0 14px` 配 **−14px 外距**（盒寬 668 vs 槽寬 640）
——把命中區往外撐 14px，**沒有視覺效果**，不照抄。

#### 🔴 兩側必須是 `minmax(max-content, 1fr)`，不能是純 `1fr`

第一版寫 `1fr minmax(0, 640px) 1fr` ＋ zone 上 `min-width: 0`。
768 實測：側槽被壓到 **48px**，而 `.top-right` 實際佔 **414–752**
⇒ **內容跨進中槽重疊**。

🔴 **那一輪的溢出稽核回報 0，因為它只比視口邊緣——典型的 fail-open。**
判準已改成「**每個 zone 的子元素必須落在自己 zone 的矩形內**」
（並排除定位祖先脫離流的子代，例如 ≤767 時 `position: fixed` 的 savebar 內部）。

反向複驗：把中欄改回純 `1fr` 跑同一個檢查，768 下抓到 **28 處** zone 溢出；
改回 `minmax(max-content, 1fr)` 後三寬度兩份檔皆 **0**。

#### 實測結果

| 寬度 | | 三欄 | 搜尋中線偏離視口中線 | zone 溢出 |
|---|---|---|---:|---:|
| 1280 | `admin.css` | 304 / 640 / 304 | **0** | 0 |
| 1280 | 原型 | 227 / 640 / 381 | 76.6 | 0 |
| 768 | `admin.css` | 182 / 364 / 190 | 3.7 | 0 |
| 768 | 原型 | 242 / 121 / 373 | 22.6 | 0 |
| 390 | `admin.css` | 118 / 196 / 44 | （搜尋隱藏） | 0 |
| 390 | 原型 | 76 / 71 / 211 | （摺疊成 36px 圖示鈕） | 0 |

🔴 **原型偏離不是 CSS 沒生效，是它的右槽控件比實作多**：原型右槽有
語言切換 chip ＋ AI ＋ 註釋 ＋ 通知 ＋ store chip（含 `demo` tag），max-content ＝ **381**，
> 1280 下可分到的 304 ⇒ 取其 max-content，左槽只剩 227，中欄因此不在正中。
**這是資訊架構問題（頂欄控件太多），不是版面 bug**，登記 `91` §3.41 W-1。
`admin.css`（＝使用者實際看到的）在 1280 是**精確置中**。

⚠️ **本尊窄寬度的分欄行為未取得**（無法縮放本尊視窗）⇒ 中欄用 `minmax(0, 640px)`：
空的時候塌成 0、擠的時候讓步，不會把兩側推爆。

#### 原型 ≤ 某寬度的搜尋摺疊形態不是本包造成的

原型另有 `.searchbox{flex:0 0 auto;width:36px;margin:0 0 0 auto;padding:0;justify-content:center}`
＋ 隱藏標籤與 kbd 的既有規則——**窄版把搜尋摺疊成 36px 圖示鈕**。
`admin.css` 則是**整個隱藏**。兩份檔在窄版的搜尋形態本來就不同，登記 `91` §3.41 W-2。

---

### D68. 兩項使用者裁定：頂欄介面語言保留＋字級 token 改 rem（2026-08-28）

使用者對上一輪兩個待決點的裁定：**①介面語言留在頂欄；②px→rem 改制執行，連同靜態檢查（B 道）一起做**。
本條落地 ①的登記與 ②的轉換本體；靜態檢查腳本觸鐵律 18.3，另開 D69 人工合併 PR。

#### ① 介面語言保留（裁定登記）

`91` §3.41 W-1 的處置＝**裁定保留**。後果如實登記：原型右槽 max-content 約 381
> 1280 下可分到的 304 ⇒ **原型在約 1400 視口以下中欄不在正中**（1280 偏 76.6）。
`admin.css`（使用者實際看到的）控件較少，1280 精確置中。
本尊沒有這個控件，且多語言面對標 SHOPLINE 不對標 Shopify ⇒ 這一格本來就只能使用者裁。

#### ② --t-* / --lh-* 兩族由 px 改 rem（21 顆）

本尊同形（`--p-font-size-325 = .8125rem`，D63 原文取證）；靠 `html = 16px` 換算。
21 顆全部整除（11→.6875、12→.75、13→.8125、…、48→3），無捨入。
射程只有字級與行高兩族（`91` §3.38 W-1 登記的射程）；`--sp-` / `--r-` / `--h-` / `--sz-`
維持 px——本尊的 space 與 radius 也是 rem，但那是另一個裁定（登記 `91` §3.42 W-1）。

#### 為什麼現有驗收法驗不出，以及用什麼代替

轉換在預設 16px 下**恆等**（`.8125rem × 16 = 13px`）⇒ 逐元素比對分不出
「轉對／沒轉／漏轉」。改用兩道：

**A. 擾動法**：root 設 32px（×2），量代表元素的 fontSize/lineHeight 比值。
🔴 **canary 先行**：轉換前先量一次，全部比值 **1.0**（證明測試有鑑別力的基線）；
轉換後 token 消費端必須全部 **2.0**，硬編字面值留在 **1.0**。
實測（原型與 `admin.css` 各自量）：轉換前 12 個代表元素全 1.0；轉換後
token 消費端全 2.0，唯二的 1.0 是 kbd 的 10px（**階外字面值，本來就該不動**）。

**B. 靜態完整性**：斷言兩族每顆都是 rem——唯一對 token 表**完整**的檢查
（渲染測試只覆蓋剛好有元素在用的）。＝D69 的 `scripts/check-rem-tokens.rb`，18.3 人工合併。

**原本的前後逐元素比對沒有廢，它換了工作**：證明預設 16px 下零視覺變化。
實測：35 條路由、每邊 2792 個元素、12 個 computed 屬性——**差異 0**。

#### 🔴 本輪事故：同一個坑踩了兩次——註釋裡的 `*/`

兩段新寫的註釋都含 `--t-*/--lh-*` 字樣：**`*/` 把 CSS 註釋提早終結**，殘骸吞掉緊鄰的宣告。
- 第一次：`:root` 內的說明吞掉 `--t-275` ⇒ `--t-2xs → var(--t-275)` 無定義，
  `.dev-tag` 掉到繼承值 12px。**擾動法的 at16 欄抓到（11→12）**——
  這就是「canary 要比對基線、不能只看比值」的實證。
- 第二次：D63 註釋的更新文字同樣寫法，吞掉 `html,body` 基準規則的前半
  ⇒ **全站 body 字重 450→400（200 個元素）**。全路由等價比對抓到。

修法＝改寫成「--t- 與 --lh- 兩族」；全檔掃描 `\*/\S`（`*/` 後緊接非空白）確認
僅剩合法的密排寫法。事故與判準登記 `91` §3.42 W-2。

修復後終態：擾動法轉換前全 1.0 → 轉換後消費端全 2.0；
全路由等價 **35 路由 × 2792 元素 × 12 屬性＝差異 0**；`--t-275` 兩份檔都解析出 `.6875rem`。

---

### D69. rem token 靜態完整性檢查（B 道）落地（2026-08-28）

D68 裁定②的後半。🔴 **觸鐵律 18.3**（新增 `scripts/` 兩支 ＋ 改 `ci.yml` ＋ `config/ci.rb`
＝機械閘門判準面）⇒ **人工審閱與人工合併**。

#### 交付

- `scripts/check-rem-tokens.rb`：producer（原型 `:root`）內 `--t-<數字>`／`--lh-<數字>`
  兩族每顆必須是 rem。**別名（`--t-sm` 這類 var() 間接層）刻意不在射程**。
  掃描前剝 CSS 註釋（D68 的 `*/` 事故同根：說明文字與宣告同形）。
  退出碼三分：0＝通過／1＝有違規／2＝取證失敗（檔案或 `:root` 不在、**兩族任一掃到 0 顆**）。
- `scripts/test-rem-token-rules.rb`：fixture 驅動回歸，8 格
  （乾淨×2、px 字級、px 行高、em、家族空、註釋偽裝、無 root）＋真 producer 必過。
- `spec/fixtures/rem_tokens/`：7 份 fixture。
- 接線：`ci.yml` quality job ＋ `config/ci.rb` 同批（check-ci-parity 通過）。

#### 🔴 突變實測（20.2⑤：改判準必須證明它殺得死）

寫完後對 checker 做五個活突變，**每個都讓回歸轉紅**才算數：

| 突變 | 殺手 |
|---|---|
| M1 判定反轉（`next if`→`unless`） | clean fixture 的反向斷言 |
| M2 零掃描 canary 整段刪 | `family_empty` 期望碼 2 |
| M3 FAMILIES 刪 `--lh-` 那條 | `px_lineheight` 期望碼 1 ＋ `family_empty` needle 指名 `--lh-` |
| M4 剝註釋那行刪掉 | `comment_masked` 期望碼 0 |
| M5 取證失敗 exit 2→0 | `no_root` 期望碼 2 |

M3 是設計期就預判會存活的形態（刪掉一族後另一族照掃、canary 誤觸發也回 2）
⇒ fixture 表因此加了 `px_lineheight` 單獨一格與指名家族的 needle。

#### 誠實聲明（checker 檔頭同文）

- `--sp-`／`--r-`／`--h-`／`--sz-` 維持 px 是現行裁定（`91` §3.42 W-1）⇒ 不掃。
- **消費端硬編 px 本檢查看不到**——那要靠擾動法（`91` §3.42 W-3，未機械化）。
- `tokens.css` 不另掃：與 producer 逐位元組同源由 `check-tokens-sync.rb` 守，再掃是第二份判準。

---

### D70. 頂欄 hover 態對齊 ＋ 兩項擱置裁定（2026-08-28）

使用者採納建議：**hover 量測收尾後離開視覺對齊弧、回 S6c 功能開發；其餘兩項擱置並記錄**。
🟢 不觸鐵律 18.3（純 CSS）。

#### hover 的取證（本機 Chrome，真觸發實測 ＋ 原文交叉）

本尊的 hover 不在按鈕上，在**外層 `_BorderGradient_bw2yn_1` 包裝**：
`_Hover_bw2yn_99` 是**常駐能力類**（rest 時就在），態靠 `:hover` 選擇器——
`._Hover_bw2yn_99:not(._Active):not(:active):hover { background: var(--nav-topbar-surface, var(--border-gradient-bg-hover)) }`
（`render-common-*.css` 原文；**這些規則不在 main-\*.css 裡**——CSS modules 分塊，
全 40 張表逐一 fetch 才定位到）。

真觸發實測（`computer.hover` ＋ 讀 computed）：

| 控件 | rest | hover |
|---|---|---|
| 搜尋鈕 | #282828（surface-2） | **#222（surface-hover）** |
| 圖示鈕 | 透明 | **#222** |
| 商店 chip | 透明 | **#222** |

**三控件全部收斂到 #222＝暗域的 `surface-hover`**；hover 時圖示色**不變**（恆 #dcdcdc）。
⚠️ 搜尋鈕的 hover（#222）比 rest（#282828）**更暗**——與直覺相反，照實照抄。

🔴 量測方法坑（登記）：`computer` 的座標框架是**最近一次截圖**的像素，不是頁面 CSS px。
頁寬 2560、截圖 1568 ⇒ 比例 0.6125；不先截圖就用 CSS 座標，hover 會落空**且不報錯**
（讀回來的全是 rest 值，看起來像「hover 沒有效果」）。判準＝先斷言 `el.matches(':hover')`。

#### 我方實作：只在暗域覆寫，不改基礎規則

`.cl-scope-dark .cl-icon-button:hover` / `.cl-scope-dark .cl-store-chip:hover`
→ `var(--surface-hover)`（暗域解析 #222）＋圖示色釘回 `var(--icon)`。

🔴 **為什麼不改基礎規則**：`.cl-icon-button` 在亮域還有 7 個用點（Calendar、商品頁動作鈕…），
而亮域的 `--surface-2`（#f7f7f7）**恰好等於本尊亮域的 `bg-surface-hover`**
——名字對不上但值是對的（`91` §3.39 W-3 名稱對映未解）。
改成 `--surface-hover`（亮域 #f1f1f1）反而比現狀離本尊更遠。

驗證（兩份檔**各自**真觸發實測）：暗域三控件 hover 全 #222、圖示色恆 #dcdcdc；
亮域 icon-button hover 仍 #f7f7f7（未被覆寫波及）。

#### 兩項擱置裁定（使用者 2026-08-28 採納建議）

**①（W-1 處置）`--sp-`/`--r-`/`--h-`/`--sz-` 四族的 rem 改制＝擱置。**
理由：收益是「間距與圓角也隨字級放大」（錦上添花），風險域是**版面斷行與溢出**
（比字級大一圈），且需另一次裁定。**重啟條件**＝實際出現「放大字級後間距不成比例」
的回饋，或下一次 token 域的大改制順帶做。登記位置不變（`91` §3.42 W-1），本條為其處置。

**②（W-3 處置）`scripts/rwd-check.mjs`（擾動法機械化 ＋ 三寬度 CI 化）＝擱置到下一個
大 UI 輪的開頭。** 理由：它是重型 18.3 包（headless 瀏覽器依賴需裁定、要固化 zone
溢出／擾動法／橫捲排除等判準），當收尾做會做薄，當下一輪 UI 地基做才划算。
**重啟條件**＝下一個 UI 密集階段開工時作為首包。`91` §3.41 W-3／§3.42 W-3 的處置同此。

#### 視覺對齊弧到此收束

D54 立案的「整體 UI 不協調」四層診斷（中性階／語義色／字重／欄寬）加上後續的
基準字級（D63）、殼層色彩域（D64）、頂欄控件與骨架（D66/D67）、字級 rem（D68/D69）、
hover（本條）——**全部收口或有裁定處置**。下一步＝回 S6c（系列 popover）功能開發。

---

### D71. S6c：系列的銷售管道 popover（完整實測 → 落地）（2026-08-28）

使用者指示「下一步，並且需要按鐵律，完整走一次實測和研究」。
🟢 不觸鐵律 18.3（前端 ＋ CSS ＋ i18n ＋ 測試）。

#### 實測（鐵律 12 全六層 ＋ 14 抓包 ＋ 12.3⑤ help 雙源）

完整 teardown＝`docs/research/82` **§17**（觸發鈕／popover 形態／互動語義／網路五件套／
help 互證／排程子視圖／寫入還原記錄）。三個決定性發現：

1. 🔴 **toggle 是表單級 dirty**：不打即時 mutation，出 `Unsaved changes` 保存列，
   Save 才送、Discard 還原、關 popover 不丟變更。help 官方步驟含 Save 步互證。
2. 🔴 **底層就是我方 S5 的 mutation**：Save 送的 persisted op 其 response data key＝
   `publishableUnpublish`／（Add 同構）⇒ 我方**零 schema 改動**直接接。
   回讀 query 全文可見：`resourcePublicationsV2(first:250, onlyPublished:false,
   catalogType: APP)` —— `catalogType: APP` 與 §9.3 官方語義互證。
3. **總開關＝三態**（`input.indeterminate`），循環 mixed→全開→全關，全程本地。

#### 落地

- `CollectionDetailPage`：`CollectionChannelsControl`（觸發鈕＋popover），
  delta 進 SaveBar dirty；save＝collectionSet 成功後套 delta（publish/unpublish 合一
  mutation）→ **重讀不樂觀翻轉**；discard 一併還原。
- **共用不複製**：SwitchRow／GroupToggle／ChannelScheduleButton／delta helpers 由
  ProductDetailPage `export`（`serverScheduleOf` 判準有紅線，複製一份＝C-2 事故形態）。
- i18n 五鍵 ×5 語系；CSS `.cl-chpop*`（值全走 token）。
- 測試 4 格：形態＋排程入口唯一性／dirty 語義＋payload＋順序／總開關循環／Discard 歸零。

#### 登記的偏離（全文 82 §17.8）

排程入口一律顯示（觸控理由，沿用商品 modal 裁定）；排程面板＝錨定子彈層
（本尊原地換頁；重用 SchedulePopover 原語）；icon 用 Lucide（鐵律 9）；
新建表單隱藏觸發鈕（本尊該形態未取得）。

---

### D72. S6c-2：商品列表的 Channels 欄與唯讀 popover（2026-08-28）

S6c 的自然延伸（82 §9.3 第三種 affordance）。🟢 不觸鐵律 18.3。
teardown＝`docs/research/82` **§18**。

實測要點：格＝計數＋hover/focus 才露 `˅`（實體是整格透明覆蓋鈕）；popover 唯讀、
只列**已發布**管道（計數 ⇔ 列數逐列驗證）；🔴 **點列＝導航到該管道的 admin 首頁**
（Online Store → `/themes` 實測）。

落地：`ProductsPage` 新增欄＋`ChannelsCell`；查詢帶 `resourcePublicationsV2(onlyPublished: true)`；
計數判準與詳情頁 `salesChannelsOf` 同（handle 非 null）。
偏離（82 §18.5）：無我方頁面的管道（shop）列出但停用；零管道形態本尊未取得 ⇒ 我方純 `0`。

🔴 落地抓到真缺陷：popover 點擊冒泡到列的 onRowActivate（＝進商品詳情）——
本尊點格只開 popover。修＝`stopPropagation`（IndexTable select 格的既有同構做法）。
測試 +2 格（10/10）。

---

### D73. S7：狀態機交互的收口（批量狀態動作＋排程 banner）（2026-08-28）

使用者指示三包連做（S7／PR-C／S8）；**PR-C 經查已於 2026-08-27 完成**（#153/#155，
consumer＋backfill＋spec 全在）⇒ 本包＝S7。🟢 不觸鐵律 18.3。
實測＝`docs/research/82` **§19**（批量選取列與溢出值域）＋既有 §9.2／PR-C 裁定書 F1-②。

#### S7 清單的逐項處置

| 項 | 處置 |
|---|---|
| 四狀態三面不對稱（商品頁 dropdown／More actions） | ✅ **既有實作已覆蓋**（三值 listbox＋封存走更多動作＋確認框，包 4 交付）——本包零改動 |
| 第三面（列表批量） | ✅ **本包交付**：選取列＋動態頂層鈕＋溢出（取消刊登／封存＋確認框），逐筆 `productSet {id, status}` |
| 排程要求 Active（88 §5 #3 的 UI 面） | ✅ **本包交付**：`SchedulePopover.notice`——DRAFT／ARCHIVED 開排程面板見 `role=status` banner，**控件不禁用**（本尊 F1-② 形態：排程照存、到點才依 D53 閘門）。判準＝`status ∉ {ACTIVE, UNLISTED}`（與 D53 PURCHASABLE 對齊） |
| `Suspended` 第五值 | ⚪ 登記（`91` §3.44 W-1）：平台施加、官方 enum 之外、語義未取得——不進我方 enum |
| 複製商品的發布繼承 | ⚪ 登記（W-2）：我方 Duplicate 尚未實作（詳情頁該項 disabled 佔位），繼承規則隨該功能一起做 |

#### ours 裁定（記錄在 82 §19.4）

①頂層動態鈕規則（本尊只取得一格）：全 ACTIVE→設為草稿；全非 ACTIVE→設為啟用；混合→兩顆。
②批量封存加確認框（本尊未取得；與詳情頁同紀律）。
③banner 配色走 `--sem-info-*`（本尊 tone-auto 的實際色值未量 ⇒ V）。

#### 測試

批量 2 格（動態鈕唯一性＋逐筆 payload＋清空選取／溢出值域＋確認框攔截）＋
banner 2 格（DRAFT 有且控件可用／ACTIVE 無）。
