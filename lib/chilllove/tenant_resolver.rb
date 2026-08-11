# frozen_string_literal: true

# CHILL LOVE 後端基礎元件的 namespace。
#
# @see HANDOFF.md D1 單體 Rails 技術棧
module Chilllove
  # 在 Rails dispatch 前，只依 `request.host` 解析一個租戶。
  #
  # 平台主網域與保留的 lvh.me 子網域會以無租戶狀態繼續；未知租戶 Host
  # 回傳 404。每次呼叫都會設定 request-local tenant，並在 ensure 清除
  # Current 與 ActsAsTenant，避免 thread/fiber 重用時洩漏租戶狀態。
  #
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F1, F4
  class TenantResolver
    CACHE_TTL = 5.minutes
    CACHE_NAMESPACE = "tenant-by-host-v1"
    VALID_SUBDOMAIN = /\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z/
    RESERVED_SUBDOMAINS = %w[
      www admin api app assets auth billing blog cache cdn checkout dashboard
      dev docs events ftp graphql help imap jobs login logout mail media merchant
      merchants mx ns1 ns2 owner partner partners payments platform pop queue
      register search shop signup smtp staff staging static status store stores
      support test webhooks
    ].freeze
    PLATFORM_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    # 取得租戶子網域使用的平台 canonical base host。
    #
    # @return [String] 小寫且不含結尾句點的 DNS host
    # @raise [KeyError] production 未提供 `CHILLLOVE_BASE_HOST` 時 fail fast
    # @note 副作用：無；會讀取 Rails environment 與環境變數。
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F1
    def self.base_host
      host = if Rails.env.production?
        ENV.fetch("CHILLLOVE_BASE_HOST")
      else
        ENV.fetch("CHILLLOVE_BASE_HOST", "lvh.me")
      end
      raise KeyError, "CHILLLOVE_BASE_HOST cannot be blank" if host.blank?

      host.downcase.delete_suffix(".")
    end

    # 建立正規化 host 對應的共享快取 key。
    #
    # @param host [String] 已正規化的 request host
    # @return [Array<String>] 可供 Solid Cache 使用的 namespace key
    # @note 副作用：無。
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F1
    def self.cache_key(host)
      [ CACHE_NAMESPACE, host ]
    end

    # 建立與 process 同壽命的 Rack middleware 實例。
    #
    # @param app [#call] 下游 Rack application
    # @param cache [#fetch] host 查詢快取；測試時可注入替身
    # @return [TenantResolver] middleware 實例
    # @note 副作用：保存下游 application 與 cache 參照，不查詢資料庫。
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F1
    def initialize(app, cache: Rails.cache)
      @app = app
      @cache = cache
    end

    # 解析 request tenant、呼叫下游 application，最後一定清除 context。
    #
    # @param env [Hash] Rack environment
    # @return [Array] Rack 的 `[status, headers, body]` response tuple
    # @raise [StandardError] 清理 tenant context 後原樣拋出下游錯誤
    # @note 副作用：可能讀取 cache/Shop、設定 `Current.shop` 與
    #   `ActsAsTenant.current_tenant`，並在 ensure 還原為空值。
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F1, F4
    def call(env)
      clear_context!
      request = ActionDispatch::Request.new(env)
      host = normalize_host(request.host)

      return @app.call(env) if platform_host?(host)

      shop = shop_for(host)
      return not_found_response unless shop

      Current.shop = shop
      ActsAsTenant.current_tenant = shop
      env["chilllove.shop_id"] = shop.id
      @app.call(env)
    ensure
      clear_context!
    end

    private

    def normalize_host(host)
      host.to_s.downcase.delete_suffix(".")
    end

    def platform_host?(host)
      return true if PLATFORM_HOSTS.include?(host) || host == self.class.base_host

      subdomain = subdomain_for(host)
      subdomain && RESERVED_SUBDOMAINS.include?(subdomain)
    end

    def subdomain_for(host)
      suffix = ".#{self.class.base_host}"
      return unless host.end_with?(suffix)

      candidate = host.delete_suffix(suffix)
      candidate unless candidate.include?(".")
    end

    def shop_for(host)
      shop_id = @cache.fetch(self.class.cache_key(host), expires_in: CACHE_TTL) do
        resolve_shop_id(host)
      end
      return unless shop_id

      shop = ActsAsTenant.without_tenant { Shop.find_by(id: shop_id, status: "active") }
      shop if shop && host_matches_shop?(host, shop)
    end

    def resolve_shop_id(host)
      ActsAsTenant.without_tenant do
        subdomain = subdomain_for(host)
        if subdomain
          next unless VALID_SUBDOMAIN.match?(subdomain)

          Shop.find_by(subdomain: subdomain, status: "active")&.id
        else
          # M0 只有網域驗證完成後才寫入 shops.custom_domain；正規化的
          # custom_domains 表在 P1 才落地。停權商店一律不符合條件。
          # 見 docs/specs/12 F1。
          Shop.find_by(custom_domain: host, status: "active")&.id
        end
      end
    end

    def host_matches_shop?(host, shop)
      subdomain = subdomain_for(host)
      if subdomain
        shop.subdomain.to_s.casecmp?(subdomain)
      else
        shop.custom_domain.to_s.casecmp?(host) && shop.custom_domain_verified?
      end
    end

    def not_found_response
      body = "找不到這間商店。"
      [
        404,
        {
          "Content-Type" => "text/plain; charset=utf-8",
          "Content-Length" => body.bytesize.to_s,
          "Cache-Control" => "no-store"
        },
        [ body ]
      ]
    end

    def clear_context!
      Current.reset if defined?(Current)
      ActsAsTenant.current_tenant = nil if defined?(ActsAsTenant)
    end
  end
end
