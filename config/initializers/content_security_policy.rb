require "securerandom"

# M0 尚未建立 storefront 或 Stripe.js，因此 production 採 self-only policy；
# development 僅額外允許本機 Vite HMR origin。等 storefront/checkout 落地時，
# 再以 controller policy 分開加入其必要來源。見 docs/specs/11 §1。
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.connect_src :self
    policy.font_src :self, :data
    policy.form_action :self
    policy.frame_ancestors :none
    policy.img_src :self, :data
    policy.object_src :none
    policy.script_src :self
    policy.style_src :self

    next unless Rails.env.development?

    vite_http_sources = %w[http://localhost:3036 http://127.0.0.1:3036]
    vite_websocket_sources = %w[ws://localhost:3036 ws://127.0.0.1:3036]
    policy.script_src :self, *vite_http_sources
    policy.connect_src :self, *vite_http_sources, *vite_websocket_sources
  end

  # React Refresh 的 inline module 由 vite_rails 自動帶 nonce；每個 request
  # 產生獨立值，不把 session identifier 當作 CSP secret。
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
