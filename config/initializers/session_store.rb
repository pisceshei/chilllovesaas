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
  #
  # 🔴 `DISABLE_FORCE_SSL=1` 的明文過渡期必須連這裡一起關，理由不是「方便」
  #    而是**這個組合會讓登入靜默失效**：Secure cookie 在 http:// 下拿不到 session
  #    ⇒ 每個 request 都是新 session ⇒ CSRF token 永遠對不上 ⇒ POST /login 一律
  #    422「無法完成這項變更」。頁面看起來完全正常、日誌只有一行
  #    "Can't verify CSRF token authenticity."，沒有任何地方會說「因為 cookie 是 Secure」。
  #    實測 2026-08-23 bt3：`GET /login` 連 `Set-Cookie` 都沒有發出。
  # 🔴 fail-secure 方向不變：**未設定該變數就是 Secure**（production 預設）。
  #    TLS 終結就緒後移除變數即回到安全預設，見 `config/environments/production.rb` 同批註釋。
  secure: Rails.env.production? && ENV["DISABLE_FORCE_SSL"] != "1"
