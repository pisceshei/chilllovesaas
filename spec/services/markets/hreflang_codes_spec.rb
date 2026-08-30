# frozen_string_literal: true

require "rails_helper"

# hreflang 碼產生器（62 §I.2 裁定表逐格；恆帶地區、多國逐國展開）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   H2 多國市場逐國展開（殺：退回本尊的「多國 ⇒ 裸語言碼」行為——62 §I.2-1 明知偏離的反向）
#   H3 空 region ⇒ raise（殺：assert 拿掉後空市場靜默輸出裸碼）
#   H5 與 url_prefix 型別分離（殺：兩函式合併成一個「對外轉換」——67 §F.1(a) 明文不可）
RSpec.describe Markets::HreflangCodes do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  let(:primary_market) { Market.find_by(is_primary: true) }

  def market(countries:, handle:)
    record = Market.create!(name: handle, handle:, status: "active", market_type: "region")
    countries.each { |code| record.market_regions.create!(country_code: code) }
    record
  end

  it "H1 單國市場：HK＋en ⇒ {en-HK}；HK＋zh-Hant ⇒ {zh-Hant-HK}（小寫語言／Title script／大寫地區）" do
    expect(described_class.for(primary_market, "en")).to eq(Set.new(%w[en-HK]))
    # 輸入大小寫髒值也要出正規形（碼的大小寫規則與前綴不同、不得互相借用）。
    expect(described_class.for(primary_market, "ZH-HANT")).to eq(Set.new(%w[zh-Hant-HK]))
  end

  it "H2 🔴 多國市場逐國展開：FR/DE/BE＋en ⇒ 三個碼、同指一 URL；恆無裸碼" do
    eu = market(countries: %w[FR DE BE], handle: "eu")
    codes = described_class.for(eu, "en")
    expect(codes).to eq(Set.new(%w[en-FR en-DE en-BE]))
    expect(codes).to be_a(Set)
    expect(codes.none? { |code| code == "en" }).to be(true)
  end

  it "H3 🔴 零 region ⇒ EmptyRegions raise（不得退回裸語言碼）" do
    empty = Market.create!(name: "B2B", handle: "b2b", status: "active", market_type: "company_location")
    expect { described_class.for(empty, "en") }.to raise_error(described_class::EmptyRegions)
  end

  it "H4 locale 自帶 region 不進 base（62 §I.2 偽代碼逐字：base＝language[+script]）：pt-BR＋HK ⇒ {pt-HK}" do
    expect(described_class.for(primary_market, "pt-BR")).to eq(Set.new(%w[pt-HK]))
  end

  it "H5 🔴 SF-9 型別分離：同一 (market, locale)——url_prefix 恰一個 String、hreflang_codes N 個碼" do
    tri = market(countries: %w[FR DE BE], handle: "tri")
    presence = tri.market_web_presences.create!(subfolder_suffix: "eu", default_shop_locale: "en")

    prefix = Markets::UrlPrefix.for(presence, "en")
    codes = described_class.for(tri, "en")

    expect(prefix).to be_a(String)
    expect(codes.size).to eq(3)
    # 把 hreflang 集合餵給路由的路徑以型別封死（不得出現任何取 .first 餵路由的寫法）。
    expect { Markets::UrlPrefix.for(presence, codes) }.to raise_error(TypeError)
  end
end
