# T13 政策頁（`/policies/{kind}`）本尊形＋`shop.*_policy`／`policy` 物件＋content_for_header 空白骨架更正

> 路線圖 T13（`docs/plans/2026-09-05-全對齊路線圖.md` §2，本包新增列）。取證全文＝`docs/dev/external-facts.md` §G29（hoko.vip 五個 `/policies/*` 快照＋官方 objects/policy／shop＋help 政策頁，2026-09-05）；
> 未取得／範圍外＝`docs/specs/91-pit-register.md` §3.90。worklog／handoff＝`docs/worklog/2026-09-05-政策頁T13.md`、`docs/handoff/2026-09-05-政策頁T13.md`。
> 起點＝T8／T9 乾跑（Kalles／Minimog）露出的引擎缺口 `shop.shipping_policy`，與 audit 快照證實 hoko 有 `pageType "policy"` 頁而我方 404。

## 1. 這是什麼（本尊行為）

- 官方 help（checkout-settings/refund-privacy-tos）：六種政策 Return／Privacy／Terms of service／Shipping／Legal notice／Subscription，路徑 `/policies/refund-policy`、
  `/policies/privacy-policy`、`/policies/terms-of-service`、`/policies/shipping-policy`、`/policies/subscription-policy`；另 hoko 有 `/policies/contact-information` 路徑（404）。
- 官方 Liquid：`shop.policies`（array of policy）、`shop.privacy_policy`／`refund_policy`／`terms_of_service`／`shipping_policy`／`subscription_policy`（policy）；`policy`＝body／id／title／url。
- hoko.vip（2026-09-05）：**只有 privacy-policy 有內容 ⇒ 200**，refund／terms／shipping／contact-information ⇒ **404**（Ella 404 模板）。200 頁：body class `template-policy`
  （Ella 以 `request.page_type` 出 class ⇒ `page_type = "policy"`）、`<title>隐私政策 – 我的商店 3</title>`、`shop-js-analytics {"pageType":"policy"}`、`__st` 只有 a／offset／reqid／pageurl／u
  （無 p／rtyp／rid）、`ShopifyAnalytics.meta.page = {"requestId":…}`（無 pageType）、hreflang 六語言、無 atom／oembed、無 trekkie track 事件。
- 主體＝平台自產、不經主題模板（Ella `<main>{{ content_for_layout }}</main>` 直接包）：

  ```html
  <div class="shopify-policy__container">
    <div class="shopify-policy__title">
      <h1>隐私政策</h1>
    </div>

    <div class="shopify-policy__body">
      <div class="rte">
          <div>
    <p>最后更新时间：2026年9月4日</p>…</div>
      </div>
    </div>
  </div>
  ```
  （body 原文第一行縮排 8 空白、其餘行照存檔原文；容器結尾換行。）
- content_for_header 首節點＝`<link rel="stylesheet" media="all" integrity="sha256-…" crossorigin="anonymous" href="//hoko.vip/cdn/shopifycloud/storefront/assets/storefront/policy-0e156355.css">`
  緊接 perf mark（無換行），再換行接 digital-wallet meta；該 css 294 位元組四條規則（容器 max-width 560px→65ch／置中／左右 20px；標題置中；remote-policy 標題包裝置中＋h1 下 20px；remote-policy 本體下 20px）。

## 2. 具體功能與值域

| 項 | 值域／規則 |
|---|---|
| kind（＝URL handle） | `refund-policy`／`privacy-policy`／`terms-of-service`／`shipping-policy`／`legal-notice`／`subscription-policy`／`contact-information`（`ShopPolicy::KINDS`） |
| 存在判準 | body 非空 ⇒ 頁 200、`shop.{kind}_policy` 非 nil、進 `shop.policies`；未設／空 ⇒ 404／nil／不收錄（hoko 四個 404） |
| title | 平台依語言給定（本尊不可改名；hoko zh-CN「隐私政策」）；先落欄位，字典＝admin 包（91 V） |
| body | HTML（本尊 rte 內容；範本產生或商家自填）；翻譯＝translations 表接（V） |
| `policy.url` | `{url_prefix}/policies/{kind}`（hreflang 六語言皆有前綴形） |
| `shop.policies` 序 | 本尊未觀測 ⇒ KINDS 序（V） |
| page_type | `policy`；`?view=` 不吃；page_title＝title |
| 快取 | 頁級快取 stamp＝該政策 `updated_at`（改內容即換 key） |

## 3. 怎樣做出來（實作落點）

| 檔 | 內容 |
|---|---|
| `db/migrate/20260905120000_create_shop_policies.rb`、`app/models/shop_policy.rb` | 表（shop_id＋kind 唯一）、KINDS、`present_body` scope |
| `app/liquid/theme_engine/drops.rb` | `PolicyDrop`（id／title／body／url）；`ShopDrop` 收 `url_prefix:`，`policies`＋五個具名 |
| `app/liquid/theme_engine/runtime.rb` | `ShopDrop.new(shop, url_prefix:)` |
| `app/liquid/theme_engine/page_renderer.rb` | `resolve` 加 `/policies/:kind`（present_body 才 200）；`policy_markup`（容器逐字）；policy 頁不走模板直接 `render_layout` |
| `app/liquid/theme_engine/page_titles.rb`、`app/services/storefront/page_cache.rb` | page_title＝title；resource stamp |
| `app/services/storefront/content_for_header.rb` | `policy_stylesheet` 首節點；**空白骨架全面照本尊位元組**（§4） |
| `app/assets/storefront/platform/policy.css`、`platform_assets.rb`、`platform_assets_controller.rb`、`config/routes.rb` | 自寫樣式表、雜湊檔名＋SRI、`text/css`、路由 `policy-{8hex}.css` |
| `app/services/render_parity/mirror.rb`、`spec/fixtures/render_parity/hoko.json` | 鏡像店 `policies[]` upsert（倉內短文；本尊全文部署時由快照代入） |
| `app/services/render_parity/normalizer.rb` | `policy-{hash}.css` 雜湊抹除 |
| `spec/requests/storefront_policies_spec.rb`（PL1–PL6）、fixture `t13-policy-probe`／`product.t13.json`、mirror_spec MR1 | 規格 |

## 4. 跨功能／跨頁／前端影響

- **content_for_header 空白骨架更正（影響所有頁型）**：以 hoko 原始位元組逐節點比對空白骨架（scratchpad `t13/cfh_ws_diff.rb`），E19a 有 15 處與本尊不同——
  perf mark 緊接下一節點、`shopify-features` JSON 緊貼標籤、globals `false;</script>` 無換行、modules 旗標單行、shop-js import 結尾空一行、UA 偵測緊接 origin-trials、
  模組形 privacy banner 前空一行且加速結帳樣式 link 緊接、dns-prefetch 前 `\n\n    \n  `、TREKKIE shim 三行、analytics meta 緊接 web pixels、perf-kit 逐行屬性＋`\n></script>`、
  shopify-s／new-cookie 緊接前一 meta。本包全部改齊：商品頁骨架 47/48、政策頁 41/42 相同（唯一剩 MCP script＝工具描述文字我方自寫，鐵律 9）。
  規格 C4／SG1 校準；E19a worklog 追加日期更正。
- **T12 同軸**：head 內 `//host/cdn/...` 五處改用 `asset_host`（本機含埠才載得到）。
- **主題**：Kalles／Minimog 讀 `shop.shipping_policy.body`／`.url`（購物車抽屜、商品頁稅運說明）自此有值；Ella 頁尾政策連結（`shop.policies` 迴圈）自此可出。
- **Admin**：Settings › Policies 編輯頁＝A1（等 audit `settings-3` 證據）；目前只能 runner／console 寫入（scratchpad `t13/seed_policy.rb`）。
- **翻譯**：`translations` 表 resource_type 待加 POLICY（V）；`/zh-hant/policies/*` 目前出來源語言 body。

## 5. 驗證

rspec：PL1–PL6 綠；C1–C9／H1–H6／SG1／JS2／P1–P3／RP1–RP8／TA1–TA10／S 系列回歸綠；閘門表見 worklog。

本機（dev server，mirror 店 seed hoko 快照 body 15,567 位元組）：`/policies/privacy-policy` 200、`/policies/refund-policy` 404、`/zh-hant/policies/privacy-policy` 200；
`__head__` 節點對表 42/42（hoko 政策頁快照）；空白骨架 41/42（MCP 描述文字除外）；商品頁空白骨架 47/48；`render_parity:diff`（hoko 政策頁 vs 本機）：11 段中 8 段 1.000，
`header_default` 0.984／`cart_drawer` 0.988＝顧客帳戶連結（新版帳戶託管 URL vs `/account/login`，T3）、`__head__` 0.987＝字型設定差（T5）＋本包前的樣式表節點（已補）。
bt3 部署後複驗＝收尾 PR。
