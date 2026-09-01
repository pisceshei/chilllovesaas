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
      sectionCatalog
      sectionSchemas
      settingsSchema
      themeSettingsJson
      themeSettingsLockVersion
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
    sectionSchemas: Record<string, { name: string; settings: SettingDef[] }>;
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
  const [draft, setDraft] = useState<TemplateJson | null>(null);
  const [undoStack, setUndoStack] = useState<TemplateJson[]>([]);
  const [redoStack, setRedoStack] = useState<TemplateJson[]>([]);
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

  const gid = `gid://chilllove/Theme/${themeId}`;

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<EditorData, { id: string; key: string }>(
        EDITOR_QUERY, { id: gid, key: templateKey }, signal);
      setData(result.theme);
      setDraft(result.theme?.templateJson ? cloneTpl(result.theme.templateJson) : null);
      setLockVersion(result.theme?.templateLockVersion ?? null);
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

  /** 每個 op 先推快照（undo 棧）再改 draft；redo 棧清空（14 §F3 快照棧語義）。 */
  const applyOp = useCallback((mutator: (tpl: TemplateJson) => void) => {
    setDraft((current) => {
      if (!current) return current;
      setUndoStack((stack) => [ ...stack.slice(-49), cloneTpl(current) ]);
      setRedoStack([]);
      const next = cloneTpl(current);
      mutator(next);
      setDirty(true);
      return next;
    });
  }, []);

  const undo = () => {
    setUndoStack((stack) => {
      if (stack.length === 0) return stack;
      const previous = stack[stack.length - 1];
      setDraft((current) => {
        if (current) setRedoStack((redo) => [ ...redo, cloneTpl(current) ]);
        return previous;
      });
      setDirty(true);
      return stack.slice(0, -1);
    });
  };

  const redo = () => {
    setRedoStack((stack) => {
      if (stack.length === 0) return stack;
      const next = stack[stack.length - 1];
      setDraft((current) => {
        if (current) setUndoStack((undoS) => [ ...undoS, cloneTpl(current) ]);
        return next;
      });
      setDirty(true);
      return stack.slice(0, -1);
    });
  };

  const orderOf = (tpl: TemplateJson) => tpl.order ?? Object.keys(tpl.sections ?? {});

  const toggleDisabled = (sectionId: string) => applyOp((tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (entry) entry.disabled = !entry.disabled; // 隱藏不是刪除（24 §3）
  });

  const removeSection = (sectionId: string) => applyOp((tpl) => {
    if (tpl.sections) delete tpl.sections[sectionId];
    tpl.order = orderOf(tpl).filter((id) => id !== sectionId);
    if (selectedId === sectionId) setSelectedId(null);
  });

  const moveSection = (sectionId: string, direction: -1 | 1) => applyOp((tpl) => {
    const order = [ ...orderOf(tpl) ];
    const index = order.indexOf(sectionId);
    const target = index + direction;
    if (index < 0 || target < 0 || target >= order.length) return;
    [ order[index], order[target] ] = [ order[target], order[index] ];
    tpl.order = order;
  });

  const duplicateSection = (sectionId: string) => applyOp((tpl) => {
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
    applyOp((tpl) => {
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
    });
    setPickerOpen(false);
  };

  /** 佈景設定寫值（16d2）：獨立 draft，不進模板快照棧（undo 整合＝16e）。 */
  const setThemeSetting = (settingKey: string, value: unknown) => {
    setSettingsDraft((current) => (current ? { ...current, [settingKey]: value } : current));
    setSettingsDirty(true);
  };

  const setSetting = (sectionId: string, settingKey: string, value: unknown) => applyOp((tpl) => {
    const entry = tpl.sections?.[sectionId];
    if (!entry) return;
    entry.settings = { ...(entry.settings ?? {}), [settingKey]: value };
  });

  const save = async () => {
    if (saving || (!dirty && !settingsDirty)) return;
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
  const selected = selectedId && draft?.sections ? draft.sections[selectedId] : null;
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
        <Button disabled={(!dirty && !settingsDirty) || saving} onClick={() => void save()} variant="primary">
          {t("common.save")}{dirty || settingsDirty ? " •" : ""}
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
          {order.length === 0 ? (
            <p className="cl-card-note">{t("editor.noSections")}</p>
          ) : (
            <ul>
              {order.map((sectionId, index) => {
                const entry = draft?.sections?.[sectionId];
                if (!entry) return null;
                return (
                  <li key={sectionId}>
                    <div className="cl-editor__noderow">
                      <button
                        aria-pressed={selectedId === sectionId}
                        className={selectedId === sectionId ? "cl-editor__node cl-editor__node--active" : "cl-editor__node"}
                        onClick={() => setSelectedId(sectionId)}
                        type="button"
                      >
                        {entry.type}
                      </button>
                      <button aria-label={t("editor.moveUp", { id: sectionId })} className="cl-editor__op" disabled={index === 0} onClick={() => moveSection(sectionId, -1)} type="button"><ArrowUp size={13} /></button>
                      <button aria-label={t("editor.moveDown", { id: sectionId })} className="cl-editor__op" disabled={index === order.length - 1} onClick={() => moveSection(sectionId, 1)} type="button"><ArrowDown size={13} /></button>
                      <button aria-label={entry.disabled ? t("editor.show", { id: sectionId }) : t("editor.hide", { id: sectionId })} className="cl-editor__op" onClick={() => toggleDisabled(sectionId)} type="button">
                        {entry.disabled ? <EyeOff size={13} /> : <Eye size={13} />}
                      </button>
                      <button aria-label={t("editor.duplicateOp", { id: sectionId })} className="cl-editor__op" onClick={() => duplicateSection(sectionId)} type="button"><Copy size={13} /></button>
                      <button aria-label={t("editor.removeOp", { id: sectionId })} className="cl-editor__op" onClick={() => removeSection(sectionId)} type="button"><Trash2 size={13} /></button>
                    </div>
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

        <aside aria-label={themeMode ? t("editor.themeSettings") : t("editor.settingsPanel")} className="cl-editor__settings">
          <h3>{themeMode ? t("editor.themeSettings") : t("editor.settingsPanel")}</h3>
          {themeMode ? (
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
