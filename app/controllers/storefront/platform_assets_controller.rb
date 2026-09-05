# frozen_string_literal: true

module Storefront
  # content_for_header 引用的平台端點（E19；docs/dev/e19-content-for-header.md；取證 external-facts §G27）。
  #
  # ①stub 資產（本體我方自寫、路徑形同本尊）：`/cdn/shopifycloud/storefront/assets/storefront/{load_feature|origin_trials|autosizes}-{8hex}.js`、
  #   `/cdn/shopifycloud/storefront/assets/shop_events_listener-{8hex}.js`、`/cdn/s/trekkie.storefront.{40hex}.min.js`、
  #   `/cdn/shopifycloud/perf-kit/shopify-perf-kit-{ver}.min.js`、`/cdn/shopifycloud/privacy-banner/storefront-banner.js`、
  #   `/cdn/shopifycloud/shop-js/modules/v2/loader.{feature}.{lang}.esm.js`、`/storefront/webmcp/webmcp-{ver}.js`、`/checkouts/internal/preloads.js`。
  # ②編譯資產：`/cdn/shop/t/{theme_id}/compiled_assets/{scripts|snippet-scripts}.js`（`Storefront::CompiledAssets`）。
  # ③端點：`GET /sf_private_access_tokens` ⇒ 401（本尊同：只有 Apple 私密存取權杖流程會 200）；`POST /api/collect` ⇒ 200（perf-kit／
  #   trekkie／棄站 beacon 的收集端；本尊 `https://hoko.vip/api/collect` POST 200）；`GET /{shop_id}/digital_wallets/dialog` ⇒ 200（本尊
  #   2,162B 獨立頁「Payment processing error」對話框骨架；我方自寫最小頁）。
  # 雜湊不符（舊 HTML 引用的檔名）⇒ 404，不回錯本體。
  class PlatformAssetsController < BaseController
    skip_forgery_protection
    skip_before_action :require_storefront_password, only: %i[collect private_access_tokens]

    JS = "text/javascript; charset=utf-8"

    def storefront_asset = serve(PlatformAssets.by_name(params[:file].to_s))
    def trekkie = serve(PlatformAssets.by_name(params[:file].to_s))
    def perf_kit = serve(PlatformAssets.by_name(params[:file].to_s))
    def privacy_banner = serve(PlatformAssets::FILES[:privacy_banner])
    def shop_js = serve(PlatformAssets::FILES[:shop_js_loader])
    def webmcp = serve(PlatformAssets::FILES[:webmcp])
    def preloads = serve(PlatformAssets::FILES[:preloads])

    # GET /cdn/shop/t/:theme_id/compiled_assets/:file
    def compiled
      theme = ActsAsTenant.with_tenant(current_shop) { Theme.find_by(shop_id: current_shop.id, id: params[:theme_id]) }
      return head :not_found if theme.nil?

      source = ThemeEngine::Sources.resolve(theme)
      return head :not_found if source.nil?

      body = params[:file].to_s == "scripts.js" ? CompiledAssets.scripts(source) : CompiledAssets.snippet_scripts(source)
      expires_in 5.minutes, public: true
      send_data body, type: JS, disposition: "inline"
    end

    def private_access_tokens = head(:unauthorized)

    # POST /api/collect（beacon 收集端；本體落地＝分析包）
    def collect = head(:ok)

    # GET /:shop_id/digital_wallets/dialog
    def digital_wallets_dialog
      return head :not_found unless params[:shop_id].to_s == current_shop.id.to_s

      render html: <<~HTML.html_safe, layout: false
        <!DOCTYPE html>
        <html class="html--invisible" lang="#{ERB::Util.html_escape(I18n.locale.to_s)}">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="robots" content="noindex, nofollow">
          <title>付款處理錯誤</title>
        </head>
        <body>
          <div class="dialog dialog--invisible" id="dialog" role="dialog" aria-labelledby="dialog__title" tabindex="-1">
            <h1 id="dialog__title">付款處理錯誤</h1>
            <p>此付款方式目前無法使用，請改用其他方式結帳。</p>
          </div>
        </body>
        </html>
      HTML
    end

    private

    def serve(entry)
      return head :not_found if entry.nil?

      expires_in 5.minutes, public: true
      send_data entry[:body], type: entry[:name].end_with?(".css") ? "text/css; charset=utf-8" : JS, disposition: "inline"
    end
  end
end
