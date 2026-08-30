import { ExternalLink, RefreshCw, Upload } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { Page } from "../components/Page";
import { useToast } from "../lib/ToastContext";
import { useT } from "../i18n/I18nContext";

/**
 * 線上商店 › 主題清單（包 30／D77）。
 *
 * 本尊對位＝Online Store › Themes（78 §4：頁面分區「已發布佈景主題／草稿佈景主題」；
 * 該頁是跨域 iframe app、實測受限 ⇒ 控件事實以 help 為準——78 §0.2）。
 * v1 三件事：清單（published 前）、登入後預覽（noindex 端點）、發布轉場
 * （themePublish；單一發布不變量在 DB 產生欄唯一索引）。
 * 主題上傳管線（25 §4）＝後續包；程式碼編輯器＝M2 編輯器包。
 */
const THEMES_QUERY = `
  query themesList {
    themes { id name role version publishedAt updatedAt previewUrl }
  }
`;

const THEME_PUBLISH_MUTATION = `
  mutation themePublish($id: ID!) {
    themePublish(id: $id) {
      theme { id role }
      userErrors { field message code }
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
}

interface ThemesData {
  themes: ThemeNode[];
}

export function StorePage() {
  const t = useT();
  const { showToast } = useToast();
  const [themes, setThemes] = useState<ThemeNode[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

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

  const publish = useCallback(async (theme: ThemeNode) => {
    if (busyId !== null) return;
    setBusyId(theme.id);
    try {
      const data = await requestAdminGraphQL<{
        themePublish: { theme: { id: string; role: string } | null; userErrors: { message: string; code: string }[] };
      }, { id: string }>(THEME_PUBLISH_MUTATION, { id: theme.id });
      const firstError = data.themePublish.userErrors[0];
      if (firstError) {
        showToast(firstError.message);
      } else {
        showToast(t("store.themes.published", { name: theme.name }));
        await load();
      }
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : String(reason));
    } finally {
      setBusyId(null);
    }
  }, [busyId, load, showToast, t]);

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
                <span className="cl-store-themes__name">{theme.name}</span>
                {theme.version !== null ? <span className="cl-store-themes__version">v{theme.version}</span> : null}
                {theme.role === "published" ? (
                  <Badge progress="full" tone="success">{t("store.themes.rolePublished")}</Badge>
                ) : (
                  <Badge progress="half" tone="default">{t("store.themes.roleDraft")}</Badge>
                )}
              </div>
              <div className="cl-store-themes__actions">
                {/* 預覽開新分頁：noindex 端點、admin session 內有效 */}
                <a className="cl-store-themes__preview" href={theme.previewUrl} rel="noreferrer" target="_blank">
                  <ExternalLink aria-hidden="true" size={14} />
                  {t("store.themes.preview")}
                </a>
                {theme.role !== "published" ? (
                  <Button disabled={busyId !== null} onClick={() => void publish(theme)}>
                    {t("store.themes.publish")}
                  </Button>
                ) : null}
              </div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );

  return (
    <Page title={t("nav.onlineStore")}>
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
    </Page>
  );
}
