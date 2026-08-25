# frozen_string_literal: true

require "rails_helper"

# ML-2：商品內容翻譯（標題／說明／SEO 三組，五語）。
# 規格：67 §C.2（逐欄位一列）／§C.4(b)（空值定義）／§C.5（過期偵測）／§C.6（進度物化）。
RSpec.describe "Admin GraphQL product translations", type: :request do
  let(:shop) { create(:shop, subdomain: "i18n-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  let(:mutation) { <<~GRAPHQL }
    mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
      productSet(input: $input, idempotencyKey: $idempotencyKey) {
        product {
          id lockVersion title
          translations { locale field value outdated outdatedSeverity valueSource reviewRequired }
          translationStatus { locale requiredFields translatedFields outdatedCount complete }
        }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "i18n-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def base_input(overrides = {})
    { title: "Rose Tonnerre EDP", descriptionHtml: "<p>Rose and spice</p>", variants: [ { price: "128.00" } ] }.merge(overrides)
  end

  def create_with(translations, extra = {})
    post_graphql(mutation, variables: {
      idempotencyKey: SecureRandom.uuid,
      input: base_input(extra.merge(translations: translations))
    })
    response.parsed_body.dig("data", "productSet")
  end

  it "建立時一次寫入四語譯文（建立態即可填多語——裁定 C1）" do
    login!
    data = create_with([
      { locale: "zh-Hant", field: "title", value: "玫瑰雷鳴淡香精" },
      { locale: "zh-Hant", field: "body_html", value: "<p>玫瑰與辛香</p>" },
      { locale: "ja", field: "title", value: "ローズトネール" },
      { locale: "fr", field: "title", value: "Rose Tonnerre EDP" }
    ], seo: { title: "Rose Tonnerre", description: "Niche fragrance" })

    expect(data["userErrors"]).to eq([])
    translations = data.dig("product", "translations")
    expect(translations.map { |row| [ row["locale"], row["field"] ] }).to contain_exactly(
      [ "zh-Hant", "title" ], [ "zh-Hant", "body_html" ], [ "ja", "title" ], [ "fr", "title" ]
    )
    expect(translations).to all(include("valueSource" => "human", "reviewRequired" => false, "outdated" => false))

    status = data.dig("product", "translationStatus").index_by { |row| row["locale"] }
    expect(status["zh-Hant"]).to include("requiredFields" => 2, "translatedFields" => 2, "complete" => true)
    expect(status["ja"]).to include("translatedFields" => 1, "complete" => false)
    expect(status["zh-Hans"]).to include("translatedFields" => 0, "complete" => false)
  end

  it "來源語言（en）不得經 translations 寫（內容在 base row）" do
    login!
    data = create_with([ { locale: "en", field: "title", value: "Anything" } ])
    expect(data["userErrors"]).to contain_exactly(
      a_hash_including("field" => [ "translations", "en", "title" ], "code" => "INVALID")
    )
    ActsAsTenant.with_tenant(shop) { expect(Product.count).to eq(0) } # 整棵樹回滾
  end

  it "未啟用語言 ⇒ LOCALE_NOT_ENABLED；不可翻欄位 ⇒ INVALID" do
    login!
    data = create_with([ { locale: "ko", field: "title", value: "장미" } ])
    expect(data["userErrors"]).to contain_exactly(a_hash_including("code" => "LOCALE_NOT_ENABLED"))

    data = create_with([ { locale: "ja", field: "handle", value: "rose" } ])
    expect(data["userErrors"]).to contain_exactly(
      a_hash_including("field" => [ "translations", "ja", "handle" ], "code" => "INVALID")
    )
  end

  it "空字串／語義空 HTML＝刪除譯文列（回落來源語言），不是存空白" do
    login!
    created = create_with([
      { locale: "ja", field: "title", value: "ローズ" },
      { locale: "fr", field: "body_html", value: "<p>Rose et épices</p>" }
    ])
    product = created["product"]

    post_graphql(mutation, variables: { input: base_input(
      id: product["id"], lockVersion: product["lockVersion"],
      translations: [ { locale: "ja", field: "title", value: "" },
                      { locale: "fr", field: "body_html", value: "<p><br></p>" } ]
    ) })
    data = response.parsed_body.dig("data", "productSet")
    expect(data["userErrors"]).to eq([])
    expect(data.dig("product", "translations")).to eq([])
  end

  # 🔴 **2026-08-25 第 7 包修正的行為**（原本這一格是用 `title` 送 `<p><br></p>` 並期待被刪）。
  #   67 §C.4(b) 的原文把 HTML 那一條明文限定在**富文本欄位**：
  #   「NULL、空字串、只含空白字元的字串三者等價視為「無譯文」。🔴 富文本欄位**另加一條**：
  #    `<p></p>`／`<p><br></p>` 這類語義空的 HTML 也算空」
  #   舊實作的 `blank_value?` 不看欄位型別，於是把富文本的規則套到純文字欄上。
  #   ⇒ 商家在**標題**欄真的打了 `<p><br></p>`（那是他打的字，標題欄不是 RTE），
  #     會被靜默刪成「未翻譯」。判準改成 kind-aware 之後這一格必須反過來斷言。
  it "🔴 純文字欄的語義空 HTML **不**判空（§C.4(b) 的 HTML 規則只適用富文本欄）" do
    login!
    created = create_with([ { locale: "ja", field: "title", value: "<p><br></p>" } ])

    expect(created["userErrors"]).to eq([])
    expect(created.dig("product", "translations"))
      .to contain_exactly(a_hash_including("field" => "title", "locale" => "ja", "value" => "<p><br></p>"))
  end

  it "改來源文字 ⇒ 該欄位所有語言標 outdated（不影響譯文內容）" do
    login!
    created = create_with([
      { locale: "zh-Hant", field: "title", value: "玫瑰雷鳴" },
      { locale: "ja", field: "title", value: "ローズトネール" }
    ])
    product = created["product"]

    post_graphql(mutation, variables: { input: base_input(
      id: product["id"], lockVersion: product["lockVersion"], title: "Rose Tonnerre EDP 100ml"
    ) })
    data = response.parsed_body.dig("data", "productSet")
    expect(data["userErrors"]).to eq([])

    rows = data.dig("product", "translations")
    expect(rows.map { |row| row["outdated"] }).to all(be(true))
    expect(rows.map { |row| row["value"] }).to contain_exactly("玫瑰雷鳴", "ローズトネール")
    status = data.dig("product", "translationStatus").index_by { |row| row["locale"] }
    expect(status["zh-Hant"]).to include("outdatedCount" => 1, "complete" => false)
  end

  # 🔴 線上實測抓到的缺口（admin SPA 恆送全樹）：改來源文字的那一次儲存**同時**送了
  #    未變更的既有譯文；早期實作無條件重寫 digest ⇒ 過期偵測永遠不觸發。
  it "改來源文字＋恆送未變更譯文 ⇒ 仍標 outdated（digest 只在譯文真的被改寫時推進）" do
    login!
    created = create_with([
      { locale: "zh-Hant", field: "title", value: "玫瑰雷鳴" },
      { locale: "ja", field: "title", value: "ローズトネール" }
    ])
    product = created["product"]

    # 前端形態：改英文標題，同時把兩條既有譯文原值一起送回。
    post_graphql(mutation, variables: { input: base_input(
      id: product["id"], lockVersion: product["lockVersion"], title: "Rose Tonnerre EDP 100ml",
      translations: [
        { locale: "zh-Hant", field: "title", value: "玫瑰雷鳴" },
        { locale: "ja", field: "title", value: "ローズトネール" }
      ]
    ) })
    data = response.parsed_body.dig("data", "productSet")
    expect(data["userErrors"]).to eq([])
    expect(data.dig("product", "translations").map { |row| row["outdated"] }).to all(be(true))
    status = data.dig("product", "translationStatus").index_by { |row| row["locale"] }
    expect(status["ja"]).to include("outdatedCount" => 1)
  end

  it "譯文被改寫 ⇒ digest 推進到新來源文字，不再標過期" do
    login!
    created = create_with([ { locale: "ja", field: "title", value: "ローズトネール" } ])
    product = created["product"]

    # 第一次：改來源文字（譯文原值送回）⇒ 過期
    post_graphql(mutation, variables: { input: base_input(
      id: product["id"], lockVersion: product["lockVersion"], title: "Rose Tonnerre EDP 100ml",
      translations: [ { locale: "ja", field: "title", value: "ローズトネール" } ]
    ) })
    intermediate = response.parsed_body.dig("data", "productSet", "product")
    expect(intermediate["translations"].first["outdated"]).to be(true)

    # 第二次：商家更新譯文本身 ⇒ digest 推進、旗標清掉
    post_graphql(mutation, variables: { input: base_input(
      id: product["id"], lockVersion: intermediate["lockVersion"], title: "Rose Tonnerre EDP 100ml",
      translations: [ { locale: "ja", field: "title", value: "ローズトネール 100ml" } ]
    ) })
    data = response.parsed_body.dig("data", "productSet")
    expect(data["userErrors"]).to eq([])
    row = data.dig("product", "translations").first
    expect(row).to include("outdated" => false, "value" => "ローズトネール 100ml")
  end

  it "缺席 translations ⇒ 完全不動既有譯文（宣告式的「缺席＝保持現值」）" do
    login!
    created = create_with([ { locale: "ja", field: "title", value: "ローズ" } ])
    product = created["product"]

    post_graphql(mutation, variables: { input: base_input(id: product["id"], lockVersion: product["lockVersion"]) })
    data = response.parsed_body.dig("data", "productSet")
    expect(data["userErrors"]).to eq([])
    expect(data.dig("product", "translations").map { |row| row["value"] }).to eq([ "ローズ" ])
  end

  it "譯文超過欄位上限 ⇒ TOO_LONG，整棵樹回滾" do
    login!
    data = create_with([ { locale: "ja", field: "title", value: "あ" * (Limits.fetch(:product, :title_max_chars) + 1) } ])
    expect(data["userErrors"]).to contain_exactly(a_hash_including("code" => "TOO_LONG"))
    ActsAsTenant.with_tenant(shop) { expect(Product.count).to eq(0) }
  end

  it "租戶隔離：別店查不到本店譯文" do
    login!
    create_with([ { locale: "ja", field: "title", value: "ローズ" } ])
    other = create(:shop, subdomain: "other-i18n-shop")
    ActsAsTenant.with_tenant(other) { expect(Translation.count).to eq(0) }
  end

  it "shopLocales：來源語言排第一、其餘照 position；停用語言不列出" do
    login!
    ActsAsTenant.with_tenant(shop) { ShopLocale.find_by!(locale_tag: "fr").update!(enabled: false) }

    post_graphql("query { shopLocales { locale { tag endonym direction } isSource published position } }")
    rows = response.parsed_body.dig("data", "shopLocales")
    expect(rows.first).to include("isSource" => true, "published" => true)
    expect(rows.first.dig("locale", "tag")).to eq("en")
    expect(rows.map { |row| row.dig("locale", "tag") }).to eq(%w[en zh-Hant zh-Hans ja])
    expect(rows.first.dig("locale", "endonym")).to eq("English")
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
