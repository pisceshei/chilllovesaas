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
    end
    get "/" => "storefront/pages#root", as: :storefront_root
    get "*path" => "storefront/pages#show", format: false, as: :storefront_page
  end

  root to: redirect("/admin")
end
