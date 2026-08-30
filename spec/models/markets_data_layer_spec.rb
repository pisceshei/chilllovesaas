# frozen_string_literal: true

require "rails_helper"

# Markets 資料層不變量（29 §1.1／§1.2；67 §C.8）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）——model 與 DB 是**兩層各自的格**，拿掉任一層另一層要接住：
#   M2 第二個 primary ⇒ DB 生成欄位唯一索引擋（殺：只留 model 驗證再被 skip_validation 繞過）
#   M5 XOR 兩層各測（殺：把 CHECK 當「model 已經擋了」刪掉）
#   M6 ③⊆② 由複合 FK 執法（殺：FK 指去 platform_locales——未啟用語言可開給市場）
#   M7 關閉預設語言 ⇒ 拒（殺：MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED 驗證被移除）
#   M9 前綴 ≡ 身分（殺：同 effective domain 兩組 (market, locale) 撞同一前綴）
RSpec.describe "Markets 資料層", type: :model do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  let(:primary_market) { Market.find_by(is_primary: true) }
  let(:primary_presence) { primary_market.market_web_presences.sole }

  it "M1 建店即有整條鏈：HK primary market（active/region）＋primary domain＋presence＋en 白名單列" do
    expect(primary_market).to have_attributes(status: "active", market_type: "region", handle: "hk")
    expect(primary_market.region_country_codes).to eq(%w[HK])

    domain = Domain.sole
    expect(domain).to have_attributes(domain_type: "primary", status: "active",
                                      host: "#{shop.subdomain}.#{Chilllove::TenantResolver.base_host}")
    expect(primary_presence.domain_id).to eq(domain.id)
    expect(primary_presence.default_shop_locale).to eq("en")

    row = primary_presence.market_web_presence_locales.sole
    expect(row).to have_attributes(locale_tag: "en", is_market_default: true, open_to_buyers: true)
  end

  it "M2 🔴 每店恰一個 primary market：第二個撞 DB 生成欄位唯一索引（uq_markets_single_primary）" do
    expect(primary_market).to be_present # 先證明第一個存在——否則本格測的是空集合
    second = Market.new(name: "第二主", handle: "hk2", status: "draft",
                        market_type: "region", is_primary: true)
    expect { second.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "M3 primary market 不可刪、恰含一國；非 primary 可刪" do
    expect(primary_market.destroy).to be(false)
    expect(primary_market.errors[:base].sole).to include("不可刪除")

    expect { primary_market.market_regions.create!(country_code: "TW") }
      .to raise_error(ActiveRecord::RecordInvalid, /恰含一個國家/)

    other = Market.create!(name: "可刪", handle: "bye", status: "draft", market_type: "region")
    expect { other.destroy! }.to change(Market, :count).by(-1)
  end

  it "M4 active 市場 region 不得重疊；draft 可以；draft 帶重疊轉 active ⇒ 拒" do
    expect { Market.create!(name: "撞", handle: "cl", status: "active", market_type: "region")
                   .market_regions.create!(country_code: "HK") }
      .to raise_error(ActiveRecord::RecordInvalid, /已屬於另一個 active 市場/)

    draft = Market.create!(name: "草稿", handle: "dr", status: "draft", market_type: "region")
    draft.market_regions.create!(country_code: "HK")
    expect(draft.reload.region_country_codes).to eq(%w[HK])

    draft.status = "active"
    expect(draft).not_to be_valid
    expect(draft.errors[:status].sole).to include("重疊")
  end

  it "M5 🔴 presence 的 domain XOR subfolder：model 與 DB CHECK 兩層各自擋" do
    both_nil = primary_market.market_web_presences.build(default_shop_locale: "en")
    expect(both_nil).not_to be_valid

    both_set = primary_market.market_web_presences.build(
      domain: Domain.sole, subfolder_suffix: "hk", default_shop_locale: "en"
    )
    expect(both_set).not_to be_valid

    # DB 層獨立的格：繞過 model 直插違反 CHECK ⇒ StatementInvalid（ck_mwp_domain_xor_subfolder）。
    expect do
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        INSERT INTO market_web_presences
          (shop_id, market_id, domain_id, subfolder_suffix, default_shop_locale, created_at, updated_at)
        VALUES (#{shop.id}, #{primary_market.id}, NULL, NULL, 'en', NOW(), NOW())
      SQL
    end.to raise_error(ActiveRecord::StatementInvalid, /(check|constraint)/i)
  end

  it "M6 🔴 ③⊆②：白名單只能開 shop_locales 既有語言（複合 FK fk_mwpl_shop_locale 執法）" do
    expect do
      primary_presence.market_web_presence_locales.create!(locale_tag: "ko", position: 9)
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "M7 🔴 預設語言不可關閉（MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED）；非預設關閉＝狀態轉換不是刪除" do
    default_row = primary_presence.market_web_presence_locales.sole
    expect { default_row.close! }
      .to raise_error(ActiveRecord::RecordInvalid, /MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED/)

    ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
    row = primary_presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
    expect { row.close! }.not_to change(primary_presence.market_web_presence_locales, :count)
    expect(row.reload).to have_attributes(open_to_buyers: false)
    expect(row.closed_at).to be_present
    row.reopen!
    expect(row.reload).to have_attributes(open_to_buyers: true, closed_at: nil)
  end

  it "M8 set_default_locale!：欄位與旗標同 transaction 翻轉；恰一個 default（DB 生成欄位兜底）" do
    ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
    primary_presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)

    primary_presence.set_default_locale!("zh-Hant")
    expect(primary_presence.reload.default_shop_locale).to eq("zh-Hant")
    defaults = primary_presence.market_web_presence_locales.where(is_market_default: true)
    expect(defaults.sole.locale_tag).to eq("zh-Hant")

    # DB 層獨立的格：繞 model 直插第二個 default ⇒ 撞 uq_mwpl_single_default。
    expect do
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        UPDATE market_web_presence_locales SET is_market_default = 1
        WHERE shop_id = #{shop.id} AND market_web_presence_id = #{primary_presence.id}
      SQL
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "M9 🔴 前綴 ≡ (market, locale) 身分：同 effective domain 撞同一前綴 ⇒ 第二組拒絕" do
    # 草稿市場 HK（與 primary 同國，draft 允許重疊）＋子資料夾 presence ⇒ /en-hk 已被 primary 佔用。
    draft = Market.create!(name: "HK 草稿", handle: "hk-d", status: "draft", market_type: "region")
    draft.market_regions.create!(country_code: "HK")
    presence = draft.market_web_presences.create!(subfolder_suffix: "hk", default_shop_locale: "en")

    row = presence.market_web_presence_locales.build(locale_tag: "en", position: 0)
    expect(row).not_to be_valid
    expect(row.errors[:locale_tag].sole).to include("/en-hk")
  end

  it "M10 白名單同 (presence, locale) 不得重複；空店可刪（刪除順序：markets→domains→shop_locales）" do
    dup = primary_presence.market_web_presence_locales.build(locale_tag: "en", position: 5)
    expect(dup).not_to be_valid

    fresh = ActsAsTenant.without_tenant { create(:shop) }
    expect { fresh.destroy! }.to change(Shop, :count).by(-1)
    expect(Market.where(shop_id: fresh.id)).to be_empty
    expect(Domain.where(shop_id: fresh.id)).to be_empty
  end
end
