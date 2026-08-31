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

    before_action :require_published_theme!

    # GET /theme-assets/*file
    def show
      rel = params[:file].to_s
      # 🔴 主題根**內**的逃逸也要擋（S7 抓到的現行犯）：FileSource 只擋根外；
      # `assets/../config/settings_data.json` 仍在根內 ⇒ 商家設定與模板原始碼會被公開讀走。
      return head :not_found if rel.blank? || rel.include?("..") || rel.include?("\\")

      source = ThemeEngine::Sources.resolve(published_theme)
      body = source&.read(File.join("assets", rel))
      return head :not_found if body.nil?

      response.headers["Cache-Control"] = "public, max-age=300"
      send_data body, type: Marcel::MimeType.for(name: params[:file].to_s), disposition: "inline"
    end
  end
end
