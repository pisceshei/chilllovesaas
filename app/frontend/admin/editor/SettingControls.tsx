import {
  AlignCenter, AlignLeft, AlignRight, Bold, Check, ChevronsUpDown, Database, ExternalLink, Italic, Link2, List,
  ListOrdered, Pilcrow, Underline,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { Popover } from "../components/Popover";
import { useT } from "../i18n/I18nContext";

/**
 * 右欄設定控件庫（E4；`docs/research/100` §3 逐型別實測形＋官方 input-settings 逐字，取證 2026-09-03）。
 *
 * ①這是什麼：每個 schema setting 型別對應一個控件；`SettingRow` 負責兩欄列（標籤／說明／控件）與 `header`／
 *   `paragraph` 兩種無值列。`visible_if` 由呼叫端（SettingsPanel）先過濾，這裡不判。
 * ②值語義（官方逐字節錄，全文 `docs/dev/external-facts.md` §F7）：checkbox 未給 default ⇒ false；radio／select 未給
 *   default ⇒ 第一個選項；range 的 min／max／step／default 不可為字串；text_alignment 未給 default ⇒ `left`；
 *   font_picker 必帶 default；video_url 必帶 `accept`（youtube／vimeo）。`effective`＝實例值 ?? default 照這些規則。
 * ③形態（100 §3）：range＝滑桿＋右側數字框＋單位後綴；select＝⌃⌄ 下拉（options[].group ⇒ optgroup）；radio＝藥丸分段；
 *   checkbox＝右對齊 toggle；color＝色票＋HEX＋資料庫 icon，popover 內 SV 方塊／HEX／色相／透明度（Escape 不關、點外關）；
 *   color_scheme＝「Aa」預覽＋Scheme N＋⌃⌄，popover 列全部 scheme（選中打勾）＋ Edit；font_picker＝「A」＋字型名＋⌃⌄
 *   ⇒ 右欄整面選字型（由 panel 承接）；image_picker＝虛線框 Select＋Explore free images；link_list＝清單 icon＋選單名
 *   ⇒ Replace／Edit ↗／Remove menu；url＝"Paste a link or search"；liquid／html＝帶行號碼編輯器。
 * ④未做（E4b／E5，這裡先以唯讀形登記）：product／collection／page／blog／article（含 *_list）、video、metaobject*、
 *   color_scheme_group 的 Editing Scheme 子面板、image_picker 的檔案庫 modal（由 panel 的 `onOpenImagePicker` 承接）。
 * ⑤跨功能影響：`SettingsPanel`（section／block 面板）與 `ThemeEditorPage` 的佈景設定手風琴共用；值寫回仍走頁面的
 *   `applyOp` 快照棧；`visible_if` 求值在 `visibleIf.ts`。
 */
export interface SettingOption { value: string; label: string; group?: string }

export interface SettingDef {
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
  options?: SettingOption[];
  visible_if?: string;
  alpha?: boolean;
  accept?: string[];
  limit?: number;
  definition?: SettingDef[];
  role?: Record<string, unknown>;
}

export interface SchemeOption { id: string; label: string; background: string; text: string; button: string }
export interface FontFamily { key: string; name: string; system: boolean; handles: string[] }
export interface MenuOption { handle: string; title: string }

export interface ControlContext {
  schemes: SchemeOption[];
  fonts: FontFamily[];
  menus: MenuOption[];
  /** color_scheme 的 "Edit" 連結／color_scheme_group 的縮圖點擊（E4b 的 Editing Scheme） */
  onEditScheme?: (schemeId: string) => void;
  /** font_picker 點開 ⇒ 右欄整面選字型（panel 承接） */
  onOpenFontPicker?: (request: { def: SettingDef; value: string; onChange: (value: string) => void }) => void;
  /** image_picker 的 Select ⇒ 檔案庫 modal（panel 承接） */
  onOpenImagePicker?: (request: { def: SettingDef; value: string; onChange: (value: string) => void }) => void;
}

/** 官方 default 規則（見檔頭②）後的有效值。 */
export function effectiveValue(def: SettingDef, value: unknown): unknown {
  if (value !== undefined && value !== null) return value;
  if (def.default !== undefined) return def.default;
  switch (def.type) {
    case "checkbox": return false;
    case "radio":
    case "select": return def.options?.[0]?.value;
    case "text_alignment": return "left";
    default: return undefined;
  }
}

const RESOURCE_TYPES = new Set([ "product", "collection", "page", "blog", "article", "product_list", "collection_list",
  "article_list", "video", "metaobject", "metaobject_list" ]);

interface RowProps {
  def: SettingDef;
  value: unknown;
  onChange: (value: unknown) => void;
  ctx: ControlContext;
}

/** 一列（含 header／paragraph）。 */
export function SettingRow({ def, value, onChange, ctx }: RowProps) {
  const t = useT();
  if (def.type === "header") return <h4 className="cl-panel__header">{def.content}</h4>;
  if (def.type === "paragraph") return <p className="cl-panel__paragraph">{def.content}</p>;
  if (!def.id) return null;

  const effective = effectiveValue(def, value);
  const inputId = `setting-${def.id}`;
  const label = def.label ?? def.id;
  let control: ReactNode = null;
  let side: ReactNode = null; // 標籤列右側（toggle／range 數字框）

  switch (def.type) {
    case "checkbox":
      side = (
        <button
          aria-checked={Boolean(effective)}
          aria-labelledby={`${inputId}-label`}
          className={`cl-switch${effective ? " cl-switch--on" : ""}`}
          id={inputId}
          onClick={() => onChange(!effective)}
          role="switch"
          type="button"
        >
          <span aria-hidden="true" className="cl-switch__knob" />
        </button>
      );
      break;
    case "range": {
      const step = def.step ?? 1;
      const decimals = String(step).includes(".") ? String(step).split(".")[1].length : 0;
      const numeric = typeof effective === "number" ? effective : Number(effective ?? def.min ?? 0);
      side = (
        <span className="cl-ctl-range__value">
          <input
            aria-label={label}
            className="cl-ctl-range__number"
            id={inputId}
            max={def.max}
            min={def.min}
            onChange={(event) => onChange(Number(event.target.value))}
            step={step}
            type="number"
            value={numeric.toFixed(decimals)}
          />
          {def.unit ? <span className="cl-ctl-range__unit">{def.unit}</span> : null}
        </span>
      );
      control = (
        <input
          aria-label={`${label} slider`}
          className="cl-ctl-range__slider"
          max={def.max}
          min={def.min}
          onChange={(event) => onChange(Number(event.target.value))}
          step={step}
          type="range"
          value={numeric}
        />
      );
      break;
    }
    case "select": {
      const groups = new Map<string, SettingOption[]>();
      for (const option of def.options ?? []) {
        const key = option.group ?? "";
        groups.set(key, [ ...(groups.get(key) ?? []), option ]);
      }
      control = (
        <span className="cl-ctl-select">
          <select id={inputId} onChange={(event) => onChange(event.target.value)} value={String(effective ?? "")}>
            {[ ...groups.entries() ].map(([ group, options ]) => (group
              ? <optgroup key={group} label={group}>{options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}</optgroup>
              : options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)))}
          </select>
          <ChevronsUpDown aria-hidden="true" size={16} />
        </span>
      );
      break;
    }
    case "radio":
      control = (
        <span aria-labelledby={`${inputId}-label`} className="cl-ctl-seg" role="radiogroup">
          {(def.options ?? []).map((option) => (
            <button
              aria-checked={String(effective ?? "") === option.value}
              className={`cl-ctl-seg__item${String(effective ?? "") === option.value ? " is-active" : ""}`}
              key={option.value}
              onClick={() => onChange(option.value)}
              role="radio"
              type="button"
            >
              {option.label}
            </button>
          ))}
        </span>
      );
      break;
    case "text_alignment":
      control = (
        <span aria-labelledby={`${inputId}-label`} className="cl-ctl-seg" role="radiogroup">
          {([ [ "left", AlignLeft, t("editor.alignLeft") ], [ "center", AlignCenter, t("editor.alignCenter") ],
              [ "right", AlignRight, t("editor.alignRight") ] ] as const).map(([ key, Icon, name ]) => (
            <button
              aria-checked={String(effective ?? "left") === key}
              aria-label={name}
              className={`cl-ctl-seg__item${String(effective ?? "left") === key ? " is-active" : ""}`}
              key={key}
              onClick={() => onChange(key)}
              role="radio"
              type="button"
            >
              <Icon aria-hidden="true" size={16} />
            </button>
          ))}
        </span>
      );
      break;
    case "color":
      control = <ColorControl alpha={Boolean(def.alpha)} id={inputId} label={label} onChange={onChange} value={String(effective ?? "")} />;
      break;
    case "color_background":
      control = (
        <input className="cl-field__input" id={inputId} onChange={(event) => onChange(event.target.value)}
          placeholder={def.placeholder} value={String(effective ?? "")} />
      );
      break;
    case "color_scheme":
      control = <ColorSchemeControl ctx={ctx} id={inputId} label={label} onChange={onChange} value={String(effective ?? "")} />;
      break;
    case "color_scheme_group":
      control = (
        <div className="cl-ctl-schemes" role="list">
          {ctx.schemes.map((scheme) => (
            <button className="cl-ctl-schemes__cell" key={scheme.id} onClick={() => ctx.onEditScheme?.(scheme.id)} role="listitem" type="button">
              <SchemeChip scheme={scheme} />
              <span>{scheme.label}</span>
            </button>
          ))}
        </div>
      );
      break;
    case "font_picker": {
      const handle = String(effective ?? "");
      const family = ctx.fonts.find((f) => handle.startsWith(`${f.key}_`));
      control = (
        <button
          aria-haspopup="dialog"
          className="cl-ctl-picker"
          id={inputId}
          onClick={() => ctx.onOpenFontPicker?.({ def, value: handle, onChange: (next) => onChange(next) })}
          type="button"
        >
          <span aria-hidden="true" className="cl-ctl-picker__glyph">A</span>
          <span className="cl-ctl-picker__text">{family?.name ?? handle}</span>
          <ChevronsUpDown aria-hidden="true" size={16} />
        </button>
      );
      break;
    }
    case "image_picker": {
      const current = String(effective ?? "");
      control = current ? (
        <div className="cl-ctl-image cl-ctl-image--set">
          <span className="cl-ctl-image__name">{current.split("/").pop()}</span>
          <button className="cl-link" onClick={() => ctx.onOpenImagePicker?.({ def, value: current, onChange: (next) => onChange(next) })} type="button">{t("editor.change")}</button>
          <button className="cl-link" onClick={() => onChange("")} type="button">{t("common.remove")}</button>
        </div>
      ) : (
        <div className="cl-ctl-image">
          <button className="cl-ctl-image__select" id={inputId} onClick={() => ctx.onOpenImagePicker?.({ def, value: "", onChange: (next) => onChange(next) })} type="button">
            {t("editor.select")}
            <Database aria-hidden="true" size={14} />
          </button>
          <span className="cl-ctl-image__explore">{t("editor.exploreFreeImages")}</span>
        </div>
      );
      break;
    }
    case "link_list":
      control = <LinkListControl ctx={ctx} id={inputId} label={label} onChange={onChange} value={String(effective ?? "")} />;
      break;
    case "url":
      control = (
        <span className="cl-ctl-url">
          <input className="cl-field__input" id={inputId} onChange={(event) => onChange(event.target.value)}
            placeholder={t("editor.urlPlaceholder")} value={String(effective ?? "")} />
          <Database aria-hidden="true" size={16} />
        </span>
      );
      break;
    case "video_url": {
      const current = String(effective ?? "");
      const accept = def.accept ?? [];
      const host = /youtu\.?be/.test(current) ? "youtube" : /vimeo\.com/.test(current) ? "vimeo" : null;
      const invalid = current !== "" && (host === null || (accept.length > 0 && !accept.includes(host)));
      control = (
        <>
          <input aria-invalid={invalid} className={`cl-field__input${invalid ? " cl-field__input--error" : ""}`} id={inputId}
            onChange={(event) => onChange(event.target.value)} placeholder={def.placeholder} value={current} />
          {invalid ? <p className="cl-field__error">{t("editor.videoUrlInvalid", { hosts: accept.join(" / ") })}</p> : null}
        </>
      );
      break;
    }
    case "number":
      control = (
        <input className="cl-field__input" id={inputId} max={def.max} min={def.min}
          onChange={(event) => onChange(event.target.value === "" ? null : Number(event.target.value))}
          placeholder={def.placeholder} type="number" value={effective == null ? "" : Number(effective)} />
      );
      break;
    case "textarea":
      control = (
        <textarea className="cl-field__input cl-field__textarea" id={inputId} onChange={(event) => onChange(event.target.value)}
          placeholder={def.placeholder} rows={3} value={String(effective ?? "")} />
      );
      break;
    case "html":
    case "liquid":
      control = <CodeControl id={inputId} onChange={(next) => onChange(next)} placeholder={def.placeholder} value={String(effective ?? "")} />;
      break;
    case "richtext":
    case "inline_richtext":
      control = <RichTextControl id={inputId} inline={def.type === "inline_richtext"} onChange={(next) => onChange(next)} value={String(effective ?? "")} />;
      break;
    case "text":
      control = (
        <input className="cl-field__input" id={inputId} onChange={(event) => onChange(event.target.value)}
          placeholder={def.placeholder} value={String(effective ?? "")} />
      );
      break;
    default:
      if (RESOURCE_TYPES.has(def.type)) {
        // E4b／E5：資源 picker；先唯讀顯示現值（不得靜默吞掉既有值）
        control = (
          <span className="cl-ctl-resource" data-type={def.type} id={inputId}>
            <span className="cl-ctl-resource__value">{effective == null || effective === "" ? t("editor.none") : String(Array.isArray(effective) ? effective.join(", ") : effective)}</span>
            <button className="cl-ctl-image__select" disabled type="button">{t("editor.select")}</button>
          </span>
        );
      } else {
        control = <code>{JSON.stringify(effective ?? null)}</code>;
      }
  }

  return (
    <div className="cl-panel__row" data-type={def.type}>
      <div className="cl-panel__labelrow">
        <label className="cl-panel__label" htmlFor={inputId} id={`${inputId}-label`}>{label}</label>
        {side}
      </div>
      {control ? <div className="cl-panel__control">{control}</div> : null}
      {def.info ? <p className="cl-panel__info">{def.info}</p> : null}
    </div>
  );
}

// ── color ────────────────────────────────────────────────────────────────
interface RGBA { r: number; g: number; b: number; a: number }

export function parseColor(input: string): RGBA | null {
  const value = input.trim();
  const hex = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(value);
  if (hex) {
    const n = parseInt(hex[1], 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a: hex[2] ? parseInt(hex[2], 16) / 255 : 1 };
  }
  const short = /^#([0-9a-f]{3})$/i.exec(value);
  if (short) {
    const [ r, g, b ] = short[1].split("").map((c) => parseInt(c + c, 16));
    return { r, g, b, a: 1 };
  }
  const rgba = /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?\s*\)$/i.exec(value);
  if (rgba) return { r: Number(rgba[1]), g: Number(rgba[2]), b: Number(rgba[3]), a: rgba[4] === undefined ? 1 : Number(rgba[4]) };
  return null;
}

export function formatColor({ r, g, b, a }: RGBA): string {
  const hex = `#${[ r, g, b ].map((c) => Math.round(c).toString(16).padStart(2, "0")).join("")}`;
  return a >= 1 ? hex : `rgba(${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)}, ${Number(a.toFixed(2))})`;
}

function rgbToHsv({ r, g, b }: RGBA): { h: number; s: number; v: number } {
  const rr = r / 255, gg = g / 255, bb = b / 255;
  const max = Math.max(rr, gg, bb), min = Math.min(rr, gg, bb), d = max - min;
  let h = 0;
  if (d !== 0) {
    if (max === rr) h = ((gg - bb) / d) % 6;
    else if (max === gg) h = (bb - rr) / d + 2;
    else h = (rr - gg) / d + 4;
    h = (h * 60 + 360) % 360;
  }
  return { h, s: max === 0 ? 0 : d / max, v: max };
}

function hsvToRgb(h: number, s: number, v: number): { r: number; g: number; b: number } {
  const c = v * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = v - c;
  const [ r, g, b ] = h < 60 ? [ c, x, 0 ] : h < 120 ? [ x, c, 0 ] : h < 180 ? [ 0, c, x ]
    : h < 240 ? [ 0, x, c ] : h < 300 ? [ x, 0, c ] : [ c, 0, x ];
  return { r: (r + m) * 255, g: (g + m) * 255, b: (b + m) * 255 };
}

function ColorControl({ id, label, value, alpha, onChange }: {
  id: string; label: string; value: string; alpha: boolean; onChange: (value: unknown) => void;
}) {
  const t = useT();
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const squareRef = useRef<HTMLDivElement | null>(null);
  const [ open, setOpen ] = useState(false);
  const parsed = parseColor(value);
  const [ hsv, setHsv ] = useState(() => (parsed ? rgbToHsv(parsed) : { h: 0, s: 0, v: 0 }));
  const [ hexDraft, setHexDraft ] = useState(value);
  useEffect(() => { setHexDraft(value); const p = parseColor(value); if (p) setHsv(rgbToHsv(p)); }, [ value ]);
  const alphaValue = parsed?.a ?? 1;

  const commit = (next: { h: number; s: number; v: number }, a = alphaValue) => {
    setHsv(next);
    onChange(formatColor({ ...hsvToRgb(next.h, next.s, next.v), a }));
  };
  const pickFromSquare = (event: ReactPointerEvent<HTMLDivElement>) => {
    const rect = squareRef.current?.getBoundingClientRect();
    if (!rect) return;
    const s = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
    const v = 1 - Math.min(1, Math.max(0, (event.clientY - rect.top) / rect.height));
    commit({ h: hsv.h, s, v });
  };
  const transparent = !parsed || parsed.a === 0;
  const swatchStyle = parsed && parsed.a > 0 ? { background: formatColor(parsed) } : undefined;

  return (
    <>
      <button aria-expanded={open} aria-haspopup="dialog" className="cl-ctl-color" id={id} onClick={() => setOpen((on) => !on)} ref={anchorRef} type="button">
        <span aria-hidden="true" className={`cl-ctl-color__swatch${transparent ? " is-transparent" : ""}`} style={swatchStyle} />
        <span className="cl-ctl-color__text">{transparent ? t("editor.transparent") : value.toUpperCase()}</span>
        <Database aria-hidden="true" size={16} />
      </button>
      <Popover anchorRef={anchorRef} dismissOnOutsideClick label={label} onClose={() => setOpen(false)} open={open}>
        <div className="cl-colorpicker" role="dialog" aria-label={label}>
          <div
            className="cl-colorpicker__square"
            onPointerDown={(event) => { event.currentTarget.setPointerCapture(event.pointerId); pickFromSquare(event); }}
            onPointerMove={(event) => { if (event.buttons & 1) pickFromSquare(event); }}
            ref={squareRef}
            role="presentation"
            style={{ background: `linear-gradient(to top, #000, transparent), linear-gradient(to right, #fff, hsl(${hsv.h} 100% 50%))` }}
          >
            <span className="cl-colorpicker__cursor" style={{ left: `${hsv.s * 100}%`, top: `${(1 - hsv.v) * 100}%` }} />
          </div>
          <label className="cl-colorpicker__field">
            <span className="cl-colorpicker__prefix">#</span>
            <input
              aria-label={t("editor.hex")}
              onBlur={() => { const p = parseColor(hexDraft.startsWith("#") ? hexDraft : `#${hexDraft}`); if (p) onChange(formatColor({ ...p, a: alpha ? alphaValue : 1 })); else setHexDraft(value); }}
              onChange={(event) => setHexDraft(event.target.value.replace(/^#/, ""))}
              value={hexDraft.replace(/^#/, "").replace(/^rgba?.*$/, "")}
            />
          </label>
          <input aria-label={t("editor.hue")} className="cl-colorpicker__hue" max={360} min={0} onChange={(event) => commit({ ...hsv, h: Number(event.target.value) })} type="range" value={Math.round(hsv.h)} />
          {alpha ? (
            <input aria-label={t("editor.alpha")} className="cl-colorpicker__alpha" max={100} min={0}
              onChange={(event) => commit(hsv, Number(event.target.value) / 100)} type="range" value={Math.round(alphaValue * 100)} />
          ) : null}
        </div>
      </Popover>
    </>
  );
}

// ── color scheme ─────────────────────────────────────────────────────────
function SchemeChip({ scheme }: { scheme: SchemeOption }) {
  return (
    <span aria-hidden="true" className="cl-ctl-scheme__chip" style={{ background: scheme.background, color: scheme.text }}>
      Aa
      <span className="cl-ctl-scheme__dot" style={{ background: scheme.button }} />
    </span>
  );
}

function ColorSchemeControl({ id, label, value, ctx, onChange }: {
  id: string; label: string; value: string; ctx: ControlContext; onChange: (value: unknown) => void;
}) {
  const t = useT();
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const [ open, setOpen ] = useState(false);
  const current = ctx.schemes.find((s) => s.id === value) ?? ctx.schemes[0];
  return (
    <>
      <button aria-expanded={open} aria-haspopup="listbox" className="cl-ctl-picker" id={id} onClick={() => setOpen((on) => !on)} ref={anchorRef} type="button">
        {current ? <SchemeChip scheme={current} /> : null}
        <span className="cl-ctl-picker__text">{current?.label ?? value}</span>
        <ChevronsUpDown aria-hidden="true" size={16} />
      </button>
      <Popover anchorRef={anchorRef} dismissOnOutsideClick label={label} onClose={() => setOpen(false)} open={open}>
        <ul className="cl-ctl-scheme__list" role="listbox">
          {ctx.schemes.map((scheme) => (
            <li key={scheme.id}>
              <button aria-selected={scheme.id === current?.id} className="cl-ctl-scheme__option" onClick={() => { onChange(scheme.id); setOpen(false); }} role="option" type="button">
                <SchemeChip scheme={scheme} />
                <span>{scheme.label}</span>
                {scheme.id === current?.id ? <Check aria-hidden="true" size={16} /> : null}
              </button>
              {scheme.id === current?.id && ctx.onEditScheme ? (
                <button className="cl-link cl-ctl-scheme__edit" onClick={() => { setOpen(false); ctx.onEditScheme?.(scheme.id); }} type="button">{t("common.edit")}</button>
              ) : null}
            </li>
          ))}
        </ul>
      </Popover>
    </>
  );
}

// ── link_list ────────────────────────────────────────────────────────────
function LinkListControl({ id, label, value, ctx, onChange }: {
  id: string; label: string; value: string; ctx: ControlContext; onChange: (value: unknown) => void;
}) {
  const t = useT();
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const [ open, setOpen ] = useState<"menu" | "replace" | null>(null);
  const [ query, setQuery ] = useState("");
  const current = ctx.menus.find((m) => m.handle === value);
  const filtered = ctx.menus.filter((m) => !query.trim() || m.title.toLowerCase().includes(query.trim().toLowerCase()));
  return (
    <>
      <button aria-expanded={open !== null} aria-haspopup="menu" className="cl-ctl-picker" id={id} onClick={() => setOpen((on) => (on ? null : "menu"))} ref={anchorRef} type="button">
        <List aria-hidden="true" size={16} />
        <span className="cl-ctl-picker__text">{current?.title ?? (value || t("editor.none"))}</span>
        <ChevronsUpDown aria-hidden="true" size={16} />
      </button>
      <Popover anchorRef={anchorRef} dismissOnOutsideClick label={label} onClose={() => setOpen(null)} open={open !== null}>
        {open === "menu" ? (
          <ul className="cl-editor__menu" role="menu">
            <li><button className="cl-editor__menuitem" onClick={() => setOpen("replace")} role="menuitem" type="button">{t("editor.replace")}</button></li>
            <li><a className="cl-editor__menuitem" href="/admin/content/menus" rel="noreferrer" role="menuitem" target="_blank">{t("common.edit")} <ExternalLink aria-hidden="true" size={14} /></a></li>
            <li><button className="cl-editor__menuitem cl-editor__menuitem--critical" onClick={() => { onChange(""); setOpen(null); }} role="menuitem" type="button">{t("editor.removeMenu")}</button></li>
          </ul>
        ) : (
          <div className="cl-editor__menu">
            <div className="cl-editor__menusearch">
              <input aria-label={t("editor.searchResources")} data-autofocus onChange={(event) => setQuery(event.target.value)} placeholder={t("editor.searchResources")} value={query} />
            </div>
            <ul className="cl-editor__menulist" role="listbox">
              {filtered.map((menu) => (
                <li key={menu.handle}>
                  <button aria-selected={menu.handle === value} className="cl-editor__menuitem" onClick={() => { onChange(menu.handle); setOpen(null); }} role="option" type="button">
                    {menu.title}{menu.handle === value ? <Check aria-hidden="true" size={14} /> : null}
                  </button>
                </li>
              ))}
              <li><a className="cl-editor__menuitem" href="/admin/content/menus/new" rel="noreferrer" target="_blank">＋ {t("editor.createMenu")}</a></li>
            </ul>
          </div>
        )}
      </Popover>
    </>
  );
}

// ── code（liquid／html／custom CSS）：帶行號的等寬編輯器 ─────────────────
export function CodeControl({ id, value, placeholder, onChange, maxLength, ariaLabel }: {
  id?: string; value: string; placeholder?: string; onChange: (value: string) => void; maxLength?: number; ariaLabel?: string;
}) {
  const lines = useMemo(() => Math.max(1, value.split("\n").length), [ value ]);
  return (
    <div className="cl-ctl-code">
      <ol aria-hidden="true" className="cl-ctl-code__gutter">
        {Array.from({ length: lines }, (_, index) => <li key={index}>{index + 1}</li>)}
      </ol>
      <textarea
        aria-label={ariaLabel}
        className="cl-ctl-code__area"
        id={id}
        maxLength={maxLength}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder ?? "h2 { font-size: 32px; }"}
        rows={Math.min(12, Math.max(4, lines))}
        spellCheck={false}
        value={value}
      />
    </div>
  );
}

// ── richtext／inline_richtext：迷你 RTE（官方：richtext＝Bold/Italic/Underline/Link/Paragraph/Unordered list；
//    inline_richtext＝Bold/Italic/Link，"doesn't support line breaks (<br />) or underline"） ──
function RichTextControl({ id, value, inline, onChange }: { id: string; value: string; inline: boolean; onChange: (value: string) => void }) {
  const t = useT();
  const ref = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (ref.current && ref.current.innerHTML !== value) ref.current.innerHTML = value;
  }, [ value ]);
  const exec = (command: string, arg?: string) => {
    ref.current?.focus();
    document.execCommand(command, false, arg);
    onChange(ref.current?.innerHTML ?? "");
  };
  const tools: [ string, ReactNode, () => void ][] = [
    [ t("editor.bold"), <Bold aria-hidden="true" key="b" size={14} />, () => exec("bold") ],
    [ t("editor.italic"), <Italic aria-hidden="true" key="i" size={14} />, () => exec("italic") ],
    ...(inline ? [] : [ [ t("editor.underline"), <Underline aria-hidden="true" key="u" size={14} />, () => exec("underline") ] as [ string, ReactNode, () => void ] ]),
    [ t("editor.link"), <Link2 aria-hidden="true" key="l" size={14} />, () => { const url = window.prompt(t("editor.linkUrl")); if (url) exec("createLink", url); } ],
    ...(inline ? [] : [
      [ t("editor.paragraph"), <Pilcrow aria-hidden="true" key="p" size={14} />, () => exec("formatBlock", "p") ] as [ string, ReactNode, () => void ],
      [ t("editor.bulletList"), <ListOrdered aria-hidden="true" key="ul" size={14} />, () => exec("insertUnorderedList") ] as [ string, ReactNode, () => void ],
    ]),
  ];
  return (
    <div className="cl-ctl-rte">
      <div className="cl-ctl-rte__toolbar" role="toolbar">
        {tools.map(([ name, icon, run ]) => (
          <button aria-label={name} className="cl-ctl-rte__tool" key={name} onMouseDown={(event) => event.preventDefault()} onClick={run} type="button">{icon}</button>
        ))}
      </div>
      <div
        aria-label={t("editor.richtext")}
        aria-multiline={!inline}
        className={`cl-ctl-rte__area${inline ? " cl-ctl-rte__area--inline" : ""}`}
        contentEditable
        id={id}
        onInput={(event) => onChange((event.currentTarget as HTMLDivElement).innerHTML)}
        onKeyDown={(event) => { if (inline && event.key === "Enter") event.preventDefault(); }}
        ref={ref}
        role="textbox"
        suppressContentEditableWarning
      />
    </div>
  );
}
