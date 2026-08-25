# frozen_string_literal: true

require "rails_helper"

# D49：繁簡字形誤借偵測（OpenCC 字元表）。
RSpec.describe Translations::ScriptDetector do
  describe "字表推導錨（2026-08-25 對 OpenCC 表實測的固定點）" do
    it "簡體專用字：汉／门／发" do
      %w[汉 门 发].each do |char|
        expect(described_class.simplified_only).to include(char), "#{char} 應為簡體專用"
        expect(described_class.traditional_only).not_to include(char)
      end
    end

    it "繁體專用字：漢／門／發" do
      %w[漢 門 發].each do |char|
        expect(described_class.traditional_only).to include(char), "#{char} 應為繁體專用"
        expect(described_class.simplified_only).not_to include(char)
      end
    end

    it "🔴 兩體共用字永不觸發（含歧義字 台／后／里／干——它們是合法繁體）" do
      %w[的 人 大 台 后 里 干].each do |char|
        expect(described_class.simplified_only).not_to include(char), "#{char} 不得判簡體專用"
        expect(described_class.traditional_only).not_to include(char), "#{char} 不得判繁體專用"
      end
    end

    it "🔴 上游雙邊矛盾字（緼苧藴輼醖）兩邊都剔除（fail-safe：寧漏報不誤報）" do
      %w[緼 苧 藴 輼 醖].each do |char|
        expect(described_class.simplified_only).not_to include(char)
        expect(described_class.traditional_only).not_to include(char)
      end
    end

    it "字表規模在預期量級（4012／4148 鍵推導出的專用集非空且上千）" do
      expect(described_class.simplified_only.size).to be > 3000
      expect(described_class.traditional_only.size).to be > 3000
    end
  end

  describe "🔴 零列 canary（fail-open 防線）" do
    it "字表讀出 0 個專用字 ⇒ raise，不得靜默變成「掃了但零命中」" do
      saved_s = described_class.instance_variable_get(:@simplified_only)
      saved_t = described_class.instance_variable_get(:@traditional_only)
      described_class.instance_variable_set(:@simplified_only, nil)
      described_class.instance_variable_set(:@traditional_only, nil)
      allow(File).to receive(:foreach)   # 不 yield＝空檔案／格式全變的形態

      expect { described_class.simplified_only }
        .to raise_error(/OpenCC 字表 .* 讀出 0 個專用字/)
    ensure
      described_class.instance_variable_set(:@simplified_only, saved_s)
      described_class.instance_variable_set(:@traditional_only, saved_t)
    end
  end

  describe ".mismatched_chars" do
    it "期望繁體的文字含簡體字 ⇒ 抓出來（去重、依出現序）" do
      expect(described_class.mismatched_chars("玫瑰与辛香的层次，门市限定", expected: :hant))
        .to eq(%w[与 层 门])
    end

    it "期望簡體的文字含繁體字 ⇒ 抓出來" do
      expect(described_class.mismatched_chars("玫瑰與辛香的層次", expected: :hans))
        .to eq(%w[與 層])
    end

    it "純正字形（含拉丁、數字、標點）⇒ 空陣列" do
      expect(described_class.mismatched_chars("玫瑰與辛香 EDP 50ml，門市限定！", expected: :hant)).to eq([])
      expect(described_class.mismatched_chars("玫瑰与辛香 EDP 50ml，门市限定！", expected: :hans)).to eq([])
    end

    it "🔴 未知 expected 一律 raise（fail-closed，不猜方向）" do
      expect { described_class.mismatched_chars("x", expected: :hant_hk) }
        .to raise_error(ArgumentError, /只有 :hant/)
    end
  end

  describe ".expected_for（locale → 期望字形；非 zh 回 nil）" do
    {
      "zh-Hant" => :hant, "zh-Hant-HK" => :hant,
      "zh-Hans" => :hans, "zh-Hans-CN" => :hans,
      "ja" => nil, "en" => nil, "ko" => nil, "fr" => nil, "" => nil
    }.each do |tag, expected|
      it "#{tag.inspect} → #{expected.inspect}" do
        expect(described_class.expected_for(tag)).to eq(expected)
      end
    end

    it "🔴 子標籤邊界：假想的 zh-Hantx 不算 zh-Hant 家族" do
      expect(described_class.expected_for("zh-Hantx")).to be_nil
    end
  end
end
