# frozen_string_literal: true

module Storefront
  # `{{ content_for_header }}` 的完整本尊形（E19；docs/dev/e19-content-for-header.md；取證 external-facts §G27，hoko.vip 74 頁 2026-09-05）。
  #
  # ①這是什麼：本尊 head 內從主題 `window.routes` script 之後到 `</head>` 之前的**全部**節點都是 content_for_header 輸出：
  #   perf mark → digital-wallet meta → [atom／prev／next] → hreflang（x-default 首）→ [oembed] → preloads.js → shopify-features JSON →
  #   `Shopify.*` 全域 → modules 旗標 → loadFeatures 佇列 stub → SignInWithShop 設定 → shop-js-analytics JSON → shop-js loader＋import＋featureAssets →
  #   `__st` → PayPal 旗標 → captcha-bootstrap → load_feature → UA 偵測 → origin-trials → MCP 設定 → webmcp adapter → 動態結帳（商品頁模組形／其餘
  #   cart.bootstrap 形）→ privacy banner → [accelerated 樣式]→ [sections-script]／[snippets-script] → cfh-end mark → analytics 尾段（dns-prefetch、
  #   棄站 beacon、trekkie shim、web pixels loader、ShopifyAnalytics.meta、trekkie loader、perf-kit、shopify-y／shopify-s／new-cookie-storage meta）。
  #   官方（objects/content_for_header）："dynamically returns all scripts required by Shopify"；"shouldn't try to modify or parse … subject to change"。
  # ②怎麼做：**延遲到 layout 渲染時才組**（`Lazy` drop 的 `to_s`）——模組形／cart.bootstrap 形取決於本頁是否渲染了 `payment_button`，
  #   `sections-script` 的 `data-sections` 取決於本頁渲染了哪些帶 `{% javascript %}` 的 section／snippet（runtime 記錄）。
  #   每請求值（reqid／u／shopify-y／shopify-s／eventMetadataId）出 placeholder，頁快取存 placeholder 形，controller 送出前代入
  #   （`Storefront::RequestValues`）。平台 script 本體一律我方自寫（鐵律 9），只有節點序、tag／id／屬性名與資料形同本尊；
  #   `RenderParity::Normalizer` 把本體視為替身。
  # ③跨功能：`ThemeEngine::PageRenderer`（assign）、`ThemeEngine::Runtime`（渲染記錄）、`ThemeEngine::Filters#payment_button`（旗標）、
  #   `Storefront::PlatformAssetsController`（stub 資產／compiled assets／端點）、`Storefront::FeedsController`（oembed／atom）、
  #   `Storefront::PagesController`／`Admin::StorefrontPreviewController`（placeholder 代入＋cookie）、`Seo::HreflangMatrix`（hreflang）、
  #   `ThemeEngine::ShopifyGlobal`（全域 script 本尊形）、`Storefront::DynamicCheckoutHead`（E18 段）。
  class ContentForHeader
    PLACEHOLDER = { reqid: "__CL_REQID__", u: "__CL_U__", y: "__CL_Y__", y_exp: "__CL_Y_EXP__",
                    s: "__CL_S__", s_exp: "__CL_S_EXP__", evmeta: "__CL_EVMETA__" }.freeze
    # `__st.p`／`ShopifyAnalytics.meta.page.pageType` 詞彙（§G27：home／product／collection／collections／cart／searchresults／page／blog；
    # article 未觀測（hoko 無文章）⇒ 依同一命名法 `article`，91 V）
    ST_PAGE = { "index" => "home", "product" => "product", "collection" => "collection", "list-collections" => "collections",
                "cart" => "cart", "search" => "searchresults", "page" => "page", "blog" => "blog", "article" => "article" }.freeze
    # 本尊 `shopify-features.betas`／trekkie `enabledBetaFlags`／web pixels `enabledBetaFlags`：平台旗標，語義未取得、值照抄（91 V）
    FEATURE_BETAS = [ "rich-media-storefront-analytics" ].freeze
    TREKKIE_BETA_FLAGS = [ "f43e7f5e", "b5387b81", "d5bdd5d0" ].freeze
    # hreflang／`__st.pageurl` 保留的 query 鍵（§G27：`?page=2`、`?q=tee&type=product` 進 hreflang；`sort_by` 不進）
    HREFLANG_QUERY_KEYS = %w[page q type].freeze
    SHOP_JS_FEATURES = %w[shop-toast-manager listener shop-cash-offers init-shop-user-recognition init-windoid init-shop-email-lookup-coordinator
                          init-fed-cm shop-button avatar checkout-modal shop-login init-customer-accounts-sign-up init-shop-for-new-customer-accounts
                          init-shop-cart-sync shop-user-recognition init-customer-accounts pay-button shop-cart-sync shop-login-button shop-follow-button
                          lead-capture payment-terms].freeze

    # Liquid 端的延遲物件：`{{ content_for_header }}` 在 layout 渲染時才呼叫 `to_s`（body 已渲染 ⇒ runtime 記錄可用）
    class Lazy < Liquid::Drop
      def initialize(builder) = @builder = builder
      def to_s = (@html ||= @builder.build)
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(shop:, theme:, presence:, locale_tag:, country_code:, url_prefix:, path:, query_string:, params:, page_type:,
                   record:, status:, origin:, host:, design_mode:, runtime:, assigns:, asset_host: nil)
      @shop, @theme, @presence = shop, theme, presence
      @locale_tag, @country_code, @url_prefix = locale_tag.to_s, country_code.to_s, url_prefix.to_s
      @path, @query_string, @params = path.to_s, query_string.to_s, params || {}
      @page_type, @record, @status = page_type.to_s, record, status
      @origin, @host, @design_mode, @runtime, @assigns = origin, host, design_mode, runtime, assigns || {}
      @asset_host = asset_host || host # T12：資產 URL 主機（含埠）
    end
    # rubocop:enable Metrics/ParameterLists

    # @return [String] head 片段；非 200／404 頁（如 password／密碼閘）不注（V）
    def build
      return "" unless @status == 200 || @page_type == "404"

      # 節點間空白照本尊位元組（T13 空白骨架對表，external-facts §G29）：perf mark 緊接下一節點（政策頁＝policy 樣式表，再換行接 digital-wallet）；
      # UA 偵測與 origin-trials 相連；模組形 privacy banner 前空一行、加速結帳樣式 link 緊接 banner；其餘以單一換行相接；尾段見 analytics_tail_html。
      first = @page_type == "policy" ? [ policy_stylesheet, "\n", digital_wallet_meta ] : [ digital_wallet_meta ]
      head = [ perf_mark_start, *first ].join
      middle = [ robots_meta, resource_links, preloads_script, shopify_features_json, globals_script, modules_script, load_features_stub,
                 sign_in_with_shop_script, shop_js_analytics_json, shop_js_loader, feature_assets_script, st_script, paypal_flag, captcha_bootstrap,
                 load_feature_tag, ua_detect_script + origin_trials_tag, mcp_script, webmcp_adapter, dynamic_checkout_block ].flatten.compact
      banner = (rendered_payment_button? ? "\n" : "") + privacy_banner_tag + accelerated_styles.to_s
      tail = [ section_scripts, perf_mark_end ].flatten.compact
      [ head, *middle, banner, *tail ].join("\n") + analytics_tail_html
    end

    # T13：政策頁首節點（hoko `/policies/*` 2026-09-05）：`<link rel="stylesheet" media="all" integrity="sha256-…" crossorigin="anonymous"
    #   href="//host/cdn/shopifycloud/storefront/assets/storefront/policy-{8hex}.css">`——本體我方自寫（platform/policy.css）
    def policy_stylesheet
      a = Storefront::PlatformAssets::FILES[:policy_css]
      %(<link rel="stylesheet" media="all" integrity="#{a[:integrity]}" crossorigin="anonymous" href="//#{@asset_host}/cdn/shopifycloud/storefront/assets/storefront/#{a[:name]}">)
    end

    private

    # ── 值 ────────────────────────────────────────────────────────────────────────────────────────
    def shopify_locale = ThemeEngine::LocaleTags.shopify_code(@locale_tag.presence || "en")
    def buyer_country = @country_code.to_s # 無市場國碼時空字串（既有 RF15 形；本尊無此情境）
    def currency = @shop.store_currency.to_s
    def access_token = Storefront::AccessToken.for(@shop.id)
    def host_path
      return "#{@host}/404" if @page_type == "404"

      "#{@host}#{@url_prefix}#{@path == '/' ? (@url_prefix.present? ? '' : '/') : @path}"
    end
    def escaped_json(obj) = JSON.generate(obj).gsub("/", "\\/")
    def rendered_payment_button? = @runtime.respond_to?(:payment_button_rendered?) && @runtime.payment_button_rendered?
    def product = @page_type == "product" ? @record : nil
    def unlisted? = product.is_a?(Product) && product.status == "unlisted"

    def st_page = ST_PAGE[@page_type]

    # 本尊 `__st.rtyp`／`rid`：product／page／blog（collection 無）；page／blog 另有 `s: "pages-{id}"`／`"blogs-{id}"`
    def resource
      case @page_type
      when "product" then [ "product", @record&.id, nil ]
      when "page" then [ "page", @record&.id, "pages" ]
      when "blog" then [ "blog", @record&.id, "blogs" ]
      when "article" then [ "article", @record&.id, "articles" ] # 未觀測（91 V）
      else [ nil, nil, nil ]
      end
    end

    # ── 節點 ──────────────────────────────────────────────────────────────────────────────────────
    def perf_mark_start = "<script>window.performance && window.performance.mark && window.performance.mark('shopify.content_for_header.start');</script>"
    def perf_mark_end = %(<script id="shopify-cfh-end">window.performance && window.performance.mark && window.performance.mark('shopify.content_for_header.end');</script>)
    def digital_wallet_meta = %(<meta id="shopify-digital-wallet" name="shopify-digital-wallet" content="/#{@shop.id}/digital_wallets/dialog">)

    # UNLISTED 商品：noindex（包 35；本尊位置未觀測——hoko 無 unlisted 商品，91 V）
    def robots_meta
      return nil unless unlisted?

      %(<meta name="robots" content="#{Limits.fetch(:product, :unlisted_meta_robots)}">)
    end

    # atom（集合／部落格，自閉合形）→ prev／next（分頁）→ hreflang（x-default 首）→ oembed（商品）；404／UNLISTED 無 hreflang
    def resource_links
      links = []
      if %w[collection blog].include?(@page_type) # 虛擬 all 集合（record nil）本尊同樣有 feed（/collections/all.atom 200）
        links << %(<link rel="alternate" type="application/atom+xml" title="Feed" href="#{@url_prefix}#{@path}.atom" />)
      end
      links.concat(pagination_links)
      links.concat(hreflang_links) unless @page_type == "404" || unlisted?
      links << %(<link rel="alternate" type="application/json+oembed" href="#{absolute_root}#{@url_prefix}#{@path}.oembed">) if product
      links
    end

    def pagination_links
      page = @params["page"].to_s
      return [] unless page.match?(/\A[0-9]+\z/) && page.to_i > 1

      [ %(<link rel="prev" href="#{@url_prefix}#{@path}?page=#{page.to_i - 1}">) ] # next：第 3 頁以上未觀測（91 V）
    end

    def hreflang_links
      return [] unless @presence

      canonical = @path
      entries = Seo::HreflangMatrix.entries(shop: @shop, canonical_path: canonical)
      ordered = entries.partition { |e| e.code == "x-default" }.flatten
      query = hreflang_query
      # §G27 首頁：帶前綴的根形無尾斜線（`https://hoko.vip/zh-hant`）；主網域根保留 `/`（`https://hoko.vip/`）
      ordered.map do |e|
        url = e.url
        url = url.chomp("/") if @path == "/" && url.sub(%r{\Ahttps?://[^/]+}, "") != "/"
        %(<link rel="alternate" hreflang="#{e.code}" href="#{ERB::Util.html_escape(url)}#{query}">)
      end
    end

    # 保留 page／q／type（原序）；`&` 以 `&amp;` 出（本尊 `?q=tee&amp;type=product`）
    def hreflang_query
      pairs = @query_string.split("&").reject(&:empty?).select { |pair| HREFLANG_QUERY_KEYS.include?(Rack::Utils.unescape(pair.split("=", 2)[0].to_s)) }
      pairs.empty? ? "" : "?#{ERB::Util.html_escape(pairs.join('&'))}"
    end

    def absolute_root
      Seo::HreflangMatrix.absolute_url(@shop, @presence, @locale_tag, "/").sub(%r{#{Regexp.escape(@url_prefix)}/\z}, "").chomp("/")
    rescue StandardError
      @origin.to_s
    end

    # `/checkouts/internal/preloads.js?locale={語言主碼}-{買家國碼}&default_configuration_id={id}`（§G27：zh-CN 頁 ⇒ zh-TW、en 頁 ⇒ en-TW）
    def preloads_script
      lang = shopify_locale.split("-").first
      %(<script async="async" src="/checkouts/internal/preloads.js?locale=#{lang}-#{buyer_country}&default_configuration_id=#{@shop.id}"></script>)
    end

    def shopify_features_json
      %(<script id="shopify-features" type="application/json">) +
        JSON.generate("accessToken" => access_token, "betas" => FEATURE_BETAS, "domain" => @host.to_s, "predictiveSearch" => false,
                      "shopId" => @shop.id, "locale" => shopify_locale.downcase) + "</script>" # 本尊：JSON 緊貼標籤、無換行
    end

    def globals_script
      ThemeEngine::ShopifyGlobal.script(shop: @shop, theme: @theme, locale: shopify_locale, currency:, root: root_path,
                                        design_mode: @design_mode, country: buyer_country, schema_name: theme_info["theme_name"],
                                        schema_version: theme_info["theme_version"], host: @host, origin: @origin)
    end

    def theme_info = @runtime.respond_to?(:theme_info) ? (@runtime.theme_info || {}) : {}
    def root_path = @url_prefix.present? ? "#{@url_prefix}/" : "/"

    def modules_script = %(<script type="module">!function(o){(o.Shopify=o.Shopify||{}).modules=!0}(window);</script>) # 本尊單行

    # loadFeatures／autoloadFeatures 佇列 stub（真正實作在 load_feature 資產；我方自寫）
    def load_features_stub
      "<script>\n(function(w){function q(){var a=[];function f(){a.push(Array.prototype.slice.call(arguments))}f.q=a;return f}" \
        "var s=w.Shopify=w.Shopify||{};s.loadFeatures=q();s.autoloadFeatures=q()})(window);\n</script>"
    end

    def sign_in_with_shop_script
      "<script>\n  window.Shopify = window.Shopify || {};\n  window.Shopify.SignInWithShop = window.Shopify.SignInWithShop || {};\n" \
        "  window.Shopify.SignInWithShop.assetMetrics = { sampleRate: 0.25 };\n  window.Shopify.SignInWithShop.eligible = true;\n</script>"
    end

    def shop_js_analytics_json = %(<script id="shop-js-analytics" type="application/json">{"pageType":"#{@page_type}"}</script>)

    def shop_js_module_url(name) = "#{@origin}/cdn/shopifycloud/shop-js/modules/v2/loader.#{name}.#{shopify_locale}.esm.js"

    def shop_js_loader
      url = shop_js_module_url("init-shop-cart-sync")
      [ %(<script defer="defer" async type="module" src="#{url}"></script>),
        %(<script type="module">\n  await import("#{url}");\n\n  window.Shopify.SignInWithShop?.initShopCartSync?.({"fedCMEnabled":true,"windoidEnabled":true});\n\n</script>) ] # 本尊：結尾空一行
    end

    def feature_assets_script
      map = SHOP_JS_FEATURES.to_h { |f| [ f, [ "modules/v2/loader.#{f}.#{shopify_locale}.esm.js" ] ] }
      "<script>\n  window.Shopify = window.Shopify || {};\n  if (!window.Shopify.featureAssets) window.Shopify.featureAssets = {};\n" \
        "  window.Shopify.featureAssets['shop-js'] = #{JSON.generate(map)};\n</script>"
    end

    def st_script
      rtyp, rid, s_prefix = resource
      st = { "a" => @shop.id, "offset" => tz_offset, "reqid" => PLACEHOLDER[:reqid], "pageurl" => host_path + pageurl_query }
      st["s"] = "#{s_prefix}-#{rid}" if s_prefix && rid
      st["u"] = PLACEHOLDER[:u]
      st["p"] = st_page if st_page
      if rtyp && rid
        st["rtyp"] = rtyp
        st["rid"] = rid
      end
      %(<script id="__st">var __st=#{escaped_json(st)};</script>)
    end

    def pageurl_query = @query_string.present? && @page_type != "404" ? "?#{@query_string}" : ""
    def tz_offset = (ActiveSupport::TimeZone[@shop.timezone.to_s]&.utc_offset || 0)

    def paypal_flag = "<script>window.ShopifyPaypalV4VisibilityTracking = true;</script>"

    # 表單 captcha 綁定（我方自寫：介面 `Shopify.captcha.protect(form, cb)`／`Shopify.ce_forms.q`；驗證碼供應商＝另包）
    def captcha_bootstrap
      %(<script id="captcha-bootstrap">!function(){"use strict";var w=window,S=w.Shopify=w.Shopify||{};S.ce_forms=S.ce_forms||{q:[]};) +
        %(S.captcha=S.captcha||{};S.captcha.protect=function(f,cb){f&&(f.dataset.cptcha="true");typeof cb=="function"&&cb()};) +
        %(S.ce_forms.bindForm=function(f,id,cb){S.captcha.protect(f,cb)};for(var i=0;i<S.ce_forms.q.length;i++){var e=S.ce_forms.q[i];S.ce_forms.bindForm(e[0][0],e[0][1],e[1])}S.ce_forms.q=[]}();</script>)
    end

    def load_feature_tag
      a = Storefront::PlatformAssets::FILES[:load_feature]
      %(<script integrity="#{a[:integrity]}" data-source-attribution="shopify.loadfeatures" defer="defer" src="//#{@asset_host}/cdn/shopifycloud/storefront/assets/storefront/#{a[:name]}" crossorigin="anonymous"></script>)
    end

    # UA 偵測（Apple Safari ⇒ 私密存取權杖；`sizes=auto` polyfill 條件載入；長影格量測骨架）——我方自寫
    def ua_detect_script
      autosizes = Storefront::PlatformAssets::FILES[:autosizes]
      "<script>(function(){var ua=navigator.userAgent,pf=navigator.platform,tp=navigator.maxTouchPoints||0;" \
        "var ios=/iPad|iPhone|iPod/.test(pf)||(pf==='MacIntel'&&tp>1);var mac=pf.indexOf('Mac')===0&&/Safari/.test(ua)&&!/Chrome|Chromium|CriOS|FxiOS|Edg|OPR|Android/.test(ua);" \
        "if(ios||mac){fetch('/sf_private_access_tokens'+location.search).catch(function(){});}" \
        "function major(re){var m=ua.match(re);return m?parseInt(m[1],10):null}" \
        "function needPolyfill(){if(!(window.PerformanceObserver&&PerformanceObserver.supportedEntryTypes&&PerformanceObserver.supportedEntryTypes.indexOf('paint')>=0))return false;" \
        "var c=major(/Chrome\\/(\\d+)/);if(c!==null)return c<126;var f=major(/Firefox\\/(\\d+)/);if(f!==null)return f<150;var s=(ios||mac)?major(/Version\\/(\\d+).*Safari\\//):null;if(s!==null)return s<27;return true}" \
        "if(needPolyfill()){var t=document.createElement('script');t.async=true;t.crossOrigin='anonymous';t.src=\"//#{@asset_host}/cdn/shopifycloud/storefront/assets/storefront/#{autosizes[:name]}\";(document.head||document.documentElement).appendChild(t);}" \
        "window.ShopifyAnalytics=window.ShopifyAnalytics||{};window.ShopifyAnalytics.performance=window.ShopifyAnalytics.performance||{};})();</script>"
    end

    def origin_trials_tag
      a = Storefront::PlatformAssets::FILES[:origin_trials]
      %(<script id="shopify-origin-trials" async="async" integrity="#{a[:integrity]}" src="//#{@asset_host}/cdn/shopifycloud/storefront/assets/storefront/#{a[:name]}" crossorigin="anonymous" onload="window.__shopifyOriginTrialsDone = true" onerror="window.__shopifyOriginTrialsDone = true"></script>)
    end

    # 店面 MCP 設定（端點 `/api/mcp`＝T11；工具清單形同本尊、描述文字我方自寫）
    def mcp_script
      tools = [ { "name" => "search_shop_policies_and_faqs", "description" => "查詢本店政策、商品或服務的事實（退貨、運送、聯絡方式、營業時間）。",
                  "inputSchema" => { "$schema" => "https://json-schema.org/draft/2020-12/schema", "type" => "object",
                                     "properties" => { "query" => { "type" => "string", "description" => "自然語言查詢。" },
                                                       "context" => { "type" => "string", "description" => "有助於回答的額外脈絡。" } },
                                     "required" => [ "query" ] } } ]
      "<script>\n  window.Shopify = window.Shopify || {};\n  window.Shopify.MCP = window.Shopify.MCP || {};\n  window.Shopify.MCP.enabled = true;\n" \
        "  window.Shopify.MCP.shop = #{shop_permanent_domain.to_json};\n  window.Shopify.MCP.mcpEndpoint = #{escaped_json("#{@origin}/api/mcp")};\n" \
        "  window.Shopify.MCP.tools = #{escaped_json(tools)};\n</script>"
    end

    def shop_permanent_domain = "#{@shop.subdomain}.#{Chilllove::TenantResolver.base_host}"

    # webmcp adapter loader（我方自寫；同名事件／旗標 `shopify:webmcp_adapter_loaded`；只在 `navigator.modelContext.registerTool` 存在時載）
    def webmcp_adapter
      src = "#{@origin}/cdn/storefront/webmcp/webmcp-0.1.1.js"
      "<script>(function(){var d=\"shopify:webmcp_adapter_loaded\",n=Symbol.for(\"shopify.webmcp_adapter_loading\");" \
        "function can(){var mc=document.modelContext||(navigator&&navigator.modelContext);return !!(mc&&typeof mc.registerTool==\"function\")}" \
        "function load(){if(window[n]||!can())return;var h=document.head;if(!h)return;var e=document.createElement(\"script\");e.type=\"module\";e.crossOrigin=\"anonymous\";e.src=#{src.to_json};" \
        "e.addEventListener(\"load\",function(){try{localStorage.setItem(d,\"true\")}catch(x){}},{once:true});e.addEventListener(\"error\",function(){window[n]=false},{once:true});h.appendChild(e);window[n]=true}" \
        "function after(cb){var e=document.getElementById(\"shopify-origin-trials\");if(!e||window.__shopifyOriginTrialsDone){cb();return}e.addEventListener(\"load\",cb,{once:true});e.addEventListener(\"error\",cb,{once:true})}" \
        "function go(){after(function(){setTimeout(load,0)})}var seen=false;try{seen=localStorage.getItem(d)===\"true\"}catch(x){}" \
        "seen?go():document.addEventListener(\"DOMContentLoaded\",go,{once:true})})();</script>"
    end

    # E18 段：本頁渲染了 payment_button ⇒ 模組形；否則 cart.bootstrap 形（§G27）
    def dynamic_checkout_block
      Storefront::DynamicCheckoutHead.build(origin: @origin, locale_tag: @locale_tag, variant: rendered_payment_button? ? :module : :cart_bootstrap)
    end

    def privacy_banner_tag = %(<script id='scb4127' type='text/javascript' async='' src='#{@origin}/cdn/shopifycloud/privacy-banner/storefront-banner.js'></script>)

    def accelerated_styles
      return nil unless rendered_payment_button?

      Storefront::DynamicCheckoutHead.styles(origin: @origin)
    end

    # T12：`?v=`＝每檔摘要＋主題版本秒（hoko 29 位形；compiled 的時間戳與 assets 的不同＝各自產生時刻）。以主題版本鍵快取，避免每頁重編。
    def compiled_version(name)
      stamp = @theme.updated_at.to_i
      Rails.cache.fetch([ "compiled_v", @theme.id, stamp, name ], expires_in: 1.day) do
        source = ThemeEngine::Sources.resolve(@theme)
        body = name == "scripts.js" ? CompiledAssets.scripts(source) : CompiledAssets.snippet_scripts(source)
        "#{ThemeEngine::AssetUrls.digest64(body)}#{stamp}"
      end
    end

    # `{% javascript %}` 編譯資產：只列本頁渲染到的 section／snippet 檔（本尊 data-sections／data-snippets）
    def section_scripts
      return [] unless @runtime.respond_to?(:rendered_asset_files)

      files = @runtime.rendered_asset_files
      base = "//#{@asset_host}/cdn/shop/t/#{@theme.id}/compiled_assets"
      out = []
      if files[:sections].any?
        out << %(<script id="sections-script" data-sections="#{files[:sections].to_a.join(',')}" defer="defer" src="#{base}/scripts.js?v=#{compiled_version('scripts.js')}"></script>)
      end
      if files[:snippets].any?
        out << %(<script id="snippets-script" data-snippets="#{files[:snippets].to_a.join(',')}" defer="defer" src="#{base}/snippet-scripts.js?v=#{compiled_version('snippet-scripts.js')}"></script>)
      end
      out
    end

    # ── analytics 尾段（本體我方自寫；事件與 payload 形同本尊）──────────────────────────────────────
    # 尾段（本尊位元組形）：cfh-end 之後 "\n\n    \n  " 接 dns-prefetch；棄站 beacon／TREKKIE shim／web pixels 各換行；analytics meta **緊接** web pixels；
    # trekkie loader／perf-kit／shopify-y 各換行；shopify-s／new-cookie **緊接**前一個 meta。
    def analytics_tail_html
      "\n\n    \n  " + %(<link href="#{@origin}" rel="dns-prefetch">) + "\n" + abandonment_script + "\n" +
        "<script>\n  window.__TREKKIE_SHIM_QUEUE = window.__TREKKIE_SHIM_QUEUE || [];\n</script>" + "\n" + web_pixels_script +
        analytics_meta_script + "\n" + trekkie_script + "\n" + perf_kit_tag + "\n" +
        %(<meta name="shopify-y" content="#{PLACEHOLDER[:y]}" data-expiration="#{PLACEHOLDER[:y_exp]}">) +
        %(<meta name="shopify-s" content="#{PLACEHOLDER[:s]}" data-expiration="#{PLACEHOLDER[:s_exp]}">) +
        %(<meta name="new-cookie-storage-activated" content="f">)
    end

    # 棄站 beacon（pagehide ⇒ 我方收集端 `/api/collect`；schema 名照本尊）
    def abandonment_script
      "<script>(function(){if(\"sendBeacon\" in navigator&&\"performance\" in window){var m=document.cookie.match(/_shopify_s=([^;]*)/);var st=m&&m.length===2?m[1]:\"\";" \
        "function h(){if(window.abandonment_tracked)return;window.abandonment_tracked=true;var now=Date.now();var ns=performance.timing.navigationStart;" \
        "var p={shop_id:#{@shop.id},url:window.location.href,navigation_start:ns,duration:now-ns,session_token:st,page_type:#{@page_type.to_json}};" \
        "navigator.sendBeacon(\"/api/collect\",JSON.stringify({schema_id:\"online_store_buyer_site_abandonment/1.1\",payload:p,metadata:{event_created_at_ms:now,event_sent_at_ms:now}}))}" \
        "window.addEventListener('pagehide',h)}}());</script>"
    end

    # web pixels：`Shopify.analytics.publish／subscribe`（Web Pixels API 介面）＋本頁標準事件（page_viewed／product_viewed／collection_viewed／search_submitted）
    def web_pixels_script
      cfg = { "shopId" => @shop.id, "storefrontBaseUrl" => @origin, "currency" => currency, "language" => shopify_locale,
              "enabledBetaFlags" => [ "d5bdd5d0" ], "surface" => "storefront-renderer", "events" => standard_events }
      "<script>(function(){var cfg=#{escaped_json(cfg)};var S=window.Shopify=window.Shopify||{};var subs={};var q=[];" \
        "S.analytics=S.analytics||{};S.analytics.subscribe=function(n,cb){(subs[n]=subs[n]||[]).push(cb);return function(){subs[n]=(subs[n]||[]).filter(function(x){return x!==cb})}};" \
        "S.analytics.publish=function(n,d){q.push([n,d||{}]);(subs[n]||[]).concat(subs.all_events||[]).forEach(function(cb){try{cb({name:n,data:d||{},timestamp:new Date().toISOString()})}catch(e){}});return true};" \
        "S.analytics.visitor=function(){return Promise.resolve(true)};window.__cl_webPixels={config:cfg,queue:q};" \
        "cfg.events.forEach(function(e){S.analytics.publish(e[0],e[1])})})();</script>"
    end

    def standard_events
      events = [ [ "page_viewed", {} ] ]
      case @page_type
      when "product"
        v = product && product_variant_payload(product)
        events << [ "product_viewed", { "productVariant" => v } ] if v
      when "collection"
        events << [ "collection_viewed", { "collection" => { "id" => @record&.id.to_s, "title" => collection_title.to_s, "productVariants" => listed_products.map { |p| product_variant_payload(p) }.compact } } ] if collection_handle.present?
      when "search"
        q = @params["q"].to_s
        events << [ "search_submitted", { "searchResult" => { "query" => q, "productVariants" => listed_products.map { |p| product_variant_payload(p) }.compact } } ] if q.present?
      end
      events
    end

    def product_variant_payload(p)
      v = first_variant(p) or return nil
      { "price" => { "amount" => (BigDecimal(v.price_cents.to_i) / 100).to_f, "currencyCode" => currency },
        "product" => { "title" => p.title, "vendor" => p.vendor.to_s, "id" => p.id.to_s, "untranslatedTitle" => p.title,
                       "url" => "#{@url_prefix}/products/#{p.handle}", "type" => p.product_type.to_s },
        "id" => v.id.to_s, "image" => nil, "sku" => v.sku.presence, "title" => v.title.to_s, "untranslatedTitle" => v.title.to_s }
    end

    def first_variant(p) = p.respond_to?(:product_variants) ? p.product_variants.order(:position, :id).first : nil

    # 集合頁 handle（虛擬 all 無 record ⇒ 由路徑取）；本尊 collections/all 的 web pixels `collection.id` 為空字串、title＝商品頁標題
    def collection_handle = @record&.handle || @path[%r{\A/collections/([^/]+)}, 1].to_s
    def collection_title = @record&.title || ThemeEngine::PageTitles.products_title(@locale_tag)

    # 集合／搜尋頁列出的商品（`ShopifyAnalytics.meta.products`／web pixels）＝**本頁實際渲染的商品**：集合＝排序＋分頁窗後的那一頁
    # （hoko collections/all 三商品依系列排序、?page=2 空、?sort_by=price-ascending 依價序），搜尋＝結果中的商品；由 body 渲染後的 drops 取當前頁記錄
    # （CollectionProductsDrop／SearchResultsDrop 的 `each`；未走 paginate ⇒ 官方前 50），上限 limits `content_for_header.analytics_listed_products_cap`。
    def listed_products
      @listed_products ||= page_product_records.first(Limits.fetch(:content_for_header, :analytics_listed_products_cap))
    end

    def page_product_records
      source =
        case @page_type
        when "collection" then @assigns["collection"].respond_to?(:products) ? @assigns["collection"].products : nil
        when "search" then @assigns["search"].respond_to?(:results) ? @assigns["search"].results : nil
        end
      return [] unless source.respond_to?(:each)

      records = []
      source.each { |d| records << d.instance_variable_get(:@p) if d.is_a?(ThemeEngine::ProductDrop) } # drop 私有記錄（不對 Liquid 開放 reader）
      records.compact
    end

    def analytics_product_json(p)
      { "id" => p.id, "gid" => "gid://chilllove/Product/#{p.id}", "vendor" => p.vendor.to_s, "type" => p.product_type.to_s, "handle" => p.handle,
        "variants" => (p.respond_to?(:product_variants) ? p.product_variants.order(:position, :id) : []).map { |v|
          { "id" => v.id, "price" => v.price_cents.to_i, "name" => (v.title.to_s == "Default Title" ? p.title : "#{p.title} - #{v.title}"),
            "public_title" => (v.title.to_s == "Default Title" ? nil : v.title), "sku" => v.sku.presence }
        }, "remote" => false }
    end

    def analytics_meta_script
      rtyp, rid, _ = resource
      meta = {}
      meta["product"] = analytics_product_json(product) if product
      meta["products"] = listed_products.map { |p| analytics_product_json(p) } if %w[collection search].include?(@page_type)
      page = {}
      page["pageType"] = st_page if st_page
      if rtyp && rid
        page["resourceType"] = rtyp
        page["resourceId"] = rid
      end
      page["requestId"] = PLACEHOLDER[:reqid]
      meta["page"] = page
      "<script>\n  window.ShopifyAnalytics = window.ShopifyAnalytics || {};\n  window.ShopifyAnalytics.meta = window.ShopifyAnalytics.meta || {};\n" \
        "  window.ShopifyAnalytics.meta.currency = '#{currency}';\n  var meta = #{escaped_json(meta)};\n  for (var attr in meta) {\n" \
        "    window.ShopifyAnalytics.meta[attr] = meta[attr];\n  }\n</script>"
    end

    # trekkie stub 佇列＋loader（我方自寫）：本頁 track 事件（Viewed Product／Viewed Product Category／Performed Search）與 page() 形同本尊
    def trekkie_script
      a = Storefront::PlatformAssets::FILES[:trekkie]
      listener = Storefront::PlatformAssets::FILES[:shop_events_listener]
      rtyp, rid, _ = resource
      page_payload = {}
      page_payload["pageType"] = st_page if st_page
      if rtyp && rid
        page_payload["resourceType"] = rtyp
        page_payload["resourceId"] = rid
      end
      page_payload["requestId"] = PLACEHOLDER[:reqid]
      page_payload["shopifyEmitted"] = true
      config = { "Trekkie" => { "appName" => "storefront", "development" => false,
                                "defaultAttributes" => { "shopId" => @shop.id, "isMerchantRequest" => nil, "themeId" => @theme.id,
                                                         "themeCityHash" => theme_city_hash, "contentLanguage" => shopify_locale,
                                                         "currency" => currency, "eventMetadataId" => PLACEHOLDER[:evmeta] },
                                "isServerSideCookieWritingEnabled" => true, "monorailRegion" => "shop_domain", "enabledBetaFlags" => TREKKIE_BETA_FLAGS },
                 "Session Attribution" => {}, "S2S" => { "facebookCapiEnabled" => false, "source" => "trekkie-storefront-renderer", "apiClientId" => api_client_id } }
      <<~JS.chomp
        <script class="analytics">
          (function () {
            var trekkie = window.ShopifyAnalytics.lib = window.trekkie = window.trekkie || [];
            window.ShopifyAnalytics.lib.trekkie = window.trekkie;
            if (trekkie.integrations) { return; }
            trekkie.methods = ['identify', 'page', 'ready', 'track', 'trackForm', 'trackLink'];
            trekkie.factory = function(method) { return function() { var args = Array.prototype.slice.call(arguments); args.unshift(method); trekkie.push(args);
              if (window.__TREKKIE_SHIM_QUEUE && (method == 'track' || method == 'page')) { try { window.__TREKKIE_SHIM_QUEUE.push({ from: 'trekkie-stub', method: method, args: args.slice(1) }); } catch (e) {} }
              return trekkie; }; };
            for (var i = 0; i < trekkie.methods.length; i++) { trekkie[trekkie.methods[i]] = trekkie.factory(trekkie.methods[i]); }
            trekkie.load = function(config) { trekkie.config = config || {}; trekkie.config.initialDocumentCookie = document.cookie;
              var first = document.getElementsByTagName('script')[0]; var script = document.createElement('script'); script.type = 'text/javascript';
              script.async = true; script.src = '//#{@asset_host}/cdn/s/#{a[:name]}'; first.parentNode.insertBefore(script, first); };
            trekkie.load(#{escaped_json(config)});
            var loaded = false;
            trekkie.ready(function() { if (loaded) return; loaded = true; window.ShopifyAnalytics.lib = window.trekkie;
              try { window.ShopifyAnalytics.merchantGoogleAnalytics.call(this); } catch(error) {};
        #{track_call}    });
            window.ShopifyAnalytics.lib.page(null,#{escaped_json(page_payload)});
            var eventsListenerScript = document.createElement('script'); eventsListenerScript.async = true;
            eventsListenerScript.src = "//#{@asset_host}/cdn/shopifycloud/storefront/assets/#{listener[:name]}";
            document.getElementsByTagName('head')[0].appendChild(eventsListenerScript);
          })();
        </script>
      JS
    end

    def track_call
      name, payload = track_event
      return "" unless name

      "      window.ShopifyAnalytics.lib.track(#{name.to_json},#{escaped_json(payload)},undefined,undefined,{\"shopifyEmitted\":true});\n"
    end

    def track_event
      case @page_type
      when "product"
        v = product && first_variant(product)
        return [ nil, nil ] unless v

        price = format("%.2f", BigDecimal(v.price_cents.to_i) / 100)
        [ "Viewed Product", { "currency" => currency, "variantId" => v.id, "productId" => product.id, "productGid" => "gid://chilllove/Product/#{product.id}",
                              "name" => product.title, "price" => price, "sku" => v.sku.presence, "brand" => product.vendor.to_s,
                              "variant" => (v.title.to_s == "Default Title" ? nil : v.title), "category" => product.product_type.to_s,
                              "nonInteraction" => true, "remote" => false, "available" => Storefront::CartWriter.sellable?(v) } ]
      when "collection"
        return [ nil, nil ] if collection_handle.blank?

        [ "Viewed Product Category", { "currency" => currency, "category" => "Collection: #{collection_handle}", "collectionName" => collection_handle, "nonInteraction" => true } ]
      when "search"
        q = @params["q"].to_s
        q.present? ? [ "Performed Search", { "query" => q } ] : [ nil, nil ]
      else
        [ nil, nil ]
      end
    end

    def theme_city_hash = Zlib.crc32("#{@theme.id}:#{@theme.name}").to_s
    def api_client_id = Limits.fetch(:content_for_header, :online_store_api_client_id)

    # 本尊 perf-kit 標籤＝每個屬性獨立一行（兩空白縮排）、`\n></script>` 收尾（hoko 原始位元組 2026-09-05）
    def perf_kit_tag
      attrs = [ "defer", %(src="#{@origin}/cdn/shopifycloud/perf-kit/#{Storefront::PlatformAssets::FILES[:perf_kit][:name]}"),
                %(data-application="storefront-renderer"), %(data-shop-id="#{@shop.id}"), %(data-render-region="#{Storefront::PlatformAssets::RENDER_REGION}"),
                %(data-page-type="#{@page_type}"), %(data-theme-instance-id="#{@theme.id}"),
                %(data-theme-name="#{ERB::Util.html_escape(theme_info['theme_name'].to_s)}"), %(data-theme-version="#{ERB::Util.html_escape(theme_info['theme_version'].to_s)}"),
                %(data-monorail-region="shop_domain"), %(data-resource-timing-sampling-rate="10"), %(data-shs="true"), %(data-shs-beacon="true"),
                %(data-shs-export-with-fetch="true"), %(data-shs-logs-sample-rate="1"), %(data-shs-beacon-endpoint="#{@origin}/api/collect") ]
      "<script\n  #{attrs.join("\n  ")}\n></script>"
    end
  end
end
