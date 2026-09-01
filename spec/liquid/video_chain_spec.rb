# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-16：影片鏈第①步（video_url setting drop＋三 filter URL 形）。
# 官方取證 2026-09-02：external_video_url（YouTube embed 官方例
# youtube.com/embed/{id}?params）、external_video_tag（iframe 官方例逐字
# frameborder/allow/allowfullscreen/src/title；輸入「either a media object or
# external_video_url」）、input-settings video_url（URL 字串＋id/type；空⇒nil）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   VC1 video_url 解析（殺：Drop 換 String 子類 ⇒ url['id'] 子字串假值）
#   VC2 embed 鏈（殺：stub 回原 URL ⇒ Ella deferred-media iframe 全空）
RSpec.describe "ThemeEngine video chain（PR-16）" do
  let(:harness) do
    h = Class.new { include ThemeEngine::Filters }.new
    h.instance_variable_set(:@context, Struct.new(:registers).new({}))
    h
  end

  it "VC1 🔴 VideoUrlDrop.parse：watch/embed/youtu.be/vimeo 四形出 id/type；垃圾 ⇒ nil" do
    y = ThemeEngine::VideoUrlDrop.parse("https://www.youtube.com/watch?v=_9VUPq3SxOc")
    expect([ y.type, y.id ]).to eq([ "youtube", "_9VUPq3SxOc" ]) # 官方例 ID 形
    expect(y.to_s).to eq("https://www.youtube.com/watch?v=_9VUPq3SxOc") # 官方：值是輸入 URL 字串

    expect(ThemeEngine::VideoUrlDrop.parse("https://youtu.be/abc123XYZ_-").id).to eq("abc123XYZ_-")
    v = ThemeEngine::VideoUrlDrop.parse("https://vimeo.com/76979871")
    expect([ v.type, v.id ]).to eq([ "vimeo", "76979871" ])
    expect(ThemeEngine::VideoUrlDrop.parse("https://example.com/x")).to be_nil
  end

  it "VC2 🔴 external_video_url → external_video_tag：官方 embed／iframe 形；參數編 query／屬性" do
    drop = ThemeEngine::VideoUrlDrop.parse("https://www.youtube.com/watch?v=_9VUPq3SxOc")
    url = harness.external_video_url(drop, { "controls" => 1, "loop" => "1" })
    expect(url).to eq("https://www.youtube.com/embed/_9VUPq3SxOc?controls=1&loop=1") # 官方 embed 形

    tag = harness.external_video_tag(url, { "class" => "youtube-video" })
    expect(tag).to include(%(frameborder="0"))                       # 官方例逐字
    expect(tag).to include(%(allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"))
    expect(tag).to include(%(allowfullscreen="allowfullscreen"))
    expect(tag).to include(%(src="https://www.youtube.com/embed/_9VUPq3SxOc?controls=1&amp;loop=1"))
    expect(tag).to include(%(class="youtube-video"))                 # 額外參數 ⇒ 屬性

    # 直餵 drop（官方：tag 收 media object「or external_video_url」——兩形都要通）
    expect(harness.external_video_tag(drop)).to include("youtube.com/embed/_9VUPq3SxOc")

    vimeo = ThemeEngine::VideoUrlDrop.parse("https://vimeo.com/76979871")
    expect(harness.external_video_url(vimeo, {})).to eq("https://player.vimeo.com/video/76979871") # V：Vimeo 官方嵌入形

    expect(harness.external_video_tag("not-a-video")).to eq("") # 不可識別 ⇒ 空（原 stub 語義保留）
  end

  it "VC3 video_tag：URL 形出 <video>；布林參數＝布林屬性、nil 略過、image_size 不落 HTML" do
    tag = harness.video_tag("https://cdn.example.com/a.mp4",
                            { "autoplay" => true, "controls" => false, "muted" => true,
                              "poster" => nil, "class" => "slide__video", "image_size" => "2500x" })
    expect(tag).to include(%(src="https://cdn.example.com/a.mp4"))
    expect(tag).to include(" autoplay")
    expect(tag).to include(%(class="slide__video"))
    expect(tag).not_to include("controls")
    expect(tag).not_to include("poster")
    expect(tag).not_to include("image_size")

    expect(harness.video_tag("garbage")).to eq("")
  end

  it "VC4 SettingsDrop coerce：video_url 空 ⇒ nil；合法 URL ⇒ VideoUrlDrop；垃圾 ⇒ nil" do
    make = lambda do |value|
      ThemeEngine::SettingsDrop.new({ "vu" => value }, { "vu" => "video_url" })
    end
    expect(make.call("").liquid_method_missing("vu")).to be_nil
    got = make.call("https://youtu.be/abc123XYZ").liquid_method_missing("vu")
    expect(got).to be_a(ThemeEngine::VideoUrlDrop)
    expect(got.type).to eq("youtube")
    expect(make.call("https://x.example/nope").liquid_method_missing("vu")).to be_nil
  end
end
