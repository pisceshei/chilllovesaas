# frozen_string_literal: true

module Catalog
  # 外嵌影片 URL 的解析與正規化（第 37 包）。
  #
  # ①這是什麼：**純字串處理**，把使用者貼的 YouTube／Vimeo URL 拆成
  #   `(host, external_id)`，再由 limits 的樣板重建 origin／embed URL。
  #   🔴 **不打網路**——不碰 `Storage::SafeFetch`、不做可用性驗證。影片是否真的存在、
  #   是否可嵌入，屬 B 面（oEmbed），閘門＝limits `media.external_video_oembed_enabled`。
  #
  # ②🔴 **這一支是注入面的主防線，不是便利函式**：
  #   `javascript:` URL 放進 `<iframe src>` 是合法的導航脈絡，而 MDN 逐字載明
  #   「Scripts executed from pages with an about:blank or `javascript:` URL inherit
  #   the origin of the document containing that URL」⇒ 那等於**在我方 origin 執行的
  #   完整 XSS**（讀得到 admin cookie、打得到 admin API）。`data:` URL 拿到的是
  #   opaque origin、偷不到 cookie，但仍可在我方頁框內渲染攻擊者完全控制的 HTML。
  #   **本模組的存在就是為了讓「使用者字串」永遠到不了 `src`**：落庫的只有
  #   一個封閉值域的 `host` 與一個受字元集約束的 `external_id`，其餘全部丟棄
  #   （`?si=`、`&list=`、`&t=`、fragment、userinfo 一律不留）。
  #   CSP `frame-src` 白名單（第 33 包）是第二道，不是第一道。
  #
  # ③🔴 **接受哪些形態全部是我方裁定（ours），不是「對齊本尊」**：官方三處措辭互斥
  #   ——API reference 範例用 `https://youtu.be/32mGBDk3LSo`；dev 指南表格寫
  #   "Provide the embed or share URL."；help center 只列
  #   `https://youtube.com/watch?v=[video-id]` 與 `https://vimeo.com/[video-id]`
  #   並說 "use the video's page URL"。**沒有任何一句規範性語句定義 `originalSource`
  #   該放哪種 URL**（未取得清單 U1）。取證日期 2026-08-25。
  #
  # ④跨功能影響：`Catalog::MediaSync.create` 的分派、`Types::ExternalVideoType` 的
  #   `embedUrl`／`originUrl` 導出、第 30／33 包的 Liquid `external_video` drop。
  module ExternalVideoUrl
    # 解析成功。`origin_url` 是**重建**的，不是使用者原字串。
    Parsed = Data.define(:host, :external_id, :origin_url)
    # 解析失敗。`code` 進 userErrors（鐵律 4 第①層，HTTP 仍 200）。
    Rejection = Data.define(:code, :message_key)

    # 🔴 只認 https。http 一律拒——兩個平台都只走 https，接受 http 等於接受一個
    #   會被中間人改寫的來源，而它最後會變成前台 iframe 的網域。
    SCHEME = "https"

    # YouTube 的 ID 字元集。🔴 **不得寫死 11 碼**——長度沒有任何官方來源
    #   （坊間說法，本輪取證＝未取得），寫死就是憑記憶造判準。上界引 limits。
    YOUTUBE_ID = /\A[A-Za-z0-9_-]+\z/
    # Vimeo 的 ID 是純數字（help 逐字 `https://vimeo.com/[video-id]`）。
    # 純數字規則順帶擋掉 vanity URL——help 逐字要求
    # "use the direct video URL instead of your custom vanity URL"。
    VIMEO_ID = /\A[0-9]+\z/

    YOUTUBE_HOSTS = %w[youtube.com www.youtube.com m.youtube.com
                       youtu.be www.youtu.be
                       youtube-nocookie.com www.youtube-nocookie.com].freeze
    VIMEO_HOSTS = %w[vimeo.com www.vimeo.com player.vimeo.com].freeze

    class << self
      # @param raw [String] 使用者貼的 URL
      # @return [Parsed, Rejection]
      def parse(raw)
        uri = safe_uri(raw)
        return Rejection.new(:invalid_url, "errors.media.external_video_invalid_url") if uri.nil?

        host = uri.host.to_s.downcase
        parsed =
          if YOUTUBE_HOSTS.include?(host) then parse_youtube(uri, host)
          elsif VIMEO_HOSTS.include?(host) then parse_vimeo(uri, host)
          else
            # help 逐字："URLs other than YouTube or Vimeo URLs aren't supported."
            Rejection.new(:unsupported_host, "errors.media.external_video_unsupported_host")
          end
        return parsed if parsed.is_a?(Rejection)

        parsed
      end

      # 由 host＋id 重建 embed URL（**導出、不落庫**——見 limits
      # `external_video_embed_url_templates` 的紅字：隱私決策會變，落庫等於
      # 改設定後舊資料還停在舊網域）。
      #
      # @return [String]
      def embed_url(host, external_id)
        # 🔴 limits 的巢狀 hash 是 **symbol 鍵**（`Limits.fetch` 深層 symbolize），
        #    而 `Limits.enum` 回的是**大寫字串**——兩者不同，混用會 KeyError。
        template = Limits.fetch(:media, :external_video_embed_url_templates).fetch(host.to_sym)
        base = format(template, id: external_id)
        params = privacy_params(host)
        params.empty? ? base : "#{base}?#{URI.encode_www_form(params)}"
      end

      # @return [String]
      def origin_url(host, external_id)
        format(Limits.fetch(:media, :external_video_origin_url_templates).fetch(host.to_sym), id: external_id)
      end

      private

      def privacy_params(host)
        return {} unless Limits.fetch(:media, :external_video_privacy_enhanced)

        Limits.fetch(:media, :external_video_privacy_params).fetch(host.to_sym, {})
      end

      # 🔴 `URI.parse` 對很多垃圾字串會拋，且對 `javascript:alert(1)` 會**成功**
      #   （scheme=javascript、host=nil）——所以 scheme 與 host 都要正面檢查，
      #   不能只靠 parse 有沒有拋。
      def safe_uri(raw)
        text = raw.to_s.strip
        return nil if text.empty? || text.length > 2048

        uri = URI.parse(text)
        return nil unless uri.is_a?(URI::HTTPS) && uri.scheme == SCHEME
        return nil if uri.host.blank?
        # userinfo（`https://user:pw@youtube.com/...`）是經典的 host 偽裝手法。
        return nil if uri.userinfo.present?

        uri
      rescue URI::InvalidURIError
        nil
      end

      def parse_youtube(uri, host)
        path = uri.path.to_s
        id =
          if host.end_with?("youtu.be")
            path.delete_prefix("/")
          elsif path.start_with?("/embed/")
            # Y3（登記 V）：官方未明文接受，但正規化後與 watch 形態是**同一列資料**、
            # 零額外攻擊面；拒收一個使用者手上真能用的 URL 是可見缺陷。
            path.delete_prefix("/embed/")
          elsif path == "/watch"
            URI.decode_www_form(uri.query.to_s).to_h["v"].to_s
          elsif path.start_with?("/shorts/")
            # Y4：help 逐字 "YouTube Shorts URLs ... aren't currently supported, but you
            # can convert them by changing the URL to the standard format." ⇒ 對齊優先，
            # 拒收並在訊息裡明示可改成 watch 形態。
            return Rejection.new(:invalid_url, "errors.media.external_video_shorts")
          else
            ""
          end
        finish(:youtube, id, YOUTUBE_ID)
      end

      def parse_vimeo(uri, host)
        segments = uri.path.to_s.split("/").reject(&:empty?)
        # `player.vimeo.com/video/{id}`（V2，登記 V）與 `vimeo.com/{id}`（V1，help 逐字）。
        segments = segments.drop(1) if host == "player.vimeo.com" && segments.first == "video"
        # 🔴 V3 `vimeo.com/{id}/{hash}`（unlisted 的 privacy hash）**拒收**：官方完全
        #   未提，接受就得知道 embed 端要不要帶 `h=`；猜錯＝存進去的影片前台一定播不出來。
        #   寧可拒收也不猜（鐵律 19）。多於一段即落到 finish 的字元集檢查而被拒。
        return Rejection.new(:invalid_url, "errors.media.external_video_invalid_url") if segments.length != 1

        finish(:vimeo, segments.first.to_s, VIMEO_ID)
      end

      def finish(host, id, pattern)
        max = Limits.fetch(:media, :external_video_id_max_length)
        return Rejection.new(:invalid_url, "errors.media.external_video_invalid_url") if
          id.empty? || id.length > max || !id.match?(pattern)

        Parsed.new(host: host.to_s, external_id: id, origin_url: origin_url(host, id))
      end
    end
  end
end
