# frozen_string_literal: true

module Storefront
  # 文章留言 POST（步 14c；98 §2 真店抓包形：POST /blogs/{blog}/{article}/comments、
  # form_type=new_comment、comment[author]/[email]/[body]）。
  #
  # ①政策分流（98 §3 官方 CommentPolicy）：closed ⇒ 404（表單本不該出現）；
  #   moderated ⇒ pending（storefront 不可見——Liquid 只見 published）；
  #   auto_published ⇒ published。
  # ②回應＝302 回文章頁 `#comment_form` 錨（真店 action 自帶錨；成功/失敗態的
  #   form drop 狀態機 ⚪ 91 §3.65——回應三層本尊被 CAPTCHA 紅線擋住未取證）。
  # ③CAPTCHA v1 不做（本尊 hCaptcha——紅線不碰不量；Rack::Attack storefront
  #   throttle 承擔濫用面）。
  class CommentsController < BaseController
    skip_forgery_protection # 主題表單 POST（cart 同紀律；靠 throttle 不靠 CSRF）

    def create
      shop = current_shop
      result = ActsAsTenant.with_tenant(shop) do
        blog = Blog.find_by(shop_id: shop.id, handle: params[:blog_handle].to_s)
        article = blog && Article.visible.find_by(shop_id: shop.id, blog_id: blog.id,
                                                  handle: params[:article_handle].to_s)
        next :not_found if article.nil? || !blog.comments_enabled?

        raw = params.fetch(:comment, {}).permit(:author, :email, :body)
        comment = ArticleComment.new(
          shop_id: shop.id, article:,
          author_name: raw[:author].to_s.strip, email: raw[:email].to_s.strip,
          body: raw[:body].to_s.strip,
          status: blog.moderated? ? "pending" : "published"
        )
        comment.save ? :ok : :invalid
      end

      return head :not_found if result == :not_found

      prefix = url_prefix
      redirect_to "#{prefix}/blogs/#{params[:blog_handle]}/#{params[:article_handle]}#comment_form",
                  allow_other_host: false
    end

    private

    # 帶前綴路由給 locale_prefix；裸路由回預設前綴（search_controller 同構）。
    def url_prefix
      prefix = params[:locale_prefix].to_s
      return "/#{prefix}" if prefix.present?

      ActsAsTenant.with_tenant(current_shop) do
        market = Market.find_by(is_primary: true)
        presence = market&.market_web_presences&.first
        presence ? Markets::UrlPrefix.for(presence, presence.default_shop_locale) : ""
      end
    rescue Markets::UrlPrefix::Error
      ""
    end
  end
end
