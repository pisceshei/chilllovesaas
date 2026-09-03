# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# 渲染 1:1 對表（使用者 2026-09-03 裁定：preview／買家前台輸出的 CSS／尺寸／參數必須與本尊同主題渲染完全一樣）——
# 由 hoko.vip 原始位元組 vs 鏡像店逐段 diff 抓到的引擎形差（docs/dev/e8-render-parity.md §2）。
#
# 🔴 假綠殺手（鐵律 20.2⑤，每格對應 scratchpad mutate_e8.py 一個突變）：
#   RF1  bug-compatible whitespace trimming：`{%-` 清空整段純空白時保留首位元組（Ella 全 CRLF ⇒ 孤立 `\r`）
#   RF2  `{% style %}` ⇒ `<style data-shopify>`（官方逐字）
#   RF3  section.index／index0／location：整頁 1-based；群組 location＝群組 type；static ⇒ nil／"static"
#   RF4  缺群組檔零輸出；群組 BEGIN 後 LF、END 前 LF、wrapper 之間無分隔
#   RF5  inline_asset_content 照檔輸出（含檔尾換行）
#   RF6  SRA／設計模式 section.index＝nil
#   RF7  shop.customer_accounts_enabled 讀店級旗標
#   RF8  zh-Hans ⇒ 輸出碼 zh-CN；主題字串取 zh-CN.json
#   RF9  `{% schema %}` tag 留位：`-%}` 只吃到 schema 前、endschema 後的換行照輸出
#   RF10 form tag：隱藏欄位緊接 `<form>`、彼此無分隔
#   RF11 block 實例 id `{A+17}__{key}`：wrapper／block.id 同值、巢狀與靜態各自前綴、編輯器屬性仍裸 key
#   RF12 color 設定與字串相等（Ella color-swatches 分支）
#   RF13 placeholder 逐名外框；無 class 參數 ⇒ 無 class 屬性
#   RF14 Liquid 錯誤訊息用檔案路徑名（snippets/x、sections/x）
#   RF15 window.Shopify bootstrap 頭段形
RSpec.describe "ThemeEngine 渲染 1:1 形（E8）" do
  let(:shop) { create(:shop) }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }
  let(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "CRLF Probe", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  # 主題檔一律 CRLF（Ella 實況：snippets 197/198、sections 73/73、blocks 245/245 為 CRLF）
  def crlf(text) = text.gsub("\n", "\r\n")

  let(:root) do
    dir = Dir.mktmpdir("cl-parity")
    files = {
      "layout/theme.liquid" => crlf(<<~L),
        <html lang="{{ request.locale.iso_code }}"><head></head><body>
        {% sections 'header-group' %}
        {% sections 'nope-group' %}
        <main>{{ content_for_layout }}</main>
        {% section 'probe' %}
        </body></html>
      L
      "templates/index.json" => JSON.generate(
        "sections" => { "a" => { "type" => "probe", "settings" => {} }, "b" => { "type" => "probe", "settings" => {} },
                        "off" => { "type" => "probe", "disabled" => true, "settings" => {} },
                        "c" => { "type" => "probe", "settings" => {} },
                        "bl" => { "type" => "blocky", "settings" => { "p" => "p1", "q" => "no-such-product", "u" => "", "w" => 7, "cl" => [ "p1", "nope" ] },
                                  "blocks" => { "x" => { "type" => "leaf", "settings" => {},
                                                         "blocks" => { "y" => { "type" => "leaf", "settings" => {} } },
                                                         "block_order" => %w[y] },
                                                "x2" => { "type" => "leaf", "settings" => {},
                                                          "blocks" => { "y" => { "type" => "leaf", "settings" => {} } },
                                                          "block_order" => %w[y] },
                                                "dyn" => { "type" => "leaf2", "static" => true,
                                                           "settings" => { "product" => "{{ closest.product }}" } } },
                                  "block_order" => %w[x x2] } },
        "order" => %w[a b off c bl]
      ),
      "sections/header-group.json" => JSON.generate(
        "type" => "header", "name" => "Header group",
        "sections" => { "h1" => { "type" => "probe", "settings" => {} }, "h2" => { "type" => "probe", "settings" => {} } },
        "order" => %w[h1 h2]
      ),
      "sections/probe.liquid" => crlf(<<~S),
        <p data-index="{{ section.index }}" data-index0="{{ section.index0 }}" data-location="{{ section.location }}" data-accounts="{{ shop.customer_accounts_enabled }}">
        {%- render 'gap' -%}
        --after: 1;
        {%- render 'hello' -%}
        <span class="svg-wrapper">
          {%- if true -%}
          {{ 'icon.svg' | inline_asset_content }}
        {%- endif -%}
        </span></p>
        {%- style -%}.x{color:red}{%- endstyle -%}

        {% schema %}{ "name": "Probe", "settings": [] }{% endschema %}
      S
      "sections/blocky.liquid" => crlf(<<~B),
        {% form 'customer' %}x{% endform %}
        {%- if section.settings.c == 'rgba(0,0,0,0)' -%}EQ{%- else -%}NE{%- endif -%}
        {%- if 'rgba(0,0,0,0)' == section.settings.c -%}EQ2{%- endif -%}
        {{ 'hero-apparel-2' | placeholder_svg_tag: 'placeholder-svg' }}{{ 'hero-apparel-3' | placeholder_svg_tag }}{{ 'product-apparel-2' | placeholder_svg_tag: 'placeholder-svg' }}{{ 'collection-1' | placeholder_svg_tag }}
        [{% render 'boom' %}][{{ 2 | divided_by: 0 }}]
        <ol>{% for b in section.blocks %}<li>{{ b.id }}</li>{% endfor %}</ol>
        {%- assign n = 1 -%}<num>{% if n.featured_media %}T{% else %}F{% endif %}[{{ n.id }}][{{ n.media | json }}]</num>
        {%- assign s = "" -%}<str>{% if s.featured_media %}T{% else %}F{% endif %}[{{ s.id }}][{{ s.media | json }}][{{ s.compare_at_price | money }}][{% if nothing.foo %}T{% else %}F{% endif %}]</str>
        <nil>{% if nothing == empty %}E{% endif %}{% if nothing != empty %}N{% endif %}{% if nothing == blank %}B{% endif %}{% if "" == empty %}S{% endif %}</nil>
        <res>[{{ section.settings.p.title }}][{% if section.settings.q == empty %}E{% else %}N{% endif %}][{{ section.settings.cl.size }}:{{ section.settings.cl.first.handle }}][{{ section.settings.q.media | json }}][{% if section.settings.u.featured_media %}T{% else %}F{% endif %}{{ section.settings.u.media | json }}][{% if section.settings.v.featured_media %}T{% else %}F{% endif %}{{ section.settings.v.media | json }}{% if section.settings.v == empty %}E{% endif %}][{{ section.settings.w }}{{ section.settings.w.media | json }}]</res>
        {% content_for 'blocks' %}
        {% content_for 'block', type: 'leaf', id: 'static-leaf' %}
        <again>{% for b in section.blocks %}{% render b %}{% endfor %}{% content_for 'block', type: 'leaf', id: 'static-leaf' %}</again>
        {% content_for 'block', type: 'leaf2', id: 'dyn', closest.product: section.settings.p %}
        {% schema %}{ "name": "Blocky", "settings": [ { "type": "color", "id": "c", "default": "rgba(0,0,0,0)" }, { "type": "product", "id": "p" }, { "type": "product", "id": "q" }, { "type": "product", "id": "u" }, { "type": "product", "id": "v" }, { "type": "product", "id": "w" }, { "type": "product_list", "id": "cl" } ], "blocks": [ { "type": "@theme" } ] }{% endschema %}
      B
      "blocks/leaf.liquid" => "<i data-bid=\"{{ block.id }}\" {{ block.shopify_attributes }}>{% content_for 'blocks' %}</i>{% schema %}{ \"name\": \"Leaf\", \"settings\": [], \"blocks\": [ { \"type\": \"@theme\" } ] }{% endschema %}",
      "blocks/leaf2.liquid" => "<dyn>[{{ block.settings.product }}][{{ block.settings.product.title }}]</dyn>{% schema %}{ \"name\": \"Leaf2\", \"settings\": [ { \"type\": \"product\", \"id\": \"product\" } ] }{% endschema %}",
      "snippets/gap.liquid" => crlf(<<~G),
        {% comment %}doc{% endcomment %}

        {%- if true -%}
          --gap: 1px;
        {%- endif -%}
      G
      "snippets/boom.liquid" => "{{ 1 | divided_by: 0 }}",
      "assets/icon.svg" => "<svg><path d=\"M0 0\"/></svg>\r\n",
      # 本尊碼形的主題 locale 檔（Ella：zh-CN.json／zh-TW.json；無 zh-Hans 檔）
      "locales/en.default.json" => JSON.generate("probe" => { "hello" => "Hello" }),
      "locales/zh-CN.json" => JSON.generate("probe" => { "hello" => "你好" }),
      "snippets/hello.liquid" => "{{ 'probe.hello' | t }}"
    }
    files.each do |rel, body|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, body)
    end
    dir
  end
  let(:source) { ThemeEngine::FileSource.new(Pathname.new(root)) }

  after { FileUtils.remove_entry(root) if File.directory?(root) }

  def render(path = "/", design_mode: false, params: {}, locale: nil)
    ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source,
                                  design_mode: design_mode, locale: locale).render(path, params: params)
  end

  PREFIX = /A[A-Za-z0-9]{17}/

  it "RF1 🔴 `{%-` 清空純空白段時保留首位元組（本尊 `column;\\r--gap`／`</svg>\\r</span>` 形）" do
    html = render.html
    # snippet：`{% endcomment %}\r\n\r\n{%- if` 留下 `\r` ⇒ 輸出 `\r--gap: 1px;`；`-%}\r\n--after` 右側整段清空不留
    expect(html).to include("\r--gap: 1px;--after: 1;")
    # RF5：資產檔尾 `\r\n` 照輸出；其後 `\r\n  {%- endif -%}` 那段被清空、保留首位元組 `\r`
    expect(html).to include("</svg>\r\n\r</span>")
  end

  it "RF2 🔴 {% style %} ⇒ `<style data-shopify>`" do
    expect(render.html).to include("<style data-shopify>.x{color:red}</style>")
  end

  it "RF3 🔴 section.index 整頁 1-based 且只數實際渲染者；群組 location＝群組 type；static ⇒ nil／static" do
    html = render.html
    expect(html).to include(%(<div id="shopify-section-template--index__a" class="shopify-section"><p data-index="1" data-index0="0" data-location="template"))
    expect(html).to include(%(id="shopify-section-template--index__b" class="shopify-section"><p data-index="2" data-index0="1"))
    expect(html).not_to include("template--index__off") # disabled 不渲染
    expect(html).to include(%(id="shopify-section-template--index__c" class="shopify-section"><p data-index="3" data-index0="2"))
    expect(html).to include(%(id="shopify-section-sections--header-group__h1" class="shopify-section shopify-section-group-header-group"><p data-index="1" data-index0="0" data-location="header"))
    expect(html).to include(%(id="shopify-section-sections--header-group__h2" class="shopify-section shopify-section-group-header-group"><p data-index="2"))
    expect(html).to include(%(id="shopify-section-probe" class="shopify-section"><p data-index="" data-index0="" data-location="static"))
  end

  it "RF4 🔴 缺群組檔零輸出；BEGIN 後 LF／END 前 LF／wrapper 之間無分隔（hoko.vip 原始位元組）" do
    html = render.html
    expect(html).not_to include("nope-group")
    expect(html).to include("<!-- BEGIN sections: header-group -->\n<div id=\"shopify-section-sections--header-group__h1\"")
    expect(html).to match(%r{</div><div id="shopify-section-sections--header-group__h2"})
    expect(html).to match(%r{</div>\n<!-- END sections: header-group -->})
  end

  it "RF6 🔴 SRA 與設計模式 section.index＝nil（location 仍給）" do
    sra = render("/", params: { "section_id" => "template--index__b" }).html
    expect(sra).to include(%(data-index="" data-index0="" data-location="template"))
    editor = render("/", design_mode: true).html
    expect(editor).to include(%(id="shopify-section-template--index__a" class="shopify-section" data-shopify-editor-section='{"id":"a","type":"probe"}'><p data-index="" data-index0=""))
  end

  it "RF7 🔴 shop.customer_accounts_enabled 讀店級旗標（預設 true；關掉 ⇒ false）" do
    expect(render.html).to include(%(data-accounts="true"))
    shop.update!(customer_accounts_enabled: false)
    expect(render.html).to include(%(data-accounts="false"))
  end

  it "RF8 🔴 我方 zh-Hans ⇒ 輸出本尊碼 zh-CN（<html lang>／Shopify.locale），主題字串取 zh-CN.json（LocaleTags）" do
    html = render("/", locale: "zh-Hans").html
    expect(html).to include(%(<html lang="zh-CN">))
    expect(html).to include(%(Shopify.locale = "zh-CN";))
    expect(html).to include("你好")
    expect(render("/", locale: "en").html).to include(%(<html lang="en">)).and include("Hello")
  end

  it "RF9 🔴 `{%- endstyle -%}\\r\\n\\r\\n{% schema %}…{% endschema %}\\r\\n` ⇒ `</style>\\r\\n</div>`（endschema 後換行照輸出）" do
    expect(render.html).to include(".x{color:red}</style>\r\n</div>")
  end

  it "RF10 🔴 form tag：`<form …>` 緊接兩個隱藏欄位再緊接內容（本尊四形一致）" do
    expect(render.html).to match(%r{<form method="post" action="/contact#[^"]*" id="[^"]*" accept-charset="UTF-8" class="contact-form"><input type="hidden" name="form_type" value="customer" /><input type="hidden" name="utf8" value="✓" />x</form>})
  end

  it "RF11 🔴 block 實例 id：wrapper 與 block.id 同值、巢狀／靜態各自前綴、drop 迭代同值、編輯器屬性裸 key、跨次穩定" do
    html = render.html
    x = html[/<div id="shopify-block-(#{PREFIX}__x)" class="shopify-block"><i data-bid="([^"]+)"/, 1]
    expect(x).to be_present
    expect(html).to include(%(<div id="shopify-block-#{x}" class="shopify-block"><i data-bid="#{x}"))
    y = html[/<div id="shopify-block-(#{PREFIX}__y)" class="shopify-block"><i data-bid="\1"/, 1]
    expect(y).to be_present
    expect(y.split("__").first).not_to eq(x.split("__").first) # 巢狀子 block 前綴不同
    # 同 key `y` 分別掛在 x 與 x2 之下 ⇒ 前綴必須不同（seed 含完整路徑；本尊 `static-collection-list` 在兩個 section 前綴不同）
    expect(html.scan(/<div id="shopify-block-(#{PREFIX})__y" class="shopify-block">/).flatten.uniq.size).to eq(2)
    st = html[/<div id="shopify-block-(#{PREFIX}__static-leaf)" class="shopify-block"><i data-bid="\1"/, 1]
    expect(st).to be_present
    expect(html).to match(%r{<ol><li>#{Regexp.escape(x)}</li><li>#{PREFIX}__x2</li></ol>}) # section.blocks 的 drop 與 content_for 路徑同值
    expect(render.html).to include(x) # 同輸入同 id（確定性）
    editor = render("/", design_mode: true).html
    expect(editor).to include(%(data-bid="#{x}" data-shopify-editor-block='{"id":"x","type":"leaf"}'))
  end

  it "RF12 🔴 color 設定與字串相等（雙向）" do
    expect(render.html).to include("EQEQ2")
  end

  it "RF16 🔴 對字串取屬性 ⇒ 空字串（Liquid 真值；json ⇒ \"\"；money ⇒ 空）；整數／nil 取屬性仍為 nil——本尊佔位商品卡形" do
    expect(render.html).to include(%(<num>F[][null]</num>))
    expect(render.html).to include(%(<str>T[][""][][F]</str>))
  end

  it "RF17 🔴 nil == empty 為真（lookbook 點位「No product selected」分支）；blank／空字串語義不變" do
    expect(render.html).to include(%(<nil>EBS</nil>))
  end

  it "RF18 🔴 資源型 setting：解析成 drop；已選但查無 ⇒ nil（json null）；未選 ⇒ 空字串（取屬性為真、json \"\"）" do
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", handle: "p1", title: "P1")
      create(:product_variant, product:, price_cents: 1000)
    end
    # v：schema 有、JSON 無 ⇒ 同「未選」；w：動態來源已解成非資源純量（整數）⇒ 官方 blank（空字串）
    expect(render.html).to include(%(<res>[P1][E][1:p1][null][T""][T""E][""]</res>))
  end

  it "RF21 🔴 靜態 block 的動態來源 setting `{{ closest.product }}` 以本 block 的 closest（含參數覆寫）求值；drop 透傳、直接輸出＝handle" do
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", handle: "p1", title: "P1")
      create(:product_variant, product:, price_cents: 1000)
    end
    expect(render.html).to include(%(<dyn>[p1][P1]</dyn>))
  end

  it "RF20 🔴 同 section 內重複渲染同一 block ⇒ key 尾綴 -N，子孫同尾綴、前綴不變；靜態 block 同規則" do
    html = render.html
    again = html[%r{<again>(.*)</again>}m, 1]
    x = html[/<div id="shopify-block-(#{PREFIX})__x" class="shopify-block">/, 1]
    expect(again).to include(%(<div id="shopify-block-#{x}__x-1" class="shopify-block"><i data-bid="#{x}__x-1"))
    y = html[/<div id="shopify-block-(#{PREFIX})__y" class="shopify-block">/, 1]
    expect(again).to include(%(<div id="shopify-block-#{y}__y-1" class="shopify-block"><i data-bid="#{y}__y-1"))
    st = html[/<div id="shopify-block-(#{PREFIX})__static-leaf" class="shopify-block">/, 1]
    expect(again).to include(%(<div id="shopify-block-#{st}__static-leaf-1" class="shopify-block"))
  end

  it "RF19 🔴 每個 block 渲染尾接 LF（render 變數形／content_for 'blocks'／'block' 三路）" do
    html = render.html
    expect(html.scan(%r{</div>\n}).size).to be >= 3 # x、y、static-leaf 三個 wrapper 後皆 LF
    expect(html).not_to match(%r{</div><div id="shopify-block-})
  end

  it "RF13 🔴 placeholder 逐名外框；無 class 參數 ⇒ 無 class；非 apparel 走官方範例形" do
    html = render.html
    expect(html).to include(%(<svg class="placeholder-svg" preserveAspectRatio="xMidYMin slice" viewBox="0 0 1300 731" fill="none" xmlns="http://www.w3.org/2000/svg">))
    expect(html).to include(%(<svg preserveAspectRatio="xMaxYMid slice" viewBox="0 0 1297 729" fill="none" xmlns="http://www.w3.org/2000/svg">))
    expect(html).to include(%(<svg class="placeholder-svg" preserveAspectRatio="xMidYMid slice" width="449" height="448" viewBox="0 0 449 448" fill="none" xmlns="http://www.w3.org/2000/svg">))
    expect(html).to include(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 525.5 525.5">))
  end

  it "RF14 🔴 Liquid 錯誤訊息用檔案路徑名（snippets/x；sections/x）" do
    html = render.html
    expect(html).to include("[Liquid error (snippets/boom line 1): divided by 0]")
    expect(html).to match(%r{\[Liquid error \(sections/blocky line \d+\): divided by 0\]})
  end

  it "RF15 🔴 window.Shopify bootstrap 頭段形（var 宣告、JSON 形 currency／theme、handle／style／cdnHost／routes.root）" do
    html = render.html
    expect(html).to include(%(<script>var Shopify = Shopify || {};\nShopify.shop = "#{shop.subdomain}.))
    expect(html).to include(%(Shopify.currency = {"active":"HKD","rate":"1.0"};\nShopify.country = "";\n))
    expect(html).to match(%r{Shopify\.theme = \{"name":"CRLF Probe","id":\d+,"schema_name":null,"schema_version":null,"theme_store_id":null,"role":"main"\};\nShopify\.theme\.handle = "null";\nShopify\.theme\.style = \{"id":null,"handle":null\};\nShopify\.cdnHost = "[^"]*/theme-assets";\nShopify\.routes = Shopify\.routes \|\| \{\};\nShopify\.routes\.root = "/";\n})
  end
end
