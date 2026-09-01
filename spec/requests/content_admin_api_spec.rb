# frozen_string_literal: true

require "rails_helper"

# 步 14a：內容線 Admin API（pages/blogs/articles/menus CRUD；98 §3 官方契約對位）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   P2 可見性語義（殺：isPublished=false 仍發布）
#   A2 handle 唯一域＝(shop, blog)（殺：全域唯一 ⇒ 兩 blog 同名文章互撞）
#   M2 menuUpdate 整棵替換（殺：合併語義 ⇒ 刪不掉舊項）
#   M3 預設選單防護（殺：main-menu 被刪 ⇒ 前台導覽整條消失）
RSpec.describe "Content admin API", type: :request do
  let(:shop) { create(:shop, subdomain: "content-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "content-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
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

  describe "pages" do
    it "P1 pageCreate：預設即發布（官方 default true）＋handle 自動生成；pages 列表可見" do
      post_graphql(<<~GQL, variables: { title: "About Us" })
        mutation($title: String!) {
          pageCreate(title: $title, body: "<p>hi</p>") {
            page { id title handle isPublished publishedAt bodySummary }
            userErrors { field message code }
          }
        }
      GQL
      data = response.parsed_body.dig("data", "pageCreate")
      expect(data["userErrors"]).to eq([])
      expect(data.dig("page", "handle")).to eq("about-us")
      expect(data.dig("page", "isPublished")).to be(true)
      expect(data.dig("page", "bodySummary")).to eq("hi")
    end

    it "P2 🔴 isPublished:false ⇒ Hidden（publishedAt null）；update 可改發布態＋redirectNewHandle 建 301" do
      post_graphql(<<~GQL, variables: {})
        mutation {
          pageCreate(title: "Hidden Page", isPublished: false) {
            page { id isPublished publishedAt }
            userErrors { message }
          }
        }
      GQL
      created = response.parsed_body.dig("data", "pageCreate", "page")
      expect(created["isPublished"]).to be(false)
      expect(created["publishedAt"]).to be_nil

      post_graphql(<<~GQL, variables: { id: created["id"] })
        mutation($id: ID!) {
          pageUpdate(id: $id, isPublished: true, handle: "renamed-page", redirectNewHandle: true) {
            page { isPublished handle }
            userErrors { message }
          }
        }
      GQL
      updated = response.parsed_body.dig("data", "pageUpdate", "page")
      expect(updated["isPublished"]).to be(true)
      expect(updated["handle"]).to eq("renamed-page")

      # 反向：published → Hidden（isPublished:false 必須真的藏起來）
      post_graphql(<<~GQL, variables: { id: created["id"] })
        mutation($id: ID!) {
          pageUpdate(id: $id, isPublished: false) {
            page { isPublished publishedAt } userErrors { message }
          }
        }
      GQL
      hidden = response.parsed_body.dig("data", "pageUpdate", "page")
      expect(hidden["isPublished"]).to be(false)
      expect(hidden["publishedAt"]).to be_nil
      redirect = ActsAsTenant.with_tenant(shop) { UrlRedirect.find_by(from_path: "/pages/hidden-page") }
      expect(redirect&.to_path).to eq("/pages/renamed-page")
      expect(redirect&.source).to eq("handle_change")
    end

    it "P3 pageDelete 永久刪＋NOT_FOUND 形" do
      page = ActsAsTenant.with_tenant(shop) do
        Page.create!(shop_id: shop.id, title: "T", handle: "t", body_html: "")
      end
      post_graphql(<<~GQL, variables: { id: "gid://chilllove/Page/#{page.id}" })
        mutation($id: ID!) { pageDelete(id: $id) { deletedPageId userErrors { code } } }
      GQL
      expect(response.parsed_body.dig("data", "pageDelete", "deletedPageId")).to be_present
      expect(ActsAsTenant.with_tenant(shop) { Page.exists?(page.id) }).to be(false)

      post_graphql(<<~GQL, variables: { id: "gid://chilllove/Page/#{page.id}" })
        mutation($id: ID!) { pageDelete(id: $id) { deletedPageId userErrors { code } } }
      GQL
      expect(response.parsed_body.dig("data", "pageDelete", "userErrors", 0, "code")).to eq("NOT_FOUND")
    end
  end

  describe "blogs 與 articles" do
    it "B1 blogCreate 預設 CLOSED（admin Disabled 實測形）；commentPolicy 可更新" do
      post_graphql(<<~GQL, variables: {})
        mutation { blogCreate(title: "News") { blog { id handle commentPolicy } userErrors { message } } }
      GQL
      blog = response.parsed_body.dig("data", "blogCreate", "blog")
      expect(blog["commentPolicy"]).to eq("CLOSED")
      expect(blog["handle"]).to eq("news")

      post_graphql(<<~GQL, variables: { id: blog["id"] })
        mutation($id: ID!) {
          blogUpdate(id: $id, commentPolicy: MODERATED) { blog { commentPolicy } userErrors { message } }
        }
      GQL
      expect(response.parsed_body.dig("data", "blogUpdate", "blog", "commentPolicy")).to eq("MODERATED")
    end

    it "A1 articleCreate（blogId!/title!/body!）＋articles(blogId:) 過濾＋blogDelete 連文章刪" do
      blog_a, blog_b = ActsAsTenant.with_tenant(shop) do
        [ Blog.create!(shop_id: shop.id, title: "A", handle: "a"),
          Blog.create!(shop_id: shop.id, title: "B", handle: "b") ]
      end
      post_graphql(<<~GQL, variables: { blogId: "gid://chilllove/Blog/#{blog_a.id}" })
        mutation($blogId: ID!) {
          articleCreate(blogId: $blogId, title: "First Post", body: "<p>hello</p>",
                        authorName: "KEN LEE", tags: ["news", "hot"]) {
            article { id handle authorName tags isPublished }
            userErrors { message }
          }
        }
      GQL
      article = response.parsed_body.dig("data", "articleCreate", "article")
      expect(article["handle"]).to eq("first-post")
      expect(article["tags"]).to eq([ "news", "hot" ])
      expect(article["isPublished"]).to be(true)

      post_graphql(<<~GQL, variables: { blogId: "gid://chilllove/Blog/#{blog_b.id}" })
        query($blogId: ID) { articles(first: 10, blogId: $blogId) { nodes { id } } }
      GQL
      expect(response.parsed_body.dig("data", "articles", "nodes")).to eq([])

      post_graphql(<<~GQL, variables: { id: "gid://chilllove/Blog/#{blog_a.id}" })
        mutation($id: ID!) { blogDelete(id: $id) { deletedBlogId userErrors { message } } }
      GQL
      expect(response.parsed_body.dig("data", "blogDelete", "deletedBlogId")).to be_present
      expect(ActsAsTenant.with_tenant(shop) { Article.count }).to eq(0)
    end

    it "A2 🔴 handle 唯一域＝(shop, blog)：兩個 blog 可同名文章、同 blog 自動 -1 尾碼" do
      blog_a, blog_b = ActsAsTenant.with_tenant(shop) do
        [ Blog.create!(shop_id: shop.id, title: "A", handle: "a"),
          Blog.create!(shop_id: shop.id, title: "B", handle: "b") ]
      end
      create_article = lambda do |blog_gid|
        post_graphql(<<~GQL, variables: { blogId: blog_gid })
          mutation($blogId: ID!) {
            articleCreate(blogId: $blogId, title: "Same Title", body: "x") {
              article { handle } userErrors { message }
            }
          }
        GQL
        response.parsed_body.dig("data", "articleCreate", "article", "handle")
      end
      expect(create_article.call("gid://chilllove/Blog/#{blog_a.id}")).to eq("same-title")
      expect(create_article.call("gid://chilllove/Blog/#{blog_b.id}")).to eq("same-title")
      expect(create_article.call("gid://chilllove/Blog/#{blog_a.id}")).to eq("same-title-1")
    end
  end

  describe "menus" do
    it "M1 menuCreate 巢狀樹＋型別驗證（http 缺 url ⇒ BLANK；4 層 ⇒ NESTING_TOO_DEEP）" do
      post_graphql(<<~GQL, variables: {})
        mutation {
          menuCreate(title: "側欄", handle: "sidebar", items: [
            { title: "首頁", type: FRONTPAGE },
            { title: "外連", type: HTTP, url: "https://example.com",
              items: [ { title: "搜尋", type: SEARCH } ] }
          ]) {
            menu { handle isDefault items { title type url items { title type } } }
            userErrors { message code }
          }
        }
      GQL
      menu = response.parsed_body.dig("data", "menuCreate", "menu")
      expect(menu["isDefault"]).to be(false)
      expect(menu["items"].map { |i| i["type"] }).to eq(%w[FRONTPAGE HTTP])
      expect(menu["items"][1]["items"][0]["type"]).to eq("SEARCH")

      post_graphql(<<~GQL, variables: {})
        mutation {
          menuCreate(title: "壞", handle: "bad", items: [ { title: "沒網址", type: HTTP } ]) {
            menu { id } userErrors { code }
          }
        }
      GQL
      expect(response.parsed_body.dig("data", "menuCreate", "userErrors", 0, "code")).to eq("BLANK")

      post_graphql(<<~GQL, variables: {})
        mutation {
          menuCreate(title: "深", handle: "deep", items: [
            { title: "1", type: FRONTPAGE, items: [
              { title: "2", type: FRONTPAGE, items: [
                { title: "3", type: FRONTPAGE, items: [ { title: "4", type: FRONTPAGE } ] }
              ] }
            ] }
          ]) { menu { id } userErrors { code } }
        }
      GQL
      expect(response.parsed_body.dig("data", "menuCreate", "userErrors", 0, "code")).to eq("NESTING_TOO_DEEP")
    end

    it "M2 🔴 menuUpdate＝整棵替換（官方語義）：未列入的舊項被移除" do
      menu = ActsAsTenant.with_tenant(shop) do
        result = Content::SaveMenu.call(shop:, menu: nil, title: "M", handle: "m",
                                        items: [ { title: "舊項", type: "frontpage" },
                                                 { title: "留下", type: "search" } ])
        result.menu
      end
      post_graphql(<<~GQL, variables: { id: "gid://chilllove/Menu/#{menu.id}" })
        mutation($id: ID!) {
          menuUpdate(id: $id, items: [ { title: "留下", type: SEARCH } ]) {
            menu { items { title } } userErrors { message }
          }
        }
      GQL
      titles = response.parsed_body.dig("data", "menuUpdate", "menu", "items").map { |i| i["title"] }
      expect(titles).to eq([ "留下" ])
      expect(ActsAsTenant.with_tenant(shop) { MenuItem.where(menu_id: menu.id).count }).to eq(1)
    end

    it "M3 🔴 預設選單不可刪、handle 不可改（DEFAULT_MENU_PROTECTED）" do
      menu = ActsAsTenant.with_tenant(shop) do
        Menu.create!(shop_id: shop.id, title: "Main menu", handle: "main-menu")
      end
      post_graphql(<<~GQL, variables: { id: "gid://chilllove/Menu/#{menu.id}" })
        mutation($id: ID!) { menuDelete(id: $id) { deletedMenuId userErrors { code } } }
      GQL
      expect(response.parsed_body.dig("data", "menuDelete", "userErrors", 0, "code"))
        .to eq("DEFAULT_MENU_PROTECTED")

      post_graphql(<<~GQL, variables: { id: "gid://chilllove/Menu/#{menu.id}" })
        mutation($id: ID!) {
          menuUpdate(id: $id, handle: "renamed", items: []) { menu { id } userErrors { code } }
        }
      GQL
      expect(response.parsed_body.dig("data", "menuUpdate", "userErrors", 0, "code"))
        .to eq("DEFAULT_MENU_PROTECTED")
    end
  end
end
