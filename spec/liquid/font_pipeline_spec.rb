# frozen_string_literal: true

require "rails_helper"

# 步 13a：字型管線（FontLibrary＋FontDrop＋font_face/font_url/font_modify）。
# 契約錨＝docs/research/97 §1（官方逐字＋chill.deals live @font-face 形）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   F2 缺變體回 nil（殺：回原 font ⇒ Ella italic 鏈輸出錯 face）
#   F4 system/未知 handle 的 font_face 空輸出（殺：炸 nil file 進 src）
RSpec.describe "Theme engine font pipeline" do
  let(:harness) { Class.new { include ThemeEngine::Filters }.new }
  let(:jost4) { ThemeEngine::FontLibrary.drop("jost_n4") }

  it "F1 handle 解析＋font_face 輸出形（live 對錨：family 無引號/weight/style/src）" do
    expect(jost4.family).to eq("Jost")
    expect(jost4.weight).to eq(400)
    expect(jost4.style).to eq("normal")
    expect(jost4.system?).to be(false)
    expect(jost4.fallback_families).to eq("sans-serif")

    css = harness.font_face(jost4)
    expect(css).to include("@font-face {")
    expect(css).to include("font-family: Jost;")
    expect(css).to include("font-weight: 400;")
    expect(css).to include("font-style: normal;")
    expect(css).not_to include("font-display") # 未傳參數不輸出該行（97 §4-1）
    # E8（2026-09-03，hoko.vip 原始位元組）：src 兩行＝woff2 之後接 woff 備援（我方 woff 檔未提供，形對位、登記）
    expect(css).to include(%(src: url("/fonts/jost/jost_n4.woff2") format("woff2"),
       url("/fonts/jost/jost_n4.woff") format("woff");))

    with_display = harness.font_face(jost4, "font_display" => "swap")
    expect(with_display).to include("font-display: swap;")
  end

  it "F2 🔴 font_modify：bold→700、'600'→n6、+100、缺變體（italic）回 nil（官方逐字）" do
    expect(harness.font_modify(jost4, "weight", "bold").weight).to eq(700)
    expect(harness.font_modify(jost4, "weight", "600").weight).to eq(600)
    expect(harness.font_modify(jost4, "weight", "+100").weight).to eq(500)
    expect(harness.font_modify(jost4, "weight", "bolder").weight).to eq(700) # CSS 400→700
    expect(harness.font_modify(jost4, "style", "italic")).to be_nil # 庫無 italic
    expect(harness.font_modify(jost4, "weight", "900")).to be_nil # 庫無 n9
    # Ella 消費鏈末端：nil 進 font_face ⇒ 空輸出（不炸）
    expect(harness.font_face(harness.font_modify(jost4, "style", "italic"))).to eq("")
  end

  it "F3 font_url 回自 host woff2 路徑；variants＝同家族 4 變體" do
    expect(harness.font_url(jost4)).to eq("/fonts/jost/jost_n4.woff2")
    expect(jost4.variants.map(&:weight)).to match_array([ 400, 500, 600, 700 ])
    # 對應實體檔存在（自 host 最小集不是紙面聲明）
    expect(Rails.root.join("public/fonts/jost/jost_n4.woff2")).to exist
  end

  it "F4 🔴 system／未知 handle：system?=true、font_face 空輸出、miss 遙測不炸" do
    sys = ThemeEngine::FontLibrary.drop("sans_serif_n4")
    expect(sys.system?).to be(true)
    expect(harness.font_face(sys)).to eq("")

    # 樣本 handle 原為 helvetica_n4——引擎缺口 PR-5 依官方字庫表把 Helvetica 收進 library 段後
    # 它不再是「未知」；改用永不入表的鍵（keyset_cursor_spec 同款教訓），斷言語義不變。
    unknown = ThemeEngine::FontLibrary.drop("nope_font_n4")
    expect(unknown.system?).to be(true)
    expect(unknown.family).to eq("Nope Font")
    expect(harness.font_face(unknown)).to eq("")
  end

  it "F5 端到端：settings font_picker → Ella global-style 形的渲染輸出真 @font-face" do
    template = Liquid::Template.parse(<<~LIQUID, environment: ThemeEngine::Runtime::ENVIRONMENT)
      {%- assign bold = font | font_modify: 'weight', 'bold' -%}
      {{ font | font_face: font_display: 'swap' }}
      {{ bold | font_face: font_display: 'swap' }}
      {%- assign italic = font | font_modify: 'style', 'italic' -%}
      {{ italic | font_face: font_display: 'swap' }}
      body { font-family: {{ font.family }}, {{ font.fallback_families }}; }
    LIQUID
    css = template.render({ "font" => jost4 })
    expect(css.scan("@font-face").size).to eq(2) # n4＋bold n7；italic 缺席不出第三塊
    expect(css).to include("font-display: swap;")
    expect(css).to include("body { font-family: Jost, sans-serif; }")
  end
end
