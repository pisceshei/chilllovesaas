# frozen_string_literal: true

module RenderParity
  # 渲染 1:1 對表（使用者 2026-09-03 裁定：preview／買家前台輸出的 CSS／尺寸／參數必須與本尊同主題渲染完全一樣）。
  #
  # ①這是什麼：把「本尊店 HTML」與「我方店 HTML」正規化成可逐段比對的形——去掉**只可能是平台／租戶身分**的差異
  #   （主機名、CDN 主題資產路徑與版本參數、群組／模板數字 id、theme block 實例 id 前綴、CSRF／request id／時間戳），
  #   其餘任何差異都視為**引擎缺口**（或資料差異，由鏡像店消除）。
  # ②每條正規化規則都是「已知本尊形 → 我方形」的對映，附取證（hoko.vip 2026-09-03 快照）；不得把不確定的差異塞進
  #   正規化來讓 diff 變綠（鐵律 19）。
  # ③跨功能影響：`RenderParity::Report`（逐段 diff）、`lib/tasks/render_parity.rake`（跑法）、
  #   `spec/services/render_parity/*`。
  class Normalizer
    # 本尊 `sections--{group 數字 id}__{key}`／`template--{模板數字 id}__{key}`；我方 `sections--{group 名}__{key}`／`template--{模板名}__{key}`
    GROUP_ID_RE = /sections--(?:\d+|[a-z0-9-]+)__/
    # E17：替代模板的我方 id 帶單底線（`template--product-quick_add__main`／`product-block_wishlist_card__main`）
    TEMPLATE_ID_RE = /template--(?:\d+|[a-z0-9.\-]+(?:_[a-z0-9.\-]+)*)__/
    # 本尊 theme block 實例 id：`{18 碼 base64-ish}__{key}`（hoko.vip 實測 `AWlFwNUZ5UVVuRmp6e__group_announcement_bar_PeTpTw`）
    BLOCK_SCOPE_RE = /\bA[A-Za-z0-9]{17}__/
    # 本尊主題資產：`//host/cdn/shop/t/{n}/assets/x.css?v=123`（主機可能已被上一步抹掉）；我方：`/theme-assets/x.css`
    CDN_ASSET_RE = %r{(?:(?:https?:)?//[^/"'\s]+)?/cdn/shop/t/\d+/assets/}
    ASSET_VERSION_RE = /\?v=\d+/
    # 本尊字型：`/cdn/fonts/{family}/{handle}.{hash}.woff2`；我方：`/fonts/{family}/{handle}.woff2`
    # E17：`.woff` 備援形（`@font-face` 的第二個 `url(…jost_n4.{hash}.woff)`）同樣抹雜湊
    CDN_FONT_RE = %r{(?:(?:https?:)?//[^/"'\s]+)?/cdn/fonts/([\w-]+)/([\w-]+)\.[0-9a-f]{40}\.(woff2?)}
    # E17：JSON 跳脫形的主題資產路徑（Ella `window.photoswipeUrls = { css: "\/\/hoko.vip\/cdn\/shop\/t\/2\/assets\/lib-photoswipe.css" }`）
    CDN_ASSET_JSON_RE = %r{(?:https?:)?\\/\\/[^\\"'\s]+\\/cdn\\/shop\\/t\\/\d+\\/assets\\/}
    # 切段終點：下一個 wrapper、`</main>` 或 `</body>`（最先出現者）——否則最後一段會把頁尾／平台注入一併算進去
    SECTION_STOP_RE = %r{</main>|</body>|<!-- END sections:}
    # placeholder 插圖本體＝本尊版權圖 vs 我方自繪（鐵律 9，已登記差異）⇒ 只比外框屬性，內容以替身取代
    PLACEHOLDER_SVG_RE = %r{(<svg\b[^>]*(?:placeholder-svg|preserveAspectRatio="xM(?:ax|id)YM(?:id|in) slice")[^>]*>).*?</svg>}m

    # @param host [String] 該份 HTML 的主機名（絕對網址抹成相對）
    # @param url_prefix [String, nil] 我方路由前綴（例 "/zh-hans-tw"）。🔴 **已登記的裁定差異**，不是引擎缺口：
    #   67 §F.1(b)（2026-08-13 裁定）我方前綴「恆帶地區、恆有前綴、無例外」，本尊主市場預設語言**無前綴**
    #   （hoko.vip：`href="/collections/all"`）。對表時抹掉我方前綴以露出其餘差異；要不要改裁定＝待使用者裁定
    #   （docs/dev/e8-render-parity.md §4）。
    def initialize(host:, url_prefix: nil)
      @host = host.to_s
      @url_prefix = url_prefix.to_s.presence
    end

    # @return [String] 正規化後 HTML
    def call(html)
      s = html.dup
      if @host.present?
        bare = Regexp.escape(@host.sub(/:\d+\z/, "")) # 本機埠形（mirror.localhost:3000）與無埠形（canonical）一併抹
        s.gsub!(%r{https?://#{bare}(?::\d+)?}, "")
        s.gsub!(%r{//#{bare}(?::\d+)?(?=/)}, "")
        # JSON-LD／`json` filter 的跳脫形 `https:\/\/host`（hoko 商品頁 `"@id": "https:\/\/hoko.vip\/products\/…"`）
        s.gsub!(%r{https?:\\/\\/#{bare}(?::\d+)?}, "")
      end
      if @url_prefix
        p = Regexp.escape(@url_prefix)
        s.gsub!(/#{p}(?=\/)/, "")            # /zh-hans-tw/collections/all ⇒ /collections/all
        s.gsub!(/#{p}(?=["'?#\s])/, "/")     # href="/zh-hans-tw" ⇒ href="/"
        s.gsub!(/#{Regexp.escape(@url_prefix.gsub('/', '\\/'))}(?=\\\/)/, "") # JSON 跳脫形 `\/zh-hans-tw\/products`
      end
      s.gsub!(CDN_ASSET_RE, "/theme-assets/")
      s.gsub!(CDN_ASSET_JSON_RE, "\\\\/theme-assets\\\\/")
      s.gsub!(CDN_FONT_RE, "/fonts/\\1/\\2.\\3")
      s.gsub!(ASSET_VERSION_RE, "")
      s.gsub!(GROUP_ID_RE, "sections--G__")
      s.gsub!(TEMPLATE_ID_RE, "template--T__")
      s.gsub!(BLOCK_SCOPE_RE, "B__")
      s.gsub!(PLACEHOLDER_SVG_RE) { "#{Regexp.last_match(1)}[placeholder]</svg>" }
      # window.Shopify 的平台身分值（永久網域、主題數字 id、CDN 主機）：形同、值必然不同
      s.gsub!(/Shopify\.shop = "[^"]*"/, 'Shopify.shop = "SHOP"')
      s.gsub!(/"id":\d+,"schema_name"/, '"id":N,"schema_name"')
      s.gsub!(/(Shopify\.theme = \{"name":")[^"]*"/, '\1NAME"') # E19：主題名（本尊＝上傳 zip 名 `ella-7-2-0-theme-source`）
      s.gsub!(/Shopify\.cdnHost = "[^"]*"/, 'Shopify.cdnHost = "CDN"')
      s.gsub!(/name="authenticity_token" value="[^"]*"/, 'name="authenticity_token" value="TOKEN"')
      s.gsub!(/"reqid":"[^"]*"/, '"reqid":"REQ"')
      # E8b：商品／變體數字 id（本尊 13 碼 vs 我方流水號；hoko.vip 商品頁 `data-product-id="7771796897895"`、`?variant=44547877830759`）
      # ——只抹 id 屬性與 query 的數值，不抹其他數字。
      s.gsub!(/(data-(?:product|variant|section-product)-id=")\d+"/, '\1ID"')
      s.gsub!(/([?&]variant=)\d+/, '\1ID')
      s.gsub!(/("(?:product_id|variant_id|productId|variantId)":\s*)\d+/, '\1ID')
      s.gsub!(/(name="id"[^>]*value=")\d+"/, '\1ID"')
      # Ella 商品頁：`countdown_{product.id}`／`data-countdown-id`／`window.product_inventory(_policy)_array_{id} = { '{variant.id}': … }`
      s.gsub!(/((?:countdown|_array)_)\d+/, '\1ID')
      s.gsub!(/(data-countdown-id=")\d+"/, '\1ID"')
      s.gsub!(/'\d+':\s*'/, "'ID': '")
      s.gsub!(/(#offer-)\d+/, '\1ID')                       # JSON-LD offer @id
      s.gsub!(/((?:for|id)=")\d+(input-)/, '\1ID\2')       # Ella 自訂欄位 `{product.id}input-text`
      s.gsub!(/(name="product-id" value=")\d+"/, '\1ID"')
      # E8b：集合頁商品卡（hoko.vip `template--T__product-grid-7771796897895`、`data-json-product='{"id": 777…`、
      # 變體 `&quot;id&quot;:4454…`、`StandardCardNoMediaLink--777…`）——只抹數字 id，handle／title 照留
      s.gsub!(/(product-grid-)\d+(?=")/, '\1ID')
      s.gsub!(/("id":\s*)\d+/, '\1ID') # 我方流水號可為一位數（`data-subtotal-variants` 的 `"id":7`）
      s.gsub!(/(ShareMessage-)\d+/, '\1ID') # Ella share-button `id="ShareMessage-{product.id}"`
      s.gsub!(/(&quot;id&quot;:)\d+/, '\1ID')
      s.gsub!(/((?:NoMediaLink|StandardBadge)--)\d+/, '\1ID') # `StandardCardNoMediaLink--`／`NoMediaStandardBadge--`
      # E17（hoko.vip 2026-09-05 區段 fetch／view 模板）：商品卡／比較表／編輯車的商品 id 屬性、推薦卡 grid item
      # `…_ecaxGU-7771802992743-1`、以商品 id 開頭的 block scope `…ecaxGU7771802992743AbjNlRGcvbVR4aWtTS__`——形同值異
      s.gsub!(/(data-(?:product-card|product-compare|cart-edit)-id=")\d+"/, '\1ID"')
      s.gsub!(/(id="product-edit-)\d+"/, '\1ID"')
      s.gsub!(/(_[A-Za-z0-9]{6}-)\d{1,13}(-\d+")/, '\1ID\2')
      s.gsub!(/\d+A[A-Za-z0-9]{17}__/, "IDB__")
      # E17：搜尋歸因的 session id（`_sid=25ef0946b`／predictive `_psid=…`：每次回應隨機）；比較表／編輯車的商品 id
      # （`data-compare-item="777…"`、`data-section="777…"`、`edit-quantity-777…`、`product-form-edit-777…`、`product-edit-options-777…`）；
      # 以 wrapper key 開頭、`-{商品 id}"` 結尾的元素 id（`template--T__main-search-777…"`、`…_ecaxGU-777…"` 售罄鈕）
      s.gsub!(/([?&]_p?sid=)[0-9a-f]{9}/, '\1SID')
      # E18：動態結帳骨架的身分值（本尊 storefront access token／店 id）
      s.gsub!(/(access-token=")[0-9a-f]{32}"/, '\1TOKEN"')
      s.gsub!(/(shop-id=")\d+"/, '\1ID"')
      # E18：平台 head 注入的動態結帳 bootstrap 內嵌 script（`data-source-attribution="shopify.dynamic_checkout.*"`＋
      # `function portableWalletsCleanup…`）——本體我方自寫（鐵律 9），只比 tag 與屬性；本體以替身取代
      s.gsub!(%r{(<script data-source-attribution="shopify\.dynamic_checkout\.[a-z_.]+">).*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{(<script>)\s*function portableWalletsCleanup.*?(</script>)}m, '\1[platform]\2')
      s.gsub!(/(portable-wallets\.)[a-z-]+(\.js)/, '\1LANG\2') # 語言別 bundle 檔名（頁語言決定；同頁必同）
      # E19：content_for_header 完整本尊形（external-facts §G27）——平台 CDN 主機、資產雜湊／SRI、每請求值、身分值、我方自寫本體的內嵌 script
      s.gsub!(%r{https?://cdn\.shopify\.com/}, "/cdn/") # 本尊平台 CDN `cdn.shopify.com/{path}` ≡ 店主機 `/cdn/{path}`（hoko 兩形並存）
      s.gsub!(%r{//cdn\.shopify\.com/}, "/cdn/")
      s.gsub!(/("pageurl":")[^"\\]+/, '\1HOST') # `__st.pageurl` 的主機段（無 scheme，主機規則抓不到）
      s.gsub!(/((?:load_feature|origin_trials|autosizes|shop_events_listener)-)[0-9a-f]{8}(\.js)/, '\1HASH\2')
      s.gsub!(/(trekkie\.storefront\.)[0-9a-f]{40}(\.min\.js)/, '\1HASH\2')
      s.gsub!(/integrity="sha256-[^"]*"/, 'integrity="SRI"')
      s.gsub!(/(default_configuration_id=)\d+/, '\1ID')
      s.gsub!(%r{(content=")/\d+(/digital_wallets/dialog")}, '\1/ID\2')
      s.gsub!(/(data-(?:shop-id|theme-instance-id)=")\d+"/, '\1ID"')
      s.gsub!(/(data-render-region=")[^"]*"/, '\1REGION"')
      s.gsub!(/(data-theme-name=")[^"]*"/, '\1NAME"')
      s.gsub!(/(name="shopify-[ys]" content=")[^"]*(" data-expiration=")\d+"/, '\1UUID\2T"')
      s.gsub!(/"u":"[0-9a-f]{12}"/, '"u":"U"')
      s.gsub!(/("(?:a|rid|shopId|resourceId|productId|variantId)":)\d+/, '\1ID')
      s.gsub!(/("s":")(pages|blogs|articles)-\d+"/, '\1\2-ID"')
      s.gsub!(/"accessToken":"[0-9a-f]{32}"/, '"accessToken":"TOKEN"')
      s.gsub!(/("domain":")[^"]*"/, '\1DOMAIN"')
      s.gsub!(/("requestId":")[^"]*"/, '\1REQ"')
      s.gsub!(%r{("(?:gid|productGid)":"gid:\\/\\/)[a-z]+(\\/Product\\/)\d+"}, '\1P\2ID"')
      s.gsub!(/(themeId":)\d+/, '\1ID')
      s.gsub!(/("themeCityHash":")\d+"/, '\1H"')
      s.gsub!(/("eventMetadataId":")[^"]*"/, '\1UUID"')
      s.gsub!(/("apiClientId":)\d+/, '\1ID')
      s.gsub!(/(shop_id:)\d+/, '\1ID')
      s.gsub!(/(Shopify\.MCP\.shop = ")[^"]*"/, '\1SHOP"')
      s.gsub!(/(Shopify\.MCP\.mcpEndpoint = ")[^"]*"/, '\1EP"')
      s.gsub!(/(Shopify\.MCP\.tools = )\[.*?\];/m, '\1[tools];') # 工具描述文字我方自寫
      s.gsub!(/(Shopify\.shopJsCdnBaseUrl = ")[^"]*"/, '\1CDN"')
      s.gsub!(/(<link href=")[^"]*(" rel="dns-prefetch">)/, '\1H\2')
      # 我方自寫本體的內嵌 script（只比 tag／屬性；依簽章辨識）
      s.gsub!(%r{(<script id="captcha-bootstrap">).*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{(<script class="analytics">).*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{(<script>)(?:\s*\(function\s*\(\)\s*\{\s*var\s+(?:userAgent|ua)\s*=\s*navigator\.userAgent).*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{(<script>)(?:\s*!function\(o\)\{function n\(\)|\s*\(function\(w\)\{function q\(\)).*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{(<script>)(?:\s*\(\(\)=>\{var d="shopify:webmcp_adapter_loaded"|\s*\(function\(\)\{var d="shopify:webmcp_adapter_loaded").*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{(<script>)\(function\(\)\{if\s*\("sendBeacon" in navigator.*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{(<script>)\(function\(\)\{var (?:wpmLoader|cfg)=.*?(</script>)}m, '\1[platform]\2')
      s.gsub!(%r{//cdn\.shopify\.com/static/images/flags/}, "/cdn/static/images/flags/") # E17：國旗平台 CDN 主機（我方＝店主機同路徑，先前已抹）
      s.gsub!(/(data-(?:compare-item|section)=")\d+"/, '\1ID"')
      s.gsub!(/((?:edit-quantity-|product-form-edit-|product-edit-options-))\d+/, '\1ID')
      # 段：`-` 後以字母／底線開頭（且不是已抹出的 `ID` 替身）才算 key 的一段——`-7771802992743-1"` 的 `-1` 是索引、由上一條處理，
      # 索引值不抹（slide 序差異要留給 diff 看見）
      s.gsub!(/(template--T__[A-Za-z0-9_]+(?:-(?!ID\b)[A-Za-z_][A-Za-z0-9_]*)*-)\d+(?=")/, '\1ID')
      s.gsub!(/\s+/, " ")
      s
    end

    # 切成 section 段：key ⇒ 該段 HTML（從 wrapper 開頭到下一個 wrapper 或 </main>/</body>）。
    def sections(html)
      out = {}
      head = html[%r{<head\b.*?</head>}m]
      out["__head__"] = head if head
      positions = html.to_enum(:scan, /<(?:div|section|header|footer|aside|article|main)[^>]*\sid="shopify-section-([^"]+)"/).map do
        [ Regexp.last_match(1).split("__").last, Regexp.last_match.begin(0) ]
      end
      positions.each_with_index do |(key, start), index|
        stop = [ positions[index + 1]&.last, html.index(SECTION_STOP_RE, start + 1), html.length ].compact.min
        out[key] = html[start...stop]
      end
      out
    end
  end
end
