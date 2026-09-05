# frozen_string_literal: true

module Storefront
  # 已發布主題的資產供給（包 33 後半；`{{ 'x.css' | asset_url }}` ⇒ `/theme-assets/x.css`）。
  #
  # 路徑逃逸由 `FileSource` 防線擋（同預覽面 spec E7——read 只接受來源根以下的相對路徑）。
  # 快取：主題資產檔名**未指紋化**（第三方主題原樣檔名）⇒ 不能 immutable；
  # 短 max-age 折衷（發布新主題後最多 300s 舊資產窗）。指紋化管線登記為後續改善。
  class AssetsController < BaseController
    # 🔴 必須跳過 CSRF：Rails 的 cross-origin JavaScript 防護（verify_same_origin_request）
    # 會對「未帶 CSRF token 的 GET ＋ JS content-type 回應」拋
    # InvalidCrossOriginRequest ⇒ 前台 <script src> 載主題 .js 一律 422、整站無腳本。
    # bt3 部署預覽實錘（2026-08-31）：.css 200、.js 全 422——content-type 選擇性觸發；
    # 🔴 test 環境 allow_forgery_protection=false ⇒ 既有 request spec 結構上測不到，
    # 對應殺手格（S10）顯式開 forgery 再打。純讀端點無狀態變更，CSRF 語義不適用。
    skip_forgery_protection

    before_action :require_published_theme!, except: %i[no_image flag portable_wallets accelerated_checkout_css cdn font themes_support global_asset]

    # E17：`img_url` 對 nil 的平台「無圖」佔位——路徑形照本尊 `/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12_{size}.gif`
    # （hoko.vip 2026-09-05），圖片本體＝我方自繪 1×1 淺灰 gif（鐵律 9：不用本尊圖片；佔位插圖自繪例外）。
    # T12：hoko.vip 主題資產回應 `cache-control: public, max-age=31557600`（＝365.25 天；Rails `1.year`＝31556952 不同值）
    THEME_ASSET_MAX_AGE = 31_557_600.seconds

    NO_IMAGE_GIF = [ "47494638396101000100800000f2f2f2ffffff21f90401000000002c00000000010001000002024401003b" ].pack("H*").freeze

    def no_image
      expires_in 1.year, public: true
      send_data NO_IMAGE_GIF, type: "image/gif", disposition: "inline"
    end

    # E17：`country | image_url` 的國旗（路徑形照本尊 `/cdn/static/images/flags/{cc}.svg`）；圖檔＝MIT `flag-icons` 4x3
    # （`node_modules/flag-icons/flags/4x3/{cc}.svg`，LICENSE 隨套件；本尊 SVG 亦為 640×480）。查無國碼 ⇒ 404。
    # 🔴 Brakeman「Parameter value used in file name」：不以參數組檔案路徑——啟動時把整個 4x3 目錄讀成 `{code => svg}` 常量
    # （271 檔、約 1 MB），以 send_data 供給；目錄不存在（未 pnpm install）⇒ 空表 ⇒ 全 404（F9 會抓到）。
    FLAG_SVGS = Dir.glob(Rails.root.join("node_modules/flag-icons/flags/4x3/*.svg").to_s)
                   .to_h { |path| [ File.basename(path, ".svg"), File.binread(path).freeze ] }.freeze

    def flag
      svg = FLAG_SVGS[params[:cc].to_s.downcase]
      return head :not_found if svg.nil?

      expires_in 1.year, public: true
      send_data svg, type: "image/svg+xml", disposition: "inline"
    end

    # E18：動態結帳模組（本尊 `portable-wallets.{lang}.js`，語言隨頁 `<html lang>`——hoko.vip 五語言頁各載 en／zh-cn／zh-tw／fr／ja；
    # 「立即購買」文案＝各語言 bundle 的 `instruments_copy.checkout.buy_now` 逐字，external-facts §G26）。本體我方自寫
    # （鐵律 9：不抄本尊 JS），只有 tag／屬性／id／class 這些主題會依賴的介面同形。檔案啟動時讀成常量（Brakeman：不以參數組路徑）。
    PORTABLE_WALLETS_JS = File.read(Rails.root.join("app/assets/storefront/portable-wallets.js")).freeze
    ACCELERATED_CHECKOUT_CSS = File.read(Rails.root.join("app/assets/storefront/accelerated-checkout-backwards-compat.css")).freeze

    def portable_wallets
      tag = ThemeEngine::LocaleTags.platform_tag(lang_code_to_shopify(params[:lang]))
      label = PlatformStrings.dict(tag).dig("_platform", "accelerated_checkout", "buy_now") ||
              PlatformStrings.dict("en").dig("_platform", "accelerated_checkout", "buy_now")
      body = PORTABLE_WALLETS_JS.sub("__BUY_NOW_LABEL__") { label.to_json }
      expires_in 5.minutes, public: true
      send_data body, type: "text/javascript; charset=utf-8", disposition: "inline"
    end

    def accelerated_checkout_css
      expires_in 5.minutes, public: true
      send_data ACCELERATED_CHECKOUT_CSS, type: "text/css; charset=utf-8", disposition: "inline"
    end

    # `zh-cn` ⇒ `zh-CN`（本尊 bundle 檔名＝語言碼小寫；LocaleTags 只認本尊大小寫形）
    def lang_code_to_shopify(code)
      lang, region = code.to_s.split("-", 2)
      region ? "#{lang.downcase}-#{region.upcase}" : lang.to_s.downcase
    end

    # T12：GET /cdn/shop/t/:theme_id/assets/*file（本尊形；ThemeEngine::AssetUrls）。任一主題以 id 供給（租戶內；本尊未發布主題亦可由 id 取得）。
    # `?v=` 只作快取鍵（本尊錯 v／無 v 皆 200——hoko.vip 2026-09-05）；`_{size}` 尺寸形 ⇒ 回原檔（我方不縮放主題資產，91 V）。
    # 回應標頭照 hoko 實測：`cache-control: public, max-age=31557600`、`access-control-allow-origin: *`；缺檔 404 `public, max-age=60`。
    def cdn
      rel = params[:file].to_s
      return not_found_asset if rel.blank? || rel.include?("..") || rel.include?("\\")

      theme = ActsAsTenant.with_tenant(current_shop) { Theme.find_by(shop_id: current_shop.id, id: params[:theme_id]) }
      source = theme && ThemeEngine::Sources.resolve(theme)
      return not_found_asset if source.nil?

      body = source.read(File.join("assets", rel))
      if body.nil?
        base, size = ThemeEngine::AssetUrls.split_size(rel)
        body = source.read(File.join("assets", base)) if size
      end
      return not_found_asset if body.nil?

      expires_in THEME_ASSET_MAX_AGE, public: true # hoko `public, max-age=31557600`；Rails 出 `max-age=…, public`（指令順序差登記 91）
      response.headers["Access-Control-Allow-Origin"] = "*"
      send_data body, type: Marcel::MimeType.for(name: rel), disposition: "inline"
    end

    # T12：GET /cdn/fonts/:family/:file（`{handle}.{sha1}.woff2`；雜湊不符或 .woff ⇒ 404）。標頭照 hoko：`public, max-age=31536000, immutable`＋CORS *。
    def font
      m = params[:file].to_s.match(/\A([a-z0-9_-]+)\.([0-9a-f]{40})\.(woff2?)\z/) or return not_found_asset
      handle, sha, ext = m[1], m[2], m[3]
      family = params[:family].to_s
      return not_found_asset unless ext == "woff2" && ThemeEngine::FontFiles.sha1(family, handle) == sha

      expires_in 365.days, public: true # ＝31536000（hoko `public, max-age=31536000, immutable`）
      response.cache_control[:extras] = [ "immutable" ]
      response.headers["Access-Control-Allow-Origin"] = "*"
      send_data ThemeEngine::FontFiles.body(family, handle), type: "font/woff2", disposition: "inline"
    end

    # T12：themes_support（option_selection／currencies／vendor/qrcode／gift-card 圖）與 global 資產——本尊本體不可抄（鐵律 9），我方尚未自寫 ⇒ 404（91 V）
    def themes_support = not_found_asset
    def global_asset = not_found_asset

    def not_found_asset
      expires_in 60.seconds, public: true # hoko 缺檔 `public, max-age=60`
      head :not_found
    end

    # GET /theme-assets/*file
    def show
      rel = params[:file].to_s
      # 🔴 主題根**內**的逃逸也要擋（S7 抓到的現行犯）：FileSource 只擋根外；
      # `assets/../config/settings_data.json` 仍在根內 ⇒ 商家設定與模板原始碼會被公開讀走。
      return head :not_found if rel.blank? || rel.include?("..") || rel.include?("\\")

      # PR-12：預覽釘選時供預覽主題的資產（同 URL 不同主題 ⇒ 必須 no-store，
      # 否則瀏覽器/代理把預覽版 CSS 快取進正式路徑，解除預覽後仍髒 300s）
      source = ThemeEngine::Sources.resolve(current_theme)
      body = source&.read(File.join("assets", rel))
      return head :not_found if body.nil?

      response.headers["Cache-Control"] = preview_theme_active? ? "no-store" : "public, max-age=300"
      send_data body, type: Marcel::MimeType.for(name: params[:file].to_s), disposition: "inline"
    end
  end
end
