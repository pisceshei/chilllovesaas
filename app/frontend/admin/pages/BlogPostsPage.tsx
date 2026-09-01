import { Plus, Trash2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 內容 › 部落格貼文（步 14b；98 §4 admin 實測形）。
 *
 * ①貼文表單＝Title/Content/Summary/Author/Tags/Blog select/Visibility 二態
 *   （98 §4：Add blog post 表單逐欄；預設 Hidden 是本尊形，我方建立預設值走
 *   表單初值 Hidden 對齊）。
 * ②Manage blogs 區＝blog 列（Comments 欄）＋comment_policy 三值（98 §4 逐字：
 *   Disabled／Allowed, pending moderation／Allowed）。
 */
const LIST_QUERY = `
  query blogContent {
    blogs { id title handle commentPolicy }
    articles(first: 100) {
      nodes { id blogId title handle authorName tags isPublished updatedAt body summary }
    }
  }
`;

const ARTICLE_CREATE = `
  mutation articleCreate($blogId: ID!, $title: String!, $body: String!, $authorName: String,
                         $summary: String, $tags: [String!], $isPublished: Boolean) {
    articleCreate(blogId: $blogId, title: $title, body: $body, authorName: $authorName,
                  summary: $summary, tags: $tags, isPublished: $isPublished) {
      article { id }
      userErrors { field message code }
    }
  }
`;

const ARTICLE_UPDATE = `
  mutation articleUpdate($id: ID!, $title: String, $body: String, $authorName: String,
                         $summary: String, $tags: [String!], $isPublished: Boolean) {
    articleUpdate(id: $id, title: $title, body: $body, authorName: $authorName,
                  summary: $summary, tags: $tags, isPublished: $isPublished) {
      article { id }
      userErrors { field message code }
    }
  }
`;

const ARTICLE_DELETE = `
  mutation articleDelete($id: ID!) {
    articleDelete(id: $id) { deletedArticleId userErrors { field message code } }
  }
`;

const BLOG_CREATE = `
  mutation blogCreate($title: String!) {
    blogCreate(title: $title) { blog { id } userErrors { field message code } }
  }
`;

const BLOG_POLICY_UPDATE = `
  mutation blogUpdate($id: ID!, $commentPolicy: CommentPolicy) {
    blogUpdate(id: $id, commentPolicy: $commentPolicy) {
      blog { id commentPolicy }
      userErrors { field message code }
    }
  }
`;

interface BlogRow {
  id: string;
  title: string;
  handle: string;
  commentPolicy: "AUTO_PUBLISHED" | "CLOSED" | "MODERATED";
}

interface ArticleRow {
  id: string;
  blogId: string;
  title: string;
  handle: string;
  authorName: string | null;
  tags: string[];
  isPublished: boolean;
  updatedAt: string;
  body: string;
  summary: string | null;
}

interface ContentData {
  blogs: BlogRow[];
  articles: { nodes: ArticleRow[] };
}

interface MutationErrors {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

/** comment_policy 值 ↔ admin 逐字標籤（98 §4）的 i18n 鍵。 */
const POLICY_LABEL_KEY: Record<BlogRow["commentPolicy"], string> = {
  CLOSED: "blog.commentsDisabled",
  MODERATED: "blog.commentsModerated",
  AUTO_PUBLISHED: "blog.commentsAllowed",
};

export function BlogPostsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<ContentData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [summary, setSummary] = useState("");
  const [author, setAuthor] = useState("");
  const [tagsCsv, setTagsCsv] = useState("");
  const [blogId, setBlogId] = useState("");
  const [visible, setVisible] = useState(false); // 98 §4：本尊預設 Hidden
  const [newBlogTitle, setNewBlogTitle] = useState("");

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<ContentData, Record<string, never>>(LIST_QUERY, {}, signal);
      setData(result);
      setError(null);
      setBlogId((current) => current || result.blogs[0]?.id || "");
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("common.loading"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const run = useCallback(
    async (query: string, variables: Record<string, unknown>, successMessage: string) => {
      if (busy) return false;
      setBusy(true);
      try {
        const result = await requestAdminGraphQL<Record<string, MutationErrors>, Record<string, unknown>>(query, variables);
        const payload = Object.values(result)[0];
        if (payload.userErrors.length > 0) {
          showToast(payload.userErrors[0].message);
          return false;
        }
        showToast(successMessage);
        await load();
        return true;
      } catch (reason: unknown) {
        showToast(reason instanceof AdminGraphQLError || reason instanceof Error ? reason.message : t("blog.actionFailed"));
        return false;
      } finally {
        setBusy(false);
      }
    },
    [busy, load, showToast, t],
  );

  const startCreate = () => {
    setEditingId(null);
    setTitle("");
    setBody("");
    setSummary("");
    setAuthor("");
    setTagsCsv("");
    setVisible(false);
  };

  const startEdit = (row: ArticleRow) => {
    setEditingId(row.id);
    setTitle(row.title);
    setBody(row.body);
    setSummary(row.summary ?? "");
    setAuthor(row.authorName ?? "");
    setTagsCsv(row.tags.join(", "));
    setBlogId(row.blogId);
    setVisible(row.isPublished);
  };

  const submit = () => {
    const tags = tagsCsv.split(",").map((tag) => tag.trim()).filter(Boolean);
    const shared = { title, body, authorName: author || null, summary: summary || null, tags, isPublished: visible };
    if (editingId) {
      void run(ARTICLE_UPDATE, { id: editingId, ...shared }, t("blog.saveDone"));
    } else {
      void run(ARTICLE_CREATE, { blogId, ...shared }, t("blog.createDone")).then((ok) => {
        if (ok) startCreate();
      });
    }
  };

  if (error) {
    return (
      <Page title={t("blog.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("blog.title")}>
        <Card padded>
          <p className="cl-card-note">{t("common.loading")}</p>
        </Card>
      </Page>
    );
  }

  return (
    <Page
      actions={
        <Button onClick={startCreate} variant="primary">
          <Plus aria-hidden="true" size={14} /> {t("blog.add")}
        </Button>
      }
      title={t("blog.title")}
    >
      <Card padded>
        <h3>{editingId ? t("blog.editTitle") : t("blog.addTitle")}</h3>
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="article-title">{t("blog.fieldTitle")}</label>
          <input className="cl-field__input" id="article-title" onChange={(event) => setTitle(event.target.value)} value={title} />
        </div>
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="article-body">{t("blog.fieldBody")}</label>
          <textarea className="cl-field__input" id="article-body" onChange={(event) => setBody(event.target.value)} rows={6} value={body} />
        </div>
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="article-summary">{t("blog.fieldSummary")}</label>
          <textarea className="cl-field__input" id="article-summary" onChange={(event) => setSummary(event.target.value)} rows={2} value={summary} />
        </div>
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="article-author">{t("blog.fieldAuthor")}</label>
          <input className="cl-field__input" id="article-author" onChange={(event) => setAuthor(event.target.value)} value={author} />
        </div>
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="article-tags">{t("blog.fieldTags")}</label>
          <input className="cl-field__input" id="article-tags" onChange={(event) => setTagsCsv(event.target.value)} value={tagsCsv} />
        </div>
        {!editingId && (
          <div className="cl-field">
            <label className="cl-field__label" htmlFor="article-blog">{t("blog.fieldBlog")}</label>
            <select className="cl-field__input" id="article-blog" onChange={(event) => setBlogId(event.target.value)} value={blogId}>
              {data.blogs.map((blog) => (
                <option key={blog.id} value={blog.id}>{blog.title}</option>
              ))}
            </select>
          </div>
        )}
        <fieldset className="cl-field">
          <legend className="cl-field__label">{t("blog.visibility")}</legend>
          <label>
            <input checked={visible} name="article-visibility" onChange={() => setVisible(true)} type="radio" />
            {" "}{t("pages.visible")}
          </label>
          <label>
            <input checked={!visible} name="article-visibility" onChange={() => setVisible(false)} type="radio" />
            {" "}{t("pages.hidden")}
          </label>
        </fieldset>
        <Button disabled={busy || !title || !blogId} onClick={submit} variant="primary">
          {t("common.save")}
        </Button>
      </Card>

      <Card padded>
        <h3>{t("blog.listTitle")}</h3>
        {data.articles.nodes.length === 0 ? (
          <p className="cl-card-note">{t("blog.empty")}</p>
        ) : (
          <ul className="cl-locale-list">
            {data.articles.nodes.map((row) => (
              <li className="cl-locale-row" key={row.id}>
                <button className="cl-locale-row__name" onClick={() => startEdit(row)} type="button">
                  {row.title} <code>{row.handle}</code>
                </button>
                <Badge progress="full" tone={row.isPublished ? "success" : "default"}>
                  {row.isPublished ? t("pages.visible") : t("pages.hidden")}
                </Badge>
                <span className="cl-locale-row__actions">
                  <Button
                    disabled={busy}
                    onClick={() => void run(ARTICLE_DELETE, { id: row.id }, t("blog.deleteDone"))}
                    size="small"
                    variant="ghost"
                  >
                    <Trash2 aria-hidden="true" size={13} /> {t("common.delete")}
                  </Button>
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card padded>
        <h3>{t("blog.manageTitle")}</h3>
        <div className="cl-locale-add">
          <input
            aria-label={t("blog.newBlogTitle")}
            className="cl-field__input"
            onChange={(event) => setNewBlogTitle(event.target.value)}
            value={newBlogTitle}
          />
          <Button
            disabled={busy || !newBlogTitle}
            onClick={() => {
              void run(BLOG_CREATE, { title: newBlogTitle }, t("blog.blogCreateDone")).then((ok) => {
                if (ok) setNewBlogTitle("");
              });
            }}
            variant="primary"
          >
            <Plus aria-hidden="true" size={14} /> {t("blog.addBlog")}
          </Button>
        </div>
        <ul className="cl-locale-list">
          {data.blogs.map((blog) => (
            <li className="cl-locale-row" key={blog.id}>
              <span className="cl-locale-row__name">{blog.title} <code>/{blog.handle}</code></span>
              {/* 98 §4 三值逐字對映（Disabled／Allowed, pending moderation／Allowed） */}
              <select
                aria-label={t("blog.commentsPolicy", { title: blog.title })}
                className="cl-field__input"
                onChange={(event) =>
                  void run(BLOG_POLICY_UPDATE, { id: blog.id, commentPolicy: event.target.value }, t("blog.policyDone"))
                }
                value={blog.commentPolicy}
              >
                <option value="CLOSED">{t("blog.commentsDisabled")}</option>
                <option value="MODERATED">{t("blog.commentsModerated")}</option>
                <option value="AUTO_PUBLISHED">{t("blog.commentsAllowed")}</option>
              </select>
              <Badge progress="full" tone={blog.commentPolicy === "CLOSED" ? "default" : "info"}>
                {t(POLICY_LABEL_KEY[blog.commentPolicy])}
              </Badge>
            </li>
          ))}
        </ul>
      </Card>
    </Page>
  );
}
