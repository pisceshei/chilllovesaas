# Handoff — G6-7 checkout 資料契約＋顧客線地基（2026-08-31）

## ① 我改了什麼

- 輸入：使用者指令「結帳頁所有欄位獲取的資料。你要做好接口。等後端所有功能模塊
  開發過程中可以完美對接。以及前端客戶管理頁面的對接」。base＝main（#225 之後）。
- 前置研究＝五讀者並行掃描（訂單鏈路/Customer 正典/GraphQL 範本/SPA 範本/原型
  要求），關鍵發現：customers/customer_addresses 兩表 M0 就在 schema 但全 app
  零消費者；orders.customer_id/checkouts.customer_id 恆 NULL；buyer_accepts_marketing
  有採集無消費。
- 交付：訂單成立交易內的 `Customers::UpsertFromCheckout` 管線（去重/consent/
  地址簿/統計增量/關聯回寫）＋`customers`/`customer` GraphQL query（keyset＋
  MoneyV2 首發）＋`/admin/customers` 真列表頁（74 §1 五欄）。
- 驗證：後端 9 例＋前端 4 例新測全綠；八格突變全紅；全套 rspec/vitest/rubocop/
  typecheck/build/brakeman/audit/20 支 invariant 腳本 exit 0。

## ② 為什麼這樣改

- 建檔語義全部錨正典：16 §F6.1（email upsert＋統計三欄）、08 §C.1（每店唯一）、
  08 §C.4（consent append-only ⇒ 只升不降、記 source/時間戳）、06 §2（訂單地址
  是快照 ⇒ 地址簿只在簿空時反向補）。
- MoneyV2Type 現在就立（而不是等 G6-6）：顧客 amountSpent 是第一個對外金額欄，
  鐵律 3 不許裸 cents 出 API——先立型別讓 Order 線共用，避免兩套。
- 被推翻的假設：①「恆建新列」突變殺不紅——DB 唯一鍵兜底 rescue 撈回贏家
  （防線正常，殺手改打正規化層）；②G3/G4 首輪測資選錯（fixture 無法區分突變前後）
  ——修正已註記在 spec 內。

## ③ 還有什麼沒解決

- consent 六值狀態機＋事件表、SMS/WhatsApp、phone 唯一索引、顧客詳情頁、
  customer* mutation、匯入匯出/合併/匿名化/RFM＝顧客模組全量包（worklog 逐項）。
- 既有生產訂單不回填 customer（管線僅對新訂單生效；回填需使用者裁定）。
- nightly 統計對帳 job 未建；F5 併發壓測欠帳掛 G6-6。

## ④ 下一個人要注意什麼

- 重跑：`bundle exec rspec spec/requests/storefront_order_customer_spec.rb
  spec/graphql/customers_contract_spec.rb`＋`pnpm vitest run
  app/frontend/admin/pages/CustomersPage.test.tsx`。
- email 正規化唯一定義點＝`Customer.normalize_email`——customerCreate/匯入等
  新寫入路徑必須走它，否則 K1 的大小寫重複檔會回來。
- 統計三欄唯一寫入端＝`UpsertFromCheckout.bump_stats!`（原子 SQL）；nightly 對帳
  只修漂移不搶寫入權（16 §F6.1）。
- GraphQL 金額欄一律 `Types::MoneyV2Type`（resolver 給 `{cents:, currency:}`）；
  不得再造第二個金額型別。
- 新資源型別三處同批：RESOLVABLE_TYPES＋resolve_type＋type 的 implements Node
  （chilllove_schema 檔頭警告是真的，缺一邊的症狀很難查）。
- i18n 新 key 必須五語包同步（messages.test 強制）；Rails locale 同理五檔。
