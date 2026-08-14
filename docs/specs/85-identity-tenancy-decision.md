# 85 — 身分表租戶歸屬：兩案影響評估（2026-08-14）

> 🔴 **本檔存在的原因是我的錯誤**：D8／G24 裁定（2026-08-14）寫「M0 的 8 張白名單表還沒建，
> 所以現況沒有違反豁免」——**那句話是錯的**。我當時只確認「沒有 `users` 表」就下結論，
> 沒去看 M0 實際建了什麼。M0 用的命名是 `staff_members`，功能相同，**且已建成商店級**。
>
> 更正後的事實：`roles`／`role_permissions`／`staff_members`／`sessions` 四張表**已存在**，
> 全部 `shop_id NOT NULL`，且已進入 M0 的 51 張表 schema、有 51 個通過的測試依賴它們。
>
> M0 **沒有做錯**——它按當時的鐵律 2「全表帶 shop_id」寫，寫得很嚴謹（見 §1）。
> 是 G24 今天才推翻那條。所以這不是「修 bug」，是**兩個都成立的設計之間選一個**。

---

## §1 現況：M0 的隔離設計比「加個 shop_id 欄」嚴謹得多

不是只有欄位，是**四層一致的機制**：

| 層 | 現況 | 意義 |
|---|---|---|
| **欄位** | 四張表皆 `shop_id NOT NULL` | 基本隔離 |
| **索引** | 每張表都有 `uq_*_tenant_id` ＝ `UNIQUE(shop_id, id)` | 為複合外鍵鋪路 |
| **外鍵** | 🔴 **複合外鍵**：`add_foreign_key "sessions", "staff_members", column: ["shop_id","staff_member_id"], primary_key: ["shop_id","id"]` | **資料庫層保證子表不可跨店引用父表**——這是最強的一層 |
| **應用層** | 四個 model 全部 `acts_as_tenant :shop`（fail-closed），`Session` 另有 `validate :staff_member_belongs_to_shop` | 預設 query/write 全被限制在當前 shop |

依賴這組複合外鍵的還有 `api_tokens` 與 `events`（都以 `["shop_id","staff_member_id"]` 指向 staff_members）。

**唯一性語義也是店級的**：`uq_staff_members_email = UNIQUE(shop_id, email)`
⇒ **同一個 email 可以在不同商店各存在一筆 staff_member**，它們是**四個互不相干的帳號**。

---

## §2 A 案：改 schema，照 G24 走（身分表升為組織層）

### 要動什麼

1. **四張表拆掉 `shop_id`**，並新增 `user_store_assignments(user_id, shop_id, ...)` 表達「誰能進哪些店」。
2. **拆掉三組複合外鍵**（sessions→staff_members、staff_members→roles、role_permissions→roles），
   改為單鍵外鍵；`api_tokens`／`events` 指向 staff_members 的複合外鍵一併改。
3. **移除四個 model 的 `acts_as_tenant :shop`**，改為在應用層自行解析可及 shop 集合。
4. **email 唯一性語義改變**：`UNIQUE(shop_id, email)` → `UNIQUE(email)`
   ⇒ 🔴 **一個 email 全平台只能有一個帳號**，該帳號透過 assignment 進入多間店。
5. 順手補 `staff_members.timezone` / `locale`（R12-V3，反正同批 migration）。

### 代價

- 🔴 **失去資料庫層的跨店引用保護**。現在是 MySQL 自己擋住「A 店的 session 指向 B 店的 staff」；
  改完之後這件事**只剩應用層在擋**。G24 的配套條款寫了「查詢層仍須逐表帶 shop_id 條件」，
  但那是**紀律**不是**約束**——寫錯不會被資料庫擋下來。
- **51 個現有測試要重跑並可能改**（`Session#staff_member_belongs_to_shop` 這類驗證會失去意義或要改寫）。
- **`acts_as_tenant` 的 fail-closed 保護要自己重做一份**。這個 gem 的價值就在「忘記加條件時預設查不到」，
  拿掉之後那個安全網沒了。
- 現在做成本最低（**M1 還沒寫任何 policy**）；等 M1 寫完幾十個 policy 再改會貴很多。

### 換到什麼

- **一個帳號管多店**（本尊的形態）。這是**唯一**能做到「組織擁有人跨店操作」「協作者一次進多店」
  「使用者群組跨店指派」的路。
- 與本尊的 RBAC 模型對齊，R12 查到的四段模型（使用者↔群組↔角色↔權限）才有地基。

---

## §3 B 案：撤回 G24，維持商店級身分表

### 要動什麼

- **schema 一行都不用改**。
- 撤回或大幅縮減 §A 的 G24，把 R12-STRUCT1 改登記為「**裁定偏離**：我方不做組織層身分」。
- 連帶：R12-V9（使用者群組）直接不做；R13-V6（POS 角色）本來就因 G26 不做。

### 代價

- 🔴 **同一個人在兩間店就是兩個帳號**，各自一組密碼與 session。**不能**做「一個登入切換商店」。
- 與本尊模型分歧，且這是**結構性分歧**不是細節——之後每一輪 parity 看到組織層的東西都要重新解釋一次。
- 若日後要支援多店（這是 SaaS 幾乎必然的需求），**那時再改的成本遠高於現在**：
  屆時已有真實資料要遷移、已有數十個 policy 與查詢要改。

### 換到什麼

- **保住資料庫層的隔離保證**與 `acts_as_tenant` 的 fail-closed 安全網。
- M1 立刻可以動工，零 migration。

---

## §4 判斷這件事的關鍵問題（不是技術問題）

**這個 SaaS 要不要支援「一個帳號管多間店」？**

- **要** → A 案。而且**現在做**，因為 M1 還沒寫 policy，這是成本最低的時點。
- **不要／暫時不要** → B 案。但要明白這不是「延後決定」，而是**選擇了單店身分模型**；
  日後翻案的成本會隨著 M1–M5 每寫一個 policy 而上升。

### 我的建議：A 案，但把安全網補回去

理由：
1. **多店是 SaaS 的預設期待**，不是進階功能。目標既然是對齊本尊，而本尊的整個使用者體系
   都建立在組織層上，B 案等於在地基上就分岔。
2. **現在是最便宜的時點**——M1 尚未寫任何 policy，51 個測試都還是骨架級。
3. A 案唯一真正的損失（資料庫層跨店保護）**是可以補回來的**：
   - 業務資料表**完全不動**，它們的 `shop_id` 與複合外鍵照舊——**隔離的主體本來就是業務資料**；
   - 身分表改為單鍵後，在應用層做一個 `Current.accessible_shop_ids` 的 fail-closed helper，
     並在 CI 加一條檢查「業務資料表的查詢一定帶 shop_id」；
   - `user_store_assignments` 本身仍可用複合鍵保證 (user, shop) 的正確性。
4. G24 的配套條款②（「豁免的是表有沒有 shop_id 欄，不是查詢可不可以不帶」）**就是為這件事寫的**——
   現在要做的是把那句話從紀律變成機制。

---

## §5 若採 A 案的動工順序（建議）

1. **先寫 migration 與新 model**，跑通 51 個既有測試（會有失敗，逐個修）。
2. **補 fail-closed helper 與 CI 檢查**（把配套條款②機制化）——這一步不能省，省了 G24 就是漏洞。
3. 同批帶上 `staff_members.timezone` / `locale`（R12-V3 結案）。
4. 然後才開始 M1 的商品 CRUD。

**預估**：1 相對機械（schema 已經很整齊）；2 是真正需要設計的部分；3 順手。

---

## §6 這次錯誤的教訓（寫給下一個人）

- **裁定前要先看現況**。我在 D8 只看了「有沒有 `users` 表」就宣布「白名單表還沒建」，
  但 M0 用的是 `staff_members` 這個名字。**命名不同不代表東西不存在**——
  下次做這類判斷，要 `grep create_table` 看全表清單，不要靠猜某個名字在不在。
- **M0 的設計比我以為的完整**（複合外鍵＋acts_as_tenant fail-closed 四層）。
  推翻它之前要先讀懂它在保護什麼，否則會把一個機制換成一句口號。
