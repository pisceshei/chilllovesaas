# frozen_string_literal: true

require "rails_helper"

# URL 前綴唯一產生器（67 §F.1(b) 裁定表逐格）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   U2 primary＋預設語言**也有**前綴（殺：加回「預設語言無前綴」的本尊行為）
#   U3 單國市場用 market region 不用 suffix（殺：推導路徑寫回「語言＋subfolderSuffix」）
#   U5 多國市場無 suffix ⇒ raise（殺：V-225 擅自選「代表國」或退回裸語言前綴）
#   U7 Set 輸入 ⇒ TypeError（殺：把 hreflang 的一組碼餵進路由——SF-9 型別分離）
RSpec.describe Markets::UrlPrefix do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # 建店已長出 primary market（HK）＋primary domain＋presence（Markets::ProvisionDefaults）。
  let(:primary_presence) { Market.find_by(is_primary: true).market_web_presences.sole }

  def secondary_presence(countries:, suffix: nil, domain: nil, status: "active")
    market = Market.create!(name: countries.join("+"), handle: countries.join("-").downcase,
                            status:, market_type: "region")
    countries.each { |code| market.market_regions.create!(country_code: code) }
    market.market_web_presences.create!(domain:, subfolder_suffix: suffix, default_shop_locale: "en")
  end

  it "U1 裁定表：HK primary ＋ zh-Hant ⇒ /zh-hant-hk（恆帶地區、全小寫）" do
    expect(described_class.for(primary_presence, "zh-Hant")).to eq("/zh-hant-hk")
  end

  it "U2 🔴 primary ＋ 預設語言 en 也有前綴 ⇒ /en-hk（舊「無前綴」規則已被裁定換掉）" do
    expect(described_class.for(primary_presence, "en")).to eq("/en-hk")
  end

  it "U3 🔴 單國次級市場 CA：region 來自 market 不來自 suffix（suffix 給錯值也不影響）" do
    presence = secondary_presence(countries: %w[CA], suffix: "xx")
    expect(described_class.for(presence, "en")).to eq("/en-ca")
  end

  it "U4 獨立網域市場一樣帶前綴（全函式；TW ＋ zh-Hant ⇒ /zh-hant-tw）" do
    external = Domain.create!(host: "example.tw", domain_type: "redirect", status: "active")
    presence = secondary_presence(countries: %w[TW], domain: external)
    expect(described_class.for(presence, "zh-Hant")).to eq("/zh-hant-tw")
  end

  it "U5 🔴 多國市場：suffix 是 region 來源（/en-eu）；無 suffix ⇒ MissingRegionSource（V-225 fail-closed）" do
    with_suffix = secondary_presence(countries: %w[FR DE], suffix: "eu")
    expect(described_class.for(with_suffix, "en")).to eq("/en-eu")

    external = Domain.create!(host: "example.eu", domain_type: "redirect", status: "active")
    domain_only = secondary_presence(countries: %w[BE NL], domain: external)
    expect { described_class.for(domain_only, "en") }
      .to raise_error(described_class::MissingRegionSource)
  end

  it "U6 零 region 市場（channel 型）⇒ MissingRegionSource；不得猜地區" do
    market = Market.create!(name: "POS", handle: "pos", status: "active", market_type: "channel")
    presence = market.market_web_presences.create!(subfolder_suffix: "po", default_shop_locale: "en")
    expect { described_class.for(presence, "en") }.to raise_error(described_class::MissingRegionSource)
  end

  it "U7 🔴 集合輸入 ⇒ TypeError（SF-9：url_prefix 簽名不收 Set／Array）" do
    expect { described_class.for(primary_presence, Set.new(%w[en-HK en-CA])) }
      .to raise_error(TypeError, /SF-9/)
    expect { described_class.for(primary_presence, %w[en zh-Hant]) }.to raise_error(TypeError)
  end

  it "U8 輸出恆匹配 67 §F.1(b) 正則；自帶 region 的 tag（pt-BR）不成前綴 ⇒ raise（fail-closed，不靜默修剪）" do
    expect(described_class.for(primary_presence, "en")).to match(described_class::FORMAT)
    expect { described_class.for(primary_presence, "pt-BR") }.to raise_error(described_class::Error)
  end
end
