# Rails cookie 只保存 raw opaque DB-session token。CookieStore 全程加密；刻意
# 不設定 `domain:` 以維持 host-only，並與未來買家 cookie 分離。見
# docs/specs/11 §1、docs/specs/12 F2。
Rails.application.config.session_store :cookie_store,
  key: "_cl_admin",
  expire_after: 30.days,
  httponly: true,
  same_site: :lax,
  # local development/system test 以 HTTP 執行；production 為 HTTPS-only，
  # 因此部署環境一定加 Secure。見 docs/specs/11 §1。
  secure: Rails.env.production?
