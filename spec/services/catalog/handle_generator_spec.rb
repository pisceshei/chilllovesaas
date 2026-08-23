# frozen_string_literal: true

require "rails_helper"

# limits `handle:` 區塊的可執行形——裁定範例逐字元釘住（此前只有 request spec
# 抽測三種行為，六個範例「通過」只存在於 commit 訊息裡；對抗審查 confirmed #16）。
RSpec.describe Catalog::HandleGenerator do
  # 使用者 2026-08-12 裁定的原始範例（86 字元，limits handle 區塊標頭逐字）。
  it "裁定範例逐字元通過（Kérastase 86 字元例）" do
    result = described_class.call(
      "Kérastase Spécifique Stimuliste Nutri-energising Daily Anti-hairloss Spray 125ml/4.2oz"
    )
    expect(result.handle).to eq(
      "kerastase-specifique-stimuliste-nutri-energising-daily-anti-hairloss-spray-125ml-4-2oz"
    )
    expect(result.flagged?).to be(false)
  end

  it "撇號類刪除而非轉分隔（Bob's → bobs，不是 bob-s）" do
    expect(described_class.call("Bob's Burgers").handle).to eq("bobs-burgers")
  end

  # 🔴 U+00B4（´）回歸釘：NFKC 會把它分解成空格＋combining acute，刪除步驟
  # 必須在 NFKC 之前，否則得到 bob-s（對抗審查 confirmed #6 的事故形）。
  it "U+00B4 尖音符同樣刪除（delete_chars 先於 NFKC）" do
    expect(described_class.call("Bob´s Burgers").handle).to eq("bobs-burgers")
  end

  it "不可分解拉丁字母查表轉寫（Straße → strasse，不是 stra-e）" do
    expect(described_class.call("Straße Shirt").handle).to eq("strasse-shirt")
  end

  it "全形經 NFKC 折半形（ＳＫ－ＩＩ　230ｍL → sk-ii-230ml）" do
    expect(described_class.call("ＳＫ－ＩＩ　230ｍL").handle).to eq("sk-ii-230ml")
  end

  it "小數點轉分隔而非刪除（規格數字不得被改寫：4.2oz → 4-2oz）" do
    expect(described_class.call("16\" Cash Drawer").handle).to eq("16-cash-drawer")
  end

  it "混合標題過品質閘門並標記字母丟棄（無印良品 MUJI 有機棉 T-Shirt）" do
    result = described_class.call("無印良品 MUJI 有機棉 T-Shirt")
    expect(result.handle).to eq("muji-t-shirt")
    expect(result.flagged?).to be(true)
  end

  it "純 CJK 落確定性 fallback（product-token8，Crockford 字母表）" do
    result = described_class.call("棉質短T")
    expect(result.handle).to match(/\Aproduct-[0-9a-hjkmnp-tv-z]{8}\z/)
    expect(result.flagged?).to be(true)
  end

  it "截斷落在分隔符邊界（max_chars 之內不切半個詞）" do
    long_title = ([ "word" ] * 80).join(" ")
    handle = described_class.call(long_title).handle
    expect(handle.length).to be <= Limits.fetch(:handle, :max_chars)
    expect(handle).not_to end_with("-")
    expect(handle.split("-")).to all(eq("word"))
  end
end
