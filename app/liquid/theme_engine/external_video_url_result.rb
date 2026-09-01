# frozen_string_literal: true

module ThemeEngine
  # PR-16：`external_video_url` 的回傳值——URL 字串子類，攜帶 host 型別與
  # 標題供 `external_video_tag` 組 iframe（官方：tag 收「either a media
  # object or external_video_url」——同 ImageUrlResult 的攜帶式設計）。
  # 🔴 這個字串只進屬性值/管道，不做 Liquid 屬性存取（String#[] 陷阱見
  # VideoUrlDrop 註釋）。
  class ExternalVideoUrlResult < String
    attr_reader :video_type, :title

    def initialize(url, video_type:, title: nil)
      super(url)
      @video_type = video_type
      @title = title
    end
  end
end
