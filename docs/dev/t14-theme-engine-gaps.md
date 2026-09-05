# T14 主題引擎缺口批次——門市取貨（store_availability／location／address／format_address）、系列語境上下一個商品、圖片焦點

> 路線圖 T14（`docs/plans/2026-09-05-全對齊路線圖.md` §2）。取證＝`docs/dev/external-facts.md` §G30（官方 objects/store_availability／location／address／
> focal_point／image_presentation／collection／search／shop／variant＋filters/format_address＋help 的 local pickup 頁，2026-09-05）；
> 未取得＝`docs/specs/91-pit-register.md` §3.91。worklog／handoff＝`docs/worklog/2026-09-05-主題引擎缺口T14.md`、`docs/handoff/2026-09-05-主題引擎缺口T14.md`。
> **起點＝證據不是猜測**：Kalles 5.4.2 與 Minimog 6.0.0 的全模板乾跑（`scratchpad/t8/conformance_probe.rb`）列出主題實際讀到、我方沒有的鍵。

## 1. 這是什麼（本尊行為）

### 1.1 門市取貨（三套主題都用）

- 商家面（help，local-pickup 頁逐字）：Settings › Shipping and delivery › **Pickup in store** → 選地點 → **Location status**
  「Let customers pick up orders directly at this location」→ **Expected pickup date**（處理時間下拉）→ **Store transfers** → **Ready for pickup notification**（取貨指示）。
- 買家面（同頁逐字）："the product page displays whether the product is available for pickup at one or more of your pickup locations"；
  多個地點時可 "Check availability at other stores"，顯示 "whether the product is available, and the estimated time frame for pickup"。
- Liquid：`variant.store_availabilities` → array of `store_availability`（`available`／`location`／`pick_up_enabled`／`pick_up_time`）。
  🔴 官方逐字："The array is defined in only the following cases:" —— `variant.selected` 為 true，或該變體是商品的 first available variant。
  `location`（address／id／latitude／longitude／metafields／name）"is only available when one or more locations have local pickup enabled"。
- `format_address`："Generates an HTML address display, with each address component ordered according to the address's locale."
  官方例輸出逐字 `<p>Polina&#39;s Potions, LLC<br>150 Elgin Street<br>8th floor<br>Ottawa ON K2P 1L4<br>Canada</p>`。

### 1.2 系列語境的上／下一個商品

`collection.previous_product`／`next_product`：product 或 nil（"Returns `nil` if there's no previous product."），官方註「可用於商品頁」——
即 `/collections/{handle}/products/{p}` 這個 `within` 形 URL。Kalles `sections/brc-nav-product.liquid` 用它做麵包屑旁的上下一個商品箭頭。

### 1.3 圖片焦點

`image.presentation` → `image_presentation`（"The presentation settings for an image."）→ `focal_point`：
`x`／`y` 是百分比，**"Returns `50` if no focal point is set"**；直接輸出形＝`X% Y%`（官方例 `1.9231% 9.7917%`）。
Kalles `blocks/_media.liquid` 用 `block.settings.image_mb.presentation.focal_point` 做 `object-position`。

## 2. 具體功能與值域

| 介面 | 值域／規則 | 我方 |
|---|---|---|
| `variant.store_availabilities` | array 或 **nil**（不符合那兩種情況時） | 同；集合＝本店 `pick_up_enabled` 的 active 地點，依 `priority, id` 排序 |
| `store_availability.available` | 該地點是否有可售庫存 | 該地點 `inventory_levels.available > 0`；未追蹤庫存 ⇒ 恆 true（同 `variant.available` 判準） |
| `store_availability.pick_up_time` | 顯示字串（本尊下拉的選項值未取得） | `locations.pick_up_time`（上限 64；admin 設定面＝後續包） |
| `location.address` | address 物件 | `AddressDrop`（`locations.address` JSON）；`latitude`／`longitude` 一律 nil（無地址驗證） |
| `address.street`／`name`／`summary` | 官方：兩行地址／名姓／整段摘要的組合 | 同（`, ` 相接） |
| `format_address` | 依 locale 排序的 HTML | company／address1／address2／`city province zip`／country，`<br>` 相接、包 `<p>`、逐段轉義；**逐國順序表未取得（V）** |
| `collection.previous_product`／`next_product` | product 或 nil | 系列語境才有；序＝該系列生效排序；掃描上限 `limits collection.neighbour_scan_limit` |
| `focal_point.x`／`y` | 百分比，未設回 50 | `files.focal_point` JSON；NULL ⇒ 50 |

**顯式宣告為 nil 的非官方屬性**（主題誤用，本尊同樣回 nil——不宣告會被誤計成引擎缺口）：
`collection.terms`（terms 只在 search）、`search.url`／`id`／`current_vendor`／`current_type`（官方 search 只有九個屬性）、
`shop.taxes_included`（含稅旗標在 `cart.taxes_included`）。🔴 `shop.taxes_included` **不得**改成回我方欄位——那會比本尊多出一段稅務文案。

## 3. 怎樣做出來（實作落點）

| 檔 | 內容 |
|---|---|
| `db/migrate/20260906090000_add_pickup_settings_and_focal_point.rb` | `locations.pick_up_enabled`／`pick_up_time`／`pick_up_instructions`；`files.focal_point`（StoredFile 的表名是 `files`） |
| `app/models/location.rb` | `pickup_enabled` scope（active ∧ pick_up_enabled）＋`pick_up_time` 長度驗證 |
| `app/liquid/theme_engine/drops.rb` | 新 `AddressDrop`／`LocationDrop`／`StoreAvailabilityDrop`／`FocalPointDrop`／`ImagePresentationDrop`；`VariantDrop#store_availabilities`；`CollectionDrop#previous_product`／`next_product`／`neighbour_ids`／`terms`；`ImageDrop`／`FileImageDrop`／`PlaceholderImageDrop#presentation`；`SearchDrop` 四個 nil；`ShopDrop#taxes_included` nil |
| `app/liquid/theme_engine/filters.rb` | `format_address` 真實作（原本回空字串） |
| `app/liquid/theme_engine/page_renderer.rb` | `/collections/{handle}/products/{p}` 帶 `collection` 進 assigns（`within_collection`） |
| `config/limits.yml` | `collection.neighbour_scan_limit`（ours） |
| `spec/requests/storefront_pickup_and_context_spec.rb`（PU1–PU6）＋fixture `t14-context-probe`／`product.t14.json` | 規格 |

🔴 **租戶語境**：`store_availabilities` 整段包在 `ActsAsTenant.with_tenant`——`first_available_variant`（讀 `available` ⇒ `inventory_item`）、
`Location` 查詢、`inventory_levels` 都是 tenant-scoped；只包一半會在請求外的呼叫點炸 `NoTenantSet`（PU2／PU3 是這個殺手格）。

## 4. 跨功能／跨頁／前端影響

- **商品頁**：三套主題的 pickup-availability 區塊自此有資料；沒有任何地點開啟取貨時 `store_availabilities` 回 `[]`，主題整區不渲染（同本尊）。
- **系列語境商品頁**：`/collections/{h}/products/{p}` 現在會多查一次系列（`Storefront::Lookup.collection_by_handle`）。系列查無 ⇒ 不帶 collection、商品頁照常 200。
- **頁級快取**：`collection.previous_product` 依系列成員與排序而變；目前快取鍵含商品與主題 stamp，**系列成員變動不會旋轉商品頁的鍵**（登記 91 §3.91 V，與既有系列頁同型）。
- **admin**：地點的取貨設定與圖片焦點都還沒有編輯介面（A1／後續包）；目前只能由 seed／console 寫入。
- **T5**：`address` 欄位在既有資料裡是空 JSON ⇒ `format_address` 出 `<p></p>`；真店資料集擴充時要一併補地點地址。

## 5. 驗證

rspec：`spec/requests/storefront_pickup_and_context_spec.rb` PU1–PU6 綠；`spec/liquid` 全部與 storefront pages／policies 回歸綠（203 例）；閘門表見 worklog。

**conformance 乾跑**（`scratchpad/t8/conformance_probe.rb`，mirror 店資料＋主題 fixture，逐模板渲染收 Liquid error 與 `ThemeEngine::MISSES`）：

| 主題 | 頁 | 例外 | Liquid error | 引擎級 miss 鍵（本包前 → 後） |
|---|---|---|---|---|
| Kalles 5.4.2 | 75 | 0 | 0 | 11 → 3 |
| Minimog 6.0.0 | 57 | 0 | 18 頁（`snippets/social-sharing` 的 `image_url` nil，與本尊同型錯誤） | 8 → 1 |

消除的鍵：`VariantDrop.store_availabilities`／`CollectionDrop.previous_product`／`next_product`／`PlaceholderImageDrop.presentation`／
`ShopDrop.shipping_policy`（T13）／`CollectionDrop.terms`／`SearchDrop.url`／`id`／`current_vendor`／`current_type`／`ShopDrop.taxes_included`。
**剩下的全部是 `FormDrop.*`**：Kalles `snippets/product-ask-question.liquid` 有 `assign name = 'templates.contact.form.name'` 後接 `{% if form[name] %}`，
探針（`scratchpad/t14/probe_name.rb`）證實我方輸出 `<input value="">`——**與本尊同**（`form` 沒有那個屬性 ⇒ nil ⇒ 走 `elsif`），屬主題怪癖而非引擎缺口。

bt3 部署後複驗＝收尾 PR。
