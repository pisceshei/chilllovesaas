import { Check, ChevronDown, ChevronUp, Code2, Copy, CopyPlus, Eye, EyeOff, MoreHorizontal, Pencil, Search, Trash2, X } from "lucide-react";
import { useMemo, useRef, useState, type ReactNode } from "react";
import { Button } from "../components/Button";
import { Popover } from "../components/Popover";
import { useT } from "../i18n/I18nContext";
import { CodeControl, SettingRow, type ControlContext, type FontFamily, type SettingDef } from "./SettingControls";
import { evaluateVisibleIf, type VisibleIfScope } from "./visibleIf";

/**
 * 右欄設定面板殼（E4；`docs/research/100` §3 結構逐字：標題列＝type icon＋名稱＋「…」＋「×」；「…」section＝
 * Copy／Duplicate／Rename／Hide／Edit code／Remove（紅），block＝Copy／Duplicate／Rename／Hide|Show／Edit code／Remove；
 * Rename＝就地改名（標題變輸入框、Enter 確定、Escape 取消）；內容兩欄列；尾部 section 的 "Theme Settings" 收合區
 * （該 section 引用到的全域設定，可直接改）與 "Custom CSS"；最後 "🗑 Remove section"／"Remove block"；面板本體可捲動、
 * 標題列固定）。
 *
 * ①`visible_if`：每列先以 `evaluateVisibleIf(def.visible_if, scope)` 過濾（隱藏的值不清）。
 * ②字型選擇：`font_picker` 點開 ⇒ 本面板整面切成 "Select {label}"（SYSTEM FONTS／OTHER FONTS 兩組＋字重＋Done；
 *   100 §3.8），Done 才寫回。
 * ③static block：不出 Remove／Duplicate（官方 F4：Cannot be removed or duplicated）。
 * ④跨功能影響：`ThemeEditorPage` 提供 ops 與資料；`SectionsTree` 的右鍵 Rename 與這裡的 Rename 同一 `startRename`。
 */
export interface PanelMenuActions {
  onCopy: () => void;
  onDuplicate?: () => void;
  onRename: () => void;
  onToggleHidden: () => void;
  hidden: boolean;
  onEditCode: () => void;
  onRemove?: () => void;
}

export interface SettingsPanelProps {
  kind: "section" | "block";
  typeIcon: ReactNode;
  title: string;
  renaming: boolean;
  renameValue: string;
  onRenameChange: (value: string) => void;
  onRenameCommit: () => void;
  onRenameCancel: () => void;
  onClose: () => void;
  menu: PanelMenuActions;
  defs: SettingDef[];
  values: Record<string, unknown>;
  onChange: (key: string, value: unknown) => void;
  scope: VisibleIfScope;
  ctx: ControlContext;
  /** 面板頂部的資訊句／連結句（block 面板的 "Displays variants from parent product" 類） */
  notes?: ReactNode;
  /** schema 沒定義但實例有的鍵（FallbackControl） */
  extras?: ReactNode;
  /** section 專屬：引用到的全域設定 */
  themeSettings?: { defs: SettingDef[]; values: Record<string, unknown>; onChange: (key: string, value: unknown) => void };
  /** section 專屬：Custom CSS（≤500 字，官方 add-css） */
  customCss?: { value: string; onChange: (value: string) => void; open: boolean; onToggle: (open: boolean) => void };
  removeLabel: string;
}

interface FontPickerState { def: SettingDef; value: string; onChange: (value: string) => void }

export function SettingsPanel(props: SettingsPanelProps) {
  const t = useT();
  const menuAnchor = useRef<HTMLButtonElement | null>(null);
  const [ menuOpen, setMenuOpen ] = useState(false);
  const [ fontPicker, setFontPicker ] = useState<FontPickerState | null>(null);
  const [ themeOpen, setThemeOpen ] = useState(false);

  const ctx = useMemo<ControlContext>(() => ({
    ...props.ctx,
    onOpenFontPicker: (request) => setFontPicker(request),
  }), [ props.ctx ]);

  const visibleDefs = props.defs.filter((def) => evaluateVisibleIf(def.visible_if, props.scope));

  return (
    <aside aria-label={t("editor.settingsPanel")} className="cl-editor__settings cl-panel">
      <div className="cl-panel__title">
        {fontPicker ? (
          <>
            <button aria-label={t("common.back")} className="cl-editor__iconbtn" onClick={() => setFontPicker(null)} type="button"><ChevronUp aria-hidden="true" size={16} /></button>
            <h3>{t("editor.selectFont", { label: fontPicker.def.label ?? fontPicker.def.id ?? "" })}</h3>
          </>
        ) : (
          <>
            <span aria-hidden="true" className="cl-panel__typeicon">{props.typeIcon}</span>
            {props.renaming ? (
              <input
                aria-label={t("editor.renamePrompt")}
                autoFocus
                className="cl-panel__rename"
                onBlur={props.onRenameCommit}
                onChange={(event) => props.onRenameChange(event.target.value)}
                onFocus={(event) => event.target.select()}
                onKeyDown={(event) => {
                  if (event.key === "Enter") { event.preventDefault(); props.onRenameCommit(); }
                  if (event.key === "Escape") { event.preventDefault(); props.onRenameCancel(); }
                }}
                value={props.renameValue}
              />
            ) : (
              <h3>{props.title}</h3>
            )}
            <button aria-expanded={menuOpen} aria-haspopup="menu" aria-label={t("editor.more")} className="cl-editor__iconbtn" onClick={() => setMenuOpen((on) => !on)} ref={menuAnchor} type="button">
              <MoreHorizontal aria-hidden="true" size={16} />
            </button>
            <Popover anchorRef={menuAnchor} dismissOnOutsideClick label={t("editor.more")} onClose={() => setMenuOpen(false)} open={menuOpen}>
              <ul className="cl-editor__menu" role="menu">
                <li><button className="cl-editor__menuitem" onClick={() => { props.menu.onCopy(); setMenuOpen(false); }} role="menuitem" type="button"><Copy aria-hidden="true" size={14} />{t("common.copy")}</button></li>
                {props.menu.onDuplicate ? <li><button className="cl-editor__menuitem" onClick={() => { props.menu.onDuplicate?.(); setMenuOpen(false); }} role="menuitem" type="button"><CopyPlus aria-hidden="true" size={14} />{t("editor.duplicate")}</button></li> : null}
                <li><button className="cl-editor__menuitem" onClick={() => { props.menu.onRename(); setMenuOpen(false); }} role="menuitem" type="button"><Pencil aria-hidden="true" size={14} />{t("editor.rename")}</button></li>
                <li><button className="cl-editor__menuitem" onClick={() => { props.menu.onToggleHidden(); setMenuOpen(false); }} role="menuitem" type="button">{props.menu.hidden ? <Eye aria-hidden="true" size={14} /> : <EyeOff aria-hidden="true" size={14} />}{props.menu.hidden ? t("editor.shortcuts.show") : t("editor.shortcuts.hide")}</button></li>
                <li><button className="cl-editor__menuitem" onClick={() => { props.menu.onEditCode(); setMenuOpen(false); }} role="menuitem" type="button"><Code2 aria-hidden="true" size={14} />{t("store.themes.editCode")}</button></li>
                {props.menu.onRemove ? (
                  <>
                    <li className="cl-tree__menusep" role="separator" />
                    <li><button className="cl-editor__menuitem cl-editor__menuitem--critical" onClick={() => { props.menu.onRemove?.(); setMenuOpen(false); }} role="menuitem" type="button"><Trash2 aria-hidden="true" size={14} />{t("common.remove")}</button></li>
                  </>
                ) : null}
              </ul>
            </Popover>
            <button aria-label={t("common.close")} className="cl-editor__iconbtn" onClick={props.onClose} type="button">
              <X aria-hidden="true" size={16} />
            </button>
          </>
        )}
      </div>

      <div className="cl-panel__body">
        {fontPicker ? (
          <FontPickerPanel
            fonts={ctx.fonts}
            onCancel={() => setFontPicker(null)}
            onDone={(handle) => { fontPicker.onChange(handle); setFontPicker(null); }}
            value={fontPicker.value}
          />
        ) : (
          <>
            {props.notes}
            {visibleDefs.map((def, index) => (
              <SettingRow
                ctx={ctx}
                def={def}
                key={def.id ?? `static-${index}`}
                onChange={(value) => def.id && props.onChange(def.id, value)}
                value={def.id ? props.values[def.id] : undefined}
              />
            ))}
            {props.extras}
            {props.themeSettings && props.themeSettings.defs.length > 0 ? (
              <section className="cl-panel__acc">
                <button aria-expanded={themeOpen} className="cl-panel__accbtn" onClick={() => setThemeOpen((on) => !on)} type="button">
                  {t("editor.themeSettings")}
                  {themeOpen ? <ChevronUp aria-hidden="true" size={16} /> : <ChevronDown aria-hidden="true" size={16} />}
                </button>
                {themeOpen ? props.themeSettings.defs.map((def, index) => (
                  <SettingRow
                    ctx={ctx}
                    def={def}
                    key={def.id ?? `theme-static-${index}`}
                    onChange={(value) => def.id && props.themeSettings?.onChange(def.id, value)}
                    value={def.id ? props.themeSettings?.values[def.id] : undefined}
                  />
                )) : null}
              </section>
            ) : null}
            {props.customCss ? (
              <section className="cl-panel__acc">
                <button aria-expanded={props.customCss.open} className="cl-panel__accbtn" onClick={() => props.customCss?.onToggle(!props.customCss.open)} type="button">
                  {t("editor.customCss")}
                  {props.customCss.open ? <ChevronUp aria-hidden="true" size={16} /> : <ChevronDown aria-hidden="true" size={16} />}
                </button>
                {props.customCss.open ? (
                  <>
                    <p className="cl-panel__info">{t("editor.customCssHelp")}</p>
                    <CodeControl ariaLabel={t("editor.customCss")} maxLength={500} onChange={props.customCss.onChange} value={props.customCss.value} />
                  </>
                ) : null}
              </section>
            ) : null}
            {props.menu.onRemove ? (
              <button className="cl-panel__remove" onClick={props.menu.onRemove} type="button">
                <Trash2 aria-hidden="true" size={14} /> {props.removeLabel}
              </button>
            ) : null}
          </>
        )}
      </div>
    </aside>
  );
}

/** font_picker 整面選字型（100 §3.8：搜尋 → SYSTEM FONTS／OTHER FONTS 各帶說明句 → 底部字型名＋字重＋Done）。 */
export function FontPickerPanel({ fonts, value, onDone, onCancel }: {
  fonts: FontFamily[]; value: string; onDone: (handle: string) => void; onCancel: () => void;
}) {
  const t = useT();
  const match = /^([a-z0-9_]+)_([nio])(\d)$/.exec(value);
  const [ family, setFamily ] = useState<string>(match?.[1] ?? fonts[0]?.key ?? "");
  const [ weight, setWeight ] = useState<string>(match ? `${match[2]}${match[3]}` : "n4");
  const [ query, setQuery ] = useState("");
  const q = query.trim().toLowerCase();
  const visible = fonts.filter((f) => !q || f.name.toLowerCase().includes(q));
  const system = visible.filter((f) => f.system);
  const other = visible.filter((f) => !f.system);
  const current = fonts.find((f) => f.key === family);
  const handles = current?.handles.length ? current.handles : [ "n4" ];
  const weightLabel = (handle: string) => {
    const w = Number(handle.slice(1)) * 100;
    const names: Record<number, string> = { 100: "Thin", 200: "Extra light", 300: "Light", 400: "Regular", 500: "Medium", 600: "Semi bold", 700: "Bold", 800: "Extra bold", 900: "Black" };
    return `${names[w] ?? w}${handle.startsWith("i") ? " italic" : ""}`;
  };
  const group = (title: string, note: string, items: FontFamily[]) => (items.length === 0 ? null : (
    <section className="cl-fontpicker__group">
      <h4 className="cl-fontpicker__heading">{title}</h4>
      <p className="cl-panel__info">{note}</p>
      <ul className="cl-fontpicker__list" role="listbox">
        {items.map((f) => (
          <li key={f.key}>
            <button aria-selected={f.key === family} className="cl-fontpicker__item" onClick={() => { setFamily(f.key); if (!f.handles.includes(weight)) setWeight(f.handles[0] ?? "n4"); }} role="option" style={{ fontFamily: f.system ? undefined : `"${f.name}", sans-serif` }} type="button">
              {f.name}{f.key === family ? <Check aria-hidden="true" size={16} /> : null}
            </button>
          </li>
        ))}
      </ul>
    </section>
  ));
  return (
    <div className="cl-fontpicker">
      <div className="cl-editor__menusearch">
        <Search aria-hidden="true" size={14} />
        <input aria-label={t("editor.searchResources")} data-autofocus onChange={(event) => setQuery(event.target.value)} placeholder={t("editor.searchResources")} value={query} />
      </div>
      <div className="cl-fontpicker__scroll">
        {group(t("editor.systemFonts"), t("editor.systemFontsNote"), system)}
        {group(t("editor.otherFonts"), t("editor.otherFontsNote"), other)}
      </div>
      <div className="cl-fontpicker__footer">
        <span className="cl-fontpicker__current">{current?.name ?? family}</span>
        <select aria-label={t("editor.fontWeight")} className="cl-field__input" onChange={(event) => setWeight(event.target.value)} value={weight}>
          {handles.map((h) => <option key={h} value={h}>{weightLabel(h)}</option>)}
        </select>
        <Button onClick={onCancel} size="small" variant="secondary">{t("common.cancel")}</Button>
        <Button onClick={() => onDone(`${family}_${weight}`)} size="small" variant="primary">{t("common.done")}</Button>
      </div>
    </div>
  );
}
