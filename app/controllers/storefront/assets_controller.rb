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

    before_action :require_published_theme!, except: %i[no_image flag]

    # E17：`img_url` 對 nil 的平台「無圖」佔位——路徑形照本尊 `/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12_{size}.gif`
    # （hoko.vip 2026-09-05），圖片本體＝我方自繪 1×1 淺灰 gif（鐵律 9：不用本尊圖片；佔位插圖自繪例外）。
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
