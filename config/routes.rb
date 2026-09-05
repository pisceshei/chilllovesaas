Rails.application.routes.draw do
  get "login" => "sessions#new", as: :login
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  # D5 只有一個正式 Admin API；此 route 必須排在 SPA catch-all 前，避免
  # REST 或 legacy v1 endpoint 意外公開。見 docs/research/28 §0.1。
  post "admin/api/2026-08/graphql.json" => "admin/api/v202608/graphql#execute",
    as: :admin_graphql,
    format: false

  # 翻譯 CSV 檔案通道（ML-5b）：檔案上傳／下載走 HTTP 語義，資料讀寫仍只走 GraphQL（D5）。
  # 🔴 必須排在 admin/*path 的 SPA catch-all **之前**，否則會被吃掉變成 SPA 頁面。
  get "admin/translations/export" => "admin/translations#export", as: :admin_translations_export
  post "admin/translations/preview" => "admin/translations#preview", as: :admin_translations_preview
  post "admin/translations/import" => "admin/translations#import", as: :admin_translations_import

  # 檔案通道（第 25 包；B6 presigned POST 的 HTTP 端）。同 CSV 通道：二進位走 HTTP、
  # 資料仍只走 GraphQL（D5）。🔴 必須在 SPA catch-all 之前。
  post "admin/uploads/staged" => "admin/uploads#create_staged", as: :admin_staged_upload
  # 步 15b：主題 zip 匯入（multipart；99 §4 Import theme 對位）。
  post "admin/themes/import" => "admin/themes#import", as: :admin_theme_import
  get "admin/files/:id/blob" => "admin/uploads#show_file", as: :admin_file_blob

  # 包 30（D77）：登入後主題預覽（noindex）。assets 路由必須排在頁面 glob 之前。
  get "admin/store/preview/:theme_id/assets/*file" => "admin/storefront_preview#asset",
      format: false, as: :admin_theme_preview_asset
  # PR-7 即時預覽：未儲存 entry 的單 section 片段渲染
  post "admin/store/preview/:theme_id/draft_section" => "admin/storefront_preview#draft_section",
       as: :admin_preview_draft_section
  # PR-11：全頁草稿渲染（佈景設定/結構/undo 改即見）
  post "admin/store/preview/:theme_id/draft_page" => "admin/storefront_preview#draft_page",
       as: :admin_preview_draft_page
  get "admin/store/preview/:theme_id(/*path)" => "admin/storefront_preview#show",
      format: false, as: :admin_theme_preview

  # 購物車 Ajax 端點（specs/15 F1；`.js` 與裸路徑同義——Ella 用裸形，83 §4.4）。
  # 包 33 後半（A1 收口）：vehicle＝**host 解析的公開端點**（租戶 host 上匿名可用；
  # 平台 host 無租戶 ⇒ 404）。staff 預覽面在同一租戶 host ⇒ 同一組端點自然共用。
  scope format: false do
    get  "cart.js"        => "storefront/cart#show"
    get  "cart.json"      => "storefront/cart#show"
    post "cart/add.js"    => "storefront/cart#add"
    post "cart/add"       => "storefront/cart#add"
    post "cart/change.js" => "storefront/cart#change"
    post "cart/change"    => "storefront/cart#change"
    post "cart/update.js" => "storefront/cart#update"
    post "cart/update"    => "storefront/cart#update"
    post "cart/clear.js"  => "storefront/cart#clear"
    post "cart/clear"     => "storefront/cart#clear"
  end

  # PSP webhook（G6-1a）：租戶 host 上的驗簽端點（HMAC fail-closed；事件收件匣冪等）。
  # 🔴 URL 已對外承諾（使用者已在 Airwallex 後台以 /webhooks/airwallex 建立訂閱）——不得改路徑。
  post "webhooks/airwallex" => "webhooks/airwallex#receive", format: false

  get "admin" => "admin/spa#show", as: :admin_root
  # API namespace 不可 fall through 到 SPA；錯誤 method/version 必須維持
  # no-route 404，避免 client 把 HTML shell 誤判成 API success。
  get "admin/*path" => "admin/spa#show", constraints: lambda { |request|
    !request.path.match?(%r{\A/admin/api(?:/|\z)})
  }

  # `/up` 供 load balancer 與 uptime monitor 判斷 Rails 是否正常啟動。
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA route 留待後續里程碑需要時啟用。
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ── 公開店面（包 33 後半；六步方案步 2）───────────────────────────────────
  # 🔴 只在租戶 host 上存在（TenantResolver 已把 shop_id 寫進 env）；平台 host
  #   落到下面的 admin root。次序＝安全邊界：admin／cart／login 等具名路由在上面
  #   先匹配，storefront catch-all 收尾——它**只**收 GET。
  constraints ->(request) { request.env["chilllove.shop_id"].present? } do
    get "robots.txt" => "storefront/pages#robots", format: false, as: :storefront_robots
    # PR-10：storefront 密碼保護（本尊 private mode）
    get "password" => "storefront/password#show", format: false, as: :storefront_password
    post "password" => "storefront/password#create", format: false
    get "theme-assets/*file" => "storefront/assets#show", format: false, as: :storefront_asset
    # E17：商品 JSON 端點（本尊 `/products/{handle}.js`＋`.json`，hoko.vip 2026-09-05）——放在 catch-all 之前；帶前綴形在下方 scope。
    get "products/:handle.js" => "storefront/products#ajax_js", format: false, as: :storefront_product_js
    get "products/:handle.json" => "storefront/products#rest_json", format: false, as: :storefront_product_json
    # E17：`img_url` 對 nil 的平台無圖佔位（路徑形照本尊；圖片本體我方自繪）
    get "cdn/shopifycloud/storefront/assets/:file" => "storefront/assets#no_image", format: false,
        constraints: { file: /no-image-2048-a2addb12(?:_[0-9x]+)?\.gif/ }, as: :storefront_no_image
    # E17：`country | image_url` 的國旗（本尊 `//cdn.shopify.com/static/images/flags/{cc}.svg`；我方同路徑、MIT flag-icons 圖檔）
    get "cdn/static/images/flags/:cc.svg" => "storefront/assets#flag", format: false,
        constraints: { cc: /[a-z]{2}/ }, as: :storefront_flag
    # E18：動態結帳（本尊 portable-wallets）——語言別模組 `portable-wallets.{lang}.js`＋光 DOM 樣式 `accelerated-checkout-backwards-compat.css`
    # （路徑形照本尊 `/cdn/shopifycloud/portable-wallets/latest/…`，hoko.vip 2026-09-05；本體我方自寫，鐵律 9）
    get "cdn/shopifycloud/portable-wallets/latest/portable-wallets.:lang.js" => "storefront/assets#portable_wallets", format: false,
        constraints: { lang: /[a-z]{2,3}(?:-[a-z]{2,4})?/ }, as: :storefront_portable_wallets
    get "cdn/shopifycloud/portable-wallets/latest/accelerated-checkout-backwards-compat.css" => "storefront/assets#accelerated_checkout_css",
        format: false, as: :storefront_accelerated_checkout_css
    # E18：Storefront API 第一片（`cartCreate`；本尊 `POST /api/unstable/graphql.json?operation_name=cartCreate`）
    post "api/:version/graphql.json" => "storefront/api#graphql", format: false,
         constraints: { version: /unstable|\d{4}-\d{2}/ }, as: :storefront_api_graphql
    # E18：Storefront API cart 的 `checkoutUrl` 落地（本尊 `/cart/c/{token}?key=…` ⇒ 302 結帳頁）
    get "cart/c/:token" => "storefront/cart#checkout_link", format: false,
        constraints: { token: /[A-Za-z0-9_-]+/ }, as: :storefront_cart_checkout_link
    # Ella 修復 PR-2：買家面媒體（真圖鏈輸出端；MediaUrl 產這個形）
    get "media/:id/:filename" => "storefront/media#show", format: false,
        constraints: { id: /\d+/, filename: /[^\/]+/ }, as: :storefront_media
    # SEO 面（包 35）：sitemap 分片（83 §3.6 形）＋ agents/llms 三別名（62 §H.2 同一生成器）。
    get "sitemap.xml" => "storefront/sitemaps#index", format: false, as: :storefront_sitemap
    %w[products collections pages].each do |kind|
      get "sitemap_#{kind}_:n.xml" => "storefront/sitemaps#show", format: false,
          defaults: { kind: }, constraints: { n: /\d+/ }
    end
    get "agents.md" => "storefront/agents#show", format: false, as: :storefront_agents
    get "llms.txt" => "storefront/agents#show", format: false
    get "llms-full.txt" => "storefront/agents#show", format: false
    # localization 表單（包 34；67 §F.2 country+language 兩欄位）：裸與帶前綴兩形。
    # 🔴 E16：POST **與 PUT** 都收——`{% form 'localization' %}` 本尊形自帶隱藏欄 `_method=put`（官方 tags/form 輸出；
    #   我方 FormTag 同形），Rack::MethodOverride 把該 POST 改寫成 PUT ⇒ 只收 POST 的路由回 404（bt3 mirror 店 2026-09-04
    #   實測：帶 `_method=put` 404、不帶 302）。本尊 `PUT /localization` 直打亦 302（hoko.vip 2026-09-04；external-facts §G24）。
    match "localization" => "storefront/localization#create", via: %i[post put], format: false, as: :storefront_localization
    # 結帳線第一包：cart→checkout 建立＋token URL（15 F3；one-page UI 隨後續包）。
    post "checkout" => "storefront/checkouts#create", format: false, as: :storefront_checkout
    # G6 步 7：挽回連結入口（302 回活結帳頁；快照還原＝checkout 本就落庫）。
    # 🔴 放在 :token 之前——"recover" 會被 :token 段吃掉。
    get "checkouts/recover/:recovery_token" => "storefront/checkouts#recover", format: false,
        as: :storefront_checkout_recover
    # G6 步 11：買家帳戶（74 §7 passwordless；非主題化頁——checkout 同法）。
    get "account/login" => "storefront/accounts#login_form", format: false
    post "account/login" => "storefront/accounts#send_code", format: false
    post "account/verify" => "storefront/accounts#verify", format: false
    post "account/logout" => "storefront/accounts#logout", format: false
    get "account" => "storefront/accounts#show", format: false
    get "account/addresses" => "storefront/accounts#addresses", format: false

    # G6 步 9b：折扣碼（結帳頁輸入＋分享連結）。
    post "checkouts/:token/discount" => "storefront/checkouts#apply_discount", format: false,
         as: :storefront_checkout_discount
    get "discount/:code" => "storefront/checkouts#discount_link", format: false,
        as: :storefront_discount_link
    get "checkouts/:token" => "storefront/checkouts#show", format: false, as: :storefront_checkout_show
    # 結帳線第二包：選國＋選運送方式（server 重驗 F3-3；85 §5.3 per-shipment 形）。
    post "checkouts/:token/delivery" => "storefront/checkouts#delivery", format: false,
         as: :storefront_checkout_delivery
    # 結帳線第三包：選付款方式（server 重驗 active；86 §4 實測形）。
    post "checkouts/:token/payment" => "storefront/checkouts#payment", format: false,
         as: :storefront_checkout_payment
    # G6-4：整頁單表單提交（87 號實測：本尊 Pay now＝一次送出全部欄位）。
    # refresh=1 ⇒ 只落庫重渲染（JS 對 select/radio 變更觸發）；否則接續 307 → /pay 或 /complete。
    post "checkouts/:token/submit" => "storefront/checkouts#submit", format: false,
         as: :storefront_checkout_submit
    # G6-0(a) 訂單成立（15-F5/F6）：POST 建單＋GET thank-you。
    # G6-1c：PSP 線上付款（QR 原生流）。/pay=POST（吃 storefront 寫入 throttle）；
    # /pay/status=GET（輪詢，刻意不落 POST throttle bucket）。
    post "checkouts/:token/pay" => "storefront/checkouts#pay", format: false,
         as: :storefront_checkout_pay
    get "checkouts/:token/pay/status" => "storefront/checkouts#pay_status", format: false,
        as: :storefront_checkout_pay_status
    post "checkouts/:token/complete" => "storefront/checkouts#complete", format: false,
         as: :storefront_checkout_complete
    get "checkouts/:token/complete" => "storefront/checkouts#thank_you", format: false,
        as: :storefront_checkout_thank_you
    # 步 14c：文章留言 POST（98 §2 真店形；handle 帶點/中文 ⇒ 寬鬆段限制）。
    post "blogs/:blog_handle/:article_handle/comments" => "storefront/comments#create",
         format: false, as: :storefront_article_comments
    # 步 12b：predictive search 雙形＋recommendations 雙形（96 §4/§5；
    # .json 形回 JSON、裸形收 section_id 回 HTML——25 §5「兩形都要」）。
    get "search/suggest.json" => "storefront/search#suggest_json", format: false
    get "search/suggest" => "storefront/search#suggest_section", format: false
    get "recommendations/products.json" => "storefront/recommendations#products_json", format: false
    get "recommendations/products" => "storefront/recommendations#products_section", format: false
    # 結帳線第三包：cart 運費試算三支（86 §6 官方現值：prepare/async/同步；
    # price＝十進位主單位字串——鐵律 3 序列化層邊界）。
    get  "cart/shipping_rates.json" => "storefront/cart#shipping_rates", format: false
    post "cart/prepare_shipping_rates.json" => "storefront/cart#prepare_shipping_rates", format: false
    get  "cart/async_shipping_rates.json" => "storefront/cart#async_shipping_rates", format: false
    # 🔴 帶前綴的 cart／localization（包 34）：RoutesDrop 對主題吐 `{prefix}/cart/add` 等
    #   帶前綴 URL（67 §F.4），POST 不經 GET catch-all ⇒ 必須顯式收。
    #   constraint 正則＝Markets::UrlPrefix::SEGMENT 的字面複本（routes 載入時機不宜
    #   引用 autoload 常量；漂移由 storefront_i18n_spec 的路由格釘住）。
    #   D80（2026-09-04）：地區段改為可選——共用網域前綴 /zh-hant、子資料夾前綴 /en-ca 兩形都要收；
    #   預設語言無前綴走上面的裸路由。段是否真是前綴由 controller 的 locale_hit 決定（查無 ⇒ 店預設）。
    scope ":locale_prefix", constraints: { locale_prefix: /[a-z]{2,3}(-[a-z]{4})?(-[a-z]{2})?/ },
                            format: false do
      get  "cart.js"        => "storefront/cart#show"
      get  "cart.json"      => "storefront/cart#show"
      post "cart/add.js"    => "storefront/cart#add"
      post "cart/add"       => "storefront/cart#add"
      post "cart/change.js" => "storefront/cart#change"
      post "cart/change"    => "storefront/cart#change"
      post "cart/update.js" => "storefront/cart#update"
      post "cart/update"    => "storefront/cart#update"
      post "cart/clear.js"  => "storefront/cart#clear"
      post "cart/clear"     => "storefront/cart#clear"
      match "localization"  => "storefront/localization#create", via: %i[post put] # E16：`_method=put`（同上）
      post "checkout"       => "storefront/checkouts#create"
      # 86 §6：官方端點形自帶 {locale} 前綴段——帶前綴形必須收。
      get  "cart/shipping_rates.json" => "storefront/cart#shipping_rates"
      post "cart/prepare_shipping_rates.json" => "storefront/cart#prepare_shipping_rates"
      get  "cart/async_shipping_rates.json" => "storefront/cart#async_shipping_rates"
      # 步 12b：Ajax API 官方形自帶 {locale} 前綴（96 §4.1 locale-aware URLs）。
      get "search/suggest.json" => "storefront/search#suggest_json"
      get "search/suggest" => "storefront/search#suggest_section"
      get "recommendations/products.json" => "storefront/recommendations#products_json"
      get "recommendations/products" => "storefront/recommendations#products_section"
      get "products/:handle.js" => "storefront/products#ajax_js" # E17
      get "products/:handle.json" => "storefront/products#rest_json" # E17
      post "blogs/:blog_handle/:article_handle/comments" => "storefront/comments#create"
    end
    get "/" => "storefront/pages#root", as: :storefront_root
    get "*path" => "storefront/pages#show", format: false, as: :storefront_page
  end

  root to: redirect("/admin")
end
