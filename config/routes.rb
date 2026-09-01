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
  get "admin/files/:id/blob" => "admin/uploads#show_file", as: :admin_file_blob

  # 包 30（D77）：登入後主題預覽（noindex）。assets 路由必須排在頁面 glob 之前。
  get "admin/store/preview/:theme_id/assets/*file" => "admin/storefront_preview#asset",
      format: false, as: :admin_theme_preview_asset
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
    get "theme-assets/*file" => "storefront/assets#show", format: false, as: :storefront_asset
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
    post "localization" => "storefront/localization#create", format: false, as: :storefront_localization
    # 結帳線第一包：cart→checkout 建立＋token URL（15 F3；one-page UI 隨後續包）。
    post "checkout" => "storefront/checkouts#create", format: false, as: :storefront_checkout
    # G6 步 7：挽回連結入口（302 回活結帳頁；快照還原＝checkout 本就落庫）。
    # 🔴 放在 :token 之前——"recover" 會被 :token 段吃掉。
    get "checkouts/recover/:recovery_token" => "storefront/checkouts#recover", format: false,
        as: :storefront_checkout_recover
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
    # 結帳線第三包：cart 運費試算三支（86 §6 官方現值：prepare/async/同步；
    # price＝十進位主單位字串——鐵律 3 序列化層邊界）。
    get  "cart/shipping_rates.json" => "storefront/cart#shipping_rates", format: false
    post "cart/prepare_shipping_rates.json" => "storefront/cart#prepare_shipping_rates", format: false
    get  "cart/async_shipping_rates.json" => "storefront/cart#async_shipping_rates", format: false
    # 🔴 帶前綴的 cart／localization（包 34）：RoutesDrop 對主題吐 `{prefix}/cart/add` 等
    #   帶前綴 URL（67 §F.4），POST 不經 GET catch-all ⇒ 必須顯式收。
    #   constraint 正則＝Markets::UrlPrefix::SEGMENT 的字面複本（routes 載入時機不宜
    #   引用 autoload 常量；漂移由 storefront_i18n_spec 的路由格釘住）。
    scope ":locale_prefix", constraints: { locale_prefix: /[a-z]{2,3}(-[a-z]{4})?-[a-z]{2}/ },
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
      post "localization"   => "storefront/localization#create"
      post "checkout"       => "storefront/checkouts#create"
      # 86 §6：官方端點形自帶 {locale} 前綴段——帶前綴形必須收。
      get  "cart/shipping_rates.json" => "storefront/cart#shipping_rates"
      post "cart/prepare_shipping_rates.json" => "storefront/cart#prepare_shipping_rates"
      get  "cart/async_shipping_rates.json" => "storefront/cart#async_shipping_rates"
    end
    get "/" => "storefront/pages#root", as: :storefront_root
    get "*path" => "storefront/pages#show", format: false, as: :storefront_page
  end

  root to: redirect("/admin")
end
