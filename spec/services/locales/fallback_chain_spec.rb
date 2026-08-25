# frozen_string_literal: true

require "rails_helper"

# 第 7 包：BCP-47 截尾鏈（67 §C.4(a)）。純函式，不碰 DB。
RSpec.describe Locales::FallbackChain do
  describe ".chain" do
    # 67 §C.4(a) 的四個逐字範例 ＋ 值域窮舉（每個 script/region 組合各一格）。
    {
      # --- §C.4(a) 逐字四例 ---
      "zh-Hant-HK" => [ "zh-Hant" ],
      "zh-Hant" => [],
      "en-GB" => [ "en" ],
      "pt-BR" => [ "pt" ],
      # --- 值域窮舉 ---
      "zh-Hans-CN" => [ "zh-Hans" ],
      "zh-Hans" => [],
      "ja" => [],
      "en" => [],
      "fr-CA" => [ "fr" ],
      "sr-Latn-RS" => [ "sr-Latn", "sr" ],
      "sr-Latn" => [ "sr" ]
    }.each do |tag, expected|
      it "#{tag} → #{expected.inspect}" do
        expect(described_class.chain(tag)).to eq(expected)
      end
    end

    it "先正規化大小寫再截（寫入層之外的呼叫端不必自己 normalize）" do
      expect(described_class.chain("ZH-hant-hk")).to eq([ "zh-Hant" ])
    end

    it "🔴 zh-Hant 的鏈裡永遠不會出現 zh（截到禁用碼就停，不是跳過繼續截）" do
      %w[zh-Hant zh-Hant-HK zh-Hans zh-Hans-CN].each do |tag|
        expect(described_class.chain(tag)).not_to include("zh")
      end
    end

    it "🔴 zh-Hant 與 zh-Hans 永不互為 fallback（never_fallback_pairs）" do
      expect(described_class.chain("zh-Hant-HK")).not_to include("zh-Hans")
      expect(described_class.chain("zh-Hans-CN")).not_to include("zh-Hant")
    end

    it "🔴 sr-Latn 會截到 sr —— 這證明「截到就停」只對**禁用表裡的**碼成立" do
      # 對照組：CLDR 對 sr-Latn 的 parent 也是 root，但我方的禁用表只列了 zh。
      # ⇒ 我方在 sr 上與 CLDR **不同構**，這是已知且刻意的射程限制（首發五語沒有 sr）。
      #   把 sr 加進 forbidden_locale_tags 是「支援塞爾維亞語」時要做的事，不是本包。
      expect(described_class.chain("sr-Latn")).to eq([ "sr" ])
    end

    it "鏈長不超過 max_chain_length - 1（含自己才是 max）" do
      maximum = Limits.fetch(:i18n, :resolve, :max_chain_length)
      %w[zh-Hant-HK en-GB pt-BR ja sr-Latn-RS].each do |tag|
        expect(described_class.candidates(tag).length).to be <= maximum
      end
    end
  end

  describe ".candidates" do
    it "含請求語言自己且排在第一位（Resolve 的 depth 0 就是它）" do
      expect(described_class.candidates("zh-Hant-HK")).to eq([ "zh-Hant-HK", "zh-Hant" ])
    end
  end

  describe "fail-closed" do
    it "🔴 limits 的 fallback_chain_mode 若被改成未實作的模式 ⇒ raise，不靜默退化成空鏈" do
      # 突變驗證：把 `assert_mode!` 刪掉，這一格會紅。
      # 靜默退化的代價＝zh-Hant-HK 的使用者直接掉到英文，而沒有任何錯誤訊息。
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:i18n, :fallback_chain_mode).and_return("cldr_parent_locales")

      expect { described_class.chain("zh-Hant-HK") }
        .to raise_error(Locales::FallbackChain::UnsupportedMode, /cldr_parent_locales/)
    end
  end
end
