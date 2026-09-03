import { Box, ChevronUp, Layers, Search } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { CreateTemplateDialog } from "../editor/CreateTemplateDialog";
import { EditorTopBar, type EditorPanel } from "../editor/EditorTopBar";
import { ImagePickerModal } from "../editor/ImagePickerModal";
import { isTypingTarget, shortcutFor } from "../editor/editorShortcuts";
import { PreviewResourceRow } from "../editor/PreviewResourceRow";
import { SectionsTree, type BlockDefLite } from "../editor/SectionsTree";
import { SettingRow, type ControlContext, type FontFamily, type MenuOption, type SchemeOption, type SettingDef } from "../editor/SettingControls";
import { FontPickerPanel, SettingsPanel } from "../editor/SettingsPanel";
import { evaluateVisibleIf } from "../editor/visibleIf";
import { ShortcutsDialog } from "../editor/ShortcutsDialog";
import { splitTemplateKey } from "../editor/TemplateSwitcher";
import {
  allExpandableKeys, blockOrderOf, decodeBlockPath, encodeBlockPath, findBlockPath, flattenRows, getBlock,
  getContainer, orderOf, rowKey, sectionAllowedIn, type BlockPath, type SectionEntry, type TemplateJson,
  type TreeBand, type BlockEntry,
} from "../editor/treeModel";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 主題編輯器（步 16a shell＋16b op-stack 編輯管線；E2 shell＋頂欄、E3 左樹依本尊重做）。
 *
 * 編輯語義（24 §3 原子 op 對照表）：set-setting／toggle-disabled（眼睛＝隱藏
 * 不是刪除）／move（拖放＝改 order）／remove（移除 entry＋order 引用）／
 * duplicate（深拷貝＋新 ID）。add-section（picker＋preset）＝16c。
 * Undo/Redo＝JSON 快照棧（14 §F3：不做 op-based——僅未儲存變更、Save 後清空）。
 * 儲存＝themeTemplateUpsert 整份 JSON＋樂觀鎖（STALE ⇒ 提示重載）；成功後
 * iframe 重載（後端已 touch theme——頁快取鍵旋轉紅線在 server 端）。
 *
 * E2 shell（`docs/research/100` §1／§5／§6／§7）：頂欄＝`EditorTopBar`；面板切換器再點已啟用者 ⇒ 全寬
 * 預覽；左欄依 `panel` 切換；右欄只在選取時掛載；URL 狀態 `template`／`section`／`block`／`context`／
 * `previewMode`／`previewPath`／`category`；快捷鍵單一表；離開／發布確認框。
 *
 * E3 左樹（100 §2）：`SectionsTree` 遞迴 block（路徑 `BlockPath`，URL `block=` 以 `__` 串接）；群組帶依
 * layout 位置排在 Template 上／下；每帶 "Add section"（依 `enabled_on`／`limit` 過濾）；列 hover 動作、
 * 右鍵選單、鍵盤 Shift+↑↓／Ctrl+Shift+O／P／Shift+Enter；就地改名寫 JSON `name`；資源模板的 Preview 列。
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
      themeBlocks
      nameTranslations
      fontLibrary
      settingsSchema
      themeSettingsJson
      themeSettingsLockVersion
    }
    menus { handle title }
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

interface BlockDef extends BlockDefLite {
  settings?: SettingDef[];
  /** theme block 可接受的子型別（"@theme"＝全部；E3 `themeBlocks`） */
  blocks?: string[];
}

interface Availability {
  enabled_on?: { templates?: string[]; groups?: string[] } | null;
  disabled_on?: { templates?: string[]; groups?: string[] } | null;
  limit?: number | null;
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
    sectionGroups: { name: string; path: string; json: TemplateJson; lockVersion: number | null;
                     label?: string; type?: string; position?: "before" | "after" }[];
    sectionSchemas: Record<string, { name: string; settings: SettingDef[];
                                     max_blocks?: number | null; blocks?: BlockDef[] } & Availability>;
    themeBlocks?: Record<string, BlockDef>;
    /** E3b：實例 `name` 的 `t:` 鍵 → 翻譯（只含實際出現的鍵） */
    nameTranslations?: Record<string, string>;
    /** E4：font_picker 字型清單（平台字典） */
    fontLibrary?: FontFamily[];
    settingsSchema: { name: string; settings: SettingDef[] }[];
    themeSettingsJson: Record<string, unknown>;
    themeSettingsLockVersion: number | null;
  } | null;
  /** E4：link_list 控件的選單清單 */
  menus?: MenuOption[];
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

/** 群組檔名人性化（"header-group" → "Header group"）；群組 JSON 自帶 name 時不用。 */
function humanize(name: string): string {
  const spaced = name.replace(/[-_]+/g, " ").trim();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

const RESOURCE_TEMPLATE_TYPES = new Set([ "product", "collection", "page", "blog", "article" ]);
const GROUP_TEMPLATE_TYPES = RESOURCE_TEMPLATE_TYPES;

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
  // E3：選中 block 以路徑定位（`[]`＝section 本身）；葉 id 供橋（cl:highlight）用
  const [selectedPath, setSelectedPath] = useState<BlockPath>([]);
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set());
  const [renaming, setRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState("");
  // E4：右欄「…」Copy 的剪貼簿（Paste 在左樹右鍵）；image_picker 的檔案庫 modal；Custom CSS 收合狀態（URL customCss=true）
  const [clipboard, setClipboard] = useState<{ kind: "section" | "block"; entry: BlockEntry } | null>(null);
  const [imagePicker, setImagePicker] = useState<{ def: SettingDef; value: string; onChange: (value: string) => void } | null>(null);
  const [customCssOpen, setCustomCssOpen] = useState(() => searchParams.get("customCss") === "true");
  const [menus, setMenus] = useState<MenuOption[]>([]);
  // E4：佈景設定面板的 font_picker ⇒ 右欄整面選字型（section／block 面板則由 SettingsPanel 自己承接）
  const [fontPicker, setFontPicker] = useState<{ def: SettingDef; value: string; onChange: (value: string) => void } | null>(null);
  const [draft, setDraft] = useState<TemplateJson | null>(null);
  // PR-5：群組帶（24 §1 本尊樹形）——群組 draft 與模板同語義（{sections, order}），寫回走 themeFileUpsert。
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
  // E3：Add section 的目標帶與插入位置（null＝關）；PR-19 picker 搜尋
  const [pickerFor, setPickerFor] = useState<{ band: string; atIndex: number | null } | null>(null);
  const [pickerQuery, setPickerQuery] = useState("");
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
  const templateType = splitTemplateKey(templateKey).type;
  const selectedBlockId = selectedPath.length > 0 ? selectedPath[selectedPath.length - 1] : null;

  // PR-11 資源語境：模板型 → 樣本路徑（product 模板帶真商品）；無樣本回落首頁。
  // E2：URL `previewPath`（預覽內導航／Preview 列寫入）優先——本尊同名參數（100 §6）。
  const previewPath = searchParams.get("previewPath")
    ?? data?.previewPaths?.[templateType] ?? "/";

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<EditorData, { id: string; key: string }>(
        EDITOR_QUERY, { id: gid, key: templateKey }, signal);
      setData(result.theme);
      setMenus(result.menus ?? []);
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

  // ── E3：帶（群組依 layout 位置排在 Template 上／下）與 schema 解析 helpers ──
  const themeBlocks = useMemo(() => data?.themeBlocks ?? {}, [data]);
  const bands = useMemo<TreeBand[]>(() => {
    const groups = (data?.sectionGroups ?? []).map((g) => ({
      band: g.name,
      label: g.label ?? humanize(g.name),
      groupType: g.type ?? g.name.replace(/-group$/, ""),
      position: (g.position ?? (g.name.includes("footer") ? "after" : "before")) as "before" | "after",
      tpl: groupDrafts[g.name] ?? null,
    }));
    return [
      ...groups.filter((g) => g.position === "before"),
      { band: "template", label: t("editor.templateBand"), position: "template" as const, tpl: draft },
      ...groups.filter((g) => g.position === "after"),
    ];
  }, [data, groupDrafts, draft, t]);

  const tplOf = (band: string) => (band === "template" ? draftRef.current : groupDraftsRef.current[band] ?? null);
  const sectionOf = (band: string, sectionId: string): SectionEntry | null => tplOf(band)?.sections?.[sectionId] ?? null;
  const sectionName = (type: string) => data?.sectionSchemas?.[type]?.name ?? type;
  /** E3b：實例 `name` 是 `t:` 鍵時顯示翻譯（本尊顯示 "Announcement bar"，不顯示鍵）；缺鍵 fail-open 顯示原鍵。 */
  const translateName = (value: string | undefined): string | undefined =>
    (value && value.startsWith("t:") ? (data?.nameTranslations?.[value] ?? value) : value);
  const blockDef = (sectionType: string, path: BlockPath, blockType: string): BlockDef | undefined => {
    const local = data?.sectionSchemas?.[sectionType]?.blocks?.find((d) => d.type === blockType);
    return path.length === 1 ? (local ?? themeBlocks[blockType]) : (themeBlocks[blockType] ?? local);
  };
  const expandAccepts = (accepts: string[]): BlockDef[] => accepts.flatMap((type) =>
    type === "@theme" ? Object.values(themeBlocks) : themeBlocks[type] ? [ themeBlocks[type] ] : []);
  const addBlockOptions = (band: string, sectionId: string, parentPath: BlockPath): BlockDef[] => {
    const section = sectionOf(band, sectionId);
    if (!section) return [];
    if (parentPath.length === 0) {
      const schema = data?.sectionSchemas?.[section.type];
      const max = schema?.max_blocks ?? 50;
      return blockOrderOf(section).length < max ? (schema?.blocks ?? []) : [];
    }
    if (parentPath.length >= 8) return []; // help："Eight levels maximum"
    const container = getBlock(section, parentPath);
    return container ? expandAccepts(themeBlocks[container.type]?.blocks ?? []) : [];
  };

  /** 展開到某路徑（選中 block 時祖先必須展開，樹才看得到它）。 */
  const expandTo = (band: string, sectionId: string, path: BlockPath) => {
    setExpanded((current) => {
      const next = new Set(current);
      next.add(rowKey(band, sectionId, []));
      for (let depth = 1; depth < path.length; depth += 1) next.add(rowKey(band, sectionId, path.slice(0, depth)));
      return next;
    });
  };

  // PR-15／E2：編輯器狀態 URL 化（本尊 100 §6：section／block／context／previewMode／
  // category 皆為 query 參數，可重載還原）。初載還原一次。
  const restoredRef = useRef(false);
  useEffect(() => {
    if (restoredRef.current || !data) return;
    restoredRef.current = true;
    const section = searchParams.get("section");
    const block = decodeBlockPath(searchParams.get("block"));
    const context = searchParams.get("context");
    if (searchParams.get("previewMode") === "fullscreen") setFullscreen(true);
    if (searchParams.get("category")) setOpenCategory(searchParams.get("category"));
    if (context === "theme" || context === "apps") {
      setPanel(context);
    } else if (section) {
      const band = draftRef.current?.sections?.[section]
        ? "template"
        : Object.entries(groupDraftsRef.current).find(([ , tpl ]) => tpl.sections?.[section])?.[0] ?? "template";
      setSelectedId(section);
      setSelectedPath(block ?? []);
      setSelectedBand(band);
      expandTo(band, section, block ?? []);
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

  /** 選中 section（＋block 路徑）：state、URL、面板回 sections、展開祖先。 */
  const selectNode = (band: string, sectionId: string, path: BlockPath) => {
    setSelectedBand(band);
    setSelectedId(sectionId);
    setSelectedPath(path);
    setPanel("sections");
    setRenaming(false);
    if (path.length > 0) expandTo(band, sectionId, path);
    syncStateParams({ section: sectionId, block: path.length > 0 ? encodeBlockPath(path) : null, context: null });
  };

  const deselect = () => {
    setSelectedId(null);
    setSelectedPath([]);
    setRenaming(false);
    syncStateParams({ section: null, block: null });
  };

  const switchPanel = (next: EditorPanel) => {
    setPanel(next);
    setFullscreen(false);
    const patch: Record<string, string | null> = { context: next === "sections" ? null : next, previewMode: null };
    if (next !== "sections") {
      // 本尊：切到佈景設定／app embeds 即取消選取（右欄收起）
      setSelectedId(null);
      setSelectedPath([]);
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
        const id = payload.id;
        const band = draftRef.current?.sections?.[id]
          ? "template"
          : Object.entries(groupDraftsRef.current).find(([ , tpl ]) => tpl.sections?.[id])?.[0] ?? "template";
        const section = tplOf(band)?.sections?.[id];
        // PR-17／E3：預覽點 block 只回葉 id ⇒ 在 section 樹裡找完整路徑
        const path = payload.blockId && section ? (findBlockPath(section, payload.blockId) ?? [ payload.blockId ]) : [];
        selectNode(band, id, path);
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

  /** 對某帶某 section 做變更（applyOp 的 section 級便捷形）。 */
  const withSection = (band: string, sectionId: string, fn: (section: SectionEntry, tpl: TemplateJson) => void) =>
    applyOp(band, (tpl) => {
      const section = tpl.sections?.[sectionId];
      if (section) fn(section, tpl);
    });

  // E3：section／block 同語義的 op（路徑 `[]`＝section）
  const toggleNodeDisabled = (band: string, sectionId: string, path: BlockPath) => withSection(band, sectionId, (section) => {
    const node = getBlock(section, path);
    if (node) node.disabled = !node.disabled; // 隱藏不是刪除（24 §3）
  });

  const removeSection = (band: string, sectionId: string) => applyOp(band, (tpl) => {
    if (tpl.sections) delete tpl.sections[sectionId];
    tpl.order = orderOf(tpl).filter((id) => id !== sectionId);
    if (selectedId === sectionId) setSelectedId(null);
  });

  const removeNode = (band: string, sectionId: string, path: BlockPath) => {
    if (path.length === 0) {
      removeSection(band, sectionId);
      if (selectedBand === band && selectedId === sectionId) deselect();
      return;
    }
    const id = path[path.length - 1];
    const sectionNow = sectionOf(band, sectionId);
    if (sectionNow && getBlock(sectionNow, path)?.static) return; // static block 不可刪（66 §A.5.2；樹也不給垃圾桶）
    withSection(band, sectionId, (section) => {
      const container = getContainer(section, path);
      if (!container?.blocks) return;
      delete container.blocks[id];
      container.block_order = blockOrderOf(container).filter((x) => x !== id);
    });
    if (selectedBand === band && selectedId === sectionId && selectedPath.join("/").startsWith(path.join("/"))) {
      selectNode(band, sectionId, path.slice(0, -1));
    }
  };

  // PR-26／E3：拖放的任意位置插入（section 同帶；block 同容器；applyOp ⇒ undo/改即見/儲存全繼承）
  const moveSectionTo = (band: string, sectionId: string, targetIndex: number) => applyOp(band, (tpl) => {
    const order = [ ...orderOf(tpl) ];
    const from = order.indexOf(sectionId);
    if (from < 0) return;
    order.splice(from, 1);
    const bounded = Math.max(0, Math.min(targetIndex, order.length));
    order.splice(bounded, 0, sectionId);
    tpl.order = order;
  });

  const moveNode = (band: string, sectionId: string, path: BlockPath, targetIndex: number) => {
    if (path.length === 0) { moveSectionTo(band, sectionId, targetIndex); return; }
    const id = path[path.length - 1];
    withSection(band, sectionId, (section) => {
      const container = getContainer(section, path);
      if (!container) return;
      const order = [ ...blockOrderOf(container) ];
      const from = order.indexOf(id);
      if (from < 0) return;
      order.splice(from, 1);
      order.splice(Math.max(0, Math.min(targetIndex, order.length)), 0, id);
      container.block_order = order;
    });
  };

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

  // ── E4：右欄「…」的 Duplicate／Copy 與左樹 Paste（section 與任意深度 block 同語義；static 不可複製）──
  const uniqueId = (taken: (id: string) => boolean, base: string) => {
    let candidate = `${base}-copy`;
    let n = 2;
    while (taken(candidate)) candidate = `${base}-copy-${n++}`;
    return candidate;
  };
  const duplicateNode = (band: string, sectionId: string, path: BlockPath) => {
    if (path.length === 0) { duplicateSection(band, sectionId); return; }
    const sectionNow = sectionOf(band, sectionId);
    const containerNow = sectionNow ? getContainer(sectionNow, path) : null;
    const id = path[path.length - 1];
    if (!containerNow?.blocks?.[id] || containerNow.blocks[id].static) return;
    const newId = uniqueId((candidate) => Boolean(containerNow.blocks?.[candidate]), id);
    withSection(band, sectionId, (section) => {
      const container = getContainer(section, path);
      const source = container?.blocks?.[id];
      if (!container?.blocks || !source) return;
      container.blocks[newId] = JSON.parse(JSON.stringify(source)) as BlockEntry;
      const order = [ ...blockOrderOf(container) ];
      order.splice(order.indexOf(id) + 1, 0, newId);
      container.block_order = order;
    });
    selectNode(band, sectionId, [ ...path.slice(0, -1), newId ]);
  };
  const copyNode = (band: string, sectionId: string, path: BlockPath) => {
    const section = sectionOf(band, sectionId);
    const node = section ? getBlock(section, path) : null;
    if (!node) return;
    setClipboard({ kind: path.length === 0 ? "section" : "block", entry: JSON.parse(JSON.stringify(node)) as BlockEntry });
  };
  /** 貼上：section 貼在目標 section 之後（同帶）；block 貼進目標容器（目標是 block ⇒ 其後；目標是 section ⇒ 尾端）。 */
  const pasteNode = (band: string, sectionId: string, path: BlockPath) => {
    if (!clipboard) return;
    if (clipboard.kind === "section") {
      const tplNow = tplOf(band);
      const base = (clipboard.entry.type ?? "section").replace(/[^A-Za-z0-9_-]/g, "");
      const newId = uniqueId((candidate) => Boolean(tplNow?.sections?.[candidate]), base);
      applyOp(band, (tpl) => {
        tpl.sections ??= {};
        tpl.sections[newId] = JSON.parse(JSON.stringify(clipboard.entry)) as SectionEntry;
        const order = [ ...orderOf(tpl) ];
        order.splice(order.indexOf(sectionId) + 1, 0, newId);
        tpl.order = order;
      });
      selectNode(band, newId, []);
      return;
    }
    const sectionNow = sectionOf(band, sectionId);
    const containerPath = path.length === 0 ? [] : path.slice(0, -1);
    const containerNow = sectionNow ? getBlock(sectionNow, containerPath) : null;
    if (!containerNow) return;
    const newId = uniqueId((candidate) => Boolean(containerNow.blocks?.[candidate]), clipboard.entry.type.replace(/[^A-Za-z0-9_-]/g, ""));
    withSection(band, sectionId, (section) => {
      const container = getBlock(section, containerPath);
      if (!container) return;
      container.blocks ??= {};
      const entry = JSON.parse(JSON.stringify(clipboard.entry)) as BlockEntry;
      delete entry.static;
      container.blocks[newId] = entry;
      const order = [ ...blockOrderOf(container) ];
      const at = path.length === 0 ? order.length : order.indexOf(path[path.length - 1]) + 1;
      order.splice(at, 0, newId);
      container.block_order = order;
    });
    selectNode(band, sectionId, [ ...containerPath, newId ]);
  };

  /** add-section（24 §3：新 entry 內容取 preset；E3：插到指定帶的指定位置，預設尾端）。 */
  const addSection = (catalogEntry: NonNullable<EditorData["theme"]>["sectionCatalog"][number]) => {
    const target = pickerFor ?? { band: "template", atIndex: null };
    const tplNow = tplOf(target.band);
    let newId = catalogEntry.type;
    let n = 1;
    while (tplNow?.sections?.[newId]) newId = `${catalogEntry.type}-${n++}`;
    applyOp(target.band, (tpl) => {
      tpl.sections ??= {};
      const entry: SectionEntry = {
        type: catalogEntry.type,
        settings: JSON.parse(JSON.stringify(catalogEntry.preset.settings)) as Record<string, unknown>,
      };
      if (catalogEntry.preset.blocks) {
        entry.blocks = JSON.parse(JSON.stringify(catalogEntry.preset.blocks)) as SectionEntry["blocks"];
        entry.block_order = Object.keys(entry.blocks ?? {});
      }
      tpl.sections[newId] = entry;
      const order = [ ...orderOf(tpl) ];
      order.splice(target.atIndex ?? order.length, 0, newId);
      tpl.order = order;
    });
    setPickerFor(null);
    selectNode(target.band, newId, []);
  };

  // ── PR-6／E3：block 級操作（任意深度；全部走 applyOp 快照棧）──
  const addBlockAt = (band: string, sectionId: string, parentPath: BlockPath, def: BlockDefLite) => {
    const containerNow = sectionOf(band, sectionId);
    const parentNow = containerNow ? getBlock(containerNow, parentPath) : null;
    let newId = def.type;
    let n = 1;
    while (parentNow?.blocks?.[newId]) newId = `${def.type}-${n++}`;
    withSection(band, sectionId, (section) => {
      const container = getBlock(section, parentPath);
      if (!container) return;
      container.blocks ??= {};
      container.block_order ??= [];
      const defaults = Object.fromEntries(((def as BlockDef).settings ?? [])
        .filter((d) => d.id && d.default !== undefined)
        .map((d) => [ d.id as string, d.default ]));
      container.blocks[newId] = { type: def.type, settings: defaults };
      container.block_order = [ ...blockOrderOf(container), newId ];
    });
    selectNode(band, sectionId, [ ...parentPath, newId ]);
  };

  const setBlockSetting = (settingKey: string, value: unknown) => {
    if (!selectedId || selectedPath.length === 0) return;
    withSection(selectedBand, selectedId, (section) => {
      const block = getBlock(section, selectedPath);
      if (!block) return;
      block.settings = { ...(block.settings ?? {}), [settingKey]: value };
    });
  };

  /** E3 Rename：就地改名寫進 JSON `name`（本尊語義；Ella 匯出的 block `name` 即此）；空值＝清掉。 */
  const commitRename = () => {
    if (!selectedId) return;
    const value = renameValue.trim();
    withSection(selectedBand, selectedId, (section) => {
      const node = getBlock(section, selectedPath);
      if (!node) return;
      if (value) node.name = value;
      else delete node.name;
    });
    setRenaming(false);
  };

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

  const openCode = (band: string, sectionId: string, path: BlockPath) => {
    const section = sectionOf(band, sectionId);
    if (!section) return;
    const node = getBlock(section, path);
    const file = path.length === 0 ? `sections/${section.type}.liquid` : `blocks/${node?.type ?? ""}.liquid`;
    window.open(`/admin/themes/${themeId}/code?file=${encodeURIComponent(file)}`, "_blank", "noopener");
  };

  const startRename = (band: string, sectionId: string, path: BlockPath) => {
    const section = sectionOf(band, sectionId);
    const node = section ? getBlock(section, path) : null;
    if (!node || !section) return;
    const def = path.length > 0 ? blockDef(section.type, path, node.type) : undefined;
    selectNode(band, sectionId, path);
    setRenameValue(translateName(node.name) ?? (path.length === 0 ? sectionName(node.type) : (def?.name ?? node.type)));
    setRenaming(true);
  };

  // E2／E3：快捷鍵——單一表 `editorShortcuts`；effect 只掛一次，經 ref 取最新動作。
  // 輸入控件內不攔 undo/redo/remove/hide/deselect/導航（讓瀏覽器原生文字編輯先行）；
  // modal 開著（#admin-root inert 或 role=dialog）時全部不攔——對話框自己管 Escape。
  const actionsRef = useRef<Record<string, () => void>>({});
  const currentRowIndex = () => {
    const rows = flattenRows(bands, expanded);
    return { rows, index: rows.findIndex((row) => row.band === selectedBand && row.sectionId === selectedId
      && row.path.join("/") === selectedPath.join("/")) };
  };
  actionsRef.current = {
    undo, redo,
    save: () => { void save(); },
    seeAll: () => setShortcutsOpen(true),
    previewInspector: () => setInspector((on) => !on),
    previewMode: () => setMobilePreview((on) => !on),
    sections: () => switchPanel("sections"),
    themeSettings: () => switchPanel("theme"),
    appEmbeds: () => switchPanel("apps"),
    hideShow: () => { if (selectedId) toggleNodeDisabled(selectedBand, selectedId, selectedPath); },
    remove: () => { if (selectedId) removeNode(selectedBand, selectedId, selectedPath); },
    deselect: () => { if (renaming) setRenaming(false); else if (selectedId) deselect(); },
    selectPrev: () => {
      const { rows, index } = currentRowIndex();
      const target = rows[index < 0 ? 0 : Math.max(0, index - 1)];
      if (target) selectNode(target.band, target.sectionId, target.path);
    },
    selectNext: () => {
      const { rows, index } = currentRowIndex();
      const target = rows[index < 0 ? 0 : Math.min(rows.length - 1, index + 1)];
      if (target) selectNode(target.band, target.sectionId, target.path);
    },
    openSelected: () => {
      (document.querySelector(".cl-editor__settings input, .cl-editor__settings select, .cl-editor__settings textarea") as HTMLElement | null)?.focus();
    },
    expandAll: () => setExpanded(new Set(allExpandableKeys(bands))),
    collapseAll: () => setExpanded(new Set()),
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
          [ "undo", "redo", "remove", "hideShow", "deselect", "selectPrev", "selectNext", "openSelected" ].includes(id)) return;
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
  const selectedBlock = selected && selectedPath.length > 0 ? getBlock(selected, selectedPath) : null;
  const selectedBlockDef = selected && selectedBlock ? blockDef(selected.type, selectedPath, selectedBlock.type) : undefined;
  const previewSrc = `/admin/store/preview/${themeId}${previewPath === "/" ? "" : previewPath}?editor=1`;
  const hasRightPanel = panel === "sections" && Boolean(selected && selectedId) && (selectedPath.length === 0 || Boolean(selectedBlock));
  const panelTitle = selected
    ? (selectedBlock ? (translateName(selectedBlock.name) ?? selectedBlockDef?.name ?? selectedBlock.type) : (translateName(selected.name) ?? sectionName(selected.type)))
    : "";


  // ── E4：控件語境——色階（color_scheme_group 的值 × role 對映）、字型清單、選單清單、Editing Scheme 入口 ──
  const schemeGroupDef = (data?.settingsSchema ?? []).flatMap((group) => group.settings).find((def) => def.type === "color_scheme_group");
  const schemes = useMemo<SchemeOption[]>(() => {
    const raw = schemeGroupDef?.id ? settingsDraft?.[schemeGroupDef.id] : null;
    if (!raw || typeof raw !== "object") return [];
    const role = (schemeGroupDef?.role ?? {}) as Record<string, unknown>;
    const roleKey = (name: string, fallback: string): string => {
      const entry = role[name];
      if (typeof entry === "string") return entry;
      if (entry && typeof entry === "object" && typeof (entry as { solid?: unknown }).solid === "string") return (entry as { solid: string }).solid;
      return fallback;
    };
    return Object.entries(raw as Record<string, { settings?: Record<string, unknown> }>).map(([ id, scheme ], index) => {
      const values = scheme?.settings ?? {};
      const read = (key: string, fallback: string) => (typeof values[key] === "string" && values[key] ? String(values[key]) : fallback);
      return {
        id,
        label: t("editor.schemeLabel", { n: String(index + 1) }),
        background: read(roleKey("background", "background"), "#ffffff"),
        text: read(roleKey("text", "foreground"), "#000000"),
        button: read(roleKey("primary_button", "primary_button_background"), "#000000"),
      };
    });
  }, [ schemeGroupDef, settingsDraft, t ]);
  const controlCtx = useMemo<ControlContext>(() => ({
    schemes,
    fonts: data?.fontLibrary ?? [],
    menus,
    onEditScheme: (schemeId) => {
      const group = (data?.settingsSchema ?? []).find((g) => g.settings.some((def) => def.type === "color_scheme_group"));
      switchPanel("theme");
      if (group) { setOpenCategory(group.name); syncStateParams({ category: group.name, colorScheme: schemeId }); }
    },
    onOpenImagePicker: (request) => setImagePicker(request),
    onOpenFontPicker: (request) => setFontPicker(request),
  }), [ schemes, data?.fontLibrary, data?.settingsSchema, menus ]); // eslint-disable-line react-hooks/exhaustive-deps
  const themeRefDefs = useMemo<SettingDef[]>(() => {
    const refs = selected ? (data?.sectionSchemas?.[selected.type] as { theme_settings?: string[] } | undefined)?.theme_settings ?? [] : [];
    if (refs.length === 0) return [];
    return (data?.settingsSchema ?? []).flatMap((group) => group.settings).filter((def) => def.id && refs.includes(def.id));
  }, [ data, selected ]);

  // E3：Add section picker 的候選（依帶過濾 enabled_on／disabled_on；limit 達標灰化並標 (n/limit)）
  const pickerBand = pickerFor ? bands.find((b) => b.band === pickerFor.band) : null;
  const pickerEntries = (data?.sectionCatalog ?? []).map((entry) => {
    const schema = data?.sectionSchemas?.[entry.type];
    const allowed = sectionAllowedIn(schema, pickerBand?.position === "template" ? { templateType } : { groupType: pickerBand?.groupType });
    const used = pickerBand?.tpl ? orderOf(pickerBand.tpl).filter((id) => pickerBand.tpl?.sections?.[id]?.type === entry.type).length : 0;
    const limit = schema?.limit ?? null;
    return { entry, allowed, used, limit, full: limit !== null && used >= limit };
  }).filter(({ entry, allowed }) => {
    const q = pickerQuery.trim().toLowerCase();
    return allowed && (!q || entry.name.toLowerCase().includes(q) || entry.type.toLowerCase().includes(q));
  });

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
    !fullscreen && (hasRightPanel || fontPicker !== null) ? "cl-editor--with-panel" : "",
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
              {RESOURCE_TEMPLATE_TYPES.has(templateType) && themeId ? (
                <PreviewResourceRow
                  currentPath={previewPath}
                  onPick={(path) => syncStateParams({ previewPath: path, section: null, block: null })}
                  templateType={templateType as "product" | "collection" | "page" | "blog" | "article"}
                  themeId={themeId}
                />
              ) : null}
              {pickerFor ? (
                <ul aria-label={t("editor.sectionPicker")} className="cl-editor__picker">
                  <li>
                    <input
                      aria-label={t("editor.pickerSearch")}
                      className="cl-field__input"
                      data-autofocus
                      onChange={(event) => setPickerQuery(event.target.value)}
                      placeholder={t("editor.pickerSearch")}
                      value={pickerQuery}
                    />
                  </li>
                  {pickerEntries.length === 0 ? (
                    <li className="cl-card-note">{t("editor.pickerEmpty")}</li>
                  ) : pickerEntries.map(({ entry, full, used, limit }) => (
                    <li key={entry.type}>
                      <button className="cl-editor__node" disabled={full} onClick={() => addSection(entry)} type="button">
                        {entry.name}{full ? ` (${used}/${limit})` : ""}
                      </button>
                    </li>
                  ))}
                </ul>
              ) : null}
              <SectionsTree
                addBlockOptions={addBlockOptions}
                bands={bands}
                blockDef={blockDef}
                expanded={expanded}
                onAddBlock={addBlockAt}
                onAddSection={(band, atIndex) => { setPickerQuery(""); setPickerFor((current) => (current?.band === band && current.atIndex === atIndex ? null : { band, atIndex })); }}
                canPaste={clipboard !== null}
                onEditCode={openCode}
                onPaste={pasteNode}
                onMove={moveNode}
                onRemove={removeNode}
                onRename={startRename}
                onSelect={selectNode}
                onToggleDisabled={toggleNodeDisabled}
                onToggleExpand={(key) => setExpanded((current) => {
                  const next = new Set(current);
                  if (next.has(key)) next.delete(key); else next.add(key);
                  return next;
                })}
                sectionName={sectionName}
                translateName={translateName}
                selection={selectedId ? { band: selectedBand, sectionId: selectedId, path: selectedPath } : null}
              />
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
                  {group.settings.filter((def) => evaluateVisibleIf(def.visible_if, { settings: settingsDraft ?? {} })).map((def, index) => (
                    <SettingRow
                      ctx={controlCtx}
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

        {!fullscreen && fontPicker && !(hasRightPanel && selected && selectedId) ? (
          <aside aria-label={t("editor.settingsPanel")} className="cl-editor__settings cl-panel">
            <div className="cl-panel__title">
              <button aria-label={t("common.back")} className="cl-editor__iconbtn" onClick={() => setFontPicker(null)} type="button"><ChevronUp aria-hidden="true" size={16} /></button>
              <h3>{t("editor.selectFont", { label: fontPicker.def.label ?? fontPicker.def.id ?? "" })}</h3>
            </div>
            <div className="cl-panel__body">
              <FontPickerPanel fonts={data?.fontLibrary ?? []} onCancel={() => setFontPicker(null)} onDone={(handle) => { fontPicker.onChange(handle); setFontPicker(null); }} value={fontPicker.value} />
            </div>
          </aside>
        ) : null}
        {!fullscreen && hasRightPanel && selected && selectedId ? (() => {
          const node = selectedBlock ?? selected;
          const defs = selectedBlock ? (selectedBlockDef?.settings ?? []) : (data?.sectionSchemas?.[selected.type]?.settings ?? []);
          const covered = new Set(defs.map((def) => def.id).filter(Boolean));
          const extras = Object.entries(node.settings ?? {}).filter(([ key ]) => !covered.has(key));
          const onChange = (key: string, value: unknown) => (selectedBlock ? setBlockSetting(key, value) : setSetting(selectedId, key, value));
          return (
            <SettingsPanel
              ctx={controlCtx}
              customCss={selectedBlock ? undefined : {
                value: selected.custom_css ?? "",
                open: customCssOpen,
                onToggle: (open) => { setCustomCssOpen(open); syncStateParams({ customCss: open ? "true" : null }); },
                onChange: (value) => applyOp(selectedBand, (tpl) => {
                  const entry = tpl.sections?.[selectedId];
                  if (!entry) return;
                  if (value) entry.custom_css = value;
                  else delete entry.custom_css;
                }),
              }}
              defs={defs}
              extras={extras.map(([ key, value ]) => (
                <FallbackControl key={key} name={key} onChange={(next) => onChange(key, next)} value={value} />
              ))}
              kind={selectedBlock ? "block" : "section"}
              menu={{
                onCopy: () => copyNode(selectedBand, selectedId, selectedPath),
                onDuplicate: selectedBlock?.static ? undefined : () => duplicateNode(selectedBand, selectedId, selectedPath),
                onRename: () => startRename(selectedBand, selectedId, selectedPath),
                onToggleHidden: () => toggleNodeDisabled(selectedBand, selectedId, selectedPath),
                hidden: Boolean(node.disabled),
                onEditCode: () => openCode(selectedBand, selectedId, selectedPath),
                onRemove: selectedBlock?.static ? undefined : () => removeNode(selectedBand, selectedId, selectedPath),
              }}
              onChange={onChange}
              onClose={deselect}
              onRenameCancel={() => setRenaming(false)}
              onRenameChange={setRenameValue}
              onRenameCommit={commitRename}
              removeLabel={selectedBlock ? t("editor.blockRemove", { id: selectedBlockId ?? "" }) : t("editor.removeSection")}
              renameValue={renameValue}
              renaming={renaming}
              scope={{ block: selectedBlock?.settings, section: selected.settings ?? {}, settings: settingsDraft ?? {} }}
              themeSettings={selectedBlock ? undefined : { defs: themeRefDefs, values: settingsDraft ?? {}, onChange: setThemeSetting }}
              title={panelTitle}
              typeIcon={selectedBlock ? <Box size={16} /> : <Layers size={16} />}
              values={node.settings ?? {}}
            />
          );
        })() : null}
        <ImagePickerModal
          onClose={() => setImagePicker(null)}
          onPick={(value) => { imagePicker?.onChange(value); setImagePicker(null); }}
          open={imagePicker !== null}
          title={imagePicker?.def.label ?? imagePicker?.def.id ?? ""}
        />
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
