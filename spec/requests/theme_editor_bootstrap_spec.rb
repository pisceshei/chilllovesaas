# frozen_string_literal: true

require "rails_helper"

# 步 16a：編輯器 bootstrap（templateJson DB 覆寫優先＋files.body＋design_mode 橋）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   E1 DB 覆寫優先（殺：只讀檔 ⇒ 編輯過的模板在編輯器裡看起來沒改）
#   E2 key 逃逸防線（殺：../ 讀出模板目錄外檔案）
#   E3 design_mode 才注入橋（殺：公開店面頁也帶編輯器 JS）
RSpec.describe "Theme editor bootstrap", type: :request do
  let(:shop) { create(:shop, subdomain: "editor-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  before do
    host! "editor-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    allow(ThemeEngine::Sources).to receive(:key_for).and_call_original
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
  end

  it "E1 🔴 templateJson：檔案版可讀；DB Template row 蓋過檔案版；files.body 出文字內容" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) {
        theme(id: $id) {
          templateJson(key: "index")
          layout: files(filenames: ["layout/*.liquid"]) { filename body }
        }
      }
    GQL
    data = response.parsed_body.dig("data", "theme")
    expect(data.dig("templateJson", "sections")).to have_key("hero")
    expect(data["layout"].first["body"]).to include("content_for_layout")

    ActsAsTenant.with_tenant(shop) do
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index",
                       template_type: "index",
                       content: { "sections" => { "custom" => { "type" => "hero", "settings" => {} } },
                                  "order" => [ "custom" ] })
    end
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { templateJson(key: "index") } }
    GQL
    overridden = response.parsed_body.dig("data", "theme", "templateJson")
    expect(overridden["order"]).to eq([ "custom" ]) # DB 覆寫贏
  end

  it "E4 sectionCatalog 只列帶 presets 的區段（24 §1.4）＋preset settings 帶出" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionCatalog } }
    GQL
    catalog = response.parsed_body.dig("data", "theme", "sectionCatalog")
    types = catalog.map { |entry| entry["type"] }
    expect(types).to include("promo")
    expect(types).not_to include("hero") # 無 presets ⇒ 不進 picker
    promo = catalog.find { |entry| entry["type"] == "promo" }
    expect(promo["name"]).to eq("促銷條")
    expect(promo.dig("preset", "settings", "text")).to eq("預設促銷文案")
  end

  it "E5 sectionSchemas 全區段（不過濾 presets）＋ t: 鍵經 *.default.schema.json 解析" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionSchemas } }
    GQL
    schemas = response.parsed_body.dig("data", "theme", "sectionSchemas")
    expect(schemas).to have_key("hero") # 無 presets 也要有（樹上選中要控件）
    heading = schemas.dig("hero", "settings").find { |d| d["id"] == "heading" }
    expect(heading).to include("type" => "text", "default" => "預設標題")

    promo_label = schemas.dig("promo", "settings").find { |d| d["id"] == "text" }["label"]
    expect(promo_label).to eq("促銷文案") # t:promo.text_label 解析
    expect(schemas.dig("promo", "name")).to eq("促銷條") # t:names.promo 解析
  end

  it "E6 settingsSchema 分組（theme_info 跳過）＋themeSettingsJson 讀序 DB 覆寫優先" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { settingsSchema themeSettingsJson themeSettingsLockVersion } }
    GQL
    body = response.parsed_body.dig("data", "theme")
    names = body["settingsSchema"].map { |group| group["name"] }
    expect(names).to eq([ "Colors" ]) # theme_info 首項不是設定分組（24 §2.5）
    brand = body["settingsSchema"].first["settings"].find { |d| d["id"] == "brand_color" }
    expect(brand).to include("type" => "color", "default" => "#000000")

    # 無 DB 列 ⇒ 檔案 current；lockVersion null（首存免帶）
    expect(body.dig("themeSettingsJson", "brand_color")).to eq("#a9502c")
    expect(body["themeSettingsLockVersion"]).to be_nil

    ActsAsTenant.with_tenant(shop) do
      ThemeSetting.create!(shop_id: shop.id, theme_id: theme.id,
                           settings: { "brand_color" => "#e2e2e2" })
    end
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { themeSettingsJson themeSettingsLockVersion } }
    GQL
    overlay = response.parsed_body.dig("data", "theme")
    expect(overlay.dig("themeSettingsJson", "brand_color")).to eq("#e2e2e2") # DB 蓋檔案
    expect(overlay["themeSettingsLockVersion"]).to eq(0)
  end

  it "E7 sectionGroups：layout {% sections %} 掃描＋group JSON＋overlay lock；渲染帶群組" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionGroups } }
    GQL
    groups = response.parsed_body.dig("data", "theme", "sectionGroups")
    # 既有 fixture 已引用 test-group；本輪加的 header/footer 依 layout 序在後
    expect(groups.map { |g| g["name"] }).to eq(%w[test-group header-group footer-group])
    header = groups.find { |g| g["name"] == "header-group" }
    expect(header["path"]).to eq("sections/header-group.json")
    expect(header.dig("json", "order")).to eq([ "header" ])
    expect(header["lockVersion"]).to be_nil # 無 overlay ⇒ 首存免帶

    # 渲染整頁帶群組 sections（前台契約同軸——群組編輯的可視面）
    html = ActsAsTenant.with_tenant(shop) do
      ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!)
                               .render("/").html
    end
    expect(html).to include("群組頁首")
    expect(html).to include("群組頁尾")
  end

  it "E8 sectionSchemas 的 blocks 面：本地 def 帶 settings＋max_blocks；@theme 展開 blocks/*.liquid" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionSchemas } }
    GQL
    schemas = response.parsed_body.dig("data", "theme", "sectionSchemas")

    promo = schemas["promo"]
    expect(promo["maxBlocks"] || promo["max_blocks"]).to eq(3)
    badge = promo["blocks"].find { |b| b["type"] == "badge" }
    expect(badge["name"]).to eq("徽章")
    expect(badge["settings"].first).to include("id" => "label", "default" => "NEW")

    # blocks-iter 的 schema 用 @theme（既有 fixture）⇒ 展開 blocks/*.liquid 全集
    themed = schemas.values.find { |sc| sc["blocks"]&.any? { |b| b["type"] == "_card" } }
    expect(themed).not_to be_nil, "@theme 展開應含 blocks/_card.liquid"
  end

  it "DS1 🔴 draft_section：未儲存 entry 渲染片段（不落 DB）；缺參 422" do
    post "/admin/store/preview/#{theme.id}/draft_section",
         params: { path: "/", section_id: "hero",
                   entry: { type: "hero", settings: { heading: "草稿即時值" } } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("草稿即時值")           # 🔴 draft 覆蓋生效
    expect(response.body).to include(%(id="shopify-section-template--index__hero")) # 片段含 wrapper（cl:replace 錨；PR-7 前綴形）
    expect(ActsAsTenant.with_tenant(shop) { Template.count }).to eq(0) # 不落 DB

    post "/admin/store/preview/#{theme.id}/draft_section",
         params: { path: "/", section_id: "", entry: {} }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "DP1 🔴 draft_page：未儲存佈景設定＋結構草稿整頁生效（不落 DB；design_mode）" do
    post "/admin/store/preview/#{theme.id}/draft_page",
         params: { path: "/",
                   sections: { "hero" => { type: "hero", settings: { heading: "整頁草稿標題" } } },
                   settings: { brand_color: "#123456" } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(content="#123456")) # 🔴 draft 佈景設定蓋過檔案 current
    expect(response.body).to include("整頁草稿標題")        # 結構草稿同通道生效
    expect(response.body).to include("cl:highlight")        # 編輯器語境（design_mode 橋）
    expect(ActsAsTenant.with_tenant(shop) { Template.count + ThemeSetting.count }).to eq(0)
  end

  it "DP2 draft_page 不帶 settings ⇒ 檔案 current 照舊；previewPaths 出樣本路徑" do
    post "/admin/store/preview/#{theme.id}/draft_page",
         params: { path: "/", sections: {} }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(content="#a9502c")) # 檔案 current 不受影響

    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { previewPaths } }
    GQL
    paths = response.parsed_body.dig("data", "theme", "previewPaths")
    expect(paths["cart"]).to eq("/cart")
    expect(paths).not_to have_key("product") # 無商品 ⇒ 不出鍵（前端回落首頁）
  end

  it "CC1 🔴 custom_css：section data 帶 custom_css ⇒ scoped style 輸出；未帶 ⇒ 無" do
    post "/admin/store/preview/#{theme.id}/draft_page",
         params: { path: "/",
                   sections: { "hero" => { type: "hero", settings: {},
                                           custom_css: "p { color: red; }" } } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<style data-shopify-custom-css>#shopify-section-template--index__hero {")
    expect(response.body).to include("p { color: red; }") # 官方「scoped to that section」

    post "/admin/store/preview/#{theme.id}/draft_page",
         params: { path: "/", sections: {} }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response.body).not_to include("data-shopify-custom-css") # 未設 ⇒ 零殘留
  end

  it "TCC1 🔴 theme 級 Custom CSS：platform_customizations 出 head style；設定值面不被汙染" do
    ActsAsTenant.with_tenant(shop) do
      ThemeSetting.create!(shop_id: shop.id, theme_id: theme.id,
                           settings: { "brand_color" => "#e2e2e2",
                                       "platform_customizations" => { "custom_css" => "body { outline: 1px solid lime; }" } })
    end
    get "/admin/store/preview/#{theme.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<style data-shopify-custom-css-theme>body { outline: 1px solid lime; }</style>")
    expect(response.body).to include(%(content="#e2e2e2")) # 一般設定照舊生效

    # 值面不曝露：platform_customizations 不是 setting id（官方＝settings_data
    # 兄弟物件）——SettingsDrop 取不到
    ActsAsTenant.with_tenant(shop) do
      runtime = ThemeEngine::Runtime.new(
        theme: theme, shop: shop,
        source: ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0")))
      expect(runtime.global_assigns["settings"].liquid_method_missing("platform_customizations")).to be_nil
      expect(runtime.theme_custom_css_style).to include("outline: 1px solid lime")
    end

    # 編輯器 draft 路徑同通道
    post "/admin/store/preview/#{theme.id}/draft_page",
         params: { path: "/", sections: {},
                   settings: { platform_customizations: { custom_css: ".draft-x { color: red }" } } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response.body).to include(".draft-x { color: red }")
  end

  it "E2 🔴 templateJson key 逃逸 ⇒ null" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { templateJson(key: "../config/settings_schema") } }
    GQL
    expect(response.parsed_body.dig("data", "theme", "templateJson")).to be_nil
  end

  it "E3 🔴 預覽 ?editor=1 才注入橋與 data-shopify-editor-section；公開店面頁不帶" do
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("cl:highlight")
    expect(response.body).to include("data-shopify-editor-section")

    get "/admin/store/preview/#{theme.id}"
    expect(response.body).not_to include("cl:highlight")
    expect(response.body).not_to include("data-shopify-editor-section")

    get "/en-hk/" # 公開店面（design_mode 恆 false）
    expect(response.body).not_to include("cl:highlight")
  end

  it "BR3 🔴 hover 工具列（PR-28）：editor 橋含 cl:op 與四鈕；公開店面不帶" do
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response.body).to include("cl-preview-toolbar")
    expect(response.body).to include("cl:op")
    expect(response.body).to include(%(data-cl-op))

    get "/en-hk/"
    expect(response.body).not_to include("cl-preview-toolbar")
  end

  it "BR2 🔴 橋導航攔截（PR-23）：editor 預覽的橋含 cl:navigate 與 preventDefault" do
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response.body).to include("cl:navigate")
    expect(response.body).to include("preventDefault")

    get "/en-hk/" # 公開店面不帶橋（既有 E3 語義的延伸面）
    expect(response.body).not_to include("cl:navigate")
  end

  it "BR1 🔴 橋 block 級（PR-17）：editor 預覽的橋含 blockId 點選/高亮處理" do
    get "/admin/store/preview/#{theme.id}?editor=1"
    expect(response.body).to include("msg.blockId")            # 點選上報 block id
    expect(response.body).to include("d.blockId")              # 高亮縮到 block 元素
    expect(response.body).to include("data-shopify-editor-block")
  end

  # E2（D79）：模板選擇器資料。🔴 假綠殺手：
  #   E9 DB-only 替代模板必須出現在 templateKeys（殺：只讀來源 ⇒ 編輯器建的模板消失）；
  #      customers/ 不列（殺：regex 放行斜線）
  #   E10 assignments 依 template_suffix 分組、鍵 ""＝預設（殺：nil 鍵漏算 ⇒ 預設模板恆 0）
  it "E9 🔴 templateKeys＝來源 templates/*.json ∪ DB Template key；不含 customers/" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    ActsAsTenant.with_tenant(shop) do
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "product.custom",
                       template_type: "product", content: { "sections" => {}, "order" => [] })
    end
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { templateKeys } }
    GQL
    keys = response.parsed_body.dig("data", "theme", "templateKeys")
    expect(keys).to include("index", "product", "collection.alt", "product.custom")
    expect(keys.grep(%r{/})).to be_empty
    expect(keys).to eq(keys.sort)
  end

  it "E10 🔴 templateAssignments：依 template_suffix 分組，鍵 \"\"＝預設模板；無該欄的型全數計入預設" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    ActsAsTenant.with_tenant(shop) do
      Page.create!(shop_id: shop.id, title: "TA default", handle: "ta-default", body_html: "<p>x</p>")
      Page.create!(shop_id: shop.id, title: "TA custom", handle: "ta-custom", body_html: "<p>x</p>",
                   template_suffix: "custom")
      Page.create!(shop_id: shop.id, title: "TA custom 2", handle: "ta-custom-2", body_html: "<p>x</p>",
                   template_suffix: "custom")
      create(:product, shop:, status: "active", handle: "ta-product", title: "TA product")
    end
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { templateAssignments } }
    GQL
    assignments = response.parsed_body.dig("data", "theme", "templateAssignments")
    expect(assignments["page"]).to eq("" => 1, "custom" => 2)
    expect(assignments["product"]).to eq("" => 1) # products 尚無 template_suffix 欄 ⇒ 全計預設
    expect(assignments.keys).to contain_exactly("product", "collection", "page", "blog", "article")
  end

  # E3（D79 左樹）：群組中繼資料、section 可用性三鍵、theme blocks 全表。🔴 假綠殺手：
  #   E11 群組 label 取 JSON name、無 name 以檔名人性化；position 依 content_for_layout 前後
  #       （殺：footer 群組排到 Template 上方）
  #   E12 enabled_on／limit 透傳（殺：picker 無法依群組過濾、limit 灰化失效）
  #   E13 themeBlocks 的 blocks＝可接受子型別（殺：巢狀 add-block 白名單空 ⇒ 子 block 加不進去）
  it "E11 🔴 sectionGroups：label／type／position（layout 順序＋content_for_layout 前後）" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionGroups } }
    GQL
    groups = response.parsed_body.dig("data", "theme", "sectionGroups")
    by_name = groups.to_h { |g| [ g["name"], g ] }
    expect(groups.map { |g| g["name"] }).to eq(%w[test-group header-group footer-group]) # layout 掃描序
    expect(by_name["test-group"].slice("label", "type", "position"))
      .to eq("label" => "Test group", "type" => "header", "position" => "before") # JSON 自帶 name／type
    expect(by_name["header-group"].slice("label", "type", "position"))
      .to eq("label" => "Header group", "type" => "header", "position" => "before")
    expect(by_name["footer-group"].slice("label", "type", "position"))
      .to eq("label" => "Footer group", "type" => "footer", "position" => "after")
  end

  it "E12 🔴 sectionSchemas 透傳 enabled_on／disabled_on／limit" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionSchemas } }
    GQL
    schemas = response.parsed_body.dig("data", "theme", "sectionSchemas")
    expect(schemas.dig("sid-probe", "enabled_on")).to eq("groups" => [ "header" ])
    expect(schemas.dig("sid-probe", "limit")).to eq(1)
    expect(schemas.dig("hero", "enabled_on")).to be_nil
    expect(schemas.dig("hero", "limit")).to be_nil
  end

  it "E13 🔴 themeBlocks：type → {name, settings, blocks 可接受子型別}" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { themeBlocks } }
    GQL
    blocks = response.parsed_body.dig("data", "theme", "themeBlocks")
    expect(blocks.dig("_parent", "name")).to eq("Parent")
    expect(blocks.dig("_parent", "blocks")).to eq([ "_leaf" ])  # 巢狀白名單
    expect(blocks.dig("_leaf", "blocks")).to eq([])
    expect(blocks.dig("_leaf", "settings").map { |d| d["id"] }).to eq([ "label" ])
  end
  it "E14 🔴 nameTranslations：實例 name 的 t: 鍵 → 翻譯（來源檔＋DB 模板）；無翻譯的鍵不列" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    ActsAsTenant.with_tenant(shop) do
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "page.contact", template_type: "page",
                       content: { "sections" => { "promo" => { "type" => "hero", "name" => "t:names.promo", "settings" => {} } },
                                  "order" => [ "promo" ] })
    end
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { nameTranslations } }
    GQL
    translations = response.parsed_body.dig("data", "theme", "nameTranslations")
    expect(translations).to eq({ "t:names.promo" => "促銷條" }) # footer-group.json 的 section name ＋ DB 模板同鍵；
    # block 的 t:names.nope 無翻譯 ⇒ 不列（前端 fail-open 顯示原鍵）
  end
  it "E15 🔴 sectionSchemas 保留 visible_if／alpha／options[].group（E4 控件與條件顯示的資料源）" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionSchemas } }
    GQL
    settings = response.parsed_body.dig("data", "theme", "sectionSchemas", "hero", "settings")
    accent = settings.find { |d| d["id"] == "accent" }
    expect(accent.slice("alpha", "visible_if")).to eq({ "alpha" => true, "visible_if" => "{{ section.settings.heading != blank }}" })
    expect(settings.find { |d| d["id"] == "align" }.dig("options", 0, "group")).to eq("Basic")
  end

  it "E16 sectionSchemas.theme_settings：section liquid 內 `settings.<id>` 引用清單（右欄 Theme Settings 收合區資料源）" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { sectionSchemas } }
    GQL
    schemas = response.parsed_body.dig("data", "theme", "sectionSchemas")
    expect(schemas.dig("sid-probe", "theme_settings")).to eq([ "brand_color" ])
    expect(schemas.dig("hero", "theme_settings")).to eq([])
  end

  it "E17 fontLibrary：system／自 host／官方表列三段扁平化（key／name／system／handles）" do
    gid = "gid://chilllove/Theme/#{theme.id}"
    post_graphql(<<~GQL, variables: { id: gid })
      query($id: ID!) { theme(id: $id) { fontLibrary } }
    GQL
    fonts = response.parsed_body.dig("data", "theme", "fontLibrary")
    jost = fonts.find { |f| f["key"] == "jost" }
    expect(jost.slice("name", "system")).to eq({ "name" => "Jost", "system" => false })
    expect(jost["handles"]).to include("n4", "n7")
    expect(fonts.find { |f| f["key"] == "system_ui" }["system"]).to be(true)
    expect(fonts.find { |f| f["key"] == "assistant" }["handles"]).to include("n4")
  end
end
