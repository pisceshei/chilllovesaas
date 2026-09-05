# frozen_string_literal: true

module Storefront
  # 平台 stub 資產登記（E19；docs/dev/e19-content-for-header.md）：content_for_header 引用的本尊平台 script，
  # 本體一律我方自寫（`app/assets/storefront/platform/*.js`），路徑形同本尊、檔名雜湊＝我方本體 SHA-256 前 8 hex、
  # `integrity`＝我方本體的 SRI（sha256 base64）。啟動時讀成常量（Brakeman：不以參數組檔案路徑）。
  #
  # 本尊形（hoko.vip 2026-09-05，external-facts §G27）：
  #   `//host/cdn/shopifycloud/storefront/assets/storefront/load_feature-{8hex}.js`（integrity、defer、crossorigin）
  #   `//cdn.shopify.com/shopifycloud/storefront/assets/storefront/origin_trials-{8hex}.js`（我方走店主機）
  #   `//host/cdn/shopifycloud/storefront/assets/storefront/autosizes-{8hex}.js`（UA 偵測 script 條件載入）
  #   `//host/cdn/shopifycloud/storefront/assets/shop_events_listener-{8hex}.js`（trekkie ready 後載）
  #   `//host/cdn/s/trekkie.storefront.{40hex}.min.js`
  #   `https://host/cdn/shopifycloud/perf-kit/shopify-perf-kit-3.8.9.min.js`
  #   `https://host/cdn/shopifycloud/privacy-banner/storefront-banner.js`
  #   `https://cdn.shopify.com/shopifycloud/shop-js/modules/v2/loader.{feature}.{lang}.esm.js`（我方走店主機）
  #   `https://cdn.shopify.com/storefront/webmcp/webmcp-0.1.1.js`（我方走店主機 `/storefront/webmcp/…`）
  #   `/checkouts/internal/preloads.js?locale=…&default_configuration_id=…`
  module PlatformAssets
    ROOT = Rails.root.join("app/assets/storefront/platform").freeze
    RENDER_REGION = "chilllove-hk-1" # 本尊 `data-render-region="gcp-asia-southeast1"`（Normalizer 抹）
    PERF_KIT_VERSION = "3.8.9"      # 本尊檔名版本段（路徑身分；本體我方自寫）

    def self.read(file) = File.read(ROOT.join(file)).freeze
    def self.short_hash(body) = Digest::SHA256.hexdigest(body)[0, 8]
    def self.sri(body) = "sha256-#{Digest::SHA256.base64digest(body)}"

    def self.entry(file, name_proc)
      body = read(file)
      { body:, name: name_proc.call(body), integrity: sri(body) }
    end

    FILES = {
      load_feature: entry("load_feature.js", ->(b) { "load_feature-#{short_hash(b)}.js" }),
      origin_trials: entry("origin_trials.js", ->(b) { "origin_trials-#{short_hash(b)}.js" }),
      autosizes: entry("autosizes.js", ->(b) { "autosizes-#{short_hash(b)}.js" }),
      shop_events_listener: entry("shop_events_listener.js", ->(b) { "shop_events_listener-#{short_hash(b)}.js" }),
      trekkie: entry("trekkie.js", ->(b) { "trekkie.storefront.#{Digest::SHA1.hexdigest(b)}.min.js" }),
      perf_kit: entry("perf_kit.js", ->(_b) { "shopify-perf-kit-#{PERF_KIT_VERSION}.min.js" }),
      privacy_banner: entry("privacy_banner.js", ->(_b) { "storefront-banner.js" }),
      shop_js_loader: entry("shop_js_loader.esm.js", ->(_b) { "loader.esm.js" }),
      webmcp: entry("webmcp.js", ->(_b) { "webmcp-0.1.1.js" }),
      preloads: entry("preloads.js", ->(_b) { "preloads.js" })
    }.freeze

    # 依本尊檔名找 stub（`load_feature-xxxxxxxx.js` 等；雜湊不符 ⇒ nil，讓舊快取的 URL 404 而不是回錯本體）
    def self.by_name(name)
      FILES.values.find { |f| f[:name] == name }
    end
  end
end
