# frozen_string_literal: true

require "rails_helper"

# 渲染 1:1 對表（2026-09-03）：官方 `color` 物件（objects/color 逐字：alpha 0.0–1.0；rgb 空白分隔；rgba 空白分隔＋斜線後
# alpha，官方例 "51 79 180 / 1.0"）。Ella 透明色存 `rgba(0,0,0,0)`，hoko.vip 首頁輸出 `rgb(0 0 0 / 0.0)` 86 處。
RSpec.describe ThemeEngine::ColorDrop do
  it "CD1 🔴 官方例：#334fb4 ⇒ rgb \"51 79 180\"、rgba \"51 79 180 / 1.0\"、alpha 1.0、直接輸出原值" do
    c = described_class.new("#334fb4")
    expect([ c.red, c.green, c.blue, c.alpha ]).to eq([ 51, 79, 180, 1.0 ])
    expect(c.rgb).to eq("51 79 180")
    expect(c.rgba).to eq("51 79 180 / 1.0")
    expect(c.to_s).to eq("#334fb4")
    expect(c.hex).to eq("#334fb4")
  end

  it "CD2 🔴 rgba(0,0,0,0)（Ella 透明色）⇒ alpha 0.0、rgba \"0 0 0 / 0.0\"；rgba(255,25,0,0.5) ⇒ \"255 25 0 / 0.5\"" do
    t = described_class.new("rgba(0,0,0,0)")
    expect(t.alpha).to eq(0.0)
    expect(t.rgba).to eq("0 0 0 / 0.0")
    expect(t.rgb).to eq("0 0 0")
    expect(described_class.new("rgba(255, 25, 0, 0.5)").rgba).to eq("255 25 0 / 0.5")
    expect(described_class.new("rgb(1,2,3)").rgba).to eq("1 2 3 / 1.0")
  end

  it "CD3 短 hex／hex8／transparent" do
    expect(described_class.new("#f00").rgb).to eq("255 0 0")
    expect(described_class.new("#ff000080").alpha).to eq(0.5)
    expect(described_class.new("transparent").rgba).to eq("0 0 0 / 0.0")
  end

  it "CD4 HSL（標準轉換；舊實作 hue／saturation 恆 0）" do
    c = described_class.new("#334fb4")
    expect([ c.hue, c.saturation, c.lightness ]).to eq([ 227, 56, 45 ])
    expect([ described_class.new("#ffffff").lightness, described_class.new("#000000").lightness ]).to eq([ 100, 0 ])
  end

  it "CD5 🔴 SettingsDrop 強轉：color 型 rgba()／transparent 都成 color 物件；color_background 的漸層字串原樣" do
    drop = ThemeEngine::SettingsDrop.new(
      { "bg" => "rgba(0,0,0,0)", "fg" => "#334fb4", "t" => "transparent", "grad" => "linear-gradient(#000, #fff)" },
      { "bg" => "color", "fg" => "color", "t" => "color", "grad" => "color_background" }
    )
    expect(drop.liquid_method_missing("bg")).to be_a(described_class)
    expect(drop.liquid_method_missing("bg").alpha).to eq(0.0)
    expect(drop.liquid_method_missing("fg").rgba).to eq("51 79 180 / 1.0")
    expect(drop.liquid_method_missing("t").alpha).to eq(0.0)
    expect(drop.liquid_method_missing("grad")).to eq("linear-gradient(#000, #fff)")
    out = Liquid::Template.parse("rgb({{ settings.bg.rgba }}){% if settings.bg.alpha != 0.0 %}X{% endif %}")
      .render("settings" => drop)
    expect(out).to eq("rgb(0 0 0 / 0.0)") # Ella global-style.liquid 的形
  end
end
