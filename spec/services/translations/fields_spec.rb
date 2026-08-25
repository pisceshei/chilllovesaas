# frozen_string_literal: true

require "rails_helper"

# 第 7 包：可翻欄位中繼資料表（67 §B.1／§B.2）。
RSpec.describe Translations::Fields do
  it "四欄的 kind 與 missing 全部登記（67 §B.2 的 v1 射程）" do
    expect(described_class::ALL).to contain_exactly("title", "body_html", "meta_title", "meta_description")
    expect(described_class::ALL.map { |f| described_class.kind(f) })
      .to eq([ :text, :html, :text, :text ])
    expect(described_class::ALL.map { |f| described_class.missing(f) })
      .to eq([ :required, :required, :optional, :optional ])
  end

  it "未知欄位保守成 :text ＋ :required（不對未知值跑 HTML parser、不靜默省略欄位）" do
    expect(described_class.kind("unknown_field")).to eq(:text)
    expect(described_class.missing("unknown_field")).to eq(:required)
  end

  # `acts_as_tenant` 的 require_tenant 讓 `Model.new` 也要租戶；本表是純中繼資料，
  # 用一個未持久化的 Shop 當租戶即可，不需要 DB 上真的有一家店。
  around { |example| ActsAsTenant.with_tenant(Shop.new(id: 0)) { example.run } }

  describe "base_value" do
    it "PRODUCT 與 COLLECTION 共用同一份屬性對照（兩張表欄名相同）" do
      # 🔴 用 `Model.new` 不用 factory：本表是純中繼資料，不該為了測它去建租戶。
      product = Product.new(title: "T", description_html: "<p>D</p>",
                            seo_title: "ST", seo_description: "SD")
      collection = Collection.new(title: "CT", description_html: "<p>CD</p>",
                                  seo_title: "CST", seo_description: "CSD")

      expect(described_class::ALL.map { |f| described_class.base_value(product, f) })
        .to eq([ "T", "<p>D</p>", "ST", "SD" ])
      expect(described_class::ALL.map { |f| described_class.base_value(collection, f) })
        .to eq([ "CT", "<p>CD</p>", "CST", "CSD" ])
    end

    it "未知欄位回空字串，不對資源 public_send 一個不存在的屬性" do
      expect(described_class.base_value(Product.new, "nope")).to eq("")
    end

    it "nil 屬性回空字串（seo_title 可為 NULL）" do
      expect(described_class.base_value(Product.new(seo_title: nil), "meta_title")).to eq("")
    end
  end

  describe "limit" do
    it "🔴 A8：未知欄位 raise，不靜默回別欄的上限" do
      expect { described_class.limit("totally_unknown") }.to raise_error(KeyError, /未知的可翻欄位/)
    end

    it "沿用來源欄位的上限（不另立一套）" do
      expect(described_class.limit("title")).to eq(Limits.fetch(:product, :title_max_chars))
      expect(described_class.limit("body_html")).to eq(Limits.fetch(:product, :description_max_bytes))
      expect(described_class.limit("meta_title")).to eq(Limits.fetch(:content, :seo_title_max_chars))
      expect(described_class.limit("meta_description")).to eq(Limits.fetch(:content, :seo_meta_description_max_chars))
    end
  end

  # 🔴 tripwire：`Upsert::REQUIRED_FIELDS` 是**進度的分母**，`Fields::MISSING` 是
  #   **缺翻譯時前台怎麼辦**——兩件不同的事，目前值相同純屬 v1 射程小（登記＝U19）。
  #   這一格紅掉時要做的是**裁定哪一邊該變**，不是把常數改成一致把測試弄綠。
  it "🔴 tripwire：進度分母與缺翻譯行為目前一致（不一致時要裁定，不是改常數對齊）" do
    required_by_missing = described_class::MISSING.select { |_, v| v == :required }.keys
    expect(required_by_missing).to eq(Translations::Upsert::REQUIRED_FIELDS),
      "Upsert::REQUIRED_FIELDS（進度分母）與 Fields::MISSING(:required)（前台行為）分岔了。" \
      "這可能是對的——例如 meta_title 變成必翻但不進進度。先裁定，再改。"
    expect(described_class::ALL).to eq(Translations::Upsert::FIELDS)
  end
end
