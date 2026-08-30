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

  root to: redirect("/admin")
end
