# frozen_string_literal: true

require "rails_helper"

# 第 11 包：標籤正規化（13 §F4.4 六步）。
RSpec.describe Tags::Normalize do
  it "🔴 官方等價四形態折同一鍵：red_new／red+new／red&new／red-new（help P9 明載）" do
    keys = [ "red_new", "red+new", "red&new", "red-new" ].map { |raw| described_class.key(raw) }
    expect(keys.uniq).to eq([ "red-new" ])
  end

  it "NFKC：全形英數折半形（ｒｅｄ－ｎｅｗ → red-new）" do
    expect(described_class.key("ｒｅｄ－ｎｅｗ")).to eq("red-new")
  end

  it "casefold＋空白壓縮＋前後修剪" do
    expect(described_class.key("  RED   New ")).to eq("red-new")
    expect(described_class.key("Red & New")).to eq("red-new")
    expect(described_class.key("--red--")).to eq("red")
  end

  it "中文標籤原樣保留（只做 NFKC 與修剪，不音譯）" do
    expect(described_class.key("夏季")).to eq("夏季")
    expect(described_class.key(" 夏季 新品 ")).to eq("夏季-新品")
  end

  it "🔴 全分隔符輸入 ⇒ 空鍵（呼叫端據此跳過，不落列）" do
    [ "_", "+&_", "  ", "--", "" ].each do |raw|
      expect(described_class.key(raw)).to eq(""), raw.inspect
    end
  end

  it "冪等：key(key(x)) == key(x)" do
    [ "Red_New", "ｒｅｄ", "夏季 新品", "A&B" ].each do |raw|
      once = described_class.key(raw)
      expect(described_class.key(once)).to eq(once)
    end
  end
end
