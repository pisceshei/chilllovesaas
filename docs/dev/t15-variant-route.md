# T15 `/variants/{id}` 路由——裸形 302 到商品頁、帶 `section_id` 回單一 section

> 路線圖 T15（`docs/plans/2026-09-05-全對齊路線圖.md` §2）。取證＝`docs/dev/external-facts.md` §G31（hoko.vip 實測＋官方 section rendering，2026-09-05）；
> 未取得＝`docs/specs/91-pit-register.md` §3.92。worklog／handoff＝`docs/worklog/2026-09-05-變體路由T15.md`、`docs/handoff/2026-09-05-變體路由T15.md`。
> **起點**：T14 把 `variant.store_availabilities` 做出來後，bt3 上 Ella 的取貨區塊仍停在「無法載入自提資訊」的 fallback——
> 因為 Ella（與 Dawn）的 `assets/pickup-availability.js` 是用 `/variants/{id}/?section_id=pickup-availability` 取內容，而我方沒有這條路由。

## 1. 這是什麼（本尊行為）

hoko.vip 實測（2026-09-05，`curl -sI`）：

| 請求 | 回應 |
|---|---|
| `/variants/44547877830759` | **302**，`location: https://hoko.vip/products/acme-tee?variant=44547877830759` |
| `/variants/44547877830759/?section_id=pickup-availability` | **200** `text/html`，body＝`<div id="shopify-section-pickup-availability" class="shopify-section"></div>`（77 位元組；內容空是因為該店沒有啟用取貨的地點） |

官方 section rendering（ajax/section-rendering，同日）："Sections rendered in response to the `section_id` query parameter are returned
directly as HTML and, like `sections`, this parameter can be used to render a section in the context of any page."
⇒ `/variants/{id}` 是「任何頁面」之一，語境＝**該變體被選取的商品頁**。

主題消費者：Ella `assets/pickup-availability.js` 逐字
`const variantSectionUrl = \`${rootUrl}variants/${variantId}/?section_id=pickup-availability\`;` → `fetch(variantSectionUrl)`；
變體切換時再 fetch 一次（`fetchAvailability(variant.id)`）。Kalles／Minimog 的取貨區塊同一形態。

## 2. 具體功能與值域

- **裸形**（無 `section_id`／`sections`）⇒ 302 到 `{語言前綴}/products/{handle}?variant={id}`。前綴保留（`/zh-hant/variants/{id}` ⇒ `/zh-hant/products/…`）。
- **section 形** ⇒ 200，只回該 section 的 HTML（不是整頁），語境＝該變體被選取的商品頁（`product.selected_variant` 為該變體）。
- **尾斜線**：`/variants/{id}/` 與 `/variants/{id}` 同形（controller 既有的 `chomp("/")`）。
- **查無變體** ⇒ 404（落回一般流程）；**非數字 id** 不吃這條路由（catch-all 走 404）。
- 🔴 **未發布商品的變體**：以 `Storefront::Lookup.product_by_handle` 過濾發布狀態 ⇒ 未發布 ⇒ 404（本尊形未取得，91 §3.92 V）。

## 3. 怎樣做出來（實作落點）

| 檔 | 內容 |
|---|---|
| `app/liquid/theme_engine/page_renderer.rb` | `resolve` 新增 `%r{\A/variants/(\d+)\z}` 分支（**放在商品分支之前**）：查變體 → 該商品頁、`selected_variant_id` ＝該變體 |
| `app/controllers/storefront/pages_controller.rb` | `serve` 開頭：路徑是 `/variants/{id}` 且非 section-rendering 請求 ⇒ 302 到 `{prefix}/products/{handle}?variant={id}` |
| `spec/requests/storefront_variant_route_spec.rb` | VR1–VR4 |

🔴 **`when` 分支的位置**：`/variants/:id` 必須放在 `%r{\A(?:/collections/([^/]+))?/products/([^/]+)\z}` **之前**且是獨立的 `when`。
本包第一版把它插進商品分支的**主體內**，使商品分支被切成兩半（`assigns` 變 nil、每個商品頁 500）——`ruby -c` 不會報錯，只有規格會抓到。

## 4. 跨功能／跨頁／前端影響

- **取貨區塊**：Ella／Kalles／Minimog 的 pickup-availability 自此能取到內容（T14 的 `store_availabilities` 終於走得到）。
- **變體切換**：主題在變體切換時會再打一次這條路由 ⇒ 每次切換一個請求（本尊同）；該回應 `no-store`（section rendering 既有紀律）。
- **301 引擎**：`/variants/{id}` 的 302 走在 404 之前，不與 `RedirectResolver` 衝突（後者只在 404 時查表）。
- **快取**：裸形是 302 不進頁快取；section 形走既有的 section-rendering 分支（`no-store`）。

## 5. 驗證

rspec：VR1–VR4 綠；content_for_header／pages／pickup 回歸綠；閘門表見 worklog。
bt3 部署後複驗＝收尾 PR（要驗 Ella 取貨區塊在有庫存商品上真的出現地點名稱、取貨時間與 `format_address` 的地址）。
