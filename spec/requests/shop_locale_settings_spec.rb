# frozen_string_literal: true

require "rails_helper"

# ML-4：設定 › 語言（docs/specs/67 §A.2 語言集合是資料／§C.1 三條規則）。
# 🔴 新增語言**不建表、不 migration**——只往 shop_locales 插一列。
RSpec.describe "Admin GraphQL shop locale settings", type: :request do
  let(:shop) { create(:shop, subdomain: "locale-settings-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  let(:settings_query) { <<~GRAPHQL }
    query localeSettings {
      shopLocales(includeDisabled: true) { locale { tag endonym direction } isSource published enabled position }
      availableLocales { tag endonym direction }
    }
  GRAPHQL

  let(:enable_mutation) { <<~GRAPHQL }
    mutation shopLocaleEnable($locale: String!) {
      shopLocaleEnable(locale: $locale) {
        shopLocale { locale { tag endonym } published enabled position }
        userErrors { field message code }
      }
    }
  GRAPHQL

  let(:disable_mutation) { <<~GRAPHQL }
    mutation shopLocaleDisable($locale: String!) {
      shopLocaleDisable(locale: $locale) {
        retainedTranslations
        userErrors { field message code }
      }
    }
  GRAPHQL

  let(:update_mutation) { <<~GRAPHQL }
    mutation shopLocaleUpdate($locale: String!, $published: Boolean) {
      shopLocaleUpdate(locale: $locale, published: $published) {
        shopLocale { locale { tag } published }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "locale-settings-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  it "候選清單＝平台字典 − 已啟用；含 RTL 語言且帶 endonym" do
    login!
    post_graphql(settings_query)
    data = response.parsed_body["data"]

    enabled = data["shopLocales"].map { |row| row.dig("locale", "tag") }
    expect(enabled).to eq(%w[en zh-Hant zh-Hans ja fr])

    available = data["availableLocales"]
    expect(available.map { |row| row["tag"] }).to include("ko", "de", "ar")
    expect(available.map { |row| row["tag"] }).not_to include(*enabled)
    expect(available.find { |row| row["tag"] == "ko" }["endonym"]).to eq("한국어")
    expect(available.find { |row| row["tag"] == "ar" }["direction"]).to eq("rtl")
  end

  it "新增語言＝插一列（預設未發布），且立刻出現在編輯頁的語言清單" do
    login!
    post_graphql(enable_mutation, variables: { locale: "ko" })
    data = response.parsed_body.dig("data", "shopLocaleEnable")
    expect(data["userErrors"]).to eq([])
    expect(data.dig("shopLocale", "locale", "endonym")).to eq("한국어")
    expect(data.dig("shopLocale", "published")).to be(false)
    expect(data.dig("shopLocale", "enabled")).to be(true)

    # 編輯頁欄位由 shopLocales 驅動 ⇒ 新語言自動長出一格（零部署、零 migration）
    post_graphql("query { shopLocales { locale { tag } } }")
    expect(response.parsed_body.dig("data", "shopLocales").map { |row| row.dig("locale", "tag") }).to include("ko")
  end

  it "不在平台字典 ⇒ NOT_FOUND；重複啟用 ⇒ ALREADY_EXISTS；非法標籤 ⇒ INVALID" do
    login!
    post_graphql(enable_mutation, variables: { locale: "xx" })
    expect(response.parsed_body.dig("data", "shopLocaleEnable", "userErrors")).to contain_exactly(
      a_hash_including("code" => "NOT_FOUND")
    )

    post_graphql(enable_mutation, variables: { locale: "ja" })
    expect(response.parsed_body.dig("data", "shopLocaleEnable", "userErrors")).to contain_exactly(
      a_hash_including("code" => "ALREADY_EXISTS")
    )

    # 裸 zh 是禁用標籤（字體歧義，67 §A.4）
    post_graphql(enable_mutation, variables: { locale: "zh" })
    expect(response.parsed_body.dig("data", "shopLocaleEnable", "userErrors")).to contain_exactly(
      a_hash_including("code" => "INVALID")
    )
  end

  it "停用保留譯文並回報筆數；重新啟用後譯文原樣回來" do
    login!
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    ActsAsTenant.with_tenant(shop) do
      Translation.create!(
        shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
        locale_tag: "ja", field_key: "title", value: "ローズ",
        source_locale_tag: "en", source_digest: Translation.digest_for("Rose"), value_source: "human"
      )
    end

    post_graphql(disable_mutation, variables: { locale: "ja" })
    data = response.parsed_body.dig("data", "shopLocaleDisable")
    expect(data["userErrors"]).to eq([])
    expect(data["retainedTranslations"]).to eq(1)
    ActsAsTenant.with_tenant(shop) do
      expect(ShopLocale.find_by(locale_tag: "ja")).to have_attributes(enabled: false, published: false)
      expect(Translation.where(locale_tag: "ja").count).to eq(1)
    end

    post_graphql(enable_mutation, variables: { locale: "ja" })
    expect(response.parsed_body.dig("data", "shopLocaleEnable", "userErrors")).to eq([])
    ActsAsTenant.with_tenant(shop) do
      expect(ShopLocale.find_by(locale_tag: "ja").enabled).to be(true)
      expect(Translation.find_by(locale_tag: "ja").value).to eq("ローズ")
    end
  end

  it "來源語言不可停用、不可取消發布（SOURCE_LOCALE_IMMUTABLE）" do
    login!
    post_graphql(disable_mutation, variables: { locale: "en" })
    expect(response.parsed_body.dig("data", "shopLocaleDisable", "userErrors")).to contain_exactly(
      a_hash_including("code" => "SOURCE_LOCALE_IMMUTABLE")
    )

    post_graphql(update_mutation, variables: { locale: "en", published: false })
    expect(response.parsed_body.dig("data", "shopLocaleUpdate", "userErrors")).to contain_exactly(
      a_hash_including("code" => "SOURCE_LOCALE_IMMUTABLE")
    )
    ActsAsTenant.with_tenant(shop) { expect(ShopLocale.source!.locale_tag).to eq("en") }
  end

  it "發布／取消發布非來源語言" do
    login!
    post_graphql(update_mutation, variables: { locale: "ja", published: true })
    expect(response.parsed_body.dig("data", "shopLocaleUpdate", "shopLocale", "published")).to be(true)

    post_graphql(update_mutation, variables: { locale: "ja", published: false })
    expect(response.parsed_body.dig("data", "shopLocaleUpdate", "shopLocale", "published")).to be(false)
  end

  it "超過 i18n.max_shop_locales ⇒ LOCALE_LIMIT_EXCEEDED" do
    login!
    allow(Limits).to receive(:fetch).and_call_original
    allow(Limits).to receive(:fetch).with(:i18n, :max_shop_locales).and_return(5)

    post_graphql(enable_mutation, variables: { locale: "de" })
    expect(response.parsed_body.dig("data", "shopLocaleEnable", "userErrors")).to contain_exactly(
      a_hash_including("code" => "LOCALE_LIMIT_EXCEEDED")
    )
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
