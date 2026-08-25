require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  #
  # CD-1 walking skeleton（2026-08-23）：bt3 伺服器位於 NAT 後、WAN 443 由另一台
  # 機器佔用，TLS 終結尚未到位。DISABLE_FORCE_SSL=1 時同時關閉 assume_ssl 與
  # force_ssl——只關其一會出事：只關 force_ssl 留 assume_ssl 會把明文請求當成
  # HTTPS 而發出 Secure cookie（瀏覽器在 http:// 下拒收 ⇒ 登入靜默失敗）；
  # 只關 assume_ssl 留 force_ssl 會在無 TLS 環境重導向迴圈。TLS 就緒後移除該
  # 環境變數即回到安全預設（fail-secure：未設定＝全開）。
  #
  # 🔴 **2026-08-25（第 31 包）：TLS 已就緒，bt3 的 `/etc/chilllove/env` 已移除
  #   該變數**，所以這兩行現在都是 true。開關本身**刻意保留**——它是「TLS 壞掉時
  #   還能把站救回明文」的唯一退路，也是本機／LAN 直連 bt3 時的逃生口。
  #   🔴 要再開它之前先看 `config/deploy/nginx-chilllove.conf` 的 `map` 那段：
  #   前置機（.187）送 `X-Forwarded-Proto: https`，bt3 必須**透傳**而不是用自己的
  #   `$scheme`（那一段是明文，$scheme 恆為 http）；照抄 $scheme 會讓 force_ssl
  #   進入無限轉址迴圈。兩者是一組，不能只改一邊。
  config.assume_ssl = ENV["DISABLE_FORCE_SSL"] != "1"

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ENV["DISABLE_FORCE_SSL"] != "1"

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
