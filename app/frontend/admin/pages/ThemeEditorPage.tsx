import { ArrowLeft, Eye, EyeOff } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { useT } from "../i18n/I18nContext";

/**
 * 主題編輯器 shell（步 16a；24 §1 實測形＋14 §F3 架構）。
 *
 * 本包射程＝三面板骨架：左＝sections 樹（template JSON 唯讀渲染：order 序＋
 * blocks 巢狀＋disabled 眼睛態）；中＝預覽 iframe（?editor=1 開 design_mode）；
 * 右＝選中 section 的 settings 唯讀檢視。postMessage 選中雙向（同源 origin
 * 嚴格比對——14 §F3 坑：不用 *）。
 * 🔴 op-stack／編輯／儲存＝16b（本包樹與設定面板刻意唯讀——先把骨架與橋
 * 立起來，寫入管線帶 lock_version 與 touch theme 紅線另包）。
 */
const EDITOR_QUERY = `
  query themeEditorBootstrap($id: ID!, $key: String!) {
    theme(id: $id) {
      id name role
      templates: files(filenames: ["templates/*.json"]) { filename }
      templateJson(key: $key)
    }
  }
`;

interface SectionEntry {
  type: string;
  disabled?: boolean;
  settings?: Record<string, unknown>;
  blocks?: Record<string, { type: string; settings?: Record<string, unknown> }>;
  block_order?: string[];
}

interface TemplateJson {
  sections?: Record<string, SectionEntry>;
  order?: string[];
}

interface EditorData {
  theme: {
    id: string;
    name: string;
    role: string;
    templates: { filename: string }[];
    templateJson: TemplateJson | null;
  } | null;
}

export function ThemeEditorPage() {
  const t = useT();
  const { themeId } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const templateKey = searchParams.get("template") ?? "index";
  const [data, setData] = useState<EditorData["theme"]>(null);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const iframeRef = useRef<HTMLIFrameElement | null>(null);

  const gid = `gid://chilllove/Theme/${themeId}`;

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<EditorData, { id: string; key: string }>(
        EDITOR_QUERY, { id: gid, key: templateKey }, signal);
      setData(result.theme);
      setError(result.theme ? null : t("editor.notFound"));
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("editor.notFound"));
    }
  }, [gid, templateKey, t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  // iframe → 編輯器：cl:select（origin 嚴格比對——14 §F3）
  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== window.location.origin) return;
      const payload = event.data as { type?: string; id?: string };
      if (payload?.type === "cl:select" && payload.id) setSelectedId(payload.id);
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, []);

  // 編輯器 → iframe：cl:highlight
  useEffect(() => {
    if (!selectedId) return;
    iframeRef.current?.contentWindow?.postMessage(
      { type: "cl:highlight", id: selectedId }, window.location.origin);
  }, [selectedId]);

  const templateNames = useMemo(() => (data?.templates ?? [])
    .map((file) => file.filename.replace(/^templates\//, "").replace(/\.json$/, ""))
    .sort(), [data]);

  const tpl = data?.templateJson;
  const order = tpl?.order ?? Object.keys(tpl?.sections ?? {});
  const selected = selectedId && tpl?.sections ? tpl.sections[selectedId] : null;

  const previewSrc = `/admin/store/preview/${themeId}?editor=1`;

  if (error) {
    return (
      <div className="cl-editor cl-editor--error">
        <p>{error}</p>
        <Link to="/admin/store">{t("editor.back")}</Link>
      </div>
    );
  }

  return (
    <div className="cl-editor">
      <header className="cl-editor__topbar">
        <Link className="cl-editor__back" to="/admin/store">
          <ArrowLeft aria-hidden="true" size={16} /> {data?.name ?? t("common.loading")}
        </Link>
        {/* 頁面（模板）切換器——24 §1.7 */}
        <select
          aria-label={t("editor.templateSwitcher")}
          className="cl-field__input cl-editor__switcher"
          onChange={(event) => setSearchParams({ template: event.target.value })}
          value={templateKey}
        >
          {(templateNames.length > 0 ? templateNames : [ templateKey ]).map((name) => (
            <option key={name} value={name}>{name}</option>
          ))}
        </select>
        {/* Save＝16b（op-stack）；本包唯讀 shell */}
        <Button disabled title={t("editor.saveComing")}>{t("common.save")}</Button>
      </header>

      <div className="cl-editor__panels">
        <aside aria-label={t("editor.sectionsTree")} className="cl-editor__tree">
          <h3>{t("editor.sectionsTree")}</h3>
          {order.length === 0 ? (
            <p className="cl-card-note">{t("editor.noSections")}</p>
          ) : (
            <ul>
              {order.map((sectionId) => {
                const entry = tpl?.sections?.[sectionId];
                if (!entry) return null;
                return (
                  <li key={sectionId}>
                    <button
                      aria-pressed={selectedId === sectionId}
                      className={selectedId === sectionId ? "cl-editor__node cl-editor__node--active" : "cl-editor__node"}
                      onClick={() => setSelectedId(sectionId)}
                      type="button"
                    >
                      {entry.disabled ? <EyeOff aria-label={t("editor.hidden")} size={13} /> : <Eye aria-hidden="true" size={13} />}
                      {" "}{entry.type}
                    </button>
                    {entry.block_order && entry.block_order.length > 0 ? (
                      <ul>
                        {entry.block_order.map((blockId) => (
                          <li className="cl-editor__block" key={blockId}>
                            {entry.blocks?.[blockId]?.type ?? blockId}
                          </li>
                        ))}
                      </ul>
                    ) : null}
                  </li>
                );
              })}
            </ul>
          )}
        </aside>

        <main className="cl-editor__preview">
          <iframe
            className="cl-editor__iframe"
            ref={iframeRef}
            src={previewSrc}
            title={t("editor.previewTitle")}
          />
        </main>

        <aside aria-label={t("editor.settingsPanel")} className="cl-editor__settings">
          <h3>{t("editor.settingsPanel")}</h3>
          {selected ? (
            <dl>
              <dt>{t("editor.sectionType")}</dt>
              <dd><code>{selected.type}</code></dd>
              {Object.entries(selected.settings ?? {}).map(([ key, value ]) => (
                <div key={key}>
                  <dt>{key}</dt>
                  <dd><code>{typeof value === "string" ? value : JSON.stringify(value)}</code></dd>
                </div>
              ))}
            </dl>
          ) : (
            <p className="cl-card-note">{t("editor.selectHint")}</p>
          )}
        </aside>
      </div>
    </div>
  );
}
