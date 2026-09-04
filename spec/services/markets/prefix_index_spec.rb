# frozen_string_literal: true

require "rails_helper"

# E13：`Markets::PrefixIndex.default_hit`——店的預設 (market, locale) 命中單一真相（根路徑／無前綴頁面／主題編輯器預覽／
# 無前綴 SRA 端點同一落點）。D80（2026-09-04）：resolve 只認裸語言段；買家選國 cookie 覆寫共用市場（with_buyer_country）。
#
# 🔴 假綠殺手：
#   DR1 預設語言沒有前綴形可解析（殺：讓 "en" 也命中——本尊 /zh-hans/ 404）
#   BC1 共用市場由國碼覆寫、presence／語言不變（殺：cookie 也改語言或 presence——語言只由 URL 決定）
#   BC2 有自己 presence 的市場不由 cookie 覆寫（殺：子資料夾市場被 cookie 拉走——它的身分在 URL）
RSpec.describe Markets::PrefixIndex do
  let(:shop) { create(:shop, subdomain: "dh-shop") }

  def presence
    ActsAsTenant.with_tenant(shop) { Market.find_by!(is_primary: true).market_web_presences.sole }
  end

  def domain
    ActsAsTenant.with_tenant(shop) { Domain.primary.sole }
  end

  def publish_zh_hant!
    ActsAsTenant.with_tenant(shop) do
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
    end
  end

  it "DH1 🔴 default_hit＝primary market × 第一個 presence × 其預設語言（建店 provision：en）；country_code nil ⇒ 生效國＝市場 region" do
    hit = described_class.default_hit(shop:)
    expect(hit).to be_a(described_class::Hit)
    expect(hit.market.is_primary).to be(true)
    expect(hit.web_presence).to eq(presence)
    expect(hit.locale_tag).to eq("en")
    expect(hit.locale_tag).to eq(presence.default_shop_locale)
    expect(hit.country_code).to be_nil
    expect(hit.effective_country_code).to eq("HK")
  end

  it "DH2 🔴 跟 presence 預設語言走（set_default_locale! 切 zh-Hant ⇒ 命中 zh-Hant），不是來源語言" do
    publish_zh_hant!
    ActsAsTenant.with_tenant(shop) { presence.set_default_locale!("zh-Hant") }
    expect(described_class.default_hit(shop:).locale_tag).to eq("zh-Hant")
  end

  it "DH3 無市場／無 presence ⇒ nil（fail-closed：呼叫端 404）" do
    ActsAsTenant.with_tenant(shop) { MarketWebPresence.delete_all }
    expect(described_class.default_hit(shop:)).to be_nil
    ActsAsTenant.with_tenant(shop) { Market.update_all(is_primary: false) }
    expect(described_class.default_hit(shop:)).to be_nil
  end

  it "DR1 🔴 resolve：非預設語言的裸語言段命中；預設語言沒有前綴形；舊地區形／空段 ⇒ nil" do
    publish_zh_hant!
    hit = described_class.resolve(shop:, domain:, first_segment: "zh-hant")
    expect([ hit.market.is_primary, hit.locale_tag, hit.web_presence ]).to eq([ true, "zh-Hant", presence ])
    expect(described_class.resolve(shop:, domain:, first_segment: "en")).to be_nil        # 預設語言＝無前綴
    expect(described_class.resolve(shop:, domain:, first_segment: "zh-hant-hk")).to be_nil # 2026-08-13 舊形不再存在
    expect(described_class.resolve(shop:, domain:, first_segment: "")).to be_nil
    expect(described_class.prefix_segments(shop:)).to eq(Set.new(%w[zh-hant]))
  end

  it "BC1 🔴 with_buyer_country：共用主網域上沒有自己 presence 的市場由國碼覆寫；presence／語言不變；不屬任何市場 ⇒ 原樣" do
    us = ActsAsTenant.with_tenant(shop) do
      market = Market.create!(name: "美國", handle: "us", status: "active", market_type: "region")
      market.market_regions.create!(country_code: "US")
      market
    end
    base = described_class.default_hit(shop:)
    hit = described_class.with_buyer_country(base, shop:, domain:, country_code: "US")
    expect(hit.market).to eq(us)
    expect(hit.web_presence).to eq(presence)
    expect(hit.locale_tag).to eq("en")
    expect(hit.effective_country_code).to eq("US")

    same = described_class.with_buyer_country(base, shop:, domain:, country_code: "HK") # primary 自己的國 ⇒ 只記國碼
    expect(same.market).to eq(base.market)
    expect(same.country_code).to eq("HK")
    expect(described_class.with_buyer_country(base, shop:, domain:, country_code: "XX")).to eq(base)
    expect(described_class.with_buyer_country(base, shop:, domain:, country_code: nil)).to eq(base)
  end

  it "BC2 🔴 有自己 presence 的市場（子資料夾）不由 cookie 覆寫；子資料夾 URL 命中的 hit 也不被 cookie 改市場" do
    publish_zh_hant!
    ca = ActsAsTenant.with_tenant(shop) do
      market = Market.create!(name: "加拿大", handle: "ca", status: "active", market_type: "region")
      market.market_regions.create!(country_code: "CA")
      market.market_web_presences.create!(subfolder_suffix: "ca", default_shop_locale: "en")
            .market_web_presence_locales.create!(locale_tag: "en", position: 0, is_market_default: true)
      market
    end
    base = described_class.default_hit(shop:)
    expect(described_class.with_buyer_country(base, shop:, domain:, country_code: "CA")).to eq(base)

    ca_hit = described_class.resolve(shop:, domain:, first_segment: "en-ca")
    expect(ca_hit.market).to eq(ca)
    us = ActsAsTenant.with_tenant(shop) do
      market = Market.create!(name: "美國", handle: "us", status: "active", market_type: "region")
      market.market_regions.create!(country_code: "US")
      market
    end
    expect(us).to be_present
    expect(described_class.with_buyer_country(ca_hit, shop:, domain:, country_code: "US")).to eq(ca_hit)
  end
end
