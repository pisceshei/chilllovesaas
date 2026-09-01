import { ArrowLeft, FileCode2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * Code editor（步 16e2；官方形取證 2026-09-01：help edit-theme-code＋
 * dev docs/storefronts/themes/tools/code-editor）：
 * - 檔案樹按型分資料夾（官方 sidebar「organizes files and folders by type」）。
 * - 多 tab＋unsaved dot（官方 "a dot displays next to the tab name to indicate
 *   unsaved changes"）；儲存＝per-file（官方 Cmd/Ctrl+S——本頁掛同快捷鍵）。
 * - 寫回走 themeFileUpsert（DB 覆寫層＋樂觀鎖＋touch theme——16e1 契約）。
 * - 🔴 templates/*.json 與 config/settings_data.json 唯讀（雙真相源禁令：
 *   各自由模板編輯器／佈景設定管理；後端白名單同軸拒收）。
 * - 語法高亮／Theme Check／Timeline＝91 §3.71 待辦（textarea 先行——鐵律 1
 *   不引入未討論編輯器依賴）。
 */

const FILES_QUERY = `
  query codeEditorFiles($id: ID!) {
    theme(id: $id) {
      id
      name
      files { filename size }
    }
  }
`;

const BODY_QUERY = `
  query codeEditorBody($id: ID!, $paths: [String!]!, $path: String!) {
    theme(id: $id) {
      files(filenames: $paths, first: 1) { filename body }
      fileLockVersion(path: $path)
    }
  }
`;

const FILE_SAVE_MUTATION = `
  mutation themeFileUpsert($themeId: ID!, $path: String!, $content: String!, $lockVersion: Int) {
    themeFileUpsert(themeId: $themeId, path: $path, content: $content, lockVersion: $lockVersion) {
      path
      lockVersion
      userErrors { field message code }
    }
  }
`;

/** 官方目錄樹順序（26 §4 inventory；templates 顯示但唯讀）。 */
const DIR_ORDER = [ "layout", "templates", "sections", "blocks", "snippets", "config", "assets", "locales" ];

interface OpenTab {
  path: string;
  content: string;
  savedContent: string;
  lockVersion: number | null;
  readonly: boolean;
}

/** 雙真相源禁令：這兩類在 code editor 唯讀（16e1 白名單同軸）。 */
function readonlyPath(path: string): boolean {
  return path.startsWith("templates/") || path === "config/settings_data.json";
}

export function CodeEditorPage() {
  const t = useT();
  const { showToast } = useToast();
  const { themeId } = useParams();
  const gid = `gid://chilllove/Theme/${themeId}`;

  const [error, setError] = useState<string | null>(null);
  const [themeName, setThemeName] = useState("");
  const [filenames, setFilenames] = useState<string[]>([]);
  const [openDirs, setOpenDirs] = useState<Set<string>>(new Set([ "layout" ]));
  const [tabs, setTabs] = useState<OpenTab[]>([]);
  const [activePath, setActivePath] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const controller = new AbortController();
    void (async () => {
      try {
        const result = await requestAdminGraphQL<{
          theme: { name: string; files: { filename: string }[] } | null;
        }, { id: string }>(FILES_QUERY, { id: gid }, controller.signal);
        if (!result.theme) { setError(t("code.notFound")); return; }
        setThemeName(result.theme.name);
        setFilenames(result.theme.files.map((file) => file.filename));
      } catch (reason: unknown) {
        if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : t("code.notFound"));
      }
    })();
    return () => controller.abort();
  }, [gid, t]);

  const openFile = useCallback(async (path: string) => {
    setActivePath(path);
    if (tabs.some((tab) => tab.path === path)) return;
    try {
      const result = await requestAdminGraphQL<{
        theme: { files: { filename: string; body: string | null }[]; fileLockVersion: number | null } | null;
      }, Record<string, unknown>>(BODY_QUERY, { id: gid, paths: [ path ], path });
      const body = result.theme?.files?.[0]?.body;
      setTabs((current) => [ ...current, {
        path,
        content: body ?? "",
        savedContent: body ?? "",
        lockVersion: result.theme?.fileLockVersion ?? null,
        readonly: readonlyPath(path) || body == null, // binary（body null）唯讀
      } ]);
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("code.loadFailed"));
    }
  }, [gid, tabs, showToast, t]);

  const active = tabs.find((tab) => tab.path === activePath) ?? null;
  const dirty = (tab: OpenTab) => tab.content !== tab.savedContent;

  const save = useCallback(async () => {
    const tab = tabs.find((entry) => entry.path === activePath);
    if (!tab || tab.readonly || !dirty(tab) || saving) return;
    setSaving(true);
    try {
      const result = await requestAdminGraphQL<{
        themeFileUpsert: { path: string | null; lockVersion: number | null;
                           userErrors: { message: string; code: string }[] };
      }, Record<string, unknown>>(FILE_SAVE_MUTATION, {
        themeId: gid, path: tab.path, content: tab.content, lockVersion: tab.lockVersion,
      });
      const payload = result.themeFileUpsert;
      if (payload.userErrors.length > 0) {
        const firstError = payload.userErrors[0];
        showToast(firstError.code === "STALE_OBJECT" ? t("code.staleConflict") : firstError.message);
        return;
      }
      setTabs((current) => current.map((entry) => (entry.path === tab.path
        ? { ...entry, savedContent: entry.content, lockVersion: payload.lockVersion }
        : entry)));
      showToast(t("code.saved"));
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("code.saveFailed"));
    } finally {
      setSaving(false);
    }
  }, [tabs, activePath, saving, gid, showToast, t]);

  // 官方快捷鍵：Cmd/Ctrl+S per-file save
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === "s") {
        event.preventDefault();
        void save();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [save]);

  const grouped = DIR_ORDER.map((dir) => ({
    dir,
    files: filenames.filter((name) => name.startsWith(`${dir}/`)).sort(),
  })).filter((group) => group.files.length > 0);

  if (error) {
    return (
      <div className="cl-page">
        <p className="cl-card-note">{error}</p>
        <Link to="/admin/store">{t("code.back")}</Link>
      </div>
    );
  }

  return (
    <div className="cl-code">
      <header className="cl-code__topbar">
        <Link className="cl-code__back" to="/admin/store">
          <ArrowLeft aria-hidden="true" size={16} /> {t("code.back")}
        </Link>
        <strong>{themeName}</strong>
        <span className="cl-card-note">{t("code.title")}</span>
        <span className="cl-code__spacer" />
        <Button
          disabled={!active || active.readonly || !dirty(active) || saving}
          onClick={() => void save()}
          variant="primary"
        >
          {t("common.save")}
        </Button>
      </header>

      <div className="cl-code__panels">
        <aside aria-label={t("code.fileTree")} className="cl-code__tree">
          {grouped.map((group) => (
            <div key={group.dir}>
              <button
                className="cl-code__dir"
                onClick={() => setOpenDirs((current) => {
                  const next = new Set(current);
                  if (next.has(group.dir)) next.delete(group.dir); else next.add(group.dir);
                  return next;
                })}
                type="button"
              >
                {openDirs.has(group.dir) ? "▾" : "▸"} {group.dir}
              </button>
              {openDirs.has(group.dir) ? (
                <ul className="cl-code__files">
                  {group.files.map((name) => (
                    <li key={name}>
                      <button
                        className={`cl-code__file${name === activePath ? " is-active" : ""}`}
                        onClick={() => void openFile(name)}
                        type="button"
                      >
                        <FileCode2 aria-hidden="true" size={12} /> {name.slice(group.dir.length + 1)}
                      </button>
                    </li>
                  ))}
                </ul>
              ) : null}
            </div>
          ))}
        </aside>

        <main className="cl-code__editor">
          {tabs.length > 0 ? (
            <div className="cl-code__tabs" role="tablist">
              {tabs.map((tab) => (
                <button
                  aria-selected={tab.path === activePath}
                  className={`cl-code__tab${tab.path === activePath ? " is-active" : ""}`}
                  key={tab.path}
                  onClick={() => setActivePath(tab.path)}
                  role="tab"
                  type="button"
                >
                  {tab.path.split("/").pop()}
                  {/* 官方形：unsaved dot */}
                  {dirty(tab) ? <span aria-label={t("code.unsaved")} className="cl-code__dot">•</span> : null}
                </button>
              ))}
            </div>
          ) : null}

          {active ? (
            <>
              {active.readonly ? (
                <p className="cl-card-note">
                  {active.path.startsWith("templates/")
                    ? t("code.readonlyTemplates")
                    : active.path === "config/settings_data.json"
                      ? t("code.readonlySettings")
                      : t("code.readonlyBinary")}
                </p>
              ) : null}
              <textarea
                aria-label={active.path}
                className="cl-code__textarea"
                disabled={active.readonly}
                onChange={(event) => {
                  const value = event.target.value;
                  setTabs((current) => current.map((entry) => (entry.path === active.path
                    ? { ...entry, content: value }
                    : entry)));
                }}
                spellCheck={false}
                value={active.content}
              />
            </>
          ) : (
            <p className="cl-card-note">{t("code.selectHint")}</p>
          )}
        </main>
      </div>
    </div>
  );
}
