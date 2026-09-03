import { ArrowDown, ArrowUp, Copy, Eye, EyeOff, Search, Trash2, X } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { CreateTemplateDialog } from "../editor/CreateTemplateDialog";
import { EditorTopBar, type EditorPanel } from "../editor/EditorTopBar";
import { isTypingTarget, shortcutFor } from "../editor/editorShortcuts";
import { ShortcutsDialog } from "../editor/ShortcutsDialog";
import { splitTemplateKey } from "../editor/TemplateSwitcher";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 主題編輯器（步 16a shell＋16b op-stack 編輯管線；E2／D79 shell＋頂欄依本尊重做）。
 *
 * 編輯語義（24 §3 原子 op 對照表）：set-setting／toggle-disabled（眼睛＝隱藏
 * 不是刪除）／move（上下移＝改 order）／remove（移除 entry＋order 引用）／
 * duplicate（深拷貝＋新 ID）。add-section（picker＋preset）＝16c。
 * Undo/Redo＝JSON 快照棧（14 §F3：不做 op-based——僅未儲存變更、Save 後清空）。
 * 儲存＝themeTemplateUpsert 整份 JSON＋樂觀鎖（STALE ⇒ 提示重載）；成功後
 * iframe 重載（後端已 touch theme——頁快取鍵旋轉紅線在 server 端）。
 *
 * E2 shell（`docs/research/100` §1／§5／§6／§7 實測對位）：
 * - 頂欄＝`EditorTopBar`（Exit＋面板切換器＋主題 chip＋市場＋模板選擇器＋工具＋Undo/Redo
 *   ＋「…」＋Publish＋Save）；面板切換器再點已啟用者 ⇒ 全寬預覽（`previewMode=fullscreen`）。
 * - 左欄依 `panel` 切換：sections（樹）／theme（佈景設定手風琴）／apps（app embeds 空態）。
 * - 右欄只在選中 section／block 時掛載（本尊：無選取 ⇒ 兩欄）。
 * - URL 狀態：`template`／`section`／`block`／`context=theme|apps`／`previewMode`／
 *   `previewPath`／`category`（本尊同名參數；`section` 值用我方 section 鍵）。
 * - 快捷鍵單一表 `editorShortcuts.ts`；離開有未存變更 ⇒ 確認框；Publish ⇒ 確認框 →
 *   先存再 `themePublish`。
 */
const EDITOR_QUERY = `
  query themeEditorBootstrap($id: ID!, $key: String!) {
    theme(id: $id) {
      id name role
      templates: files(filenames: ["templates/*.json"]) { filename }
      templateKeys
      templateAssignments
      templateJson(key: $key)
      templateLockVersion(key: $key)
      previewPaths
      sectionGroups
      sectionCatalog
      sectionSchemas
      settingsSchema
      themeSettingsJson
      themeSettingsLockVersion
    }
  }
`;

const BASE_TEMPLATE_QUERY = `
  query themeEditorBaseTemplate($id: ID!, $key: String!) {
    theme(id: $id) { templateJson(key: $key) }
  }
`;

const PUBLISH_MUTATION = `
  mutation themePublish($id: ID!) {
    themePublish(id: $id) {
      theme { id role }
      userErrors { field message code }
    }
  }
`;

const GROUP_SAVE_MUTATION = `
  mutation themeFileUpsert($themeId: ID!, $path: String!, $content: String!, $lockVersion: Int) {
    themeFileUpsert(themeId: $themeId, path: $path, content: $content, lockVersion: $lockVersion) {
      path
      lockVersion
      userErrors { field message code }
    }
  }
`;

const SETTINGS_MUTATION = `
  mutation themeSettingsUpsert($themeId: ID!, $settings: JSON!, $lockVersion: Int) {
    themeSettingsUpsert(themeId: $themeId, settings: $settings, lockVersion: $lockVersion) {
      lockVersion
      userErrors { field message code }
    }
  }
`;

const SAVE_MUTATION = `
  mutation themeTemplateUpsert($themeId: ID!, $key: String!, $content: JSON!, $lockVersion: Int) {
    themeTemplateUpsert(themeId: $themeId, key: $key, content: $content, lockVersion: $lockVersion) {
      templateKey
      lockVersion
      userErrors { field message code }
    }
  }
`;

interface SectionEntry {
  type: string;
  disabled?: boolean;
  custom_css?: string;
  settings?: Record<string, unknown>;
  blocks?: Record<string, { type: string; settings?: Record<string, unknown> }>;
  block_order?: string[];
}

interface TemplateJson {
  sections?: Record<string, SectionEntry>;
  order?: string[];
}

/** 26 §5 型別子集：16d 先接 T0 純值控件；資源選擇器唯讀（16e 射程）。 */
interface SettingDef {
  id?: string;
  type: string;
  label?: string;
  info?: string;
  content?: string;
  default?: unknown;
  placeholder?: string;
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  options?: { value: string; label: string }[];
}

interface BlockDef {
  type: string;
  name?: string;
  limit?: number;
  settings?: SettingDef[];
}

interface EditorData {
  theme: {
    id: string;
    name: string;
    role: string;
    templates: { filename: string }[];
    templateKeys?: string[];
    templateAssignments?: Record<string, Record<string, number>>;
    templateJson: TemplateJson | null;
    templateLockVersion: number | null;
    sectionCatalog: { type: string; name: string;
                      preset: { settings: Record<string, unknown>;
                                blocks: Record<string, unknown> | null } }[];
    previewPaths: Record<string, string>;
    sectionGroups: { name: string; path: string; json: TemplateJson; lockVersion: number | null }[];
    sectionSchemas: Record<string, { name: string; settings: SettingDef[];
                                     max_blocks?: number | null; blocks?: BlockDef[] }>;
    settingsSchema: { name: string; settings: SettingDef[] }[];
    themeSettingsJson: Record<string, unknown>;
    themeSettingsLockVersion: number | null;
  } | null;
}

/** PR-23：買家路徑 → 模板型（預覽內導航同步左欄模板；99/96 路由對映） */
export function templateForPath(path: string): string {
  const clean = path.replace(/^\/[a-z]{2}(-[a-z]{2})?(?=\/|$)/i, "").split("?")[0] || "/";
  if (clean === "/" || clean === "") return "index";
  if (clean.startsWith("/products/")) return "product";
  if (clean === "/collections") return "list-collections";
  if (clean.startsWith("/collections/")) return "collection";
  if (clean === "/cart") return "cart";
  if (clean.startsWith("/pages/")) return "page";
  if (/^\/blogs\/[^/]+\/.+/.test(clean)) return "article";
  if (clean.startsWith("/blogs/")) return "blog";
  if (clean.startsWith("/search")) return "search";
  return "index";
}

function cloneTpl(tpl: TemplateJson): TemplateJson {
  return JSON.parse(JSON.stringify(tpl)) as TemplateJson;
}

const HEX_RE = /^#[0-9a-fA-F]{6}$/;

/** schema 驅動控件（26 §5 對映）：T0 純值型可編輯；資源選擇器唯讀（16e）。 */
function SettingControl({ def, value, onChange }: {
  def: SettingDef;
  value: unknown;
  onChange: (value: unknown) => void;
}) {
  const t = useT();
  // header/paragraph＝側欄結構元素，無值（26 §5「schema 解析必須接受」）
  if (def.type === "header") return <h4 className="cl-editor__group">{def.content}</h4>;
  if (def.type === "paragraph") return <p className="cl-card-note">{def.content}</p>;
  if (!def.id) return null;

  // 🔴 值解析＝實例值 ?? schema default（本尊語義：未覆寫顯示預設）
  const effective = value ?? def.default;
  const inputId = `setting-${def.id}`;
  const label = def.label ?? def.id;

  let control: ReactNode;
  switch (def.type) {
    case "checkbox":
      control = (
        <input checked={Boolean(effective)} id={inputId}
          onChange={(event) => onChange(event.target.checked)} type="checkbox" />
      );
      break;
    case "number":
      control = (
        <input className="cl-field__input" id={inputId} max={def.max} min={def.min}
          onChange={(event) => onChange(event.target.value === "" ? null : Number(event.target.value))}
          placeholder={def.placeholder} type="number" value={effective == null ? "" : Number(effective)} />
      );
      break;
    case "range":
      control = (
        <span className="cl-editor__range">
          <input id={inputId} max={def.max} min={def.min}
            onChange={(event) => onChange(Number(event.target.value))}
            step={def.step} type="range" value={Number(effective ?? def.min ?? 0)} />
          <span className="cl-card-note">{String(effective ?? "")}{def.unit ?? ""}</span>
        </span>
      );
      break;
    case "select":
    case "text_alignment": {
      const options = def.type === "text_alignment"
        ? [ { value: "left", label: t("editor.alignLeft") },
            { value: "center", label: t("editor.alignCenter") },
            { value: "right", label: t("editor.alignRight") } ]
        : def.options ?? [];
      control = (
        <select className="cl-field__input" id={inputId}
          onChange={(event) => onChange(event.target.value)} value={String(effective ?? "")}>
          {options.map((option) => (
            <option key={option.value} value={option.value}>{option.label}</option>
          ))}
        </select>
      );
      break;
    }
    case "radio":
      control = (
        <span role="radiogroup">
          {(def.options ?? []).map((option) => (
            <label className="cl-editor__radio" key={option.value}>
              <input checked={String(effective ?? "") === option.value} name={inputId}
                onChange={() => onChange(option.value)} type="radio" value={option.value} />
              {option.label}
            </label>
          ))}
        </span>
      );
      break;
    case "textarea":
    case "richtext":
    case "inline_richtext":
    case "html":
    case "liquid":
      control = (
        <textarea className="cl-field__input" id={inputId}
          onChange={(event) => onChange(event.target.value)}
          placeholder={def.placeholder} rows={3} value={String(effective ?? "")} />
      );
      break;
    case "color":
      control = HEX_RE.test(String(effective ?? "")) ? (
        <input id={inputId} onChange={(event) => onChange(event.target.value)}
          type="color" value={String(effective)} />
      ) : (
        <input className="cl-field__input" id={inputId}
          onChange={(event) => onChange(event.target.value)} value={String(effective ?? "")} />
      );
      break;
    case "text":
    case "url":
    case "video_url":
    case "color_background":
    case "font_picker":
      control = (
        <input className="cl-field__input" id={inputId}
          onChange={(event) => onChange(event.target.value)}
          placeholder={def.placeholder} value={String(effective ?? "")} />
      );
      break;
    default:
      // 資源選擇器（image_picker/product/collection/*_list…）＝16e 射程，先唯讀
      control = <code>{JSON.stringify(effective ?? null)}</code>;
  }

  return (
    <div className="cl-field">
      <label className="cl-field__label" htmlFor={inputId}>{label}</label>
      {control}
      {def.info ? <p className="cl-card-note">{def.info}</p> : null}
    </div>
  );
}

/** schema 未覆蓋鍵（或整型缺 schema）＝16b 原 typeof 分派，保持可編輯。 */
function FallbackControl({ name, value, onChange }: {
  name: string;
  value: unknown;
  onChange: (value: unknown) => void;
}) {
  const inputId = `setting-${name}`;
  return (
    <div className="cl-field">
      <label className="cl-field__label" htmlFor={inputId}>{name}</label>
      {typeof value === "boolean" ? (
        <input checked={value} id={inputId}
          onChange={(event) => onChange(event.target.checked)} type="checkbox" />
      ) : typeof value === "number" ? (
        <input className="cl-field__input" id={inputId}
          onChange={(event) => onChange(Number(event.target.value))} type="number" value={value} />
      ) : typeof value === "string" ? (
        <input className="cl-field__input" id={inputId}
          onChange={(event) => onChange(event.target.value)} value={value} />
      ) : (
        <code>{JSON.stringify(value)}</code>
      )}
    </div>
  );
}

const GROUP_TEMPLATE_TYPES = new Set([ "product", "collection", "page", "blog", "article" ]);

export function ThemeEditorPage() {
  const t = useT();
  const { showToast } = useToast();
  const navigate = useNavigate();
  const { themeId } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const templateKey = searchParams.get("template") ?? "index";
  const [data, setData] = useState<EditorData["theme"]>(null);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedBlockId, setSelectedBlockId] = useState<string | null>(null);
  const [draft, setDraft] = useState<TemplateJson | null>(null);
  // PR-5：三帶（24 §1 本尊樹形＝Header group／Template／Footer group）——
  // 群組 draft 與模板同語義（{sections, order}），寫回走 themeFileUpsert。
  const [groupDrafts, setGroupDrafts] = useState<Record<string, TemplateJson>>({});
  const [groupLocks, setGroupLocks] = useState<Record<string, number | null>>({});
  const [dirtyGroups, setDirtyGroups] = useState<string[]>([]);
  // PR-11：任何 draft 變更（section op／佈景設定／undo/redo）都 bump ⇒
  // 全頁草稿刷新 effect 的單一觸發源
  const [draftsVersion, setDraftsVersion] = useState(0);
  const [selectedBand, setSelectedBand] = useState<string>("template");
  const [undoStack, setUndoStack] = useState<{ band: string; snap: TemplateJson }[]>([]);
  const [redoStack, setRedoStack] = useState<{ band: string; snap: TemplateJson }[]>([]);
  const [lockVersion, setLockVersion] = useState<number | null>(null);
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [pickerQuery, setPickerQuery] = useState(""); // PR-19：⑤a picker 搜尋
  // E2：左欄面板（sections／theme／apps；本尊面板切換器）＋全寬預覽＋inspector＋手機檢視
  const [panel, setPanel] = useState<EditorPanel>("sections");
  const [fullscreen, setFullscreen] = useState(false);
  const [inspector, setInspector] = useState(true);
  const [mobilePreview, setMobilePreview] = useState(false);
  // E2：對話框（快捷鍵／離開／發布／建立模板）與佈景設定手風琴展開分類
  const [shortcutsOpen, setShortcutsOpen] = useState(false);
  const [leaveOpen, setLeaveOpen] = useState(false);
  const [publishOpen, setPublishOpen] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [createType, setCreateType] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [openCategory, setOpenCategory] = useState<string | null>(null);
  const [settingsDraft, setSettingsDraft] = useState<Record<string, unknown> | null>(null);
  const [settingsLock, setSettingsLock] = useState<number | null>(null);
  const [settingsDirty, setSettingsDirty] = useState(false);
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const draftRef = useRef<TemplateJson | null>(null);
  const groupDraftsRef = useRef<Record<string, TemplateJson>>({});
  const activeDraftRef = useRef<TemplateJson | null>(null);
  const settingsDraftRef = useRef<Record<string, unknown> | null>(null);
  draftRef.current = draft;
  groupDraftsRef.current = groupDrafts;
  activeDraftRef.current = selectedBand === "template" ? draft : groupDrafts[selectedBand] ?? null;
  settingsDraftRef.current = settingsDraft;

  const themeMode = panel === "theme";
  const gid = `gid://chilllove/Theme/${themeId}`;
  const dirtyAny = dirty || settingsDirty || dirtyGroups.length > 0;

  // PR-11 資源語境：模板型 → 樣本路徑（product 模板帶真商品）；無樣本回落首頁。
  // E2：URL `previewPath`（預覽內導航寫入）優先——本尊同名參數（100 §6）。
  const previewPath = searchParams.get("previewPath")
    ?? data?.previewPaths?.[splitTemplateKey(templateKey).type] ?? "/";

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<EditorData, { id: string; key: string }>(
        EDITOR_QUERY, { id: gid, key: templateKey }, signal);
      setData(result.theme);
      setDraft(result.theme?.templateJson ? cloneTpl(result.theme.templateJson) : null);
      setLockVersion(result.theme?.templateLockVersion ?? null);
      const groups = result.theme?.sectionGroups ?? [];
      setGroupDrafts(Object.fromEntries(groups.map((g) => [ g.name, cloneTpl(g.json) ])));
      setGroupLocks(Object.fromEntries(groups.map((g) => [ g.name, g.lockVersion ])));
      setDirtyGroups([]);
      setSelectedBand("template");
      setSettingsDraft(result.theme ? { ...result.theme.themeSettingsJson } : null);
      setSettingsLock(result.theme?.themeSettingsLockVersion ?? null);
      setSettingsDirty(false);
      setUndoStack([]);
      setRedoStack([]);
      setDirty(false);
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

  // PR-15／E2：編輯器狀態 URL 化（本尊 100 §6：section／block／context／previewMode／
  // category 皆為 query 參數，可重載還原）。初載還原一次。
  const restoredRef = useRef(false);
  useEffect(() => {
    if (restoredRef.current || !data) return;
    restoredRef.current = true;
    const section = searchParams.get("section");
    const block = searchParams.get("block");
    const context = searchParams.get("context");
    if (searchParams.get("previewMode") === "fullscreen") setFullscreen(true);
    if (searchParams.get("category")) setOpenCategory(searchParams.get("category"));
    if (context === "theme" || context === "apps") {
      setPanel(context);
    } else if (section) {
      setSelectedId(section);
      setSelectedBlockId(block);
      setSelectedBand(
        draftRef.current?.sections?.[section]
          ? "template"
          : Object.entries(groupDraftsRef.current).find(([ , tpl ]) => tpl.sections?.[section])?.[0] ?? "template",
      );
    }
  }, [data, searchParams]);

  const syncStateParams = (patch: Record<string, string | null>) => {
    setSearchParams((current) => {
      const next = new URLSearchParams(current);
      for (const [ key, value ] of Object.entries(patch)) {
        if (value === null) next.delete(key);
        else next.set(key, value);
      }
      return next;
    }, { replace: true });
  };

  /** 選中 section（＋block）：三處同步——state、URL、面板回 sections。 */
  const selectNode = (band: string, sectionId: string, blockId: string | null) => {
    setSelectedBand(band);
    setSelectedId(sectionId);
    setSelectedBlockId(blockId);
    setPanel("sections");
    syncStateParams({ section: sectionId, block: blockId, context: null });
  };

  const deselect = () => {
    setSelectedId(null);
    setSelectedBlockId(null);
    syncStateParams({ section: null, block: null });
  };

  const switchPanel = (next: EditorPanel) => {
    setPanel(next);
    setFullscreen(false);
    const patch: Record<string, string | null> = { context: next === "sections" ? null : next, previewMode: null };
    if (next !== "sections") {
      // 本尊：切到佈景設定／app embeds 即取消選取（右欄收起）
      setSelectedId(null);
      setSelectedBlockId(null);
      patch.section = null;
      patch.block = null;
    }
    syncStateParams(patch);
  };

  const toggleFullscreen = () => {
    setFullscreen((on) => {
      syncStateParams({ previewMode: on ? null : "fullscreen" });
      return !on;
    });
  };

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== window.location.origin) return;
      const payload = event.data as { type?: string; id?: string; blockId?: string };
      if (payload?.type === "cl:navigate" && typeof (payload as { path?: string }).path === "string") {
        const path = (payload as { path: string }).path;
        const frame = iframeRef.current;
        if (frame) frame.src = `/admin/store/preview/${themeId}${path}?editor=1`;
        const inferred = templateForPath(path);
        syncStateParams({ previewPath: path, section: null, block: null,
                          ...(inferred !== templateKey ? { template: inferred } : {}) });
        return;
      }
      if (payload?.type === "cl:op" && payload.id) {
        const op = (payload as { op?: string }).op;
        const id = payload.id;
        const band = draftRef.current?.sections?.[id]
          ? "template"
          : Object.entries(groupDraftsRef.current).find(([ , tpl ]) => tpl.sections?.[id])?.[0];
        if (!band) return;
        if (op === "up") moveSection(band, id, -1);
        else if (op === "down") moveSection(band, id, 1);
        else if (op === "duplicate") duplicateSection(band, id);
        else if (op === "remove") { removeSection(band, id); setSelectedId((cur) => (cur === id ? null : cur)); }
        return;
      }
      if (payload?.type === "cl:select" && payload.id) {
        setSelectedId(payload.id);
        setSelectedBlockId(payload.blockId ?? null); // PR-17：預覽點 block ⇒ 直開 block 面板
        // PR-5：預覽點選可能是群組 section——跨帶定位
        setSelectedBand((current) => {
          if (draftRef.current?.sections?.[payload.id!]) return "template";
          const hit = Object.entries(groupDraftsRef.current)
            .find(([ , tpl ]) => tpl.sections?.[payload.id!]);
          return hit ? hit[0] : current;
        });
        setPanel("sections");
        syncStateParams({ section: payload.id, block: payload.blockId ?? null, context: null });
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    iframeRef.current?.contentWindow?.postMessage(
      { type: "cl:highlight", id: selectedId, blockId: selectedBlockId }, window.location.origin);
  }, [selectedId, selectedBlockId]);

  // E2：inspector 開關送進預覽（E6 的橋消費 `cl:inspector`；本包只維持狀態與訊息形）
  useEffect(() => {
    iframeRef.current?.contentWindow?.postMessage(
      { type: "cl:inspector", active: inspector }, window.location.origin);
  }, [inspector]);

  // PR-7 即時預覽：選中 section 的 entry 一變（設定/block 操作），debounce 400ms
  // 以未儲存 entry 渲染片段 → cl:replace 換進 iframe（本尊「改即見」對位）。
  const selectedEntryJson = selectedId && activeDraftRef.current?.sections?.[selectedId]
    ? JSON.stringify(activeDraftRef.current.sections[selectedId]) : null;
  useEffect(() => {
    if (!selectedId || !selectedEntryJson || themeMode) return;
    const handle = window.setTimeout(() => {
      void (async () => {
        try {
          const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") ?? "";
          const path = previewPath;
          const response = await fetch(`/admin/store/preview/${themeId}/draft_section`, {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
            body: JSON.stringify({ path, section_id: selectedId,
                                   entry: JSON.parse(selectedEntryJson) as unknown }),
          });
          if (!response.ok) return;
          const html = await response.text();
          iframeRef.current?.contentWindow?.postMessage(
            { type: "cl:replace", id: selectedId, html }, window.location.origin);
        } catch {
          // 即時預覽是增強面——失敗靜默（儲存路徑不受影響）
        }
      })();
    }, 400);
    return () => window.clearTimeout(handle);
  }, [selectedEntryJson, selectedId, selectedBand, themeMode, themeId, previewPath]);

  // PR-11：全頁草稿刷新——結構操作/佈景設定/undo/redo 的改即見（fleet
  // editor-live 軸①②③統一通道）。debounce 600ms；srcdoc 換入（srcdoc 繼承父
  // origin ⇒ postMessage 橋照常）；保留捲動位置。單 section 設定變更另有
  // draft_section 片段 fast-path（400ms）先行，全頁刷新殿後兜底。失敗靜默。
  useEffect(() => {
    if (draftsVersion === 0) return;
    const handle = window.setTimeout(() => {
      void (async () => {
        try {
          const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") ?? "";
          const merged: Record<string, unknown> = { ...(draftRef.current?.sections ?? {}) };
          for (const tpl of Object.values(groupDraftsRef.current)) {
            Object.assign(merged, tpl.sections ?? {});
          }
          const response = await fetch(`/admin/store/preview/${themeId}/draft_page`, {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
            body: JSON.stringify({ path: previewPath, sections: merged,
                                   settings: settingsDraftRef.current ?? {} }),
          });
          if (!response.ok) return;
          const html = await response.text();
          const frame = iframeRef.current;
          if (!frame) return;
          const scrollY = frame.contentWindow?.scrollY ?? 0;
          frame.srcdoc = html;
          frame.addEventListener("load", () => {
            frame.contentWindow?.scrollTo(0, scrollY);
          }, { once: true });
        } catch {
          // 靜默：改即見是增強面
        }
      })();
    }, 600);
    return () => window.clearTimeout(handle);
  }, [draftsVersion, themeId, previewPath]);

  /** 每個 op 先推快照（undo 棧＝跨帶 {band, snap}）再改該帶 draft；
   *  redo 棧清空（14 §F3 快照棧語義；PR-5 band 化——群組與模板同一棧）。 */
  const applyOp = useCallback((band: string, mutator: (tpl: TemplateJson) => void) => {
    const write = (current: TemplateJson | null): TemplateJson | null => {
      if (!current) return current;
      setUndoStack((stack) => [ ...stack.slice(-49), { band, snap: cloneTpl(current) } ]);
      setRedoStack([]);
      const next = cloneTpl(current);
      mutator(next);
      return next;
    };
    if (band === "template") {
      setDraft((current) => write(current));
      setDirty(true);
    } else {
      setGroupDrafts((current) => {
        const next = write(current[band] ?? null);
        return next ? { ...current, [band]: next } : current;
      });
      setDirtyGroups((current) => (current.includes(band) ? current : [ ...current, band ]));
    }
    setDraftsVersion((v) => v + 1);
  }, []);

  const restoreBand = (band: string, snap: TemplateJson): TemplateJson | null => {
    // 回傳被覆蓋前的現值（推入對向棧）
    if (band === "template") {
      const current = draftRef.current;
      setDraft(snap);
      setDirty(true);
      return current;
    }
    const current = groupDraftsRef.current[band] ?? null;
    setGroupDrafts((all) => ({ ...all, [band]: snap }));
    setDirtyGroups((all) => (all.includes(band) ? all : [ ...all, band ]));
    return current;
  };

  // undo/redo 也驅動預覽（fleet editor-live 軸③）
  const bumpDrafts = () => setDraftsVersion((v) => v + 1);

  const undo = () => {
    setUndoStack((stack) => {
      if (stack.length === 0) return stack;
      const { band, snap } = stack[stack.length - 1];
      const previous = restoreBand(band, snap);
      if (previous) setRedoStack((redoS) => [ ...redoS, { band, snap: cloneTpl(previous) } ]);
      return stack.slice(0, -1);
    });
    bumpDrafts();
  };

  const redo = () => {
    setRedoStack((stack) => {
      if (stack.length === 0) return stack;
      const { band, snap } = stack[stack.length - 1];
      const previous = restoreBand(band, snap);
      if (previous) setUndoStack((undoS) => [ ...undoS, { band, snap: cloneTpl(previous) } ]);
      return stack.slice(0, -1);
    });
    bumpDrafts();
  };

  const orderOf = (tpl: TemplateJson) => tpl.order ?? Object.keys(tpl.sections ?? {});

  const toggleDisabled = (band: string, sectionId: string) => applyOp(band, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (entry) entry.disabled = !entry.disabled; // 隱藏不是刪除（24 §3）
  });

  const removeSection = (band: string, sectionId: string) => applyOp(band, (tpl) => {
    if (tpl.sections) delete tpl.sections[sectionId];
    tpl.order = orderOf(tpl).filter((id) => id !== sectionId);
    if (selectedId === sectionId) setSelectedId(null);
  });

  // PR-26：拖放的任意位置插入（同帶；applyOp ⇒ undo/改即見/儲存全繼承）
  const moveSectionTo = (band: string, sectionId: string, targetIndex: number) => applyOp(band, (tpl) => {
    const order = [ ...orderOf(tpl) ];
    const from = order.indexOf(sectionId);
    if (from < 0) return;
    order.splice(from, 1);
    const bounded = Math.max(0, Math.min(targetIndex, order.length));
    order.splice(bounded, 0, sectionId);
    tpl.order = order;
  });

  const dragRef = useRef<{ band: string; sectionId: string } | null>(null);

  const moveSection = (band: string, sectionId: string, direction: -1 | 1) => applyOp(band, (tpl) => {
    const order = [ ...orderOf(tpl) ];
    const index = order.indexOf(sectionId);
    const target = index + direction;
    if (index < 0 || target < 0 || target >= order.length) return;
    [ order[index], order[target] ] = [ order[target], order[index] ];
    tpl.order = order;
  });

  const duplicateSection = (band: string, sectionId: string) => applyOp(band, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (!entry || !tpl.sections) return;
    let copyId = `${sectionId}-copy`;
    let n = 1;
    while (tpl.sections[copyId]) copyId = `${sectionId}-copy-${n++}`;
    tpl.sections[copyId] = JSON.parse(JSON.stringify(entry)) as SectionEntry;
    const order = [ ...orderOf(tpl) ];
    order.splice(order.indexOf(sectionId) + 1, 0, copyId);
    tpl.order = order;
  });

  /** add-section（24 §3：新 entry 內容取 preset；插到尾端＋order）。 */
  const addSection = (catalogEntry: NonNullable<EditorData["theme"]>["sectionCatalog"][number]) => {
    applyOp("template", (tpl) => {
      tpl.sections ??= {};
      let newId = catalogEntry.type;
      let n = 1;
      while (tpl.sections[newId]) newId = `${catalogEntry.type}-${n++}`;
      const entry: SectionEntry = {
        type: catalogEntry.type,
        settings: JSON.parse(JSON.stringify(catalogEntry.preset.settings)) as Record<string, unknown>,
      };
      if (catalogEntry.preset.blocks) {
        entry.blocks = JSON.parse(JSON.stringify(catalogEntry.preset.blocks)) as SectionEntry["blocks"];
        entry.block_order = Object.keys(entry.blocks ?? {});
      }
      tpl.sections[newId] = entry;
      tpl.order = [ ...orderOf(tpl), newId ];
      setSelectedId(newId);
      setSelectedBand("template");
    });
    setPickerOpen(false);
  };

  // ── PR-6：block 級操作（24 §3 同語義向下一層；全部走 applyOp 快照棧）──
  const addBlock = (band: string, sectionId: string, def: BlockDef) => applyOp(band, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (!entry) return;
    entry.blocks ??= {};
    entry.block_order ??= [];
    let newId = def.type;
    let n = 1;
    while (entry.blocks[newId]) newId = `${def.type}-${n++}`;
    const defaults = Object.fromEntries((def.settings ?? [])
      .filter((d) => d.id && d.default !== undefined)
      .map((d) => [ d.id as string, d.default ]));
    entry.blocks[newId] = { type: def.type, settings: defaults };
    entry.block_order = [ ...entry.block_order, newId ];
    setSelectedBand(band);
    setSelectedId(sectionId);
    setSelectedBlockId(newId);
  });

  const removeBlock = (band: string, sectionId: string, blockId: string) => applyOp(band, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (!entry?.blocks) return;
    delete entry.blocks[blockId];
    entry.block_order = (entry.block_order ?? []).filter((id) => id !== blockId);
    if (selectedBlockId === blockId) setSelectedBlockId(null);
  });

  // PR-27：block 拖放任意位置（同 section；applyOp 全繼承——PR-26 同構）
  const moveBlockTo = (band: string, sectionId: string, blockId: string, targetIndex: number) => applyOp(band, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    const order = [ ...(entry?.block_order ?? []) ];
    const from = order.indexOf(blockId);
    if (!entry || from < 0) return;
    order.splice(from, 1);
    const bounded = Math.max(0, Math.min(targetIndex, order.length));
    order.splice(bounded, 0, blockId);
    entry.block_order = order;
  });

  const blockDragRef = useRef<{ band: string; sectionId: string; blockId: string } | null>(null);

  const moveBlock = (band: string, sectionId: string, blockId: string, direction: -1 | 1) => applyOp(band, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    const order = [ ...(entry?.block_order ?? []) ];
    const index = order.indexOf(blockId);
    const target = index + direction;
    if (!entry || index < 0 || target < 0 || target >= order.length) return;
    [ order[index], order[target] ] = [ order[target], order[index] ];
    entry.block_order = order;
  });

  const setBlockSetting = (settingKey: string, value: unknown) => applyOp(selectedBand, (tpl) => {
    const block = selectedId && selectedBlockId
      ? tpl.sections?.[selectedId]?.blocks?.[selectedBlockId] : null;
    if (!block) return;
    block.settings = { ...(block.settings ?? {}), [settingKey]: value };
  });

  /** 佈景設定寫值（16d2）：獨立 draft，不進模板快照棧（undo 整合＝16e）。 */
  const setThemeSetting = (settingKey: string, value: unknown) => {
    setSettingsDraft((current) => (current ? { ...current, [settingKey]: value } : current));
    setSettingsDirty(true);
    setDraftsVersion((v) => v + 1); // PR-11：佈景設定也改即見
  };

  const setSetting = (sectionId: string, settingKey: string, value: unknown) => applyOp(selectedBand, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (!entry) return;
    entry.settings = { ...(entry.settings ?? {}), [settingKey]: value };
  });

  /** 儲存三面（模板／佈景設定／群組）；回傳是否全部成功（Publish 先存再發布要看這個）。 */
  const save = async (): Promise<boolean> => {
    if (saving || !dirtyAny) return !dirtyAny;
    setSaving(true);
    try {
      if (dirty && draft) {
        const result = await requestAdminGraphQL<{
          themeTemplateUpsert: { templateKey: string | null; lockVersion: number | null;
                                 userErrors: { message: string; code: string }[] };
        }, Record<string, unknown>>(SAVE_MUTATION, {
          themeId: gid, key: templateKey, content: draft, lockVersion,
        });
        const payload = result.themeTemplateUpsert;
        if (payload.userErrors.length > 0) {
          const firstError = payload.userErrors[0];
          showToast(firstError.code === "STALE_OBJECT" ? t("editor.staleConflict") : firstError.message);
          return false;
        }
        setLockVersion(payload.lockVersion);
        setUndoStack([]); // Save 後清空（24 §3 Undo 僅未儲存變更）
        setRedoStack([]);
        setDirty(false);
      }
      // 16d2：佈景設定另走 themeSettingsUpsert（同樣後端 touch theme）
      if (settingsDirty && settingsDraft) {
        const result = await requestAdminGraphQL<{
          themeSettingsUpsert: { lockVersion: number | null;
                                 userErrors: { message: string; code: string }[] };
        }, Record<string, unknown>>(SETTINGS_MUTATION, {
          themeId: gid, settings: settingsDraft, lockVersion: settingsLock,
        });
        const payload = result.themeSettingsUpsert;
        if (payload.userErrors.length > 0) {
          const firstError = payload.userErrors[0];
          showToast(firstError.code === "STALE_OBJECT" ? t("editor.staleConflict") : firstError.message);
          return false;
        }
        setSettingsLock(payload.lockVersion);
        setSettingsDirty(false);
      }
      // PR-5：群組 JSON 寫回（16e1 檔案覆寫層——後端 touch theme 同軸）
      for (const name of dirtyGroups) {
        const tpl = groupDrafts[name];
        if (!tpl) continue;
        const result = await requestAdminGraphQL<{
          themeFileUpsert: { path: string | null; lockVersion: number | null;
                             userErrors: { message: string; code: string }[] };
        }, Record<string, unknown>>(GROUP_SAVE_MUTATION, {
          themeId: gid, path: `sections/${name}.json`,
          content: JSON.stringify({ sections: tpl.sections ?? {}, order: tpl.order ?? [] }, null, 2),
          lockVersion: groupLocks[name] ?? null,
        });
        const payload = result.themeFileUpsert;
        if (payload.userErrors.length > 0) {
          const firstError = payload.userErrors[0];
          showToast(firstError.code === "STALE_OBJECT" ? t("editor.staleConflict") : firstError.message);
          return false;
        }
        setGroupLocks((locks) => ({ ...locks, [name]: payload.lockVersion }));
      }
      setDirtyGroups([]);
      showToast(t("editor.saved"));
      // 後端已 touch theme（頁快取鍵旋轉）；重載 iframe 看到存檔後渲染
      iframeRef.current?.contentWindow?.location.reload();
      return true;
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("editor.saveFailed"));
      return false;
    } finally {
      setSaving(false);
    }
  };

  /** E2 Publish（本尊 "Save and publish …?"）：先存（有變更時）再 themePublish；成功重載資料。 */
  const publish = async () => {
    setPublishing(true);
    try {
      if (dirtyAny) {
        const ok = await save();
        if (!ok) return;
      }
      const result = await requestAdminGraphQL<{
        themePublish: { theme: { id: string; role: string } | null;
                        userErrors: { message: string; code: string }[] };
      }, { id: string }>(PUBLISH_MUTATION, { id: gid });
      const firstError = result.themePublish.userErrors[0];
      if (firstError) {
        showToast(firstError.message || t("editor.publishFailed"));
        return;
      }
      setData((current) => (current ? { ...current, role: "published" } : current));
      showToast(t("editor.published"));
      setPublishOpen(false);
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("editor.publishFailed"));
    } finally {
      setPublishing(false);
    }
  };

  /** E2 Create template：base 模板 JSON → themeTemplateUpsert(`type.name`) → 切到新模板。 */
  const createTemplate = async (name: string, baseKey: string) => {
    if (!createType) return;
    setCreating(true);
    try {
      const base = await requestAdminGraphQL<{ theme: { templateJson: TemplateJson | null } | null },
        { id: string; key: string }>(BASE_TEMPLATE_QUERY, { id: gid, key: baseKey });
      const content = base.theme?.templateJson ?? { sections: {}, order: [] };
      const key = `${createType}.${name}`;
      const result = await requestAdminGraphQL<{
        themeTemplateUpsert: { templateKey: string | null; userErrors: { message: string; code: string }[] };
      }, Record<string, unknown>>(SAVE_MUTATION, { themeId: gid, key, content, lockVersion: null });
      const firstError = result.themeTemplateUpsert.userErrors[0];
      if (firstError) {
        showToast(firstError.message);
        return;
      }
      showToast(t("editor.templateCreated"));
      setCreateType(null);
      syncStateParams({ template: key, section: null, block: null, previewPath: null });
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("editor.saveFailed"));
    } finally {
      setCreating(false);
    }
  };

  const requestExit = () => {
    if (dirtyAny) setLeaveOpen(true);
    else navigate("/admin/store");
  };

  // E2：快捷鍵——單一表 `editorShortcuts`；effect 只掛一次，經 ref 取最新動作。
  // 輸入控件內不攔 undo/redo/remove/hide/deselect（讓瀏覽器原生文字編輯先行）；
  // modal 開著（#admin-root inert）時全部不攔——對話框自己管 Escape。
  const actionsRef = useRef<Record<string, () => void>>({});
  actionsRef.current = {
    undo, redo,
    save: () => { void save(); },
    seeAll: () => setShortcutsOpen(true),
    previewInspector: () => setInspector((on) => !on),
    previewMode: () => setMobilePreview((on) => !on),
    sections: () => switchPanel("sections"),
    themeSettings: () => switchPanel("theme"),
    appEmbeds: () => switchPanel("apps"),
    hideShow: () => { if (selectedId) toggleDisabled(selectedBand, selectedId); },
    remove: () => {
      if (!selectedId) return;
      if (selectedBlockId) removeBlock(selectedBand, selectedId, selectedBlockId);
      else { removeSection(selectedBand, selectedId); deselect(); }
    },
    deselect: () => { if (selectedId) deselect(); },
  };
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      // modal 開著 ⇒ 不攔（Modal 原語：#admin-root inert＋role=dialog aria-modal；兩個訊號任一成立即停）
      if (document.getElementById("admin-root")?.hasAttribute("inert")) return;
      if (document.querySelector('[role="dialog"][aria-modal="true"]')) return;
      const id = shortcutFor(event);
      if (!id) return;
      if (isTypingTarget(event.target) &&
          [ "undo", "redo", "remove", "hideShow", "deselect" ].includes(id)) return;
      event.preventDefault();
      actionsRef.current[id]?.();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const templateKeys = useMemo(() => {
    const fromFiles = (data?.templates ?? [])
      .map((file) => file.filename.replace(/^templates\//, "").replace(/\.json$/, ""))
      .filter((key) => !key.includes("/"));
    return [ ...new Set([ ...(data?.templateKeys ?? []), ...fromFiles ]) ].sort();
  }, [data]);

  // Create template 的 base 候選（預設＋同型替代）；memo 以免對話框每 render 收到新陣列
  const createBaseKeys = useMemo(
    () => (createType ? templateKeys.filter((key) => splitTemplateKey(key).type === createType) : []),
    [ createType, templateKeys ],
  );

  const templateLabel = (() => {
    const { type, suffix } = splitTemplateKey(templateKey);
    if (suffix) return suffix;
    return GROUP_TEMPLATE_TYPES.has(type) ? t(`editor.tplDefault.${type}`) : t(`editor.tpl.${type}`);
  })();

  const activeDraft = selectedBand === "template" ? draft : groupDrafts[selectedBand] ?? null;
  const selected = selectedId && activeDraft?.sections ? activeDraft.sections[selectedId] : null;
  const previewSrc = `/admin/store/preview/${themeId}${previewPath === "/" ? "" : previewPath}?editor=1`;
  const hasRightPanel = panel === "sections" && Boolean(selected && selectedId);

  if (error) {
    return (
      <div className="cl-editor cl-editor--error">
        <p>{error}</p>
        <Link to="/admin/store">{t("editor.back")}</Link>
      </div>
    );
  }

  const rootClass = [
    "cl-editor",
    fullscreen ? "cl-editor--fullscreen" : "",
    !fullscreen && hasRightPanel ? "cl-editor--with-panel" : "",
  ].filter(Boolean).join(" ");

  return (
    <div className={rootClass}>
      <EditorTopBar
        assignments={data?.templateAssignments ?? {}}
        canRedo={redoStack.length > 0}
        canUndo={undoStack.length > 0}
        codeHref={`/admin/themes/${themeId}/code`}
        dirty={dirtyAny}
        fullscreen={fullscreen}
        inspector={inspector}
        mobile={mobilePreview}
        onCreateTemplate={(type) => setCreateType(type)}
        onExit={requestExit}
        onFullscreen={toggleFullscreen}
        onInspector={() => setInspector((on) => !on)}
        onMobile={() => setMobilePreview((on) => !on)}
        onPanel={switchPanel}
        onPublish={() => setPublishOpen(true)}
        onRedo={redo}
        onSave={() => { void save(); }}
        onShortcuts={() => setShortcutsOpen(true)}
        onTemplate={(key) => syncStateParams({ template: key, section: null, block: null, previewPath: null })}
        onUndo={undo}
        panel={panel}
        previewHref={`/?preview_theme_id=${themeId}`}
        role={data?.role ?? "draft"}
        saving={saving}
        templateKey={templateKey}
        templateKeys={templateKeys}
        themeName={data?.name ?? t("common.loading")}
      />
      {saving ? <div aria-hidden="true" className="cl-editor__progress" /> : null}

      <div className="cl-editor__panels">
        {fullscreen ? null : panel === "sections" ? (
          <aside aria-label={t("editor.sectionsTree")} className="cl-editor__sidebar cl-editor__tree">
            <div className="cl-editor__paneltitle"><h3>{templateLabel}</h3></div>
            <div className="cl-editor__panelbody">
              <Button onClick={() => setPickerOpen((open) => !open)} size="small">
                {t("editor.addSection")}
              </Button>
              {pickerOpen ? (
                <ul aria-label={t("editor.sectionPicker")} className="cl-editor__picker">
                  <li>
                    <input
                      aria-label={t("editor.pickerSearch")}
                      className="cl-field__input"
                      onChange={(event) => setPickerQuery(event.target.value)}
                      placeholder={t("editor.pickerSearch")}
                      value={pickerQuery}
                    />
                  </li>
                  {(data?.sectionCatalog ?? []).length === 0 ? (
                    <li className="cl-card-note">{t("editor.pickerEmpty")}</li>
                  ) : (
                    (data?.sectionCatalog ?? [])
                      .filter((entry) => {
                        const q = pickerQuery.trim().toLowerCase();
                        return !q || entry.name.toLowerCase().includes(q) || entry.type.toLowerCase().includes(q);
                      })
                      .map((entry) => (
                      <li key={entry.type}>
                        <button className="cl-editor__node" onClick={() => addSection(entry)} type="button">
                          {entry.name}
                        </button>
                      </li>
                    ))
                  )}
                </ul>
              ) : null}
              {(() => {
                // PR-5 三帶（24 §1 本尊樹形）：header 群組帶 → 範本帶 → 其餘群組帶
                const groups = data?.sectionGroups ?? [];
                const headerGroups = groups.filter((g) => g.name.includes("header"));
                const otherGroups = groups.filter((g) => !g.name.includes("header"));

                const renderRows = (band: string, tpl: TemplateJson | null) => {
                  const rows = tpl ? (tpl.order ?? Object.keys(tpl.sections ?? {})) : [];
                  if (rows.length === 0) return <p className="cl-card-note">{t("editor.noSections")}</p>;
                  return (
                    <ul>
                      {rows.map((sectionId, index) => {
                        const entry = tpl?.sections?.[sectionId];
                        if (!entry) return null;
                        const isActive = selectedBand === band && selectedId === sectionId;
                        return (
                          <li
                            draggable
                            key={`${band}:${sectionId}`}
                            onDragOver={(event) => {
                              if (dragRef.current?.band === band) event.preventDefault();
                            }}
                            onDragStart={() => { dragRef.current = { band, sectionId }; }}
                            onDrop={(event) => {
                              event.preventDefault();
                              const drag = dragRef.current;
                              dragRef.current = null;
                              if (!drag || drag.band !== band || drag.sectionId === sectionId) return;
                              moveSectionTo(band, drag.sectionId, index); // 放到目標列位置
                            }}
                          >
                            <div className="cl-editor__noderow">
                              <button
                                aria-pressed={isActive}
                                className={isActive ? "cl-editor__node cl-editor__node--active" : "cl-editor__node"}
                                onClick={() => selectNode(band, sectionId, null)}
                                type="button"
                              >
                                {entry.type}
                              </button>
                              <button aria-label={t("editor.moveUp", { id: sectionId })} className="cl-editor__op" disabled={index === 0} onClick={() => moveSection(band, sectionId, -1)} type="button"><ArrowUp size={13} /></button>
                              <button aria-label={t("editor.moveDown", { id: sectionId })} className="cl-editor__op" disabled={index === rows.length - 1} onClick={() => moveSection(band, sectionId, 1)} type="button"><ArrowDown size={13} /></button>
                              <button aria-label={entry.disabled ? t("editor.show", { id: sectionId }) : t("editor.hide", { id: sectionId })} className="cl-editor__op" onClick={() => toggleDisabled(band, sectionId)} type="button">
                                {entry.disabled ? <EyeOff size={13} /> : <Eye size={13} />}
                              </button>
                              <button aria-label={t("editor.duplicateOp", { id: sectionId })} className="cl-editor__op" onClick={() => duplicateSection(band, sectionId)} type="button"><Copy size={13} /></button>
                              <button aria-label={t("editor.removeOp", { id: sectionId })} className="cl-editor__op" onClick={() => removeSection(band, sectionId)} type="button"><Trash2 size={13} /></button>
                            </div>
                            {(() => {
                              const blockDefs = data?.sectionSchemas?.[entry.type]?.blocks ?? [];
                              const maxBlocks = data?.sectionSchemas?.[entry.type]?.max_blocks ?? 50;
                              const blockOrder = entry.block_order ?? [];
                              return (
                                <ul>
                                  {blockOrder.map((blockId, blockIndex) => {
                                    const blockActive = selectedBand === band && selectedId === sectionId && selectedBlockId === blockId;
                                    return (
                                      <li
                                        className="cl-editor__block"
                                        draggable
                                        key={blockId}
                                        onDragOver={(event) => {
                                          const drag = blockDragRef.current;
                                          if (drag && drag.band === band && drag.sectionId === sectionId) {
                                            event.preventDefault();
                                            event.stopPropagation();
                                          }
                                        }}
                                        onDragStart={(event) => {
                                          event.stopPropagation(); // 別讓 section li 也進入拖曳
                                          blockDragRef.current = { band, sectionId, blockId };
                                        }}
                                        onDrop={(event) => {
                                          event.preventDefault();
                                          event.stopPropagation();
                                          const drag = blockDragRef.current;
                                          blockDragRef.current = null;
                                          if (!drag || drag.band !== band || drag.sectionId !== sectionId ||
                                              drag.blockId === blockId) return;
                                          moveBlockTo(band, sectionId, drag.blockId, blockIndex);
                                        }}
                                      >
                                        <button
                                          aria-pressed={blockActive}
                                          className={blockActive ? "cl-editor__node cl-editor__node--active" : "cl-editor__node"}
                                          onClick={() => selectNode(band, sectionId, blockId)}
                                          type="button"
                                        >
                                          {entry.blocks?.[blockId]?.type ?? blockId}
                                        </button>
                                        <button aria-label={t("editor.blockUp", { id: blockId })} className="cl-editor__op" disabled={blockIndex === 0} onClick={() => moveBlock(band, sectionId, blockId, -1)} type="button"><ArrowUp size={12} /></button>
                                        <button aria-label={t("editor.blockDown", { id: blockId })} className="cl-editor__op" disabled={blockIndex === blockOrder.length - 1} onClick={() => moveBlock(band, sectionId, blockId, 1)} type="button"><ArrowDown size={12} /></button>
                                        <button aria-label={t("editor.blockRemove", { id: blockId })} className="cl-editor__op" onClick={() => removeBlock(band, sectionId, blockId)} type="button"><Trash2 size={12} /></button>
                                      </li>
                                    );
                                  })}
                                  {blockDefs.length > 0 && blockOrder.length < maxBlocks ? (
                                    <li className="cl-editor__block">
                                      {blockDefs.map((def) => (
                                        <button
                                          className="cl-editor__addblock"
                                          key={def.type}
                                          onClick={() => addBlock(band, sectionId, def)}
                                          type="button"
                                        >
                                          ＋ {def.name ?? def.type}
                                        </button>
                                      ))}
                                    </li>
                                  ) : null}
                                </ul>
                              );
                            })()}
                          </li>
                        );
                      })}
                    </ul>
                  );
                };

                return (
                  <>
                    {headerGroups.map((g) => (
                      <section key={g.name}>
                        <h4 className="cl-editor__band">{t("editor.headerBand")}</h4>
                        {renderRows(g.name, groupDrafts[g.name] ?? null)}
                      </section>
                    ))}
                    <h4 className="cl-editor__band">{t("editor.templateBand")}</h4>
                    {renderRows("template", draft)}
                    {otherGroups.map((g) => (
                      <section key={g.name}>
                        <h4 className="cl-editor__band">{g.name.includes("footer") ? t("editor.footerBand") : g.name}</h4>
                        {renderRows(g.name, groupDrafts[g.name] ?? null)}
                      </section>
                    ))}
                  </>
                );
              })()}
            </div>
          </aside>
        ) : panel === "theme" ? (
          <aside aria-label={t("editor.themeSettings")} className="cl-editor__sidebar">
            <div className="cl-editor__paneltitle"><h3>{t("editor.themeSettings")}</h3></div>
            <div className="cl-editor__panelbody">
              {/* E2：本尊佈景設定＝左欄手風琴分類（100 §7）；展開分類寫進 URL `category` */}
              {(data?.settingsSchema ?? []).map((group) => (
                <details
                  className="cl-editor__acc"
                  key={group.name}
                  onToggle={(event) => {
                    const open = (event.currentTarget as HTMLDetailsElement).open;
                    setOpenCategory((current) => (open ? group.name : current === group.name ? null : current));
                    syncStateParams({ category: open ? group.name : null });
                  }}
                  open={openCategory === group.name}
                >
                  <summary>{group.name}</summary>
                  {group.settings.map((def, index) => (
                    <SettingControl
                      def={def}
                      key={def.id ?? `static-${index}`}
                      onChange={(value) => def.id && setThemeSetting(def.id, value)}
                      value={def.id ? (settingsDraft ?? {})[def.id] : undefined}
                    />
                  ))}
                </details>
              ))}
              {/* PR-19：theme 級 Custom CSS（官方 Theme settings → Custom CSS；
                  1500 字上限；存 platform_customizations 對位） */}
              <details className="cl-editor__acc cl-editor__customcss">
                <summary>{t("editor.customCss")}</summary>
                <textarea
                  aria-label={t("editor.customCss")}
                  className="cl-field__input"
                  maxLength={1500}
                  onChange={(event) =>
                    setThemeSetting("platform_customizations", { custom_css: event.target.value })}
                  rows={5}
                  value={String(
                    ((settingsDraft ?? {}).platform_customizations as { custom_css?: string } | undefined)
                      ?.custom_css ?? "",
                  )}
                />
              </details>
            </div>
          </aside>
        ) : (
          <aside aria-label={t("editor.panelApps")} className="cl-editor__sidebar">
            <div className="cl-editor__paneltitle"><h3>{t("editor.panelApps")}</h3></div>
            <div className="cl-editor__panelbody">
              <div className="cl-editor__menusearch">
                <Search aria-hidden="true" size={14} />
                <input aria-label={t("editor.appsSearch")} placeholder={t("editor.appsSearch")} />
              </div>
              <p className="cl-editor__empty">{t("editor.appsEmpty")}</p>
            </div>
          </aside>
        )}

        <main className="cl-editor__preview">
          <iframe
            className={mobilePreview ? "cl-editor__iframe cl-editor__iframe--mobile" : "cl-editor__iframe"}
            ref={iframeRef}
            src={previewSrc}
            style={mobilePreview ? { width: 390 } : undefined}
            title={t("editor.previewTitle")}
          />
        </main>

        {!fullscreen && hasRightPanel && selected && selectedId ? (
          <aside aria-label={t("editor.settingsPanel")} className="cl-editor__settings">
            <div className="cl-editor__paneltitle">
              <h3>{selectedBlockId ? (selected.blocks?.[selectedBlockId]?.type ?? selectedBlockId) : (data?.sectionSchemas?.[selected.type]?.name ?? selected.type)}</h3>
              <button aria-label={t("common.close")} className="cl-editor__iconbtn" onClick={deselect} type="button">
                <X aria-hidden="true" size={16} />
              </button>
            </div>
            <div className="cl-editor__panelbody">
              {selectedBlockId ? (
                (() => {
                  const block = selected.blocks?.[selectedBlockId];
                  const blockDef = (data?.sectionSchemas?.[selected.type]?.blocks ?? [])
                    .find((d) => d.type === block?.type);
                  if (!block) return <p className="cl-card-note">{t("editor.selectHint")}</p>;
                  const defs = blockDef?.settings ?? [];
                  const covered = new Set(defs.map((d) => d.id).filter(Boolean));
                  const extras = Object.entries(block.settings ?? {}).filter(([ key ]) => !covered.has(key));
                  return (
                    <>
                      <p className="cl-card-note"><code>{block.type}</code>（block）</p>
                      {defs.map((def, index) => (
                        <SettingControl
                          def={def}
                          key={def.id ?? `static-${index}`}
                          onChange={(value) => def.id && setBlockSetting(def.id, value)}
                          value={def.id ? (block.settings ?? {})[def.id] : undefined}
                        />
                      ))}
                      {extras.map(([ key, value ]) => (
                        <FallbackControl key={key} name={key}
                          onChange={(next) => setBlockSetting(key, next)} value={value} />
                      ))}
                    </>
                  );
                })()
              ) : (
                <>
                  <p className="cl-card-note"><code>{selected.type}</code>{selected.disabled ? ` — ${t("editor.hidden")}` : ""}</p>
                  {(() => {
                    const schema = data?.sectionSchemas?.[selected.type];
                    const defs = schema?.settings ?? [];
                    const covered = new Set(defs.map((def) => def.id).filter(Boolean));
                    const extras = Object.entries(selected.settings ?? {}).filter(([ key ]) => !covered.has(key));
                    return (
                      <>
                        {defs.map((def, index) => (
                          <SettingControl
                            def={def}
                            key={def.id ?? `static-${index}`}
                            onChange={(value) => def.id && setSetting(selectedId, def.id, value)}
                            value={def.id ? (selected.settings ?? {})[def.id] : undefined}
                          />
                        ))}
                        {extras.map(([ key, value ]) => (
                          <FallbackControl
                            key={key}
                            name={key}
                            onChange={(next) => setSetting(selectedId, key, next)}
                            value={value}
                          />
                        ))}
                      </>
                    );
                  })()}
                  {/* PR-18：官方「At the bottom of section properties, click Custom CSS」；
                      section 級上限 500 字（help add-css 逐字） */}
                  <details className="cl-editor__acc cl-editor__customcss">
                    <summary>{t("editor.customCss")}</summary>
                    <textarea
                      aria-label={t("editor.customCss")}
                      className="cl-field__input"
                      maxLength={500}
                      onChange={(event) => {
                        const value = event.target.value;
                        applyOp(selectedBand, (tpl) => {
                          const entry = tpl.sections?.[selectedId];
                          if (!entry) return;
                          if (value) entry.custom_css = value;
                          else delete entry.custom_css;
                        });
                      }}
                      rows={4}
                      value={selected.custom_css ?? ""}
                    />
                  </details>
                  <Button
                    onClick={() => { removeSection(selectedBand, selectedId); deselect(); }}
                    size="small"
                    variant="critical"
                  >
                    <Trash2 aria-hidden="true" size={13} /> {t("editor.removeSection")}
                  </Button>
                </>
              )}
            </div>
          </aside>
        ) : null}
      </div>

      <ShortcutsDialog onClose={() => setShortcutsOpen(false)} open={shortcutsOpen} />
      <ConfirmDialog
        cancelLabel={t("editor.stay")}
        confirmLabel={t("editor.leave")}
        danger
        message={t("editor.leaveMessage")}
        onCancel={() => setLeaveOpen(false)}
        onConfirm={() => { setLeaveOpen(false); navigate("/admin/store"); }}
        open={leaveOpen}
        title={t("editor.leaveTitle")}
      />
      <ConfirmDialog
        busy={publishing}
        confirmLabel={t("editor.publish")}
        message={t("editor.publishMessage")}
        onCancel={() => setPublishOpen(false)}
        onConfirm={() => { void publish(); }}
        open={publishOpen}
        title={t("editor.publishTitle", { name: data?.name ?? "" })}
      />
      <CreateTemplateDialog
        baseKeys={createBaseKeys}
        busy={creating}
        existing={templateKeys}
        onCancel={() => setCreateType(null)}
        onCreate={(name, baseKey) => { void createTemplate(name, baseKey); }}
        open={createType !== null}
        type={createType}
      />
    </div>
  );
}
