# 工作記錄：userErrors 契約與金額正負全面對齊本尊（M1 PR-1 第 3.5 步，2026-08-15）

> 裁定全文＝`docs/DECISIONS.md` D14｜考掘基準版＝Shopify Admin API **2026-07**

## 已完成的工作 (Done)

寫 S4（BaseMutation 地基）之前，先把**規格本身**對齊本尊——在錯的規格上實作，
之後每一支 mutation 都要跟著改。

使用者對三個待裁定的問題（`userErrors.field` 路徑語義、`code` enum 結構、金額正負）
的回覆是同一句：**「深度分析和研究 shopify 的架構，然後我們和 shopify 一樣」**
——不從選項裡挑，去查本尊實際怎麼做。

方法：四路平行考掘 shopify.dev ＋ **三路對抗式覆核**（找反例／查版本差異／檢查我方誤讀）。
覆核者逐頁複核 24 條 load-bearing 事實，結論是「引用可信度異常地高，
逐字抄錄的地方不會出錯，出錯的全是**從散落證據歸納出通則**的地方」。

### 🔴 覆核推翻了考掘一次，而且是往「我方本來就對」的方向

考掘從論壇回傳 `["input"]` 外推「path 的 root ＝ mutation 參數名」，
據此判 63 §A.4 的 `field: ["lockVersion"]` 應改成 `["input","lockVersion"]`。
覆核用官方 `/mutations/productDelete` 的錯誤範例正面推翻：
參數就叫 `input`、id 住在 `input.id`，而官方回的是 **`"field": ["id"]`**——
**本尊會把 `input` 這層外殼剝掉**。⇒ 我方原本就是對的，不改。

**沒有這一層覆核，我會照著錯的結論去改一份本來正確的規格。**

### 11 條照抄本尊、6 條刻意偏離

全表見 `docs/DECISIONS.md` D14。最關鍵的三條：

1. 🔴 **`CONFLICT` 不是樂觀鎖碼**。本尊的 `CONFLICT` 只存在於 `DiscountErrorCode`，
   語義是「折扣屬性選擇互相衝突」的**輸入驗證**。63 §L-3 原本要把它「提升為泛用碼」，
   本輪**以相反方向結案**：28 §8 的分類是對的，改的是 63。
   樂觀鎖用 `STALE_OBJECT`、庫存 CAS 用 `CHANGE_FROM_QUANTITY_STALE`。
   **教訓：把一個碼「提升為泛用」之前要先查它在本尊那裡是什麼意思。**
   `CONFLICT` 這個英文詞看起來當然像樂觀鎖——光看名字推語義是本輪最容易犯的錯。

2. 🔴 **本尊的泛用 `UserError` 沒有 `code`**（`/enums/UserErrorCode` 回 404，無共用 base enum）。
   我方「所有 mutation 一開始就上 typed code enum」是**加嚴的 ours**，
   而 28 §0.3 的節標題寫著「GraphQL 核心慣例（**全部照抄**）」——**那會誤導實作者以為有官方背書**。

3. 🔴 **金額型別層一律不驗正負**。65 號原本從頭到尾沒提過負數，而 R4/R6 寫的
   「無**符號**、無千分位」有歧義：照「無正負號」實作出 `^\d+\.\d{2}$` 就會**擋掉退款差額**。
   `limits.yml:189` 逐字是「無**幣別**符號」、正則也是 `^-?\d+\.\d{2}$`，
   所以規格內部本來就是對的，只是中文寫得不夠死。五處全部改掉，並新增 §A.7 把
   「哪一層驗、哪一層不驗」寫成表。

### 順帶抓到兩條數字/清單對不上

- `limits.yml` 的冪等註解寫「官方共 17 個」，清單裡只有 **10 支**官方的
  ——**對不上的方向是少收**，漏掉的 7 支會在沒有冪等的情況下被實作。已補齊（33 支：官方 17 ＋ ours 16）。
- `compareQuantity` **自 2026-04 已從本尊 schema 移除**，改名 `changeFromQuantity`。
  ⚠ 型別是 `Int`（**nullable**）不是 `Int!`——changelog 說的「必填」是行為層要求
  （key 必須明確出現），型別層做成 `Int!` 會讓官方明文的「傳 null＝關閉 CAS」逃生門消失。

## 修改的檔案與核心邏輯 (Changes)

- `CLAUDE.md` **鐵律 4**：「HTTP 恆 200」→ 三層（業務錯誤 200／限流成本 200／認證租戶格式**非 200**）；
  補 `field` 型別與 `null` 語義；補「`code` 一律有值是 ours」的紅字。
- `docs/research/28`：§0.1 釘死對齊版本 **2026-07** ＋ **查證方法陷阱**
  （shopify.dev 只保留最近四個 stable 版，`/2024-01/` 會**靜默回傳 latest 且不報錯**
  ⇒ 所有「跨版本逐字相同」的舊結論都是假證據）；
  新增 §0.3.1（field 型別與路徑）／§0.3.2（code，標 ours）／§0.3.3（payload 形狀、無 clientMutationId）／
  §0.3.4（input object 命名已落後）／§0.3.5（warnings，照抄 Storefront）／§0.3.6（假設清單）。
- `docs/specs/63`：§A.4 `CONFLICT` → `STALE_OBJECT`（並註明 `["lockVersion"]` **不改**及其理由）；
  §E.5 `compareQuantity` → `changeFromQuantity` ＋ field 改三段含索引；
  §L-3 以相反方向結案；驗收清單兩條同步。
- `docs/specs/65`：新增 **§A.7 正負號**（哪一層驗、哪一層不驗的對照表）；五處「無符號」→「無幣別符號」。
- `config/limits.yml`：冪等區塊補「本尊是 directive 形」的說明、官方段與 ours 段的分隔說明、
  補齊官方 17 支中缺的 7 支。
- `docs/DECISIONS.md`：**D14**（11 條照抄 ＋ 6 條偏離 ＋ 仍未查到的四項）。

## 尚未完成或需注意的風險 (Pending / TODO)

- 🔴 **具名參數形下的多段 path 沒有官方範例**。官方只有單段 `["productId"]`、
  剝殼後的 `["id"]`、以及 `["variants","0",...]`。
  「`productCreate(product:{title:""})` 回 `["product","title"]` 還是 `["title"]`」查不到。
  我方採「只剝名為 `input` 的參數」（三個官方實例都相容），**登記為假設**。
  補證方式＝拿真實 Admin API token 打三發。
  ⚠️ **測試店的 admin 走的是內部 persisted-query API**（`/api/operations/{hash}/{Op}/`），
  **不是公開 Admin GraphQL** ⇒ 用瀏覽器在後台操作抓到的 payload **不能當 parity 依據**。
- 🔴 **`UserError` 是否 `implements DisplayableError` 未確認**：shopify.dev 對它
  **不印 Implements 區塊**（三版、兩種格式皆無），而 `DiscountUserError` 等都明確印出。
  ⇒ **不得假設所有 userErrors 都能用 `... on DisplayableError` fragment 取用**。
  要確認只能對真實 store 跑 introspection。
- 🔴 **鐵律 7 的一致性測試不得斷言 `sales_reversals` 的符號**：報表 UI 明文
  「reversal 顯示為負」，但**沒有任何官方頁面把「UI 顯示符號」與「API 回傳符號」連起來**。
- **`@idempotent` directive 的 SDL 定義是反推的**（shopify.dev 無 directives 索引），
  我方寫的 `directive @idempotent(key: String!) on FIELD` 登記為假設。
- **冪等回放的邊界未定**：官方只說「由當前 DB 狀態重建、非逐字儲存」，
  但「原請求回了非空 userErrors（業務失敗）算不算成功而被快取」**官方沒說** ⇒ S5 要自己定義並標明。
- **`elementIndex` 的並存語義**（若日後要相容第三方客戶端）仍是未知；我方不採用所以不擋路。
- **Shopify payments app 的 REFUND payload 對 zero-decimal 幣別怎麼送**官方沒寫
  （只說一律用小數點分隔、範例只有 CAD "123.00"）⇒ 我方 PSP pack 的 `decimal_string`
  在這一點上**沒有本尊可對齊**，必須逐 PSP 依其自家文檔宣告（鐵律 3 本來就這樣要求）。
- **本輪只改規格、沒有寫任何程式碼**——S4 起才落地。改規格不改實作**不會**造成不一致，
  因為對應的實作根本還不存在；但**下一步一定要接上**，否則規格會領先實作而沒有人發現。
