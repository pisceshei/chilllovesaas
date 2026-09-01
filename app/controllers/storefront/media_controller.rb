# frozen_string_literal: true

module Storefront
  # 買家面媒體服務（Ella 修復 PR-2；根因 A＝ImageDrop#url 恆 nil、買家面無任何
  # 媒體端點 ⇒ 真圖鏈輸出端斷裂）。
  # ①查找憑 shop_id＋id（租戶隔離天然成立）；filename 段不參與查找。
  # ②Cache-Control public 1 天（檔案可被同 id 換內容的形態未定案前不設 immutable）。
  class MediaController < BaseController
    # PR-9：?width=/?height= 變體選擇（官方語義：CDN 依尺寸參數縮圖、
    # "an image can never be resized to be larger than its original dimensions"
    # ——文檔取證 2026-09-01）。候選＝derivatives 的 fit 變體（排除 og——cover
    # 裁切改比例）；以 entry 實際 width/height 選「最小的 ≥ requested」；全部
    # 不足或無 derivatives ⇒ 原圖（天然滿足永不放大）。衍生 blob 缺檔回落原圖。
    FIT_VARIANTS = %w[thumb card detail].freeze

    def show
      file = StoredFile.find_by(shop_id: current_shop.id, id: params[:id])
      return head :not_found if file.nil? || file.status == "failed"

      entry = pick_variant(file, params[:width].to_i, params[:height].to_i)
      expires_in 1.day, public: true
      if entry
        begin
          return send_data Storage::LocalDisk.read(entry["key"]), type: "image/webp",
                           disposition: "inline"
        rescue Errno::ENOENT, Storage::LocalDisk::InvalidKey
          # 衍生缺檔 ⇒ 回落原圖
        end
      end
      send_data Storage::LocalDisk.read(file.storage_key),
                type: file.content_type.presence || Marcel::MimeType.for(name: file.filename.to_s),
                disposition: "inline"
    rescue Errno::ENOENT, Storage::LocalDisk::InvalidKey
      head :not_found
    end

    private

    def pick_variant(file, req_w, req_h)
      return nil if req_w.zero? && req_h.zero?

      derivatives = file.derivatives
      return nil unless derivatives.is_a?(Hash)

      candidates = FIT_VARIANTS.filter_map { |name| derivatives[name] }
                               .select { |e| e.is_a?(Hash) && e["key"] }
      dim = req_w.positive? ? "width" : "height"
      req = req_w.positive? ? req_w : req_h
      candidates.select { |e| e[dim].to_i >= req }.min_by { |e| e[dim].to_i }
    end
  end
end
