require "digest"

# test 以外由 Rack::Attack 使用 Solid Cache；Rails test cache 是 NullStore，
# 因此測試改用私有 MemoryStore，讓 request spec 保持 deterministic。
Rack::Attack.cache.store = if Rails.env.test?
  ActiveSupport::Cache::MemoryStore.new
else
  Rails.cache
end

login_request = lambda do |request|
  request.post? && request.path == "/login"
end

# 兩組獨立 key 分別攔截單一攻擊 IP 與針對已知帳號的分散式攻擊；帳號 key
# 使用 resolver 寫入的 shop_id，讓同店子網域與 custom domain 共用額度。
# email 進入 cache key 前先 hash，避免 PII 落入 cache。見 docs/specs/12 F2。
# 限流值一律讀 limits.yml `auth:` 區塊（鐵律 6；原骨架硬編碼 10/1min 與
# 10/10min，2026-08-13 移植時外移）。
auth_limits = Rails.configuration.x.limits.fetch(:auth)
per_ip = auth_limits.fetch(:admin_login_throttle_per_ip)
per_account = auth_limits.fetch(:admin_login_throttle_per_account)

Rack::Attack.throttle("admin-login/ip",
  limit: Integer(per_ip.fetch(:limit)),
  period: Integer(per_ip.fetch(:period_seconds)).seconds) do |request|
  request.ip if login_request.call(request)
end

Rack::Attack.throttle("admin-login/account",
  limit: Integer(per_account.fetch(:limit)),
  period: Integer(per_account.fetch(:period_seconds)).seconds) do |request|
  next unless login_request.call(request)

  shop_id = request.env["chilllove.shop_id"] || "unresolved"
  email = request.params["email"].to_s.strip.downcase
  Digest::SHA256.hexdigest("#{shop_id}\0#{email}")
rescue Rack::QueryParser::ParameterTypeError
  Digest::SHA256.hexdigest("#{shop_id}\0invalid-parameters")
end

# 公開店面限流（包 33 後半；limits `storefront.rate_limits`——本尊 cart 端點
# 有 bot 牆 429，83 §12.5 實測，我方對位）。只作用於租戶 host（env 有 shop_id）。
sf_limits = Rails.configuration.x.limits.fetch(:storefront).fetch(:rate_limits)
cart_ip = sf_limits.fetch(:cart_writes_per_ip)
page_ip = sf_limits.fetch(:page_views_per_ip)

Rack::Attack.throttle("storefront-cart/ip",
  limit: Integer(cart_ip.fetch(:limit)),
  period: Integer(cart_ip.fetch(:period_seconds)).seconds) do |request|
  next unless request.env["chilllove.shop_id"]
  next unless request.post?

  # 帶前綴形（/zh-hant/cart/add、/en-ca/localization——包 34 路由；D80 地區段可選）同樣計數。
  path = request.path.sub(%r{\A/[a-z]{2,3}(-[a-z]{4})?(-[a-z]{2})?(?=/)}, "")
  # /checkouts/<token>/delivery（第二包選費率）與 /checkout 同屬結帳寫入面。
  request.ip if path.start_with?("/cart/", "/checkouts/") || path == "/localization" || path == "/checkout"
end

Rack::Attack.throttle("storefront-page/ip",
  limit: Integer(page_ip.fetch(:limit)),
  period: Integer(page_ip.fetch(:period_seconds)).seconds) do |request|
  next unless request.env["chilllove.shop_id"]
  # 只數店面頁面（GET 非 /admin、非 /cart、非資產）；資產不限流（一頁數十個資產請求）。
  next unless request.get?
  next if request.path.start_with?("/admin", "/cart", "/theme-assets", "/login", "/up")

  request.ip
end

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env.fetch("rack.attack.match_data", {})
  retry_after = match_data.fetch(:period, 60).to_i

  [
    429,
    {
      "Content-Type" => "application/json; charset=utf-8",
      "Retry-After" => retry_after.to_s,
      "Cache-Control" => "no-store"
    },
    [ { errors: [ { code: "TOO_MANY_ATTEMPTS", message: "嘗試次數過多，請稍後再試。" } ] }.to_json ]
  ]
end
