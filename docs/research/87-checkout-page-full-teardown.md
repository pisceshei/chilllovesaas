# 87 — 本尊結帳頁六層實測 teardown（G6-4 1:1 複刻的量測基準）

> 取證：2026-08-31。對象＝測試店 chill-love-u5q5mnzq 的**真實 open checkout**
> （chill.deals `/checkouts/cn/<token>/en-us`，Airwallex custom provider 已啟、
> preview_theme_id=165451858155＝Ella；購物車＝1 件、HKD $188.00）。
> 工具＝本地 Chrome（使用者登入態）＋頁內 JS 量測；**三寬度走同源 iframe 法**
> （`resize_window` 在本機回報成功但 `innerWidth` 不變——量測環境污染登記在案，
> 此輪以頁內注入 `<iframe src=location.href>` 取代，同源可直讀 computed style）。
> 🔴 **本機兩個已中和的量測污染**：①Chrome 擴充 `STYLE#font-bolder-style` 注入
> `font-weight:500 !important`＋`text-shadow`——**全部字重量測皆在停用該節點後取得**
> （探針：inline 700/400 均被壓 500 ⇒ 停用後探針回 700）；②devicePixelRatio=1.75
> ⇒ 1px 邊框 computed 回 0.571429px（floor(1×1.75)/1.75）——**本檔一律記宣告值**。
> 合規式落法（總方案 G6-4 裁定）：結構/行為/值域/量測值 1:1；CSS 由量測值自寫
> （同值不同碼）；不抄本尊 CSS 源碼與圖片資產。UI 標籤文字＝功能性短語，照使用者
> 2026-08-31 裁定連字面對齊（登記於本輪 worklog）。

## §1 架構：頁面骨架與區塊序

```
<body>
├ header（白底 h65、底部髮絲線 #dedede；logo=店名文字連結，20px/600，
│         與左欄內容左緣對齊）
├ 手機 accordion 列（僅 <1006px；見 §6）
├ 雙欄容器（≥1006px）
│ ├ 左欄（白底）＜main＞
│ │ ├ h1 sr-only（"<店名> Checkout"——視覺上只有 header logo）
│ │ ├ Contact 區（h2 + 右側 Sign in 連結同列）
│ │ │ ├ Email 欄（浮動 label＋右側 ? icon 鈕 18×18）
│ │ │ └ checkbox「Email me with news and offers」
│ │ ├ Delivery 區
│ │ │ ├ Country/Region select（永遠浮標）
│ │ │ ├ First name ｜ Last name（2 欄）
│ │ │ ├ Address（右側放大鏡 icon＝自動完成暗示）
│ │ │ ├ Apartment, suite, etc. (optional)
│ │ │ ├ City ｜ State(select) ｜ ZIP code（3 欄；值域見 §3）
│ │ │ ├ Phone (optional)（右側 ? icon）
│ │ │ └ checkbox「Save this information for next time」
│ │ ├ Shipping method 區（未填地址＝灰盒占位；見 §4）
│ │ ├ Payment 區（h2＋副標＋方法盒＋redirect 面板）
│ │ ├ Billing address 區（h3＋兩列 radio 組；different ⇒ 展開地址表單）
│ │ ├ h2 sr-only「Finalize order」＋ Pay now 鈕
│ │ └ footer（頂部髮絲線＋Privacy policy 連結）
│ └ 右欄（#f5f5f5 底、左緣髮絲線【左半 border-right 1px #dedede】，
│         灰底延伸到視窗右緣）＜aside＞
│   ├ h2 sr-only「Order summary」（桌機無可見標題）
│   ├ 行項列（64px 縮圖＋數量 badge＋標題＋右側價格）
│   ├ Cost summary（sr 標題）：Subtotal／Shipping 列
│   └ Total 列（左 Total 18/600；右「HKD」12px 灰＋$188.00 18/600）
```

- 桌機側欄**非 sticky**（祖先鏈 position 全非 sticky/fixed——實測）。
- 無折扣碼輸入欄（此店未啟用折扣；input 掃描 0 命中）。**條件性控件**：
  折扣欄存在與否隨商店設定——我方對位＝折扣線接上時才render。
- 無 Express checkout 區（僅 custom provider 時本尊不渲染錢包快捷列；
  input/button 全掃無 Shop Pay/PayPal 鈕）。

## §2 逐字文案（en-us；主欄 innerText 全量）

Contact／Sign in／Email／Used for your order confirmation and cart reminders／
Email me with news and offers／Delivery／Country/Region／First name／Last name／
Address／Apartment, suite, etc. (optional)／City／State／ZIP code／Phone (optional)／
Save this information for next time／Shipping method／
Enter your shipping address to view available shipping methods.／Payment／
All transactions are secure and encrypted.／Billing address／
Same as shipping address／Use a different billing address／Pay now／Privacy policy／
You'll be redirected to Additional payment methods to complete your purchase.
（redirect 句式＝`You'll be redirected to <方法名> to complete your purchase.`）

側欄：Order summary／Shopping cart／Cost summary（皆 sr）／Subtotal／Shipping／
Enter shipping address（Shipping 值的未填態）／Total／HKD。
aria：`More information about how your contact info is used`（email ?）、
`More information about Phone`（phone ?）、`Skip to content`。

## §3 欄位與值域窮舉

| # | 控件 | name | type | autocomplete | required | placeholder/label |
|---|------|------|------|--------------|----------|-------------------|
| 1 | Email | email | email | shipping email | ✓ | Email |
| 2 | 行銷 checkbox | marketing_opt_in | checkbox | — | — | Email me with news and offers |
| 3 | 國家 | countryCode | select | shipping country-name | ✓ | Country/Region |
| 4 | 名 | firstName | text | shipping given-name | ✓ | First name |
| 5 | 姓 | lastName | text | shipping family-name | ✓ | Last name |
| 6 | 地址 | address1 | text | shipping address-line1 | ✓ | Address |
| 7 | 地址 2 | address2 | text | shipping address-line2 | — | Apartment, suite, etc. (optional) |
| 8 | 城市 | city | text | shipping address-level2 | ✓ | City |
| 9 | 州 | zone | select | shipping address-level1 | ✓ | State |
| 10 | 郵遞區號 | postalCode | text | shipping postal-code | ✓ | ZIP code |
| 11 | 電話 | phone | tel | shipping tel-national | — | Phone (optional) |
| 12 | 儲存資訊 | save_shipping_information | checkbox | — | — | Save this information for next time |
| 13 | 帳單模式 | billing_address_selector | radio×2 | — | — | Same as shipping address／Use a different… |
| 14 | 提交 | checkout-pay-button (id) | submit | — | — | Pay now |

- 🔴 **countryCode 值域＝商店 Markets 啟用國集合**（此店僅 `US:United States`，
  TOTAL=1）——不是全球清單。我方對位＝sellable_countries（已同構）。
- zone（US State）63 項：首項空白占位＋62 值（AL…WY 50 州＋DC＋PR/GU/AS/MP/VI/
  FM/MH/PW＋AA/AE/AP 軍郵）。值＝二碼、text＝全名（`DC:Washington DC`）。
- 帳單 different 展開＝第二套地址表單（aria-hidden 收合預載；欄位同 Delivery，
  country 是 combobox 形、電話帶國碼鈕）——我方以同欄位組實作。
- State/ZIP 標籤與欄位組合**依國家而變**（僅 US 有實測；其他國家的官方格式此輪
  不可測——店只開 US market。V-87-1）。

## §4 元件量測（宣告值；字重＝消融後真值）

**基底**：字族 `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica,
Arial, sans-serif`＋emoji 補集；root/body 12px（實際控件皆顯式 14px）；
行高 18.9px（=1.35）。色板：黑 `#000`／muted `#707070`（左欄）與 `#666`（側欄）／
髮絲線 `#dedede`／面 `#f5f5f5`／redirect 面板 `rgba(0,0,0,0.043)`／
accent 藍 `#005bd1`／選中列底 `#f5f6ff`／縮圖底 `#ededed`。圓角：欄位/按鈕/盒 12px、
badge 8px、+82 chip 3px。

| 元件 | 量測 |
|------|------|
| h1 logo | 20px/600 lh24 黑 |
| h2 區標 | 20px/600 lh24；區塊縱距（stack rowGap）20px、區與區視覺間距 ~38px |
| h3（Billing address） | 16px/600 lh19.2；與盒距 29px |
| h3（方法名） | 14px/600 |
| 輸入框 | h47（select h49）、border 1px #dedede、r12、白底、值 14px/500、pad-x 10+wrap、caret 黑 |
| 浮動 label | 12px span（a11y label 另存 14px）；select 恆浮、input 填值後浮 |
| placeholder | #707070 |
| focus | wrapper outline 3px 黑（宣告）、input 自身 outline 0 |
| 欄位縱橫距 | grid gap 11px（名/姓 2 欄 gap 11、City/State/ZIP 3 欄） |
| checkbox | 18×18、自繪（appearance:none）、r~5、勾選＝藍 #005bd1 |
| radio | 18×18 自繪；選中＝藍環 border 6px #005bd1（白心） |
| Sign in／連結 | 14px/400 #005bd1 underline |
| muted 說明 | 14px/500 #707070（"Used for…"／"All transactions…"） |
| Shipping 占位盒 | bg #f5f5f5、r12、pad 16、文字 14 #707070、text-align start、h51 |
| 方法盒 | border 1px #dedede r12 白底；方法列 h50（pad 14）＋redirect 面板 h66 |
| 選中列 | bg #f5f6ff＋**::before 疊 1px #005bd1 藍環**（radius 同步 11/12） |
| 方法列右側 | 品牌 icon 38×24 imgs＋溢出 chip「+N」（白底、border 1px rgba(0,0,0,.07)、r3、14px、**內層字藍 #005bd1**）；點開＝浮層 4 欄 icon 網格 |
| redirect 面板 | bg rgba(0,0,0,0.043)、文字 14 黑置中、h66 |
| Billing 兩列組 | 首列 r12 12 0 0、次列 r0 0 12 12、列 h47/48、選中同上藍環＋#f5f6ff |
| Pay now | 全寬×h50、bg #005bd1、白字 14px/600、r12 |
| footer | 頂部髮絲線 #dedede；Privacy policy 14 #005bd1 underline |
| ? icon 鈕 | 18×18 svg（圓問號），黑 |
| select chevron | 10×10 svg 右緣 |

**側欄**：內容寬 400（容器 480 含 40px 內距）；縮圖 64×64 r16 bg #ededed；
數量 badge 20×20 黑底 r8 白字 12px（縮圖右上角疊）；行項標題 14/400 lh18.9、
價格右列 14/400；行項→cost 區距 21px、cost 列距 7px；Subtotal 標/值 14/400、
Shipping 未填值 14 #666；Total 標 18/600、值 18/600、「HKD」12/400 #666 前綴。
金額顯示＝`$188.00`（幣別符號；code 只在 Total 前綴出現）。

## §5 版面幾何（桌機，vw 1951）

- 分欄線位置 x=1026 ≈ `calc(50% + 50px)`（1951/2+50.5）；左半白、右半 #f5f5f5
  **灰底延伸到視窗右緣**；豎線＝左半 `border-right 1px #dedede`。
- 左欄內容右靠分欄線：max-width ≈500、與分欄線距 41px（x 486…985）。
- 右欄內容左靠：pad-left 40 ⇒ x1066、寬 400。
- header h65、logo x＝左欄內容 x（486）。單欄模式（<1006）內容 max-width 552
  置中（768 實測 x98 w552；1000 實測 x214 w552）。

## §6 三寬度 RWD（同源 iframe 實測）

| 條件 | 實測 |
|------|------|
| 雙欄斷點 | **≥1006px**（1005 hide／1006 show；雙向逼近）|
| 表單併欄斷點 | **≥586px**（585 stack／586 2col）|
| 390 | 全部單欄（姓名也不併欄）；main pad-x 14；accordion 列現身；pay 鈕全寬 342×50；logo 靠左 x14；header h65 |
| 768/1000 | 單欄置中 max-w 552；表單 2col/3col；accordion 仍在 |
| accordion 列 | 全寬 bg #f5f5f5、h64、上下髮絲線；左「Order summary ⌄」14px 藍＋chevron、右合計 14~/600 黑；aria-expanded 切換展開行項＋cost summary |

## §7 network 取證（14.3 誠實登記）

- 州 select 變更＝僅遙測（`/unstable/produce_batch`、`/v1/logs`、`/v1/metrics`），
  **不打 checkout GraphQL**；地址協商（Proposal）需完整地址才觸發——本輪不填真
  地址不觸發（不污染使用者活車）。persisted query 全文不可觀測（14.3）。
- 我方對位：欄位變更走我方 `/delivery`／`/payment` POST（28 號契約自定、行為對位）。

## §8 V 項（未取得/待補）

- **V-87-1** 非 US 國家的地址格式（標籤/欄位組合/州值域）：店只開 US market，
  測不到。方法＝使用者在測試店 Markets 加國家後重測。
- **V-87-2** 錯誤態三層（訊息逐字/欄位紅框/摘要）：合成 blur 不觸發其 React 驗證，
  Pay now 點擊被權限層擋。方法＝使用者手動觸發一次空表單提交供量測。
- **V-87-3** hover/active 態（Pay 鈕 hover 深藍等）：computed 無法讀 pseudo-class；
  方法＝devtools force state。
- **V-87-4** 付款方式品牌 icon 資產：本尊用其 CDN svg（不可抄）；我方需自備
  官方品牌資源包（各品牌 brand kit），本輪先以純文字列對位。
- **V-87-5** 州 combobox（帳單表單的 country 是 combobox 形）與電話國碼鈕的
  展開行為——收合態預載，未展開實測。
- **V-87-6** email/phone「?」tooltip 的浮層文案與樣式（未點開——aria-label 已收）。
