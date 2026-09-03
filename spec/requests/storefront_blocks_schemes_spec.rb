# frozen_string_literal: true

require "rails_helper"

# 步 13b：{% render <var> %} 變數形＋block.blocks 巢狀＋色階群組 drop 化＋
# 頁快取 BOOT_STAMP 維度。契約錨＝docs/research/97 §2/§3。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   B1 變數形 render（殺：parse fatal ⇒ 整 section 缺席——Ella _editorial_list 形）
#   B2 巢狀 children（殺：block.blocks 空轉 ⇒ 子層靜默消失）
#   C1 scheme 迭代＋C2 color_scheme 解引用（殺：裸 hash 進 Liquid 全 nil）
#   K1 部署後舊頁（殺：key 無代碼版本維——13a 生產實錘）
RSpec.describe "Storefront theme blocks and color schemes", type: :request do
  let(:shop) { create(:shop, subdomain: "g13-shop") }

  before do
    host! "g13-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  it "B1 🔴 {% render child_block %} 變數形不再 parse fatal；B2 巢狀子層渲染（Ella 消費形）" do
    get "/en-hk/"
    expect(response).to have_http_status(:ok)
    # 父 block 渲染＋設定；子層兩個 leaf 依 block_order 進括號內
    expect(response.body).to include('data-tone="warm"')
    # 子層依 block_order 序（fixture 檔尾換行 ⇒ 寬鬆空白匹配；E8：`{% render <block> %}` 輸出尾接 LF）；子塊各帶官方包裝
    # （`<div id="shopify-block-{id}" class="shopify-block">`——引擎缺口 PR-2）
    expect(response.body).to match(
      %r{\[<div id="shopify-block-A[A-Za-z0-9]{17}__c1" class="shopify-block"><b class="leaf">子一</b>\s*</div>\s*<div id="shopify-block-A[A-Za-z0-9]{17}__c2" class="shopify-block"><b class="leaf">子二</b>\s*</div>\s*\]}
    )
  end

  it "B3 🔴 section.blocks 迭代形＋{% render block %}：第二構造點（ordered_block_drops）的巢狀 children" do
    get "/en-hk/"
    # section.blocks → SectionDrop.blocks（ordered_block_drops 遞迴）→ render 變數形
    expect(response.body).to include('data-tone="iter"')
    expect(response.body).to match(
      %r{data-tone="iter">\[<div id="shopify-block-A[A-Za-z0-9]{17}__d1" class="shopify-block"><b class="leaf">迭代子</b>\s*</div>\s*\]}
    )
    # 🔴 drop 面直讀（不經 render 重建）：Ella 有「先數 slides 再渲染」形——
    # ordered_block_drops 的 children 必須自身正確，不能靠 render_block 重算兜底
    expect(response.body).to include('<span id="bic">1</span>')
  end

  it "C1 色階群組迭代 emit CSS 變數（official 範例形）" do
    get "/en-hk/"
    expect(response.body).to include(".color-scheme-1{--bg:#ffffff;--fg:#111111;}")
    expect(response.body).to include(".color-scheme-2{--bg:#101010;--fg:#fafafa;}")
  end

  it "C2 color_scheme 型 setting：直接輸出＝id、.settings.background 解引用（官方兩形）" do
    get "/en-hk/"
    expect(response.body).to include('<span id="pick">scheme-2</span>')
    expect(response.body).to include('<span id="pickbg">#101010</span>')
  end

  it "K1 🔴 BOOT_STAMP 進頁快取 key：代碼版本翻新 ⇒ 不吃舊 entry（13a 生產實錘形）" do
    memory = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory)
    allow(ThemeEngine::PageRenderer).to receive(:new).and_call_original

    2.times { get "/en-hk/" }
    expect(ThemeEngine::PageRenderer).to have_received(:new).once # 第二發吃快取

    stub_const("Storefront::PageCache::BOOT_STAMP", Storefront::PageCache::BOOT_STAMP + 1)
    get "/en-hk/"
    expect(ThemeEngine::PageRenderer).to have_received(:new).twice # 新 stamp ⇒ 重渲染
  end
end
