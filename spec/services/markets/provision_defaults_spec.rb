# frozen_string_literal: true

require "rails_helper"

# 建店預設市場鏈與回填（包 32；單一實作＝Markets::ProvisionDefaults）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   P2 冪等（殺：backfill 重跑對已回填店二次建鏈——handle 唯一索引會炸生產 migration）
#   P4 backfill 走同一支實作（殺：migration 長出自己那份規則——20260826060000 檔頭事故）
#   P5 PrefixIndex 端到端（殺：resolver 忘掉 published／open 兩個閘之一）
RSpec.describe Markets::ProvisionDefaults do
  let(:shop) { create(:shop) }

  it "P1 建店即整鏈（after_create 已跑）：市場／region／網域／presence／白名單各就位" do
    ActsAsTenant.with_tenant(shop) do
      market = Market.find_by!(is_primary: true)
      expect(market.region_country_codes).to eq(%w[HK])
      presence = market.market_web_presences.sole
      expect(presence.domain).to eq(Domain.sole)
      # 白名單＝已發布語言（launch 種子只有 en 已發布）；預設＝來源語言。
      expect(presence.market_web_presence_locales.pluck(:locale_tag)).to eq(%w[en])
    end
  end

  it "P2 🔴 冪等：對已有鏈的店重呼叫＝原樣返回，不建第二份" do
    expect do
      result = described_class.call(shop:)
      expect(result).to eq(ActsAsTenant.with_tenant(shop) { Market.find_by!(is_primary: true) })
    end.not_to change { ActsAsTenant.with_tenant(shop) { [ Market.count, Domain.count ] } }
  end

  it "P3 有 custom_domain 的店：網域種子用它（不是平台子網域）" do
    custom = create(:shop, custom_domain: "shop.example.hk")
    ActsAsTenant.with_tenant(custom) do
      expect(Domain.sole.host).to eq("shop.example.hk")
    end
  end

  it "P4 🔴 backfill_all!：補建缺鏈的店、回報建立數；已回填店不重建（migration 可重跑）" do
    ActsAsTenant.with_tenant(shop) do
      Market.delete_all
      Domain.delete_all
    end
    expect(described_class.backfill_all!).to eq(1)
    expect(ActsAsTenant.with_tenant(shop) { Market.where(is_primary: true).count }).to eq(1)
    expect(described_class.backfill_all!).to eq(0)
  end

  it "P4b 無語言列的殘店：跳過並警示，不建半條鏈" do
    ActsAsTenant.with_tenant(shop) do
      Market.delete_all
      Domain.delete_all
      ShopLocale.delete_all
    end
    allow(Rails.logger).to receive(:warn).and_call_original
    expect(described_class.backfill_all!).to eq(0)
    expect(Rails.logger).to have_received(:warn).with(/provision_defaults\.skipped shop_id=#{shop.id}/)
    expect(ActsAsTenant.with_tenant(shop) { Market.count }).to eq(0)
  end

  it "P5 🔴 PrefixIndex 端到端：/en-hk 命中 (primary, en)；未知／未發布／已關閉 ⇒ nil（404 判準）" do
    ActsAsTenant.with_tenant(shop) do
      domain = Domain.sole
      hit = Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "en-hk")
      expect(hit.market).to eq(Market.find_by!(is_primary: true))
      expect(hit.locale_tag).to eq("en")

      expect(Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "fr-hk")).to be_nil

      # 開了白名單但語言未發布 ⇒ 不可路由（67 §A.5(c) 情形 4）。
      presence = hit.web_presence
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
      expect(Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "zh-hant-hk")).to be_nil

      # 發布後可路由；關閉（狀態轉換）後回到 404（情形 3）。
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      expect(Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "zh-hant-hk")).not_to be_nil
      presence.market_web_presence_locales.find_by!(locale_tag: "zh-Hant").close!
      expect(Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "zh-hant-hk")).to be_nil
    end
  end
end
