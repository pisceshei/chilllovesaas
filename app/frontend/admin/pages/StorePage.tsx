import { Copy, ExternalLink, Pencil, RefreshCw, Trash2, Upload } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { EmptyState } from "../components/EmptyState";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 線上商店 › 主題（包 30 清單＋步 15c 動作全集）。
 *
 * 動作對位（99 §4／41 §634 親點全集）：Preview／Publish（🔴 確認 dialog——
 * 41 §634；原主題自動退回 Draft 區＝publish! 轉場）／Rename（inline）／
 * Duplicate（"Copy of" 命名＝help 逐字）／Delete（確認 dialog；published 拒刪
 * ＝後端官方行為）／匯入 zip（multipart＋授權聲明 gate——鐵律 9）。
 * Edit code／Edit default theme content＝步 16 編輯器射程（91 §3.68 同組登記）。
 */
const THEMES_QUERY = `
  query storeThemes {
    themes { id name role version publishedAt updatedAt previewUrl source }
  }
`;

const THEME_PUBLISH_MUTATION = `
  mutation themePublish($id: ID!) {
    themePublish(id: $id) {
      theme { id role }
      userErrors { message code }
    }
  }
`;

const THEME_RENAME_MUTATION = `
  mutation themeRename($id: ID!, $name: String!) {
    themeRename(id: $id, name: $name) {
      theme { id name }
      userErrors { message code }
    }
  }
`;

const THEME_DUPLICATE_MUTATION = `
  mutation themeDuplicate($id: ID!) {
    themeDuplicate(id: $id) {
      theme { id name }
      userErrors { message code }
    }
  }
`;

const THEME_DELETE_MUTATION = `
  mutation themeDelete($id: ID!) {
    themeDelete(id: $id) {
      deletedThemeId
      userErrors { message code }
    }
  }
`;

interface ThemeNode {
  id: string;
  name: string;
  role: string;
  version: string | null;
  publishedAt: string | null;
  updatedAt: string;
  previewUrl: string;
  source: string;
}

interface ThemesData {
  themes: ThemeNode[];
}

interface MutationErrors {
  userErrors: { message: string; code: string }[];
}

type ConfirmState = { kind: "publish" | "delete"; theme: ThemeNode } | null;

export function StorePage() {
  const t = useT();
  const { showToast } = useToast();
  const [themes, setThemes] = useState<ThemeNode[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [confirming, setConfirming] = useState<ConfirmState>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [importOpen, setImportOpen] = useState(false);
  const [importName, setImportName] = useState("");
  const [importLicense, setImportLicense] = useState(false);
  const [importBusy, setImportBusy] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);

  const load = useCallback(async (signal?: AbortSignal) => {
    setLoading(true);
    setError(null);
    try {
      const data = await requestAdminGraphQL<ThemesData, Record<string, never>>(THEMES_QUERY, {}, signal);
      setThemes(data.themes ?? []); // 防禦：回應形狀缺欄時顯示空清單而非炸頁
    } catch (reason: unknown) {
      if (reason instanceof DOMException && reason.name === "AbortError") return;
      setError(t("store.themes.loadError"));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const runMutation = useCallback(
    async (theme: ThemeNode, query: string, variables: Record<string, unknown>, successMessage: string) => {
      if (busyId !== null) return false;
      setBusyId(theme.id);
      try {
        const data = await requestAdminGraphQL<Record<string, MutationErrors>, Record<string, unknown>>(query, variables);
        const payload = Object.values(data)[0];
        if (payload.userErrors.length > 0) {
          showToast(payload.userErrors[0].message);
          return false;
        }
        showToast(successMessage);
        await load();
        return true;
      } catch (reason: unknown) {
        showToast(reason instanceof Error ? reason.message : String(reason));
        return false;
      } finally {
        setBusyId(null);
      }
    },
    [busyId, load, showToast],
  );

  const confirmAction = () => {
    if (!confirming) return;
    const { kind, theme } = confirming;
    setConfirming(null);
    if (kind === "publish") {
      void runMutation(theme, THEME_PUBLISH_MUTATION, { id: theme.id },
        t("store.themes.published", { name: theme.name }));
    } else {
      void runMutation(theme, THEME_DELETE_MUTATION, { id: theme.id },
        t("store.themes.deleted", { name: theme.name }));
    }
  };

  const submitRename = (theme: ThemeNode) => {
    void runMutation(theme, THEME_RENAME_MUTATION, { id: theme.id, name: renameValue },
      t("store.themes.renamed")).then((ok) => {
      if (ok) setRenamingId(null);
    });
  };

  // 匯入（multipart；CSRF 同 GraphQL——meta token）
  const submitImport = async () => {
    const file = fileRef.current?.files?.[0];
    if (!file || importBusy) return;
    setImportBusy(true);
    try {
      const body = new FormData();
      body.append("file", file);
      body.append("name", importName || file.name.replace(/\.zip$/i, ""));
      body.append("license_attested", importLicense ? "true" : "false");
      const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "";
      const response = await fetch("/admin/themes/import", {
        method: "POST", body, headers: { "X-CSRF-Token": token }, credentials: "same-origin",
      });
      const payload = await response.json() as {
        report?: { files: number; liquid_errors: { file: string }[] };
        error_message?: string; error_code?: string;
      };
      if (response.ok && payload.report) {
        const issues = payload.report.liquid_errors.length;
        showToast(issues > 0
          ? t("store.themes.importedWithIssues", { files: String(payload.report.files), issues: String(issues) })
          : t("store.themes.imported", { files: String(payload.report.files) }));
        setImportOpen(false);
        setImportName("");
        setImportLicense(false);
        await load();
      } else {
        showToast(payload.error_message ?? payload.error_code ?? t("store.themes.importFailed"));
      }
    } catch {
      showToast(t("store.themes.importFailed"));
    } finally {
      setImportBusy(false);
    }
  };

  const published = themes.filter((theme) => theme.role === "published");
  const drafts = themes.filter((theme) => theme.role !== "published");

  const section = (title: string, rows: ThemeNode[], empty: string) => (
    <Card padded>
      <h2 className="cl-store-themes__heading">{title}</h2>
      {rows.length === 0 ? (
        <p className="cl-store-themes__empty">{empty}</p>
      ) : (
        <ul className="cl-store-themes__list">
          {rows.map((theme) => (
            <li className="cl-store-themes__row" key={theme.id}>
              <div className="cl-store-themes__meta">
                {renamingId === theme.id ? (
                  <>
                    <input
                      aria-label={t("store.themes.renameLabel")}
                      className="cl-field__input"
                      onChange={(event) => setRenameValue(event.target.value)}
                      value={renameValue}
                    />
                    <Button disabled={busyId !== null || !renameValue.trim()} onClick={() => submitRename(theme)} size="small">
                      {t("common.save")}
                    </Button>
                    <Button onClick={() => setRenamingId(null)} size="small" variant="ghost">
                      {t("common.cancel")}
                    </Button>
                  </>
                ) : (
                  <>
                    <span className="cl-store-themes__name">{theme.name}</span>
                    {theme.version !== null ? <span className="cl-store-themes__version">v{theme.version}</span> : null}
                    {theme.role === "published" ? (
                      <Badge progress="full" tone="success">{t("store.themes.rolePublished")}</Badge>
                    ) : (
                      <Badge progress="half" tone="default">{t("store.themes.roleDraft")}</Badge>
                    )}
                  </>
                )}
              </div>
              <div className="cl-store-themes__actions">
                {/* 預覽開新分頁：noindex 端點、admin session 內有效 */}
                <a className="cl-store-themes__preview" href={theme.previewUrl} rel="noreferrer" target="_blank">
                  <ExternalLink aria-hidden="true" size={14} />
                  {t("store.themes.preview")}
                </a>
                <Button
                  disabled={busyId !== null}
                  onClick={() => {
                    setRenamingId(theme.id);
                    setRenameValue(theme.name);
                  }}
                  size="small"
                  variant="ghost"
                >
                  <Pencil aria-hidden="true" size={13} /> {t("store.themes.rename")}
                </Button>
                <Button
                  disabled={busyId !== null}
                  onClick={() => void runMutation(theme, THEME_DUPLICATE_MUTATION, { id: theme.id },
                    t("store.themes.duplicated"))}
                  size="small"
                  variant="ghost"
                >
                  <Copy aria-hidden="true" size={13} /> {t("store.themes.duplicate")}
                </Button>
                {theme.role !== "published" ? (
                  <>
                    <Button disabled={busyId !== null} onClick={() => setConfirming({ kind: "publish", theme })}>
                      {t("store.themes.publish")}
                    </Button>
                    <Button
                      disabled={busyId !== null}
                      onClick={() => setConfirming({ kind: "delete", theme })}
                      size="small"
                      variant="ghost"
                    >
                      <Trash2 aria-hidden="true" size={13} /> {t("common.delete")}
                    </Button>
                  </>
                ) : null}
              </div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );

  return (
    <Page
      actions={
        <Button onClick={() => setImportOpen((open) => !open)} variant="primary">
          <Upload aria-hidden="true" size={14} /> {t("store.themes.import")}
        </Button>
      }
      title={t("nav.onlineStore")}
    >
      {importOpen ? (
        <Card padded>
          <h2 className="cl-store-themes__heading">{t("store.themes.importTitle")}</h2>
          <div className="cl-field">
            <label className="cl-field__label" htmlFor="theme-zip">{t("store.themes.importFile")}</label>
            <input accept=".zip" className="cl-field__input" id="theme-zip" ref={fileRef} type="file" />
          </div>
          <div className="cl-field">
            <label className="cl-field__label" htmlFor="theme-import-name">{t("store.themes.importName")}</label>
            <input
              className="cl-field__input"
              id="theme-import-name"
              onChange={(event) => setImportName(event.target.value)}
              value={importName}
            />
          </div>
          {/* 🔴 授權聲明 gate（鐵律 9）：不勾不送——後端同閘雙保險 */}
          <label className="cl-field">
            <input
              checked={importLicense}
              onChange={(event) => setImportLicense(event.target.checked)}
              type="checkbox"
            />
            {" "}{t("store.themes.importLicense")}
          </label>
          <Button disabled={importBusy || !importLicense} onClick={() => void submitImport()} variant="primary">
            {t("store.themes.importSubmit")}
          </Button>
        </Card>
      ) : null}

      {error !== null ? (
        <EmptyState
          action={(
            <Button onClick={() => void load()}>
              <RefreshCw aria-hidden="true" size={14} />
              {t("common.retry")}
            </Button>
          )}
          description={error}
          illustration={<Upload size={30} strokeWidth={1.7} />}
          title={t("store.themes.loadErrorTitle")}
        />
      ) : loading ? (
        <p className="cl-store-themes__loading" role="status">{t("common.loading")}</p>
      ) : themes.length === 0 ? (
        <EmptyState
          action={<span />}
          description={t("store.themes.emptyBody")}
          illustration={<Upload size={30} strokeWidth={1.7} />}
          title={t("store.themes.emptyTitle")}
        />
      ) : (
        <>
          {section(t("store.themes.publishedSection"), published, t("store.themes.publishedEmpty"))}
          {section(t("store.themes.draftSection"), drafts, t("store.themes.draftEmpty"))}
        </>
      )}

      <ConfirmDialog
        confirmLabel={confirming?.kind === "delete" ? t("common.delete") : t("store.themes.publish")}
        danger={confirming?.kind === "delete"}
        message={confirming?.kind === "delete"
          ? t("store.themes.deleteConfirmBody", { name: confirming.theme.name })
          : t("store.themes.publishConfirmBody", { name: confirming?.theme.name ?? "" })}
        onCancel={() => setConfirming(null)}
        onConfirm={confirmAction}
        open={confirming !== null}
        title={confirming?.kind === "delete"
          ? t("store.themes.deleteConfirmTitle")
          : t("store.themes.publishConfirmTitle")}
      />
    </Page>
  );
}
