# frozen_string_literal: true

require "rails_helper"

# 渲染 1:1 對表工具：正規化只抹掉「平台／租戶身分」形（主機、CDN 資產路徑與版本、群組／模板數字 id、block 實例前綴、
# CSRF／reqid），其餘差異必須留下（鐵律 19：不得靠正規化把 diff 弄綠）。
RSpec.describe RenderParity::Normalizer do
  subject(:normalizer) { described_class.new(host: "hoko.vip") }

  it "RP1 🔴 本尊形 → 我方形：CDN 主題資產、字型、版本參數、群組／模板數字 id、block 實例前綴、主機名" do
    html = <<~HTML
      <link href="//hoko.vip/cdn/shop/t/2/assets/base.css?v=88290808517547527771663872409" rel="stylesheet" type="text/css" media="all" />
      <link rel="preload" href="//hoko.vip/cdn/fonts/jost/jost_n4.d47a1b6347ce4a4c9f437608011273009d91f2b7.woff2">
      <div id="shopify-section-sections--19763396837479__announcement_bar_4tGfEp" class="group-block--AWlFwNUZ5UVVuRmp6e__group_announcement_bar_PeTpTw"></div>
      <div id="shopify-section-template--19774791385191__slideshow_tyrRgz"></div>
      <a href="https://hoko.vip/collections/all">x</a>
    HTML
    out = normalizer.call(html)
    expect(out).to include(%(<link href="/theme-assets/base.css" rel="stylesheet" type="text/css" media="all" />))
    expect(out).to include(%(href="/fonts/jost/jost_n4.woff2"))
    expect(out).to include(%(id="shopify-section-sections--G__announcement_bar_4tGfEp"))
    expect(out).to include(%(class="group-block--B__group_announcement_bar_PeTpTw"))
    expect(out).to include(%(id="shopify-section-template--T__slideshow_tyrRgz"))
    expect(out).to include(%(href="/collections/all"))
    expect(out).not_to include("hoko.vip")
  end

  it "RP2 我方形同樣收斂到同一形（群組名／模板名 ⇒ G／T），差異才可比" do
    ours = described_class.new(host: "demo.chilling.com.hk").call(
      %(<div id="shopify-section-sections--header-group__announcement_bar_4tGfEp"></div><div id="shopify-section-template--index__slideshow_tyrRgz"></div>))
    expect(ours).to include("sections--G__announcement_bar_4tGfEp")
    expect(ours).to include("template--T__slideshow_tyrRgz")
  end

  it "RP3 🔴 非身分差異不得被抹掉（例：tag 格式、色值）" do
    a = normalizer.call(%(<link rel="stylesheet" href="/theme-assets/a.css">))
    b = normalizer.call(%(<link href="/theme-assets/a.css" rel="stylesheet" type="text/css" media="all" />))
    expect(a).not_to eq(b)
    expect(normalizer.call("rgb(0 0 0 / 0.0)")).not_to eq(normalizer.call("rgb()"))
  end

  it "RP6 url_prefix（已登記裁定差異）：只抹我方前綴，根路徑收斂成 /" do
    n = described_class.new(host: "mirror.localhost:3000", url_prefix: "/zh-hans-tw")
    out = n.call(%(<a href="http://mirror.localhost:3000/zh-hans-tw/collections/all">a</a><a href="/zh-hans-tw">r</a><a href="/zh-hans-tw?x=1">q</a><a href="/zh-hans-two/x">no</a>))
    expect(out).to include(%(href="/collections/all")).and include(%(href="/">r)).and include(%(href="/?x=1")).and include(%(href="/zh-hans-two/x"))
  end

  it "RP8 E19 編譯資產路徑的主題 id 是身分值（hoko 主題 2 vs bt3 mirror 主題 7）⇒ 抹成 ID；路徑其餘照留" do
    hoko = %(<script id="sections-script" data-sections="section-product-tabs" defer="defer" src="//hoko.vip/cdn/shop/t/2/compiled_assets/scripts.js?v=123"></script>)
    ours = %(<script id="sections-script" data-sections="section-product-tabs" defer="defer" src="//mirror.chilling.com.hk/cdn/shop/t/7/compiled_assets/scripts.js?v=456"></script>)
    a = normalizer.call(hoko)
    b = described_class.new(host: "mirror.chilling.com.hk").call(ours)
    expect(a).to eq(b)
    expect(a).to include(%(src="/cdn/shop/t/ID/compiled_assets/scripts.js"))
    expect(a).not_to include("/t/2/")
  end

  it "RP4 sections 切段：以 wrapper id 的最後 `__` 段為 key" do
    html = %(<div id="shopify-section-sections--G__a" class="shopify-section">A</div><section id="shopify-section-template--T__b" class="shopify-section">B</section><footer id="shopify-section-sections--G__c">C</footer>)
    parts = normalizer.sections(html)
    expect(parts.keys).to eq(%w[a b c])
    expect(parts["b"]).to start_with("<section id=\"shopify-section-template--T__b\"")
  end
end

RSpec.describe RenderParity::Report do
  let(:normalizer) { RenderParity::Normalizer.new(host: "") }

  it "RP5 🔴 逐段相似度＋差異片段＋head 資產集合差；全同 ⇒ 1.0 且無片段" do
    ref = %(<html><head><link href="/theme-assets/a.css" rel="stylesheet" type="text/css" media="all" /><script src="/theme-assets/x.js" type="text/javascript"></script></head><body><div id="shopify-section-template--T__hero" class="shopify-section"><h1>Hi</h1><p style="--c: rgb(0 0 0 / 0.0)">x</p></div><div id="shopify-section-template--T__demo">same</div></body></html>)
    cand = %(<html><head><link rel="stylesheet" href="/theme-assets/a.css"></head><body><div id="shopify-section-template--T__hero" class="shopify-section"><h1>Hi</h1><p style="--c: rgb()">x</p></div><div id="shopify-section-template--T__demo">same</div><div id="shopify-section-template--T__extra">only ours</div></body></html>)
    report = described_class.new(reference: ref, candidate: cand, normalizer: normalizer)
    by_key = report.sections.to_h { |s| [ s.key, s ] }
    expect(by_key["demo"].similarity).to be >= 0.999
    expect(by_key["hero"].similarity).to be < 0.999
    expect(by_key["hero"].fragments.first.reference).to include("rgb(0 0 0 / 0.0)")
    expect(by_key["extra"].similarity).to eq(0.0) # 只在我方
    head = report.head_assets
    expect(head[:scripts]).to eq([ [ "/theme-assets/x.js" ], [] ])
    md = report.to_markdown
    expect(md).to include("| hero |").and include("## Head assets")
  end

  it "RP7 集合頁商品卡的商品／變體數字 id（product-grid-、data-json-product id、&quot;id&quot;:、NoMediaLink--）抹成 ID；handle 照留" do
    card = %(<li id="template--19774791385191__product-grid-7771796897895"><div data-json-product='{"id": 7771796897895,"handle": "acme-tee","variants": [{&quot;id&quot;:44547877830759,&quot;title&quot;:&quot;Acme Tee&quot;}]}'></div>)
    link = %(<a id="StandardCardNoMediaLink--7771796897895" aria-labelledby="StandardCardNoMediaLink--7771796897895 NoMediaStandardBadge--7771796897895">acme-tee</a></li>) +
           %(<span id="ShareMessage-7771796897895"></span><script type="application/json" data-subtotal-variants>[{"id":7,"title":"Default Title"}]</script>)
    out = normalizer.call(card + link)
    expect(out).to include(%(id="template--T__product-grid-ID")).and include(%({"id": ID,"handle": "acme-tee"))
    expect(out).to include(%(&quot;id&quot;:ID,&quot;title&quot;:&quot;Acme Tee&quot;))
    expect(out).to include(%(id="StandardCardNoMediaLink--ID" aria-labelledby="StandardCardNoMediaLink--ID NoMediaStandardBadge--ID"))
    expect(out).to include(%(id="ShareMessage-ID")).and include(%([{"id":ID,"title":"Default Title"}]))
    expect(out).not_to include("7771796897895")
    expect(out).not_to include("44547877830759")
  end
end
