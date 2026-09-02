# frozen_string_literal: true

require "rails_helper"

# `{% form %}` 與 `form` 物件的平台契約（D78 缺口 triage 已驗證項：FormDrop.password_needed／
# email／body／first_name／last_name；hoko 稽核候選：丟變數 `id:`、posted_successfully? 寫死 true）。
# 官方來源：shopify.dev/docs/api/liquid/tags/form ＋ objects/form（取證 2026-09-02）；
# 真店金標本：hoko.vip（Ella 7.2.0，2026-09-02）首頁／`/pages/contact` 的 `<form>` 逐字。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤；每格點名它要殺的反向實作）：
#   F1 customer_login ⇒ password_needed=true（殺：未宣告 ⇒ nil ⇒ Ella／Kalles 密碼欄整段消失）
#   F2 型別宣告的欄位不計 miss（殺：BaseDrop 對 nil 欄位計 miss 的假缺口回歸）
#   F3 變數 id ＋ action fragment 跟隨生效 id（殺：只吃引號字串的參數解析；靜態 action 表）
#   F4 純 GET posted_successfully?=false；customer_address 恆 true（殺：寫死 true）
#   F5 product 型：product_form_{id}／shopify-product-form／enctype／hidden product-id
#      （殺：資源隱藏欄漏發；預設 id 不帶資源 id）
#   F6 localization／currency／guest_login 型別專屬隱藏欄（殺：只發 form_type＋utf8）
#   F7 帶連字號的 key 與變數值參數；nil 參數不輸出（殺：`\w+` key 正則丟 data-*）
#   F8 真店逐字形（屬性序、自閉隱藏欄）（殺：任何順序／格式漂移）
RSpec.describe "ThemeEngine {% form %}（型別化）" do
  let(:themes) { Rails.root.join("test/fixtures/themes") }

  before { ThemeEngine::MISSES.clear }

  # 全部位置參數（assigns 是字串鍵 hash——放尾端會被 Ruby 3 當關鍵字參數吃掉）。
  def render(src, assigns = {}, registers = {})
    Liquid::Template.parse(src, environment: ThemeEngine::Runtime::ENVIRONMENT)
                    .render(assigns, registers: { request_path: "/pages/contact" }.merge(registers))
  end

  # 從真主題檔切出第一個指定型別的 {% form %}…{% endform %} 片段。
  def theme_form(path, type)
    src = File.read(themes.join(path))
    src[/\{%-?\s*form\s+'#{type}'.*?\{%-?\s*endform\s*-?%\}/m] or raise "no #{type} form in #{path}"
  end

  it "F1 🔴 customer_login：password_needed=true；Ella／Kalles 登入表單渲染出密碼欄" do
    out = render("{% form 'customer_login' %}[{{ form.password_needed }}]{% endform %}")
    expect(out).to include("[true]")
    expect(out).to include('<form method="post" action="/account/login" id="customer_login" accept-charset="UTF-8" data-login-with-shop-sign-in="true">')

    ella = render(theme_form("ella-7.2.0/sections/main-login.liquid", "customer_login"))
    expect(ella).to include('name="customer[password]"')
    kalles = render(theme_form("kalles-5.4.2/sections/main-login.liquid", "customer_login"))
    expect(kalles).to include('name="customer[password]"')
  end

  it "F2 型別宣告的欄位（email／first_name／last_name／body／author）不計 miss，未宣告者才計" do
    render(theme_form("ella-7.2.0/sections/main-login.liquid", "create_customer"))
    render(theme_form("minimog-6.0.0/sections/contact-form.liquid", "contact"))
    render("{% form 'new_comment', article %}{{ form.author }}{{ form.body }}{{ form.email }}{% endform %}")
    expect(ThemeEngine::MISSES.keys.grep(/\AFormDrop\./)).to eq([])

    render("{% form 'customer_login' %}{{ form.first_name }}{% endform %}")
    expect(ThemeEngine::MISSES.keys).to include("FormDrop.first_name")
  end

  it "F3 🔴 變數 id 生效且 contact／customer 的 action fragment 跟隨它（真店 hoko.vip 形）" do
    out = render(theme_form("ella-7.2.0/snippets/contact-form.liquid", "contact"), "form_id" => "ContactForm-x1")
    expect(out).to include('<form method="post" action="/contact#ContactForm-x1" id="ContactForm-x1" accept-charset="UTF-8" class="contact-form__form">')
    expect(out).to include('<input type="hidden" name="form_type" value="contact" />')

    signup = render("{% form 'customer', id: form_id, class: 'email-signup__form' %}x{% endform %}",
                    "form_id" => "EmailSignup-a")
    expect(signup).to include('action="/contact#EmailSignup-a" id="EmailSignup-a" accept-charset="UTF-8" class="email-signup__form">')

    # 無主題 id ⇒ 官方預設 id 與 fragment
    expect(render("{% form 'contact' %}x{% endform %}"))
      .to include('action="/contact#contact_form" id="contact_form" accept-charset="UTF-8" class="contact-form">')
    expect(render("{% form 'customer_login' %}{{ form.id }}{% endform %}")).to include(">\ncustomer_login</form>")
  end

  it "F4 posted_successfully?：純 GET 為 false（Ella 成功訊息不出）；customer_address 恆 true" do
    out = render(theme_form("ella-7.2.0/snippets/contact-form.liquid", "contact"), "form_id" => "c")
    expect(out).not_to include("post_success")
    expect(render("{% form 'contact' %}[{{ form.posted_successfully? }}]{% endform %}")).to include("[false]")
    expect(render("{% form 'customer_address', customer.new_address %}[{{ form.posted_successfully? }}]{% endform %}"))
      .to include("[true]")
    expect(render("{% form 'contact' %}[{{ form.errors | json }}]{% endform %}")).to include("[null]")
  end

  it "F5 🔴 product 型：id product_form_{id}、class、enctype、hidden product-id" do
    shop = create(:shop)
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:, handle: "form-tee", title: "Form Tee") }
    drop = ActsAsTenant.with_tenant(shop) { ThemeEngine::ProductDrop.new(product) }
    out = render("{% form 'product', product, id: 'ProductForm-1', class: 'form', novalidate: 'novalidate', " \
                 "data-type: 'add-to-cart-form' %}x{% endform %}", "product" => drop)
    expect(out).to include(%(<form method="post" action="/cart/add" id="ProductForm-1" accept-charset="UTF-8" class="form" enctype="multipart/form-data" novalidate="novalidate" data-type="add-to-cart-form">))
    expect(out).to include(%(<input type="hidden" name="product-id" value="#{product.id}" />))

    bare = render("{% form 'product', product %}x{% endform %}", "product" => drop)
    expect(bare).to include(%(id="product_form_#{product.id}" accept-charset="UTF-8" class="shopify-product-form" enctype="multipart/form-data">))
  end

  it "F6 localization／currency 帶 _method＋return_to（預設當前路徑）；guest_login 帶 guest=true" do
    loc = render("{% form 'localization' %}x{% endform %}", {}, { request_path: "/collections/all" })
    expect(loc).to include('<form method="post" action="/localization" id="localization_form" accept-charset="UTF-8" class="shopify-localization-form" enctype="multipart/form-data">')
    expect(loc).to include('<input type="hidden" name="_method" value="put" />')
    expect(loc).to include('<input type="hidden" name="return_to" value="/collections/all" />')

    cur = render("{% form 'currency', return_to: 'back' %}x{% endform %}")
    expect(cur).to include('action="/cart/update" id="currency_form" accept-charset="UTF-8" class="shopify-currency-form" enctype="multipart/form-data">')
    expect(cur).to include('<input type="hidden" name="return_to" value="back" />')

    guest = render("{% form 'guest_login' %}x{% endform %}")
    expect(guest).to include('id="customer_login_guest" accept-charset="UTF-8">')
    expect(guest).to include('<input type="hidden" name="guest" value="true" />')
  end

  it "F7 帶連字號的 key、變數值與 nil 參數" do
    out = render("{% form 'customer_login', novalidate: 'novalidate', id: form_id, style: form_styles, " \
                 "data-gift-card-recipient: 'true' %}x{% endform %}",
                 "form_id" => "Login-1", "form_styles" => "--x: 1")
    expect(out).to include(%(id="Login-1" accept-charset="UTF-8" data-login-with-shop-sign-in="true" novalidate="novalidate" style="--x: 1" data-gift-card-recipient="true">))

    nil_style = render("{% form 'customer_login', style: missing_var %}x{% endform %}")
    expect(nil_style).not_to include("style=")
  end

  it "F8 🔴 真店逐字形（hoko.vip 2026-09-02）：屬性序＋自閉隱藏欄各一行" do
    out = render("{% form 'customer_login', id: 'CustomerLoginForm', class: 'customer-drawer__form' %}x{% endform %}")
    expect(out).to start_with(
      %(<form method="post" action="/account/login" id="CustomerLoginForm" accept-charset="UTF-8" data-login-with-shop-sign-in="true" class="customer-drawer__form">\n) \
      "<input type=\"hidden\" name=\"form_type\" value=\"customer_login\" />\n" \
      "<input type=\"hidden\" name=\"utf8\" value=\"✓\" />\n"
    )
  end
end
