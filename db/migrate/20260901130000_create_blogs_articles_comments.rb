# frozen_string_literal: true

# G2 步 14a（內容線；98 §3/§4）：
# ①blogs——comment_policy 三值（官方 CommentPolicy：closed/moderated/auto_published；
#   admin 預設 Disabled＝closed，98 §4 實測）。
# ②articles——published_at NULL＝Hidden（admin Visibility 二態＋排程；Page 同紀律）；
#   handle 唯一域＝(shop, blog)（URL 複合形 /blogs/{blog}/{article}——98 §1）。
# ③article_comments——三態 status（pending/published/spam＝admin Approved/
#   Not approved/Spam 對映；Liquid 只見 published——官方 comment.status 恆 published）。
class CreateBlogsArticlesComments < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:blogs)
      create_table :blogs, comment: "部落格（98 §3；comment_policy 官方三值）" do |t|
        t.bigint :shop_id, null: false
        t.string :title, null: false
        t.string :handle, null: false
        t.string :comment_policy, limit: 20, null: false, default: "closed"
        t.string :template_suffix
        t.timestamps

        t.index [ :shop_id, :handle ], unique: true, name: "uq_blogs_handle"
        t.index [ :shop_id, :id ], unique: true, name: "uq_blogs_tenant_id"
      end
    end

    unless table_exists?(:articles)
      create_table :articles, comment: "部落格文章（98 §1/§4；published_at NULL＝Hidden）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :blog_id, null: false
        t.string :title, null: false
        t.string :handle, null: false
        t.string :author_name, comment: "顯示名（98 §4 byline『By KEN LEE』形；不掛 staff FK）"
        t.text :body_html, size: :long, null: false
        t.text :excerpt_html, comment: "摘要（官方 summary/excerpt——列表與 excerpt_or_content 用）"
        t.datetime :published_at, comment: "NULL＝Hidden；未來時刻＝排程（Page.visible 同紀律）"
        t.json :tags, null: false, default: -> { "(json_array())" }
        t.string :template_suffix
        t.timestamps

        t.index [ :shop_id, :blog_id, :handle ], unique: true, name: "uq_articles_handle"
        t.index [ :shop_id, :blog_id, :published_at ], name: "ix_articles_published"
        t.index [ :shop_id, :id ], unique: true, name: "uq_articles_tenant_id"
      end
    end
    if table_exists?(:articles) &&
       foreign_keys(:articles).none? { |fk| fk.to_table == "blogs" }
      safety_assured { add_foreign_key :articles, :blogs }
    end

    unless table_exists?(:article_comments)
      create_table :article_comments, comment: "文章留言（三態；Liquid 只見 published）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :article_id, null: false
        t.string :author_name, null: false
        t.string :email, limit: 320, null: false
        t.text :body, null: false
        t.string :status, limit: 12, null: false, default: "pending"
        t.timestamps

        t.index [ :shop_id, :article_id, :status ], name: "ix_article_comments_status"
        t.index [ :shop_id, :id ], unique: true, name: "uq_article_comments_tenant_id"
      end
    end
    if table_exists?(:article_comments) &&
       foreign_keys(:article_comments).none? { |fk| fk.to_table == "articles" }
      safety_assured { add_foreign_key :article_comments, :articles }
    end
  end
end
