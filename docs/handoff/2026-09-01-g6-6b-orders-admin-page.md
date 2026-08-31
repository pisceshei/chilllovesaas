# Handoff — G6-6b admin 訂單頁＋orderMarkAsPaid（2026-09-01）

## ① 我改了什麼

- 輸入：20 步計畫步 4；依賴步 3（#227）已合併。base＝main babf596（本分支
  自最新 main 開出——#226 的 pre-squash 分支坑不再犯）。
- 交付：/admin/orders 列表＋/admin/orders/:orderId 詳情（88 號量測骨架的
  資料已備子集）＋orderMarkAsPaid（manual 收款確認；三件套＋limits 登記）＋
  OrderType.itemCount＋i18n 66 鍵×5＋docs/dev/g6-order-line.md（含補 #227 的
  dev 文檔義務）。
- 驗證：後端 12 例＋前端 5 例綠；突變 M1/M2/M4 紅、M5 見③。

## ② 為什麼這樣改

- 頁面欄集只出資料已備欄（誠實子集）——Channel/Delivery status 等欄放到對應
  資料線，不擺空欄。
- markAsPaid 與 MarkPaidFromPsp 分兩服務：PSP 路徑靜默冪等（雙路徑競速），
  admin 路徑顯式報錯（可解釋性）——兩檔頭互引理由。
- 被推翻的假設：FE 狀態字樣斷言沒考慮篩選 option 同字樣（getAllByText 收口）。

## ③ 還有什麼沒解決

- MUT-M5（拔顯式 shop_id）不紅＝with_tenant 預設 scope 兜底；顯式 shop_id
  依鐵律 2 條款②保留。其餘 Pending 見 worklog（步 5 接續面/列表全量包/
  店時區顯示）。

## ④ 下一個人要注意什麼

- 步 5 動刀點：詳情頁行項卡加出貨鈕、金額卡下加退款入口；FulfillmentType
  掛回 OrderType.fulfillments；refund 金額一律 MoneyBag。
- ConfirmDialog 用 `message` prop（非 children）；showToast 單參數；
  Page 無 backTo（自鋪 .cl-back-link）；詳情雙欄用 cl-od-grid 既有類。
- 新 mutation 三件套＋limits idempotency 登記＋`enforce_idempotency_contract!`
  ——照 order_mark_as_paid.rb 抄。
