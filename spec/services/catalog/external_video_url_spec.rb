# frozen_string_literal: true

require "rails_helper"

# 第 37 包：外嵌影片 URL 的解析與正規化。
#
# 🔴 本檔最重要的一段是**攻擊形態**那一組，不是快樂路徑。`ExternalVideoUrl` 是
#   「使用者字串永遠到不了 iframe src」這條防線的實作；它一旦鬆掉，`javascript:`
#   會在我方 origin 執行（MDN 逐字：`javascript:` URL 的 script 繼承載入它的文件的
#   origin）⇒ 讀得到 admin cookie、打得到 admin API。CSP 是第二道，不是第一道。
RSpec.describe Catalog::ExternalVideoUrl do
  Parsed = Catalog::ExternalVideoUrl::Parsed

  def parse(url) = described_class.parse(url)
  def ok?(url) = parse(url).is_a?(Parsed)

  describe "接受的形態" do
    {
      "https://www.youtube.com/watch?v=dQw4w9WgXcQ" => %w[youtube dQw4w9WgXcQ],
      "https://youtube.com/watch?v=dQw4w9WgXcQ" => %w[youtube dQw4w9WgXcQ],
      "https://m.youtube.com/watch?v=dQw4w9WgXcQ" => %w[youtube dQw4w9WgXcQ],
      "https://youtu.be/32mGBDk3LSo" => %w[youtube 32mGBDk3LSo],
      "https://www.youtube.com/embed/dQw4w9WgXcQ" => %w[youtube dQw4w9WgXcQ],
      "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" => %w[youtube dQw4w9WgXcQ],
      "https://vimeo.com/76979871" => %w[vimeo 76979871],
      "https://player.vimeo.com/video/76979871" => %w[vimeo 76979871]
    }.each do |url, (host, id)|
      it "#{url} → #{host}/#{id}" do
        result = parse(url)
        expect(result).to be_a(Parsed)
        expect([ result.host, result.external_id ]).to eq([ host, id ])
      end
    end

    it "🔴 追蹤參數一律丟棄（不存使用者原字串）" do
      result = parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLxx&t=42&si=track")
      # 存進 DB 的是**重建**的 URL——使用者可控字元從此不存在於任何會進 HTML 的欄位
      expect(result.origin_url).to eq("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      expect(result.origin_url).not_to include("list", "si", "t=")
    end
  end

  describe "拒絕的形態" do
    {
      "Shorts（help 逐字：不支援，可改成 watch 形態）" => "https://www.youtube.com/shorts/abc123",
      "Vimeo unlisted 的 privacy hash（path 載體）" => "https://vimeo.com/76979871/abcdef",
      "🔴 同一個 hash 的 query 載體也要拒（官方 Share→Embed 給的形態）" => "https://player.vimeo.com/video/76979871?h=abcdef1234",
      "query 載體之二（影片頁 URL 帶 h）" => "https://vimeo.com/76979871?h=abcdef1234",
      "Vimeo vanity URL（help 逐字要求用 direct video URL）" => "https://vimeo.com/mychannel/myvideo",
      "Vimeo 非數字 id" => "https://vimeo.com/notanumber",
      "空的 v 參數" => "https://www.youtube.com/watch?v=",
      "沒有影片的首頁" => "https://www.youtube.com/",
      "非 YouTube/Vimeo（help 逐字：其他平台不支援）" => "https://dailymotion.com/video/x1"
    }.each do |label, url|
      it(label) { expect(ok?(url)).to be(false) }
    end
  end

  describe "🔴 攻擊形態" do
    {
      "javascript: 在我方 origin 執行 ⇒ 完整 XSS" => "javascript:alert(document.cookie)",
      "data: 取得 opaque origin，仍可渲染攻擊者的 HTML" => "data:text/html,<script>alert(1)</script>",
      "http 可被中間人改寫，而它會變成前台 iframe 的網域" => "http://www.youtube.com/watch?v=dQw4w9WgXcQ",
      "userinfo 偽裝 host" => "https://user:pw@youtube.com/watch?v=dQw4w9WgXcQ",
      "fragment 偽裝 host" => "https://evil.com/watch?v=x#youtube.com",
      "後綴偽裝 host" => "https://www.youtube.com.evil.com/watch?v=x",
      "超長 id（防呆上界）" => "https://www.youtube.com/watch?v=#{'A' * 100}",
      "空字串" => "",
      "nil" => nil
    }.each do |label, url|
      it(label) { expect(ok?(url)).to be(false) }
    end
  end

  describe "導出的 URL（不落庫）" do
    it "YouTube 用 privacy-enhanced 網域" do
      # 官方逐字："Change the domain for the embed URL in your HTML from
      # https://www.youtube.com to https://www.youtube-nocookie.com."
      expect(described_class.embed_url("youtube", "abc")).to eq("https://www.youtube-nocookie.com/embed/abc")
    end

    it "Vimeo 帶 dnt 參數" do
      expect(described_class.embed_url("vimeo", "123")).to eq("https://player.vimeo.com/video/123?dnt=1")
    end

    it "🔴 embed URL 由 limits 樣板導出 ⇒ 翻設定即全店生效，不必跑 data migration" do
      # 這一條釘的是「導出」這個設計本身：把隱私開關關掉，同一列資料要立刻產出不同的 URL。
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:media, :external_video_privacy_enhanced).and_return(false)
      expect(described_class.embed_url("vimeo", "123")).to eq("https://player.vimeo.com/video/123")
    end
  end
end
