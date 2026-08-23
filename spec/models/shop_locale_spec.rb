# frozen_string_literal: true

require "rails_helper"

# ML-0 地基（docs/plans/2026-08-23-多語言方案.md §3.2；67 §C.1／C.3）。
RSpec.describe ShopLocale, type: :model do
  let(:shop) { create(:shop) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  describe "新店首發語言（Shop#after_create）" do
    it "啟用 limits 的 launch_locales，來源語言＝source_locale_default 且已發布；其餘啟用未發布" do
      tags = shop.shop_locales.order(:position).pluck(:locale_tag)
      expect(tags).to eq(Limits.fetch(:i18n, :launch_locales).map(&:to_s))
      expect(tags).to eq(%w[en zh-Hant zh-Hans ja fr])

      source = shop.shop_locales.find_by!(is_source: true)
      expect(source.locale_tag).to eq(Limits.fetch(:i18n, :source_locale_default).to_s)
      expect(source).to be_published
      expect(shop.shop_locales.where(is_source: false).where(published: true)).not_to exist
      expect(shop.shop_locales.where(enabled: false)).not_to exist
    end

    it "平台字典五語齊全且 endonym 用語言自稱" do
      expect(PlatformLocale.available.pluck(:tag, :endonym)).to contain_exactly(
        [ "en", "English" ], [ "zh-Hant", "繁體中文" ], [ "zh-Hans", "简体中文" ],
        [ "ja", "日本語" ], [ "fr", "Français" ]
      )
    end
  end

  describe "來源語言不變量（67 §C.3）" do
    it "每店恰一來源語言：model 層擋第二個" do
      second = shop.shop_locales.find_by!(locale_tag: "fr")
      second.is_source = true
      second.published = true
      expect(second).not_to be_valid
      expect(second.errors[:is_source]).to be_present
    end

    it "DB 層也擋（生成欄位 source_guard 唯一索引）——model 被繞過時仍守住" do
      expect do
        described_class.where(locale_tag: "ja").update_all(is_source: true)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "來源語言不可取消發布、不可停用、不可刪除（SOURCE_LOCALE_IMMUTABLE）" do
      source = described_class.source!
      source.published = false
      expect(source).not_to be_valid

      source.reload.enabled = false
      expect(source).not_to be_valid

      expect(source.reload.destroy).to be(false)
      expect(source.errors[:base].join).to include("SOURCE_LOCALE_IMMUTABLE")
      expect(described_class.where(is_source: true).count).to eq(1)
    end
  end

  describe "語言數上限與標籤正規化" do
    it "新增超過 i18n.max_shop_locales 即拒絕（LOCALE_LIMIT_EXCEEDED）" do
      stub_const("Limits::TEST_OVERRIDE", nil) # 僅確保常數存在時不影響；上限由 limits 決定
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:i18n, :max_shop_locales).and_return(5)

      PlatformLocale.create!(tag: "de", language: "de", endonym: "Deutsch", plural_rule: "de", collation: "utf8mb4_0900_ai_ci")
      extra = described_class.new(locale_tag: "de")
      expect(extra).not_to be_valid
      expect(extra.errors[:base].join).to include("LOCALE_LIMIT_EXCEEDED")
    end

    it "寫入層正規化大小寫（zh-hant → zh-Hant），不依賴 collation" do
      record = described_class.find_by!(locale_tag: "zh-Hant")
      record.locale_tag = "ZH-hant"
      record.valid?
      expect(record.locale_tag).to eq("zh-Hant")
    end

    it "非來源語言可停用並保留（enabled=false），re-enable 即復原" do
      record = described_class.find_by!(locale_tag: "ja")
      record.update!(enabled: false)
      expect(described_class.enabled.pluck(:locale_tag)).not_to include("ja")
      record.update!(enabled: true)
      expect(described_class.enabled.pluck(:locale_tag)).to include("ja")
    end
  end
end
