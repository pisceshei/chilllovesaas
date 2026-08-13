Rails.application.routes.draw do
  get "login" => "sessions#new", as: :login
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  # D5 只有一個正式 Admin API；此 route 必須排在 SPA catch-all 前，避免
  # REST 或 legacy v1 endpoint 意外公開。見 docs/research/28 §0.1。
  post "admin/api/2026-08/graphql.json" => "admin/api/v202608/graphql#execute",
    as: :admin_graphql,
    format: false

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
