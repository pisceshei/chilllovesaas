# 2026-08-23 — productSet 地基（claim/replay＋第一支 mutation＋對抗審查輪）

> 本輪 worklog：`docs/worklog/2026-08-23-M1-productSet地基.md`（含對抗審查補記）。
> 對接文檔（裁定與跨功能影響的正式落點）：`docs/dev/m1-product-set-foundation.md`。
> 本檔是「這一輪的判斷與教訓」——四段固定，判斷寫全，接手的人不必重新調查。

## ① 我改了什麼

**後端第一條寫入路徑整包落地**（單一 PR，branch `m1/product-create`）：

1. **冪等 claim/replay**（11 §2.1 逐字）：`Idempotency::Guard` 狀態機、
   `IdempotencyKey` model、表形對齊遷移（`20260823000000`：補 `mutation_name`、
   `request_digest`→`params_fingerprint`、刪 response_body/response_digest/
   status_code 三個廢棄欄；空表，全環境安全）。
2. **mutation root 掛載**＋`productSet`（63 §B.4 的 SaveBar 唯一寫入映射）
   v1＝建立態＋隱含變體：`Catalog::SaveProduct`（normalize→validate→commit，
   單一 transaction 寫 products/product_variants/event_outbox）、
   `Catalog::HandleGenerator`（limits handle 區塊全管線）、
   GraphQL input/error 型別、`ProductPolicy#create?`（products.edit）、
   `EventOutbox` model、ProductType 加 `lockVersion`。
3. **規格同步**：65 §B 補 X12 列（admin 金額入向——該表封閉條款要求「先改表」，
   已照做）；91 §3.7 新開（四條登記）；guard spec 反轉＋新增 resolve 靜態掃描
   spec（兌現 2026-08-15 worklog 的 CI 斷言承諾）。
4. **發 PR 前的對抗審查輪**：45-agent 工作流（5 鏡頭並行找問題、每條 finding
   2 個獨立反駁者驗證）→ 17 條確認／3 條被反駁 → 四紅全修＋十黃修＋三黃登記，
   每條紅色配回歸釘。修畢全套 rspec 324 例 0 失敗、rubocop/brakeman 0。

## ② 為什麼這樣改（含被推翻的假設）

**架構級：寫入入口是 productSet 不是 productCreate。**
28 號契約與 `required_for_catalog_create` 都圍著 productCreate 寫，但 63 §B.4
的使用者裁定〔ours〕明確：SaveBar 一次儲存＝一支 productSet 全樹 upsert，
建立與更新同一支。第一輪研究的缺口批判（gap critic）抓到三份報告對此各說各話
——**沒有那一步，這包會照 28 號做成 productCreate，然後在前端接 SaveBar 時發現
價格欄位進不去（B1-5 禁令）而返工**。ProductSetInput 的 variants 子輸入天然
承載價格，禁令射程只在 Product 層 input。

**被推翻的假設一：「productSet 天然冪等，所以 limits 刻意不列入強制清單」。**
那句註釋只對**更新態**成立。無 id 的建立態重放＝憑空多一個商品（handle 自動
尾碼＋title 可合法重複 ⇒ 無業務唯一鍵可兜底）。裁定 D-PS5：條件強制落在
resolver 內（名單機制以 mutation 名為鍵，表達不了「同一支、分態強制」——
這個表達力缺口登記在 91 §3.7）。

**被推翻的假設二：「claim 完全放 transaction 外」（我自己的第一版 D-PS1）。**
對抗審查 confirmed #5 指出：succeeded 落款若在業務 commit 之後另一個
autocommit，「業務已 commit、落款前 process 死掉」的窗口會讓列卡 processing
到 TTL、過期讓位後同 key 重試**把已存在的商品再建一次**——正是冪等要防的事故。
修訂＝三段式：claim INSERT 在外（立即 CONCURRENT 而非 innodb lock wait）、
**succeeded 落款在業務 transaction 內**（同 commit，窗口消滅——兩張表同一個
MySQL 才有這條路可走）、failed 落款在外（rollback 後存活）。

**被推翻的假設三：「failed 重試先比指紋」（我自己的第一版 Guard）。**
11 §2.1(b) 的「failed＝視為未執行、同 key 可重試」，重試帶的正是**修正後**
參數；先比指紋會把每次修正判成 MISMATCH，語義形同虛設。改為 failed 分流先於
指紋比對、指紋隨新嘗試重置。

**被推翻的假設四：「規格說 status 欄叫 status」。**
2026-08-15 兩份 worklog 都寫「規格說 params_fingerprint／status」，但 11 §2.1(a)
的 SQL 區塊逐字是 `state ENUM(...)`——**worklog 對規格的轉述本身錯了一半**。
教訓：改表前把規格原文抓回來逐字對，不要信二手轉述（連自己專案的都不要信）。

**新知（教訓級，接手必讀）：**
- 🔴 **`ActiveRecord::Rollback` 在 joined 巢狀 transaction 裡被靜默吞掉且什麼都
  不回滾**。Guard 外層 transaction＋SaveProduct 內層 transaction 的組合下，
  SaveProduct「rescue 例外回 userErrors」路徑不再觸發真 rollback，變體 INSERT
  失敗前寫入的 product 列會被外層 commit 成**孤兒**。修法＝`requires_new: true`
  （巢狀時 SAVEPOINT）＋業務失敗顯式 `raise ActiveRecord::Rollback`。
  這條是我在對抗審查後自查抓到的——審查找到的是別的原子性問題，修它時引入了
  這個新縫，**重構冪等邊界時必須重新畫一次 transaction 邊界圖**。
- 🔴 **Ruby regex 的 `$` 匹配尾隨換行之前**：limits `decimal_string_regex` 用
  `^$` 錨點 ⇒ 「128.00＋LF」穿過 from_string、在 to_storage 炸
  `Money::ExcessPrecision`（非 ArgumentError）⇒ 一路無人接 ⇒ HTTP 500。
  修法雙防線：錨點改 `\A\z` ＋ parse_money 補 rescue。**同型的
  `psp_decimal_string_regex` 刻意不改**（無外部輸入面，91 §3.7 已登記界線）。
- 🔴 **NFKC 會分解 U+00B4（´）成空格＋combining acute**：撇號刪除步驟排在
  NFKC 後面就永遠刪不到它（得到 bob-s 而非 bobs）。HandleGenerator 的管線
  順序是語義的一部分，不是實作細節。
- **測試端算冪等指紋的兩個坑**（都實踩過）：指紋要照 resolver 的
  `input.to_h`（snake_case）形算，不是 GraphQL 線上格式（camelCase）；
  `mutation_name` 是類別 graphql_name（`"ProductSet"`），不是欄位名。
- **journal.jsonl 的順序與 workflow 腳本的宣告順序無關**——按內容特徵配對，
  不要按索引配對（本輪研究結果檔一度全部貼錯標籤，靠檔頭特徵改回）。

## ③ 還有什麼沒解決

- **PR 尚未開**（本 handoff 與修復同批 commit 後即推送開 PR；CI 兩測綠後照
  D40 自合、`deploy.sh` 上 bt3）。
- **前端「新增商品」頁（PR B）未動工**：對接要點已寫死在 dev doc §4 第二列
  ——送完整樹、建立態必帶 uuid key、金額兩位小數字串、status 顯式 DRAFT、
  三層錯誤都要接。原型側 `PV.isNew` 分流架構、PD_NEW 預設值、SaveBar 狀態機、
  金額 null≠0 的研究已在第一輪 prototype 報告（本 session scratchpad
  `research_prototype.md`；要點已進 dev doc）。
- **v1 射程外**（dev doc §6 全清單）：更新態（lockVersion 全樹比對＋B.5 變體
  身分保持）、具名選項/多變體、初始庫存量通道、auto_publish callback、
  translation base row、CDN 白名單、`reserved_first_segments` 全表檢查、
  letters_dropped 落庫欄位、payload 的 variants selection。
- **11-vs-90 的 `IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED` 語義矛盾**（91 §3.7 第
  1 條）：商品線遵循 11（failed＝同 key 可重試、不發該碼）；**庫存線落地前必須
  先解**，否則兩線對同一個 code 觸發條件不一致。
- 對外入口 http://demo.chilling.com.hk:28080 已通（路由器 28080→bt3:80）；
  TLS 仍未終結（`DISABLE_FORCE_SSL=1` 掛著，接真資料前必須先做）。

## ④ 下一個人要注意什麼

1. **接手第一步**：讀 `docs/dev/m1-product-set-foundation.md`（裁定 D-PS1〜6
   ＋§4 跨功能對接表＋§5 審查輪處置）。改 Guard 的任何交易邊界前先重讀
   D-PS1 的三段式理由——每一段的位置都有一個事故形撐著，挪動任何一段都要
   回答「那個事故形怎麼防」。
2. **新增 mutation 的三義務**在 `mutation_type.rb` 檔頭：①resolve 開頭呼叫
   `enforce_idempotency_contract!`（有靜態掃描 spec 擋）②建立型進 limits 清單
   ③專屬 code enum＋error type（②③目前靠 review，無機械斷言——誠實標示）。
3. **金額入向只有一條路**：65 §B X12（`Money::Decimal.from_string→to_storage`）。
   要新增任何金額跨界點，先改 65 §B 表（封閉條款），再動代碼。
4. **部署**：合併後 `ssh bt3-wan`，`cd /www/wwwroot/chilllove/app &&
   bash scripts/deploy.sh origin/main`；遷移會自動跑（db:prepare）。
   demo 店登入見 `/etc/chilllove/env`。
5. **對抗審查工作流的模式可複用**（scratchpad `product-set-adversarial-review`
   腳本）：5 鏡頭×2 反駁者，寧可漏報不誤報；本輪 20 條原始 finding 反駁掉 3 條，
   全部 17 條確認都是真問題——這個誤報率值得沿用。注意 2 個反駁者曾因模型安全
   閘門失敗（spec-fidelity 鏡頭），該鏡頭那輪等效單反駁者，下次可補跑。
