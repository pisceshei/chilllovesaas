# frozen_string_literal: true

require "rails_helper"

# 步 14c：前台 blog 線（/blogs 路由三型＋blogs 全域＋tagged＋留言 POST 政策分流
# ＋linklist 型別擴充＋搜尋 article 型）。契約錨＝docs/research/98 §1/§2。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   BA2 Hidden 文章 404（殺：visible 閘漏 ⇒ 未發布文章公開可讀）
#   CM1-3 政策分流（殺：closed 也收留言／moderated 直接 published）
#   TG1 tagged 過濾＋`+` 多 tag AND（殺：忽略 tag ⇒ 全量照出）
RSpec.describe "Storefront blog line", type: :request do
  let(:shop) { create(:shop, subdomain: "blog-shop") }

  before do
    host! "blog-shop.lvh.me"
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

  let!(:blog) do
    ActsAsTenant.with_tenant(shop) do
      Blog.create!(shop_id: shop.id, title: "News", handle: "news", comment_policy: "moderated")
    end
  end
  let!(:article_a) do
    ActsAsTenant.with_tenant(shop) do
      Article.create!(shop_id: shop.id, blog:, title: "早文", handle: "early", body_html: "<p>早</p>",
                      author_name: "KEN", tags: [ "hot", "news" ],
                      published_at: Time.zone.parse("2026-08-01 00:00"))
    end
  end
  let!(:article_b) do
    ActsAsTenant.with_tenant(shop) do
      Article.create!(shop_id: shop.id, blog:, title: "晚文", handle: "late", body_html: "<p>晚</p>",
                      excerpt_html: "摘要", tags: [ "hot" ],
                      published_at: Time.zone.parse("2026-08-15 00:00"))
    end
  end
  let!(:hidden_article) do
    ActsAsTenant.with_tenant(shop) do
      Article.create!(shop_id: shop.id, blog:, title: "隱文", handle: "ghost", body_html: "x",
                      published_at: nil)
    end
  end

  it "BA1 /blogs/news：新到舊、隱藏文章不列、tags 聯集、真分頁；文章頁複合 URL＋留言表單" do
    get "/blogs/news"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<h1 id="btitle">News</h1>')
    expect(response.body).to include('<span id="bcount">2</span>') # 官方：不含 hidden
    expect(response.body).to include('<span id="btags">hot,news</span>')
    expect(response.body.index('data-h="news/late"')).to be < response.body.index('data-h="news/early"')
    expect(response.body).not_to include("隱文")
    expect(response.body).to include("摘要") # excerpt_or_content：有摘要用摘要
    expect(response.body).to include("|<p>早</p>") # 無摘要退 content

    get "/blogs/news/early"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<h1 id="atitle">早文</h1>')
    expect(response.body).to include('<span id="aauthor">KEN</span>')
    expect(response.body).to include('<span id="amod">true</span>')
    # form new_comment：action＝comment_post_url（98 §2 真店抓包形）
    expect(response.body).to include('action="/blogs/news/early/comments"')
    expect(response.body).to include('name="form_type" value="new_comment"')
  end

  it "BA2 🔴 隱藏文章 404；未知 blog 404" do
    get "/blogs/news/ghost"
    expect(response).to have_http_status(:not_found)
    get "/blogs/nope"
    expect(response).to have_http_status(:not_found)
  end

  it "TG1 🔴 tagged 過濾＋`+` 多 tag AND；current_tags 注入" do
    get "/blogs/news/tagged/news"
    expect(response.body).to include('<span id="bcur">news</span>')
    expect(response.body).to include('data-h="news/early"')
    expect(response.body).not_to include('data-h="news/late"') # late 無 news tag

    get "/blogs/news/tagged/hot+news"
    expect(response.body).to include('data-h="news/early"') # 兩 tag 都有
    expect(response.body).not_to include('data-h="news/late"')
  end

  it "CM1 🔴 moderated：留言落 pending、頁面不出現；CM2 auto_published 直接可見" do
    post "/blogs/news/early/comments",
         params: { comment: { author: "訪客", email: "v@example.com", body: "審核中留言" } }
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/blogs/news/early#comment_form")
    row = ActsAsTenant.with_tenant(shop) { ArticleComment.last }
    expect(row.status).to eq("pending")

    get "/blogs/news/early"
    expect(response.body).not_to include("審核中留言") # Liquid 只見 published
    expect(response.body).to include("0 則留言")

    ActsAsTenant.with_tenant(shop) { blog.update!(comment_policy: "auto_published") }
    post "/blogs/news/early/comments",
         params: { comment: { author: "訪客二", email: "v2@example.com", body: "直發留言" } }
    expect(ActsAsTenant.with_tenant(shop) { ArticleComment.last }.status).to eq("published")

    get "/blogs/news/early?page=1" # 換 key 避開頁快取
    expect(response.body).to include("訪客二:直發留言")
    expect(response.body).to include("1 則留言")
  end

  it "CM3 🔴 closed：POST 404 不落列" do
    ActsAsTenant.with_tenant(shop) { blog.update!(comment_policy: "closed") }
    post "/blogs/news/early/comments",
         params: { comment: { author: "x", email: "x@example.com", body: "不該進" } }
    expect(response).to have_http_status(:not_found)
    expect(ActsAsTenant.with_tenant(shop) { ArticleComment.count }).to eq(0)
  end

  it "LN1 linklist 型別擴充：blog/article/frontpage/search 的 URL 與官方 *_link 型" do
    menu = ActsAsTenant.with_tenant(shop) do
      Content::SaveMenu.call(shop:, menu: nil, title: "M", handle: "probe-menu", items: [
        { title: "首頁", type: "frontpage" },
        { title: "找", type: "search" },
        { title: "誌", type: "blog", resource_id: "gid://chilllove/Blog/#{blog.id}" },
        { title: "文", type: "article", resource_id: "gid://chilllove/Article/#{article_a.id}" }
      ]).menu
    end
    drop = ThemeEngine::LinkListsDrop.new(shop, url_prefix: "/zh-hant") # D80：非預設語言的裸語言前綴
    links = ActsAsTenant.with_tenant(shop) do
      drop.liquid_method_missing("probe-menu").links.map { |l| [ l.type, l.url ] }
    end
    expect(links).to eq([
      [ "frontpage_link", "/zh-hant" ],
      [ "search_link", "/zh-hant/search" ],
      [ "blog_link", "/zh-hant/blogs/news" ],
      [ "article_link", "/zh-hant/blogs/news/early" ]
    ])
    expect(ActsAsTenant.with_tenant(shop) { menu.menu_items.count }).to eq(4)
  end

  it "SR1 搜尋 article 型：整頁混型＋suggest articles 鍵" do
    get "/search?q=#{CGI.escape('早')}&type=article"
    expect(response.body).to include('data-ot="article"')
    expect(response.body).to include('data-h="news/early"')

    get "/search/suggest.json", params: { q: "早", resources: { type: "article" } }
    results = response.parsed_body.dig("resources", "results")
    expect(results.keys).to eq([ "articles" ])
    expect(results["articles"].first["url"]).to include("/blogs/news/early")
  end
end
