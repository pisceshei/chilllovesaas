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
    TEMPLATE_ID_RE = /template--(?:\d+|[a-z0-9.\-]+)__/
    # 本尊 theme block 實例 id：`{18 碼 base64-ish}__{key}`（hoko.vip 實測 `AWlFwNUZ5UVVuRmp6e__group_announcement_bar_PeTpTw`）
    BLOCK_SCOPE_RE = /\bA[A-Za-z0-9]{17}__/
    # 本尊主題資產：`//host/cdn/shop/t/{n}/assets/x.css?v=123`；我方：`/theme-assets/x.css`
    CDN_ASSET_RE = %r{(?:https?:)?//[^/"'\s]+/cdn/shop/t/\d+/assets/}
    ASSET_VERSION_RE = /\?v=\d+/
    # 本尊字型：`/cdn/fonts/{family}/{handle}.{hash}.woff2`；我方：`/fonts/{family}/{handle}.woff2`
    CDN_FONT_RE = %r{(?:https?:)?//[^/"'\s]+/cdn/fonts/([\w-]+)/([\w-]+)\.[0-9a-f]{40}\.woff2}

    def initialize(host:)
      @host = host
    end

    # @return [String] 正規化後 HTML
    def call(html)
      s = html.dup
      s.gsub!(%r{https?://#{Regexp.escape(@host)}}, "")
      s.gsub!(%r{//#{Regexp.escape(@host)}(?=/)}, "")
      s.gsub!(CDN_ASSET_RE, "/theme-assets/")
      s.gsub!(CDN_FONT_RE, "/fonts/\\1/\\2.woff2")
      s.gsub!(ASSET_VERSION_RE, "")
      s.gsub!(GROUP_ID_RE, "sections--G__")
      s.gsub!(TEMPLATE_ID_RE, "template--T__")
      s.gsub!(BLOCK_SCOPE_RE, "B__")
      s.gsub!(/name="authenticity_token" value="[^"]*"/, 'name="authenticity_token" value="TOKEN"')
      s.gsub!(/"reqid":"[^"]*"/, '"reqid":"REQ"')
      s.gsub!(/\s+/, " ")
      s
    end

    # 切成 section 段：key ⇒ 該段 HTML（從 wrapper 開頭到下一個 wrapper 或 </main>/</body>）。
    def sections(html)
      out = {}
      positions = html.to_enum(:scan, /<(?:div|section|header|footer|aside|article|main)[^>]*\sid="shopify-section-([^"]+)"/).map do
        [ Regexp.last_match(1).split("__").last, Regexp.last_match.begin(0) ]
      end
      positions.each_with_index do |(key, start), index|
        stop = positions[index + 1]&.last || html.length
        out[key] = html[start...stop]
      end
      out
    end
  end
end
