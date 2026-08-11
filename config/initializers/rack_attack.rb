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
Rack::Attack.throttle("admin-login/ip", limit: 10, period: 1.minute) do |request|
  request.ip if login_request.call(request)
end

Rack::Attack.throttle("admin-login/account", limit: 10, period: 10.minutes) do |request|
  next unless login_request.call(request)

  shop_id = request.env["chilllove.shop_id"] || "unresolved"
  email = request.params["email"].to_s.strip.downcase
  Digest::SHA256.hexdigest("#{shop_id}\0#{email}")
rescue Rack::QueryParser::ParameterTypeError
  Digest::SHA256.hexdigest("#{shop_id}\0invalid-parameters")
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
