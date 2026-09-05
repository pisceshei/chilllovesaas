# Handoff：content_for_header 完整本尊形 E19a（路線圖 T10）——2026-09-05

> 讀法：`docs/plans/2026-09-05-全對齊路線圖.md` §0 → 本檔 → `docs/dev/e19-content-for-header.md` → `docs/dev/external-facts.md` §G27 →
> `docs/specs/91-pit-register.md` §3.88 → `docs/worklog/2026-09-05-content_for_header本尊形E19.md`。

## ① 我改了什麼

- **目標**：把 `{{ content_for_header }}` 從「canonical＋hreflang＋JSON-LD＋E18 段」改成本尊的完整節點序列（商品頁 38＋尾段 10），含頁型變體、資料節點、
  每請求值、平台 stub 資產、`{% javascript %}` 編譯資產、oEmbed／Atom 端點。base＝`origin/main 4b86d4eb`（E18 收尾之後）。
- **輸入／證據**：hoko.vip 74 頁 HTML 快照（scratchpad `audit/storefront/*-hoko.html`、`t10/cfh_*.html`、`cfh_tags.json`、`nodes_product.txt`、
  `after_cfh_product_nodes.txt`）、CDN 檔（compiled scripts、bundle、backwards-compat css、preloads.js）、端點 curl（oembed／atom 五語言／sf_private_access_tokens／
  digital_wallets／api/collect）、執行期 `typeof Shopify.*` 探針、官方文檔四頁；全部落 §G27。
- **做了**：見 worklog Changes 表；檔案清單與數量以 `git diff --stat origin/main..HEAD` 為準（不在此重抄）。
- **驗證輸出**：rspec C1–C9 綠、SEO／dynamic checkout／render_parity／page_renderer 回歸綠（閘門表見 worklog）；bt3 對表待收尾 PR。

## ② 為什麼這樣改

- **本尊 head 不是「幾個 SEO 標籤」而是一整段平台注入**：E16 把 `__head__` 登記成 ⚪ 是因為當時無法逐節點取證；本包用 74 頁快照把節點序、變體判準、資料形全部落地，
  差異就從「不可觀測」變成「可對表」。
- **平台不注 canonical／JSON-LD**：hoko 每頁恰一個 canonical（Ella theme.liquid 自出）、JSON-LD 只在 body（主題 schema snippet）——包 35 的假設被證偽，
  `Seo::HeadTags` 退場、fixture layout 補主題 canonical。
- **延遲組裝**：模組形／cart.bootstrap 形與 `data-sections` 取決於 body 渲染結果 ⇒ `Lazy` drop 在 layout 渲染時才 build。
- **placeholder 而非關快取**：`__st.reqid`／`u`／`shopify-y|s` 每請求不同，但整頁快取要留 ⇒ 快取存 placeholder、controller 代入。
- **本體自寫**：鐵律 9 不抄本尊 JS；主題依賴的只有介面名（`Shopify.loadFeatures`／`PaymentButton`／`captcha`／`analytics`…），Normalizer 把本體視為替身。
- **被推翻的假設**：①「`Shopify.bind`／`setSelectorByValue`… 是平台全域」——錯，Ella global.js 自定義（grep＋執行期 typeof）；PR-3 的 ours 擴充移除。
  ②「動態結帳段每頁同形」（E18）——錯，非商品頁走 `cart.bootstrap`。③「`cdn.shopify.com/...` 與 `host/cdn/...` 是不同路徑」——同一資產兩形並存，
  Normalizer 對映 `cdn.shopify.com/` ⇒ `/cdn/`。

## ③ 還有什麼沒解決

- bt3 部署後 `__head__` 逐節點對表未做（收尾 PR）。
- E19b 行為對位（同意 API／驗證碼／web pixels／收集端落庫／`/api/mcp`）。
- 91 §3.88 V 清單；T12（主題資產 URL 本尊形）另包。

## ④ 下一個人要注意什麼

- **重跑**：`bundle exec rspec spec/requests/storefront_content_for_header_spec.rb`；本機看 head：`curl -s http://mirror.lvh.me:3000/products/acme-tee | sed -n '/content_for_header.start/,/new-cookie-storage-activated/p'`。
- 🔴 改 `app/assets/storefront/platform/*.js` 後檔名雜湊會變（常量在啟動時算）⇒ 重啟 dev server；舊 HTML 引用的檔名 404 是設計（不回錯本體）。
- 🔴 本尊 script 本體**不得抄入**；要加節點先到 §G27 找證據，沒有就登記 V。
- 🔴 Bash 長 heredoc 含引號會整段解析失敗——補丁寫成檔案再跑（scratchpad `t10/patch_e19a*.py` 為例）。
- 停止條件：本包合併＋bt3 `__head__` 對表記回 worklog／handoff（收尾 PR）即結束；E19b／T11／T12 另開包。
