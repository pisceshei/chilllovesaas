# frozen_string_literal: true

require "rails_helper"

# translations 表（67 §C.2）的不變量：一列＝(resource, locale, field)；六稽核欄；自動內容必待覆核。
RSpec.describe Translation, type: :model do
  let(:shop) { create(:shop) }
  let(:product) { create(:product, shop:) }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  def build_translation(overrides = {})
    described_class.new({
      resource_type: "PRODUCT", resource_id: product.id, locale_tag: "zh-Hant",
      field_key: "title", value: "繁中標題", source_locale_tag: "en",
      source_digest: described_class.digest_for(product.title), value_source: "human"
    }.merge(overrides))
  end

  it "快樂路徑：human 譯文不需覆核" do
    translation = build_translation
    expect(translation).to be_valid
    translation.save!
    expect(translation.review_required).to be(false)
  end

  it "同 (resource, locale, field) 第二列被唯一鍵擋（model＋DB 雙層）" do
    build_translation.save!
    duplicate = build_translation(value: "另一份")
    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "machine／script_conversion 一律 review_required（寫入層強制，不信呼叫端）" do
    %w[machine script_conversion].each do |source|
      translation = build_translation(locale_tag: "ja", value_source: source, review_required: false)
      translation.valid?
      expect(translation.review_required).to be(true), source
    end
  end

  it "譯文語言不得等於來源語言（來源語言文字在 base row）" do
    translation = build_translation(locale_tag: "en")
    expect(translation).not_to be_valid
    expect(translation.errors[:locale_tag]).to be_present
  end

  it "v1 射程：resource_type／field_key 值域封閉" do
    expect(build_translation(resource_type: "ARTICLE")).not_to be_valid
    expect(build_translation(field_key: "handle")).not_to be_valid
  end

  it "digest 正規化：CRLF 與首尾空白不影響" do
    expect(described_class.digest_for("a\r\nb  ")).to eq(described_class.digest_for("a\nb"))
    expect(described_class.digest_for("a")).not_to eq(described_class.digest_for("b"))
  end

  it "租戶隔離：別店看不到本店譯文" do
    build_translation.save!
    other = create(:shop)
    ActsAsTenant.with_tenant(other) do
      expect(described_class.count).to eq(0)
    end
  end
end
