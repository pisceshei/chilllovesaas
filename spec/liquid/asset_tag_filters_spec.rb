# frozen_string_literal: true

require "rails_helper"

# 渲染 1:1 對表（2026-09-03）：`stylesheet_tag`／`script_tag` 輸出改成官方逐字形（filters/stylesheet_tag、filters/script_tag）。
RSpec.describe "ThemeEngine asset tag filters" do
  let(:harness) do
    h = Class.new { include ThemeEngine::Filters }.new
    h.instance_variable_set(:@context, Struct.new(:registers).new({}))
    h
  end

  it "AT1 🔴 stylesheet_tag：官方形 `<link href=\"…\" rel=\"stylesheet\" type=\"text/css\" media=\"all\" />`" do
    expect(harness.stylesheet_tag("/theme-assets/base.css"))
      .to eq(%(<link href="/theme-assets/base.css" rel="stylesheet" type="text/css" media="all" />))
  end

  it "AT2 stylesheet_tag：media 參數與額外屬性可加；href／rel 不可覆蓋" do
    expect(harness.stylesheet_tag("/a.css", "print")).to include(%(media="print"))
    out = harness.stylesheet_tag("/a.css", { "media" => "screen", "onload" => "x()", "href" => "/evil.css", "rel" => "preload" })
    expect(out).to eq(%(<link href="/a.css" rel="stylesheet" type="text/css" media="screen" onload="x()" />))
  end

  it "AT3 🔴 script_tag：官方形 `<script src=\"…\" type=\"text/javascript\"></script>`（無 defer）" do
    expect(harness.script_tag("/theme-assets/global.js")).to eq(%(<script src="/theme-assets/global.js" type="text/javascript"></script>))
  end
end
