# frozen_string_literal: true

require "rails_helper"

# hreflang 碼產生器（62 §I.2；🔴 2026-09-04 D80 方案 1 使用者裁定：共用網域一語言一碼、子資料夾逐國展開）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   H1 共用網域 presence ⇒ 語言碼無地區（殺：加回 -HK——本尊五語言五市場每頁零地區碼，§G23）
#   H2 子資料夾 presence 逐國展開（殺：退回語言碼——子資料夾形未取得本尊證據，沿用逐國展開 V）
#   H3 子資料夾 presence 的市場零 region ⇒ raise（殺：assert 拿掉後靜默輸出裸碼）
#   H5 與 url_prefix 型別分離（殺：兩函式合併成一個「對外轉換」——67 §F.1(a) 明文不可）
RSpec.describe Markets::HreflangCodes do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  let(:primary_market) { Market.find_by(is_primary: true) }
  let(:primary_presence) { primary_market.market_web_presences.sole }

  def market(countries:, handle:)
    record = Market.create!(name: handle, handle:, status: "active", market_type: "region")
    countries.each { |code| record.market_regions.create!(country_code: code) }
    record
  end

  it "H1 🔴 共用網域 presence：en ⇒ {en}；zh-Hant ⇒ {zh-Hant}（小寫語言／Title script／無地區）——大小寫髒值出正規形" do
    expect(described_class.for_presence(primary_presence, "en")).to eq(Set.new(%w[en]))
    expect(described_class.for_presence(primary_presence, "ZH-HANT")).to eq(Set.new(%w[zh-Hant]))
    expect(described_class.language_code("zh-hans")).to eq("zh-Hans")
  end

  it "H2 🔴 子資料夾 presence 逐國展開：FR/DE/BE＋en ⇒ 三個碼、同指一 URL" do
    eu = market(countries: %w[FR DE BE], handle: "eu")
    presence = eu.market_web_presences.create!(subfolder_suffix: "eu", default_shop_locale: "en")
    codes = described_class.for_presence(presence, "en")
    expect(codes).to eq(Set.new(%w[en-FR en-DE en-BE]))
    expect(codes).to be_a(Set)
    expect(described_class.for(eu, "en")).to eq(codes)
  end

  it "H3 🔴 子資料夾 presence 的市場零 region ⇒ EmptyRegions raise；共用網域不看 regions" do
    empty = Market.create!(name: "B2B", handle: "b2b", status: "active", market_type: "company_location")
    presence = empty.market_web_presences.create!(subfolder_suffix: "bb", default_shop_locale: "en")
    expect { described_class.for_presence(presence, "en") }.to raise_error(described_class::EmptyRegions)
    expect { described_class.for(empty, "en") }.to raise_error(described_class::EmptyRegions)

    external = Domain.create!(host: "b2b.example", domain_type: "redirect", status: "active")
    domain_presence = empty.market_web_presences.create!(domain: external, default_shop_locale: "en")
    expect(described_class.for_presence(domain_presence, "en")).to eq(Set.new(%w[en]))
  end

  it "H4 locale 自帶 region 不進碼（62 §I.2 偽代碼逐字：base＝language[+script]）：pt-BR ⇒ {pt}；子資料夾 HK ⇒ {pt-HK}" do
    expect(described_class.for_presence(primary_presence, "pt-BR")).to eq(Set.new(%w[pt]))
    expect(described_class.for(primary_market, "pt-BR")).to eq(Set.new(%w[pt-HK]))
    expect { described_class.language_code("zh Hant") }.to raise_error(described_class::InvalidTag)
  end

  it "H5 🔴 SF-9 型別分離：同一 (presence, locale)——url_prefix 恰一個 String、hreflang_codes N 個碼" do
    tri = market(countries: %w[FR DE BE], handle: "tri")
    presence = tri.market_web_presences.create!(subfolder_suffix: "eu", default_shop_locale: "en")

    prefix = Markets::UrlPrefix.for(presence, "en")
    codes = described_class.for_presence(presence, "en")

    expect(prefix).to eq("/en-eu")
    expect(codes.size).to eq(3)
    # 把 hreflang 集合餵給路由的路徑以型別封死（不得出現任何取 .first 餵路由的寫法）。
    expect { Markets::UrlPrefix.for(presence, codes) }.to raise_error(TypeError)
  end
end
