# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-10：storefront 密碼保護＋template layout 鍵＋current_page
# （chill.deals /password 標本對表軸）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   PW2 密碼閘（殺：閘失守＝private 店全裸）＋改密碼失效舊 cookie
#   PW4 layout 鍵三值（殺：password.json 被錯包進 theme.liquid＝整站
#       header/footer 出現在密碼頁——標本 diff critical）
#   PW5 current_page（殺：nil!=1 ⇒ 每頁 title 長「– Page 」尾巴）
RSpec.describe "Storefront password protection", type: :request do
  let(:shop) { create(:shop, subdomain: "pw-shop") }
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  before do
    allow(ThemeEngine::Sources).to receive(:base_resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    host! "pw-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def enable_password!(pw = "12345")
    shop.update!(storefront_password_digest: BCrypt::Password.create(pw))
  end

  it "PW1 未啟用＝全站開放；/password 頁本身可達（平台形：零 script、對表類名、noindex）" do
    get "/"
    expect(response).to have_http_status(:ok)

    get "/password"
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Robots-Tag"]).to include("noindex")
    body = response.body
    expect(body.scan("<script").size).to eq(0)                  # 標本：零 script
    expect(body).to include("This store is password protected. Use the password to enter the store.")
    expect(body).to include(%(<label for="password">Enter store password</label>))
    expect(body).to include(%(autocomplete="nope"))              # 標本逐字
    expect(body).to include(%(class="error-container"))
    expect(body).to include(%(<meta name="referrer" content="never">))
    expect(body).not_to include("shopify-section")               # 平台頁不走主題
  end

  it "PW2 🔴 啟用後全站 302 → /password；對密碼種簽名 cookie 後放行；改密碼失效舊 cookie" do
    enable_password!
    get "/"
    expect(response).to redirect_to("/password")

    post "/password", params: { password: "wrong" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("error-message")

    post "/password", params: { password: "12345" }
    expect(response).to redirect_to("/")
    get "/"
    expect(response).to have_http_status(:ok) # cookie 放行

    shop.update!(storefront_password_digest: BCrypt::Password.create("changed"))
    get "/"
    expect(response).to redirect_to("/password") # 🔴 舊 cookie 即失效
  end

  it "PW4 🔴 layout 鍵三值：字串→layout/{name}；false→無 layout；缺鍵→theme.liquid" do
    ActsAsTenant.with_tenant(shop) do
      ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id,
                               path: "layout/bare.liquid",
                               content: "<html><body data-bare>{{ content_for_layout }}</body></html>")
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index", template_type: "index",
                       content: { "layout" => "bare",
                                  "sections" => { "h" => { "type" => "hero", "settings" => { "heading" => "L 測" } } },
                                  "order" => [ "h" ] })
    end
    html = ActsAsTenant.with_tenant(shop) do
      ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!).render("/").html
    end
    expect(html).to include("data-bare")            # 指名 layout 生效
    expect(html).not_to include("data-shop=")       # theme.liquid 未被使用

    ActsAsTenant.with_tenant(shop) do
      Template.find_by!(theme_id: theme.id, key: "index").update!(
        content: { "layout" => false,
                   "sections" => { "h" => { "type" => "hero", "settings" => { "heading" => "無殼" } } },
                   "order" => [ "h" ] })
    end
    bare = ActsAsTenant.with_tenant(shop) do
      ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!).render("/").html
    end
    expect(bare).to include("無殼")
    expect(bare).not_to include("<html")            # false＝完全無 layout
  end

  it "PW5 🔴 current_page 全域＝1（非分頁）；帶 ?page= 反映頁碼" do
    ActsAsTenant.with_tenant(shop) do
      ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id,
                               path: "sections/cl-cp.liquid", content: <<~LIQUID)
                                 CP[{{ current_page }}]
                                 {% schema %}{ "name": "CP", "settings": [] }{% endschema %}
                               LIQUID
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index", template_type: "index",
                       content: { "sections" => { "c" => { "type" => "cl-cp", "settings" => {} } },
                                  "order" => [ "c" ] })
    end
    renderer = ->(params) do
      ActsAsTenant.with_tenant(shop) do
        ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!)
                                 .render("/", params:).html
      end
    end
    expect(renderer.call({})).to include("CP[1]")
    expect(renderer.call({ "page" => "3" })).to include("CP[3]")
  end
end
