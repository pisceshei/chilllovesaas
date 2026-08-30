import { ArrowRight, Plus, Trash2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 設定 › 網址重導（包 36；docs/specs/62 §B.5）。
 *
 * 🔴 路徑一律**無 locale 前綴正規形**——各語言（/en-hk/…）由路由層自動保留前綴，
 * 一列覆蓋全部語言（UrlRedirects::Normalize 的 DOC-5 裁定）。
 * 系統列（handle_change 等）唯讀可刪：刪除＝釋放舊 handle（HDL-8）；
 * 改名鏈坍縮由後端不變量維護，人手不可改。
 */
const REDIRECTS_QUERY = `
  query urlRedirectList($query: String) {
    urlRedirects(first: 250, query: $query) {
      nodes { id path target source }
    }
  }
`;

const CREATE_MUTATION = `
  mutation urlRedirectCreate($path: String!, $target: String!) {
    urlRedirectCreate(path: $path, target: $target) {
      urlRedirect { id }
      userErrors { field message code }
    }
  }
`;

const DELETE_MUTATION = `
  mutation urlRedirectDelete($id: ID!) {
    urlRedirectDelete(id: $id) {
      deletedUrlRedirectId
      userErrors { field message code }
    }
  }
`;

interface RedirectRow {
  id: string;
  path: string;
  target: string;
  source: string;
}

interface RedirectsData {
  urlRedirects: { nodes: RedirectRow[] };
}

interface MutationErrors {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

export function SettingsRedirectsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<RedirectsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [path, setPath] = useState("");
  const [target, setTarget] = useState("");

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      setData(await requestAdminGraphQL<RedirectsData, { query: string | null }>(REDIRECTS_QUERY, { query: null }, signal));
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("settings.redirects.loadFailed"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const run = useCallback(
    async (label: string, query: string, variables: Record<string, unknown>, successMessage: string) => {
      if (busy) return false;
      setBusy(label);
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
        showToast(reason instanceof AdminGraphQLError || reason instanceof Error ? reason.message : t("settings.redirects.actionFailed"));
        return false;
      } finally {
        setBusy(null);
      }
    },
    [busy, load, showToast, t],
  );

  if (error) {
    return (
      <Page title={t("settings.redirects.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("settings.redirects.title")}>
        <Card padded>
          <p className="cl-card-note">{t("common.loading")}</p>
        </Card>
      </Page>
    );
  }

  const rows = data.urlRedirects.nodes;

  return (
    <Page title={t("settings.redirects.title")}>
      <Card padded>
        <h3>{t("settings.redirects.addTitle")}</h3>
        <p className="cl-card-note">{t("settings.redirects.hint")}</p>
        <div className="cl-locale-add">
          <input
            aria-label={t("settings.redirects.path")}
            className="cl-field__input"
            onChange={(event) => setPath(event.target.value)}
            placeholder="/products/old-handle"
            value={path}
          />
          <input
            aria-label={t("settings.redirects.target")}
            className="cl-field__input"
            onChange={(event) => setTarget(event.target.value)}
            placeholder="/products/new-handle"
            value={target}
          />
          <Button
            disabled={busy !== null || !path || !target}
            onClick={() => {
              void run("create", CREATE_MUTATION, { path, target }, t("settings.redirects.addDone")).then((ok) => {
                if (ok) {
                  setPath("");
                  setTarget("");
                }
              });
            }}
            variant="primary"
          >
            <Plus aria-hidden="true" size={14} /> {t("settings.redirects.add")}
          </Button>
        </div>
      </Card>

      <Card padded>
        <h3>{t("settings.redirects.listTitle")}</h3>
        {rows.length === 0 ? (
          <p className="cl-card-note">{t("settings.redirects.empty")}</p>
        ) : (
          <ul className="cl-locale-list">
            {rows.map((row) => (
              <li className="cl-locale-row" key={row.id}>
                <span className="cl-locale-row__name">
                  <code>{row.path}</code>
                  <ArrowRight aria-hidden="true" size={14} />
                  <code>{row.target}</code>
                </span>
                <Badge progress="full" tone={row.source === "manual" ? "default" : "info"}>
                  {row.source === "manual"
                    ? t("settings.redirects.sourceManual")
                    : t("settings.redirects.sourceSystem")}
                </Badge>
                <span className="cl-locale-row__actions">
                  <Button
                    disabled={busy !== null}
                    onClick={() =>
                      void run(`delete:${row.id}`, DELETE_MUTATION, { id: row.id }, t("settings.redirects.deleteDone"))
                    }
                    size="small"
                    variant="ghost"
                  >
                    <Trash2 aria-hidden="true" size={13} /> {t("settings.redirects.delete")}
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
