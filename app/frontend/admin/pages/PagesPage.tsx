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
 * 線上商店 › 頁面（步 14b；98 §4 admin 實測形——列＝Title/Visibility/Updated，
 * 表單＝標題＋內文＋可見性二態 Visible/Hidden）。
 *
 * 🔴 可見性語義（98 §3 官方）：建立預設發布（isPublished default true）；
 * Hidden＝publishedAt null。選列即編輯（單頁面板，不另開路由）。
 */
const PAGES_QUERY = `
  query pageList {
    pages(first: 250) {
      nodes { id title handle isPublished updatedAt body templateSuffix }
    }
  }
`;

const CREATE_MUTATION = `
  mutation pageCreate($title: String!, $body: String, $isPublished: Boolean) {
    pageCreate(title: $title, body: $body, isPublished: $isPublished) {
      page { id }
      userErrors { field message code }
    }
  }
`;

const UPDATE_MUTATION = `
  mutation pageUpdate($id: ID!, $title: String, $body: String, $isPublished: Boolean) {
    pageUpdate(id: $id, title: $title, body: $body, isPublished: $isPublished) {
      page { id }
      userErrors { field message code }
    }
  }
`;

const DELETE_MUTATION = `
  mutation pageDelete($id: ID!) {
    pageDelete(id: $id) {
      deletedPageId
      userErrors { field message code }
    }
  }
`;

interface PageRow {
  id: string;
  title: string;
  handle: string;
  isPublished: boolean;
  updatedAt: string;
  body: string;
  templateSuffix: string | null;
}

interface PagesData {
  pages: { nodes: PageRow[] };
}

interface MutationErrors {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

export function PagesPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<PagesData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [visible, setVisible] = useState(true);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      setData(await requestAdminGraphQL<PagesData, Record<string, never>>(PAGES_QUERY, {}, signal));
      setError(null);
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
        showToast(reason instanceof AdminGraphQLError || reason instanceof Error ? reason.message : t("pages.actionFailed"));
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
    setVisible(true);
  };

  const startEdit = (row: PageRow) => {
    setEditingId(row.id);
    setTitle(row.title);
    setBody(row.body);
    setVisible(row.isPublished);
  };

  const submit = () => {
    const variables = { title, body, isPublished: visible };
    if (editingId) {
      void run(UPDATE_MUTATION, { id: editingId, ...variables }, t("pages.saveDone"));
    } else {
      void run(CREATE_MUTATION, variables, t("pages.createDone")).then((ok) => {
        if (ok) startCreate();
      });
    }
  };

  if (error) {
    return (
      <Page title={t("pages.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("pages.title")}>
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
          <Plus aria-hidden="true" size={14} /> {t("pages.add")}
        </Button>
      }
      title={t("pages.title")}
    >
      <Card padded>
        <h3>{editingId ? t("pages.editTitle") : t("pages.addTitle")}</h3>
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="page-title">{t("pages.fieldTitle")}</label>
          <input
            className="cl-field__input"
            id="page-title"
            onChange={(event) => setTitle(event.target.value)}
            value={title}
          />
        </div>
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="page-body">{t("pages.fieldBody")}</label>
          <textarea
            className="cl-field__input"
            id="page-body"
            onChange={(event) => setBody(event.target.value)}
            rows={6}
            value={body}
          />
        </div>
        {/* 98 §4：Visibility 二態逐字 Visible/Hidden（radio） */}
        <fieldset className="cl-field">
          <legend className="cl-field__label">{t("pages.visibility")}</legend>
          <label>
            <input checked={visible} name="page-visibility" onChange={() => setVisible(true)} type="radio" />
            {" "}{t("pages.visible")}
          </label>
          <label>
            <input checked={!visible} name="page-visibility" onChange={() => setVisible(false)} type="radio" />
            {" "}{t("pages.hidden")}
          </label>
        </fieldset>
        <Button disabled={busy || !title} onClick={submit} variant="primary">
          {t("common.save")}
        </Button>
      </Card>

      <Card padded>
        <h3>{t("pages.listTitle")}</h3>
        {data.pages.nodes.length === 0 ? (
          <p className="cl-card-note">{t("pages.empty")}</p>
        ) : (
          <ul className="cl-locale-list">
            {data.pages.nodes.map((row) => (
              <li className="cl-locale-row" key={row.id}>
                <button className="cl-locale-row__name" onClick={() => startEdit(row)} type="button">
                  {row.title} <code>/{row.handle}</code>
                </button>
                <Badge progress="full" tone={row.isPublished ? "success" : "default"}>
                  {row.isPublished ? t("pages.visible") : t("pages.hidden")}
                </Badge>
                <span className="cl-locale-row__actions">
                  <Button
                    disabled={busy}
                    onClick={() => void run(DELETE_MUTATION, { id: row.id }, t("pages.deleteDone"))}
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
    </Page>
  );
}
