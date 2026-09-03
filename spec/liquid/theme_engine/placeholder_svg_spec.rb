# frozen_string_literal: true

require "rails_helper"

# E3b：`placeholder_svg_tag` 對位本尊實測形（hoko.vip 2026-09-03）：整張插圖、class 規則、viewBox 依名稱。
RSpec.describe ThemeEngine::PlaceholderSvg do
  # 2026-09-03 更正（E8 渲染 1:1，hoko.vip 原始位元組）：原文「未給 class 也得到 placeholder-svg」是誤讀——
  # background-image snippet 的 `hero-apparel-3` 輸出 `<svg preserveAspectRatio="xMaxYMid slice" viewBox="0 0 1297 729" …>`
  # **沒有 class 屬性**，與官方範例一致；且 preserveAspectRatio／viewBox 逐名不同（FRAMES）。
  it "PS1 未給 class ⇒ 無 class 屬性；外框逐名（hero-apparel-2＝xMidYMin 1300×731、hero-apparel-3＝xMaxYMid 1297×729）" do
    svg = described_class.tag("hero-apparel-2")
    expect(svg).to start_with('<svg preserveAspectRatio="xMidYMin slice" viewBox="0 0 1300 731" fill="none"')
    expect(described_class.tag("hero-apparel-3")).to start_with('<svg preserveAspectRatio="xMaxYMid slice" viewBox="0 0 1297 729" fill="none"')
    expect(described_class.tag("hero-apparel-2", "placeholder-svg")).to start_with('<svg class="placeholder-svg" preserveAspectRatio="xMidYMin slice" viewBox="0 0 1300 731" fill="none"')
    expect(svg).to end_with("</svg>")
    expect(svg).to include("<path")
  end

  it "PS2 給了 class ⇒ 逐字使用、不附加（舊實作會變成 \"x placeholder-svg\"）" do
    svg = described_class.tag("collection-3", "placeholder-svg placeholder-svg--bg")
    expect(svg).to include('class="placeholder-svg placeholder-svg--bg"')
    expect(svg).not_to include("placeholder-svg--bg placeholder-svg")
  end

  it "PS3 方形名稱走 525.5 viewBox、寬幅名稱走 1300×731；未知名稱 fail-open 回通用線稿" do
    expect(described_class.tag("product-1")).to include('viewBox="0 0 525.5 525.5"')
    expect(described_class.tag("lifestyle-2")).to include('viewBox="0 0 1300 731"')
    expect(described_class.tag("blog-apparel-3")).to include('viewBox="0 0 1300 731"')
    expect(described_class.tag("no-such-name")).to eq(described_class.tag("image"))
  end

  it "PS4 官方名稱表全部有插圖（每個名稱輸出含至少一個圖形元素，且彼此不全相同）" do
    names = %w[product-1 product-2 product-3 product-4 product-5 product-6
               collection-1 collection-2 collection-3 collection-4 collection-5 collection-6
               lifestyle-1 lifestyle-2 image
               product-apparel-1 product-apparel-2 product-apparel-3 product-apparel-4
               collection-apparel-1 collection-apparel-2 collection-apparel-3 collection-apparel-4
               hero-apparel-1 hero-apparel-2 hero-apparel-3
               blog-apparel-1 blog-apparel-2 blog-apparel-3 detailed-apparel-1]
    bodies = names.map { |name| described_class.tag(name) }
    bodies.each { |svg| expect(svg).to match(/<(path|rect|circle)/) }
    expect(bodies.uniq.size).to be > names.size / 2
  end

  it "PS5 class 值經 HTML escape（防止主題把使用者輸入餵進 class）" do
    expect(described_class.tag("image", 'x" onload="alert(1)')).to include('class="x&quot; onload=&quot;alert(1)"')
  end
end
