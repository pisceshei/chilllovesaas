# Handoff — G6-4a 結帳頁 1:1 複刻（2026-08-31）

## ① 我改了什麼

- 輸入：使用者裁定「完全複製 Shopify 結帳頁所有內容（欄位/按鈕/下拉/CSS/字體/
  顏色/佈局），不得自行發揮」＋參考 URL（測試店 chill.deals 真 checkout，
  Airwallex 已啟、en-us）。base＝main ab476eb。
- 先做 87 號六層實測（`docs/research/87-checkout-page-full-teardown.md`）——
  量測工具鏈兩個坑都在該檔頭註記（字重污染消融、dpr=1.75 邊框折算、
  resize_window 假成功 ⇒ 同源 iframe 法）。斷點雙向逼近：雙欄 1006、併欄 586。
- 再照量測值重構結帳主頁：單表單制（新 POST /submit；307 接 /pay 或 /complete）、
  全地址表單（US 條件欄）、方法盒選中藍環、billing different 展開、側欄摘要、
  手機 accordion。CSS 全自寫（checkout.css --ck-* tokens 逐項註 87 §錨）。
- 驗證：checkout 線 spec 40 例全綠（新 clone spec 5 例）；突變 MUT-A/B2/C/D/E
  全紅復原；本地 dev server 視覺驗證（見 ④ 的已知阻塞）。

## ② 為什麼這樣改

- 文字連字面對齊英文＝使用者本輪明示（覆蓋鐵律 10 的預設；zh 隨多語言線）；
  CSS 同值不同碼＝總方案 G6-4 合規式落法（鐵律 9 不動）。
- 單表單制取代「每段一個更新鈕」：87 實測本尊 Pay now＝一次送出整頁；
  保留 /delivery /payment 舊端點（specs 與既有重驗契約零破壞）。
- 被推翻的假設：①國家下拉不是全球清單（值域＝Markets 啟用國，此店僅 US）；
  ②「+82」不是電話國碼——是方法列品牌 icon 溢出計數 chip；③側欄非 sticky；
  ④選中藍環是 ::before 疊層非 border/box-shadow。

## ③ 還有什麼沒解決

- V-87-1～6（87 §8）：非 US 地址格式／錯誤態三層／hover／品牌 icon 資產／
  combobox＋電話國碼鈕／? tooltip——全登記待補，均不擋本包。
- Sign in→/account/login 404（帳戶線未建）；save_shipping_information 不落庫；
  buyer_accepts_marketing 未傳導 Order；四個付款子頁仍 zh 舊形。
- 本地瀏覽器窗格對 `*.localhost` 子網域導航逾時（兩次 300s）——curl 對
  127.0.0.1＋Host 標頭可通，視覺驗證以此＋生產部署後親測補。

## ④ 下一個人要注意什麼

- 重跑：`bundle exec rspec spec/requests/storefront_checkout_page_clone_spec.rb
  spec/requests/storefront_checkout_{spec,delivery_spec,payment_spec}.rb
  spec/requests/storefront_{psp_payment,order_creation}_spec.rb`。
- 改頁面文案前先讀 87 §2 逐字表——en 字面是裁定值，不是可自行潤飾的草稿。
- checkout.css 值改動必須帶 87 §錨或新量測；別把 --ck-* 換回全站 tokens
  （本頁刻意獨立——量測值 1:1 優先於 23 號 tokens，總方案裁定）。
- 量測輪重跑時：先停用 `STYLE#font-bolder-style` 再讀字重；三寬度用頁內同源
  iframe，不信 resize_window。
- migration 版本號 2026083130xxxx 起跳（290000 已被 psp 欄位包佔用——同日多包
  的撞號坑，本包實撞過）。
