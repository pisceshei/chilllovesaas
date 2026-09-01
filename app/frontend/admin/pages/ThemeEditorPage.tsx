import { ArrowDown, ArrowLeft, ArrowUp, Copy, Eye, EyeOff, Redo2, Trash2, Undo2 } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 主題編輯器（步 16a shell＋16b op-stack 編輯管線）。
 *
 * 編輯語義（24 §3 原子 op 對照表）：set-setting／toggle-disabled（眼睛＝隱藏
 * 不是刪除）／move（上下移＝改 order）／remove（移除 entry＋order 引用）／
 * duplicate（深拷貝＋新 ID）。add-section（picker＋preset）＝16c。
 * Undo/Redo＝JSON 快照棧（14 §F3：不做 op-based——僅未儲存變更、Save 後清空）。
 * 儲存＝themeTemplateUpsert 整份 JSON＋樂觀鎖（STALE ⇒ 提示重載）；成功後
 * iframe 重載（後端已 touch theme——頁快取鍵旋轉紅線在 server 端）。
 */
const EDITOR_QUERY = `
  query themeEditorBootstrap($id: ID!, $key: String!) {
    theme(id: $id) {
      id name role
      templates: files(filenames: ["templates/*.json"]) { filename }
      templateJson(key: $key)
      templateLockVersion(key: $key)
      sectionGroups
      sectionCatalog
      sectionSchemas
      settingsSchema
      themeSettingsJson
      themeSettingsLockVersion
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
    templateJson: TemplateJson | null;
    templateLockVersion: number | null;
    sectionCatalog: { type: string; name: string;
                      preset: { settings: Record<string, unknown>;
                                blocks: Record<string, unknown> | null } }[];
    sectionGroups: { name: string; path: string; json: TemplateJson; lockVersion: number | null }[];
    sectionSchemas: Record<string, { name: string; settings: SettingDef[];
                                     max_blocks?: number | null; blocks?: BlockDef[] }>;
    settingsSchema: { name: string; settings: SettingDef[] }[];
    themeSettingsJson: Record<string, unknown>;
    themeSettingsLockVersion: number | null;
  } | null;
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

export function ThemeEditorPage() {
  const t = useT();
  const { showToast } = useToast();
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
  const [selectedBand, setSelectedBand] = useState<string>("template");
  const [undoStack, setUndoStack] = useState<{ band: string; snap: TemplateJson }[]>([]);
  const [redoStack, setRedoStack] = useState<{ band: string; snap: TemplateJson }[]>([]);
  const [lockVersion, setLockVersion] = useState<number | null>(null);
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);
  // 16d2：佈景設定（settings_data current）——獨立 draft；undo 整合＝16e（91 §3.70）
  const [themeMode, setThemeMode] = useState(false);
  const [settingsDraft, setSettingsDraft] = useState<Record<string, unknown> | null>(null);
  const [settingsLock, setSettingsLock] = useState<number | null>(null);
  const [settingsDirty, setSettingsDirty] = useState(false);
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const draftRef = useRef<TemplateJson | null>(null);
  const groupDraftsRef = useRef<Record<string, TemplateJson>>({});
  const activeDraftRef = useRef<TemplateJson | null>(null);
  draftRef.current = draft;
  groupDraftsRef.current = groupDrafts;
  activeDraftRef.current = selectedBand === "template" ? draft : groupDrafts[selectedBand] ?? null;

  const gid = `gid://chilllove/Theme/${themeId}`;

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

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== window.location.origin) return;
      const payload = event.data as { type?: string; id?: string };
      if (payload?.type === "cl:select" && payload.id) {
        setSelectedId(payload.id);
        // PR-5：預覽點選可能是群組 section——跨帶定位
        setSelectedBand((current) => {
          if (draftRef.current?.sections?.[payload.id!]) return "template";
          const hit = Object.entries(groupDraftsRef.current)
            .find(([ , tpl ]) => tpl.sections?.[payload.id!]);
          return hit ? hit[0] : current;
        });
        setThemeMode(false);
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    iframeRef.current?.contentWindow?.postMessage(
      { type: "cl:highlight", id: selectedId }, window.location.origin);
  }, [selectedId]);

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
          // v1 一律以首頁語境渲染片段（非 index 模板的資源語境＝登記限制）
          const path = "/";
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
  }, [selectedEntryJson, selectedId, selectedBand, themeMode, themeId]);

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

  const undo = () => {
    setUndoStack((stack) => {
      if (stack.length === 0) return stack;
      const { band, snap } = stack[stack.length - 1];
      const previous = restoreBand(band, snap);
      if (previous) setRedoStack((redoS) => [ ...redoS, { band, snap: cloneTpl(previous) } ]);
      return stack.slice(0, -1);
    });
  };

  const redo = () => {
    setRedoStack((stack) => {
      if (stack.length === 0) return stack;
      const { band, snap } = stack[stack.length - 1];
      const previous = restoreBand(band, snap);
      if (previous) setUndoStack((undoS) => [ ...undoS, { band, snap: cloneTpl(previous) } ]);
      return stack.slice(0, -1);
    });
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
  };

  const setSetting = (sectionId: string, settingKey: string, value: unknown) => applyOp(selectedBand, (tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (!entry) return;
    entry.settings = { ...(entry.settings ?? {}), [settingKey]: value };
  });

  const save = async () => {
    if (saving || (!dirty && !settingsDirty && dirtyGroups.length === 0)) return;
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
          return;
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
          return;
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
          return;
        }
        setGroupLocks((locks) => ({ ...locks, [name]: payload.lockVersion }));
      }
      setDirtyGroups([]);
      showToast(t("editor.saved"));
      // 後端已 touch theme（頁快取鍵旋轉）；重載 iframe 看到存檔後渲染
      iframeRef.current?.contentWindow?.location.reload();
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("editor.saveFailed"));
    } finally {
      setSaving(false);
    }
  };

  const templateNames = useMemo(() => (data?.templates ?? [])
    .map((file) => file.filename.replace(/^templates\//, "").replace(/\.json$/, ""))
    .sort(), [data]);

  const order = draft ? orderOf(draft) : [];
  const activeDraft = selectedBand === "template" ? draft : groupDrafts[selectedBand] ?? null;
  const selected = selectedId && activeDraft?.sections ? activeDraft.sections[selectedId] : null;
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
        <span className="cl-editor__spacer" />
        <Button disabled={undoStack.length === 0} onClick={undo} size="small" variant="ghost">
          <Undo2 aria-hidden="true" size={14} /> {t("editor.undo")}
        </Button>
        <Button disabled={redoStack.length === 0} onClick={redo} size="small" variant="ghost">
          <Redo2 aria-hidden="true" size={14} /> {t("editor.redo")}
        </Button>
        <Button
          disabled={(!dirty && !settingsDirty && dirtyGroups.length === 0) || saving}
          onClick={() => void save()}
          variant="primary"
        >
          {t("common.save")}{dirty || settingsDirty || dirtyGroups.length > 0 ? " •" : ""}
        </Button>
      </header>

      <div className="cl-editor__panels">
        <aside aria-label={t("editor.sectionsTree")} className="cl-editor__tree">
          <h3>{t("editor.sectionsTree")}</h3>
          <Button onClick={() => setPickerOpen((open) => !open)} size="small">
            {t("editor.addSection")}
          </Button>
          <Button onClick={() => { setThemeMode(true); setSelectedId(null); }} size="small" variant="ghost">
            {t("editor.themeSettings")}
          </Button>
          {pickerOpen ? (
            <ul aria-label={t("editor.sectionPicker")} className="cl-editor__picker">
              {(data?.sectionCatalog ?? []).length === 0 ? (
                <li className="cl-card-note">{t("editor.pickerEmpty")}</li>
              ) : (
                (data?.sectionCatalog ?? []).map((entry) => (
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
                      <li key={`${band}:${sectionId}`}>
                        <div className="cl-editor__noderow">
                          <button
                            aria-pressed={isActive}
                            className={isActive ? "cl-editor__node cl-editor__node--active" : "cl-editor__node"}
                            onClick={() => { setSelectedBand(band); setSelectedId(sectionId); setSelectedBlockId(null); setThemeMode(false); }}
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
                                  <li className="cl-editor__block" key={blockId}>
                                    <button
                                      aria-pressed={blockActive}
                                      className={blockActive ? "cl-editor__node cl-editor__node--active" : "cl-editor__node"}
                                      onClick={() => { setSelectedBand(band); setSelectedId(sectionId); setSelectedBlockId(blockId); setThemeMode(false); }}
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
        </aside>

        <main className="cl-editor__preview">
          <iframe
            className="cl-editor__iframe"
            ref={iframeRef}
            src={previewSrc}
            title={t("editor.previewTitle")}
          />
        </main>

        <aside aria-label={themeMode ? t("editor.themeSettings") : t("editor.settingsPanel")} className="cl-editor__settings">
          <h3>{themeMode ? t("editor.themeSettings") : t("editor.settingsPanel")}</h3>
          {!themeMode && selected && selectedId && selectedBlockId ? (
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
          ) : themeMode ? (
            (data?.settingsSchema ?? []).map((group) => (
              <section key={group.name}>
                <h4 className="cl-editor__group">{group.name}</h4>
                {group.settings.map((def, index) => (
                  <SettingControl
                    def={def}
                    key={def.id ?? `static-${index}`}
                    onChange={(value) => def.id && setThemeSetting(def.id, value)}
                    value={def.id ? (settingsDraft ?? {})[def.id] : undefined}
                  />
                ))}
              </section>
            ))
          ) : selected && selectedId ? (
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
            </>
          ) : (
            <p className="cl-card-note">{t("editor.selectHint")}</p>
          )}
        </aside>
      </div>
    </div>
  );
}
