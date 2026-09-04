# frozen_string_literal: true

require "rails_helper"

# E13：`Markets::PrefixIndex.default_hit`——店的預設 (market, locale) 命中單一真相（根路徑 302 目標／主題編輯器預覽／
# 無前綴 SRA 端點三個消費者同一落點）。
RSpec.describe Markets::PrefixIndex do
  let(:shop) { create(:shop, subdomain: "dh-shop") }

  def presence
    ActsAsTenant.with_tenant(shop) { Market.find_by!(is_primary: true).market_web_presences.sole }
  end

  it "DH1 🔴 default_hit＝primary market × 第一個 presence × 其預設語言（建店 provision：en）" do
    hit = described_class.default_hit(shop:)
    expect(hit).to be_a(described_class::Hit)
    expect(hit.market.is_primary).to be(true)
    expect(hit.web_presence).to eq(presence)
    expect(hit.locale_tag).to eq("en")
    expect(hit.locale_tag).to eq(presence.default_shop_locale)
  end

  it "DH2 🔴 跟 presence 預設語言走（set_default_locale! 切 zh-Hant ⇒ 命中 zh-Hant），不是來源語言" do
    ActsAsTenant.with_tenant(shop) do
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
      presence.set_default_locale!("zh-Hant")
    end
    expect(described_class.default_hit(shop:).locale_tag).to eq("zh-Hant")
  end

  it "DH3 無市場／無 presence ⇒ nil（fail-closed：呼叫端維持舊行為）" do
    ActsAsTenant.with_tenant(shop) { MarketWebPresence.delete_all }
    expect(described_class.default_hit(shop:)).to be_nil
    ActsAsTenant.with_tenant(shop) { Market.update_all(is_primary: false) }
    expect(described_class.default_hit(shop:)).to be_nil
  end
end
