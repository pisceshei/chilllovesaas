# frozen_string_literal: true

require "rails_helper"

# URL 前綴唯一產生器（67 §F.1(b)；🔴 2026-09-04 D80 方案 1 使用者裁定＝本尊形；取證 external-facts §G23）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   U2 共用網域預設語言**無**前綴（殺：退回 2026-08-13「恆有前綴」——本尊 / 200、/zh-hans/ 404）
#   U1 共用網域其他語言＝裸語言段 /zh-hant（殺：加回地區段 /zh-hant-hk——本尊 /zh-hant-hk 404）
#   U3 子資料夾 presence 的 region 段＝suffix 本身（殺：從市場國家推導——本尊 subfolder 是商家設定的識別字）
#   U5 前綴不看市場 regions（殺：多國／零 region 市場 raise——那是 hreflang 的事）
#   U7 Set 輸入 ⇒ TypeError（殺：把 hreflang 的一組碼餵進路由——SF-9 型別分離）
RSpec.describe Markets::UrlPrefix do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # 建店已長出 primary market（HK）＋primary domain＋presence（Markets::ProvisionDefaults；預設語言 en）。
  let(:primary_presence) { Market.find_by(is_primary: true).market_web_presences.sole }

  def secondary_presence(countries:, suffix: nil, domain: nil, status: "active", default: "en")
    market = Market.create!(name: countries.join("+"), handle: countries.join("-").downcase,
                            status:, market_type: "region")
    countries.each { |code| market.market_regions.create!(country_code: code) }
    market.market_web_presences.create!(domain:, subfolder_suffix: suffix, default_shop_locale: default)
  end

  it "U1 🔴 共用網域 ＋ 非預設語言 ⇒ 裸語言段全小寫：zh-Hant ⇒ /zh-hant（本尊 hoko.vip /zh-hant/ 200、/zh-hant-hk 404）" do
    expect(described_class.for(primary_presence, "zh-Hant")).to eq("/zh-hant")
    expect(described_class.for(primary_presence, "ja")).to eq("/ja")
  end

  it "U2 🔴 共用網域 ＋ presence 預設語言 ⇒ 無前綴（空字串；本尊 / 200 lang=zh-CN、/zh-hans/ 404）" do
    expect(described_class.for(primary_presence, "en")).to eq("")
    expect(described_class.for(primary_presence, "EN")).to eq("") # 大小寫髒值仍判為預設
    primary_presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
    primary_presence.set_default_locale!("zh-Hant")
    expect(described_class.for(primary_presence, "zh-Hant")).to eq("")
    expect(described_class.for(primary_presence, "en")).to eq("/en")
  end

  it "U3 🔴 子資料夾 presence：全部語言（含預設）＝/{lang}-{suffix}，region 段＝suffix 本身（官方例 example.com/fr-ca）" do
    presence = secondary_presence(countries: %w[CA], suffix: "ca")
    expect(described_class.for(presence, "en")).to eq("/en-ca")     # 預設語言也有前綴（子資料夾本身就是市場身分）
    expect(described_class.for(presence, "fr")).to eq("/fr-ca")
    odd = secondary_presence(countries: %w[MX], suffix: "xx")
    expect(described_class.for(odd, "en")).to eq("/en-xx")          # suffix 不是從市場國家推導
  end

  it "U4 自有網域市場與共用網域同形：預設語言在根、其他 /{lang}（原 2026-08-13「獨立網域也帶地區」已隨 D80 推翻）" do
    external = Domain.create!(host: "example.tw", domain_type: "redirect", status: "active")
    presence = secondary_presence(countries: %w[TW], domain: external, default: "zh-Hant")
    expect(described_class.for(presence, "zh-Hant")).to eq("")
    expect(described_class.for(presence, "en")).to eq("/en")
  end

  it "U5 🔴 前綴不看市場 regions：多國市場無 suffix、零 region 市場都算得出前綴（不再 MissingRegionSource）" do
    with_suffix = secondary_presence(countries: %w[FR DE], suffix: "eu")
    expect(described_class.for(with_suffix, "en")).to eq("/en-eu")

    external = Domain.create!(host: "example.eu", domain_type: "redirect", status: "active")
    domain_only = secondary_presence(countries: %w[BE NL], domain: external)
    expect(described_class.for(domain_only, "en")).to eq("")
    expect(described_class.for(domain_only, "fr")).to eq("/fr")

    channel = Market.create!(name: "POS", handle: "pos", status: "active", market_type: "channel")
    presence = channel.market_web_presences.create!(subfolder_suffix: "po", default_shop_locale: "en")
    expect(described_class.for(presence, "en")).to eq("/en-po")
  end

  it "U6 撞保留第一路徑段 ⇒ raise（67 §F.1(c)）；空前綴不做保留段檢查" do
    reserved = Limits.fetch(:handle, :reserved_first_segments).map(&:to_s)
    expect(reserved).to include("cart")
    allow(Limits).to receive(:fetch).and_call_original
    allow(Limits).to receive(:fetch).with(:handle, :reserved_first_segments).and_return(reserved + [ "ja" ])
    expect { described_class.for(primary_presence, "ja") }.to raise_error(described_class::Error, /保留/)
    expect(described_class.for(primary_presence, "en")).to eq("")
  end

  it "U7 🔴 集合輸入 ⇒ TypeError（SF-9：url_prefix 簽名不收 Set／Array）" do
    expect { described_class.for(primary_presence, Set.new(%w[en-HK en-CA])) }
      .to raise_error(TypeError, /SF-9/)
    expect { described_class.for(primary_presence, %w[en zh-Hant]) }.to raise_error(TypeError)
  end

  it "U8 輸出恆匹配 67 §F.1(b) 正則；自帶 region 的 tag 照本尊小寫成段（pt-BR ⇒ /pt-br）；髒 tag ⇒ raise（不靜默修剪）" do
    expect(described_class.for(primary_presence, "en")).to match(described_class::FORMAT)
    expect(described_class.for(primary_presence, "zh-Hant")).to match(described_class::FORMAT)
    expect(described_class.for(primary_presence, "pt-BR")).to eq("/pt-br")
    expect { described_class.for(primary_presence, "zh Hant") }.to raise_error(described_class::Error)
    expect { described_class.for(primary_presence, "zh-hant-hk-x") }.to raise_error(described_class::Error)
  end
end
