# frozen_string_literal: true

require "rails_helper"

# BCP-47 標籤正規化與驗證（67 §C.1 規則 2／3；limits i18n.forbidden_locale_tags 等）。
RSpec.describe Locales::Tag do
  describe ".normalize" do
    it "語言小寫、script Title case、region 大寫" do
      expect(described_class.normalize("ZH-hant")).to eq("zh-Hant")
      expect(described_class.normalize("en-gb")).to eq("en-GB")
      expect(described_class.normalize("  Ja ")).to eq("ja")
      expect(described_class.normalize("zh-hant-hk")).to eq("zh-Hant-HK")
    end
  end

  describe ".validate!" do
    it "接受首發五語與帶 script／region 的合法形態" do
      %w[en zh-Hant zh-Hans ja fr en-GB pt-BR zh-Hant-HK].each do |tag|
        expect(described_class.validate!(tag)).to eq(tag), tag
      end
    end

    it "拒裸 zh（字體歧義）與 zh-TW／zh-CN（用地區冒充字體）" do
      expect { described_class.validate!("zh") }.to raise_error(described_class::Invalid)
      expect { described_class.validate!("zh-TW") }.to raise_error(described_class::Invalid)
      expect { described_class.validate!("zh-CN") }.to raise_error(described_class::Invalid)
    end

    it "拒 limits 禁用表（EU／UK／es-419）與格式不符" do
      expect { described_class.validate!("EU") }.to raise_error(described_class::Invalid)
      expect { described_class.validate!("es-419") }.to raise_error(described_class::Invalid)
      expect { described_class.validate!("english") }.to raise_error(described_class::Invalid)
      expect { described_class.validate!("") }.to raise_error(described_class::Invalid)
    end
  end
end
