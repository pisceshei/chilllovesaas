require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Middleware 實例與 process 同壽命，因此必須直接 require；若交給開發環境
# reload，Rack stack 會殘留舊 class。見 docs/specs/12 F1。
require_relative "../lib/chilllove/tenant_resolver"

# 載入 Gemfile 內屬於目前 Rails groups 的 gems。
Bundler.require(*Rails.groups)

# CHILL LOVE 應用程式的頂層 namespace。
#
# @see HANDOFF.md D1 單體 Rails 技術棧
module Chilllove
  # CHILL LOVE Rails 單體應用程式的集中設定。
  #
  # 設定載入品牌、全域上限與 process-lifetime tenant middleware；啟動時
  # 會讀取 YAML 並建立 middleware stack。見 HANDOFF.md D1/D3 與
  # docs/specs/12 F1。
  class Application < Rails::Application
    # 套用專案建立時 Rails 版本的預設設定。
    config.load_defaults 8.1

    # chilllove 目錄由上方明確 require，不能交給 Zeitwerk reload。
    config.autoload_lib(ignore: %w[assets tasks chilllove])

    # 品牌與操作上限只從設定載入，不在 controller 或 GraphQL type 重複常數。
    # 見 HANDOFF.md D3、docs/research/22 §9.4。
    config.x.brand = config_for(:brand)
    config.x.limits = config_for(:limits)

    # M0 尚無 attachment API；保留 Active Storage engine 供後續媒體里程碑，
    # 但不公開其 REST routes，確保 Admin data plane 只有 GraphQL。見
    # HANDOFF.md D5、docs/research/28 §0.1。
    config.active_storage.draw_routes = false

    # Executor 會在 request 邊界重設 CurrentAttributes，因此 resolver 必須放在
    # 它之後；HostAuthorization 再移到 resolver 後，才能只允許已解析成功的
    # custom domain。tenant context 會完整覆蓋 dispatch 並在 ensure 清除。
    # 見 docs/specs/12 F1/F4。
    config.middleware.insert_after ActionDispatch::Executor, Chilllove::TenantResolver
    config.middleware.move_after Chilllove::TenantResolver, ActionDispatch::HostAuthorization

    # 自訂網域只有在 TenantResolver 以完全相同且驗證過的 host 綁定
    # Current.shop 後才放行；未知 host 已由 resolver 回傳規格要求的 404。
    base_host = Chilllove::TenantResolver.base_host
    config.hosts << ".#{base_host}"
    config.hosts << lambda { |host|
      normalized_host = host.to_s.downcase.delete_suffix(".")
      Current.shop&.custom_domain_verified? && Current.shop.custom_domain.casecmp?(normalized_host)
    }

    # environment-specific 設定可在稍後載入的 config/environments 覆寫。
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # M0 暫不由 generator 自動產生 system test 檔案。
    config.generators.system_tests = nil
  end
end
