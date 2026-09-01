# frozen_string_literal: true

module ThemeEngine
  # image_url 的回傳物（PR-9）：字串子類（to_s＝URL），攜帶來源 drop 與請求
  # 尺寸——供 image_tag 推導 srcset／width/height/alt（官方："By default,
  # width and height attributes are derived from image dimensions and aspect
  # ratio"＋alt "set to the media alt text"，image_tag 文檔取證 2026-09-01）。
  class ImageUrlResult < String
    attr_reader :source_drop, :requested_width, :requested_height

    def initialize(url, source_drop: nil, requested_width: nil, requested_height: nil)
      super(url.to_s)
      @source_drop = source_drop
      @requested_width = requested_width
      @requested_height = requested_height
    end
  end
end
