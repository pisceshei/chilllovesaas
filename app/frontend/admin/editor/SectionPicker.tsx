import { ChevronDown, ChevronUp, Layers, Search, Sparkles } from "lucide-react";
import { useMemo, useState, type ReactNode, type RefObject } from "react";
import { Popover } from "../components/Popover";
import { useT } from "../i18n/I18nContext";

/**
 * 區段／區塊 picker（E5；`docs/research/100` §4 兩者同一元件＋§8.1 1:1 量測）。
 *
 * ①這是什麼：popover，錨點＝左樹 "Add section"／"Add block" 列（貼左欄右緣、與該列同高）；左欄＝搜尋框
 *   （"Search sections"／"Search blocks"）→ "Sections｜Apps"（"Blocks｜Apps"）分段 → 首列 "Generate"（AI 星芒；我方無 AI ⇒
 *   顯示但不可用，登記）→ **該群組／模板可用的扁平清單**（達 `limit`／`max_blocks` 者灰化並標 "(n/limit)"）→ 依分類收合區
 *   （preset／block schema 的 `category`，翻譯後；無分類歸「其他」）；右欄＝hover 項目的預覽（呼叫端給 `renderPreview`，
 *   拿不到 ⇒ "No preview available"）；Apps 分頁＝空態句（無 app 層）。
 * ②選取：點項目 ⇒ `onPick(item)`；`disabled` 項不可點。
 * ③跨功能影響：`ThemeEditorPage`（section 候選＝`pickerEntries`：過濾與 (n/limit) 在頁面；block 候選＝`addBlockOptions`）、
 *   `SectionsTree`（錨點列與插入線）。
 */
export interface PickerItem {
  key: string;
  name: string;
  category?: string | null;
  disabled?: boolean;
  /** 灰化後綴，如 "(1/1)" */
  suffix?: string;
  icon?: ReactNode;
}

export interface SectionPickerProps {
  open: boolean;
  anchorRef: RefObject<HTMLElement | null>;
  /** x 貼此元素右緣（左欄卡片）；未給 ⇒ 錨點右緣 */
  edgeRef?: RefObject<HTMLElement | null>;
  kind: "section" | "block";
  /** 扁平清單（已依可用性過濾、含灰化資訊）；分類收合區由本元件依 `category` 分組 */
  items: PickerItem[];
  onPick: (item: PickerItem) => void;
  onClose: () => void;
  /** hover 項目的預覽節點（無 ⇒ "No preview available"） */
  renderPreview?: (item: PickerItem) => ReactNode;
}

export function SectionPicker({ open, anchorRef, edgeRef, kind, items, onPick, onClose, renderPreview }: SectionPickerProps) {
  const t = useT();
  const [ query, setQuery ] = useState("");
  const [ tab, setTab ] = useState<"main" | "apps">("main");
  const [ hovered, setHovered ] = useState<PickerItem | null>(null);
  const [ collapsed, setCollapsed ] = useState<Set<string>>(() => new Set());

  const q = query.trim().toLowerCase();
  const visible = useMemo(() => items.filter((item) => !q || item.name.toLowerCase().includes(q)), [ items, q ]);
  const groups = useMemo(() => {
    const map = new Map<string, PickerItem[]>();
    for (const item of visible) {
      const key = item.category ?? "";
      map.set(key, [ ...(map.get(key) ?? []), item ]);
    }
    return [ ...map.entries() ].sort(([ a ], [ b ]) => (a === "" ? 1 : b === "" ? -1 : a.localeCompare(b)));
  }, [ visible ]);

  const row = (item: PickerItem) => (
    <li key={item.key}>
      <button
        className={`cl-picker__item${hovered?.key === item.key ? " is-active" : ""}`}
        disabled={item.disabled}
        onClick={() => onPick(item)}
        onFocus={() => setHovered(item)}
        onMouseEnter={() => setHovered(item)}
        type="button"
      >
        {item.icon ?? <Layers aria-hidden="true" size={16} />}
        <span>{item.name}{item.suffix ? ` ${item.suffix}` : ""}</span>
      </button>
    </li>
  );

  return (
    <Popover anchorRef={anchorRef} dismissOnOutsideClick edgeRef={edgeRef} label={kind === "section" ? t("editor.sectionPicker") : t("editor.addBlock")} onClose={onClose} open={open} placement="right-start">
      <div className="cl-picker" data-kind={kind}>
        <div className="cl-picker__list">
          <label className="cl-picker__search">
            <Search aria-hidden="true" size={14} />
            <input
              aria-label={kind === "section" ? t("editor.searchSections") : t("editor.searchBlocks")}
              data-autofocus
              onChange={(event) => setQuery(event.target.value)}
              placeholder={kind === "section" ? t("editor.searchSections") : t("editor.searchBlocks")}
              value={query}
            />
          </label>
          <div className="cl-picker__tabs" role="tablist">
            <button aria-selected={tab === "main"} className={`cl-picker__tab${tab === "main" ? " is-active" : ""}`} onClick={() => setTab("main")} role="tab" type="button">
              {kind === "section" ? t("editor.pickerSections") : t("editor.pickerBlocks")}
            </button>
            <button aria-selected={tab === "apps"} className={`cl-picker__tab${tab === "apps" ? " is-active" : ""}`} onClick={() => setTab("apps")} role="tab" type="button">
              {t("editor.pickerApps")}
            </button>
          </div>
          <div className="cl-picker__scroll">
            {tab === "apps" ? (
              <p className="cl-picker__empty">{kind === "section" ? t("editor.noAppSections") : t("editor.noAppBlocks")}</p>
            ) : (
              <>
                {/* 本尊首列 "Generate"（AI）：我方無 AI 入口 ⇒ 顯示登記形、不可用（100 §V V13） */}
                <button aria-disabled="true" className="cl-picker__generate" type="button">
                  <Sparkles aria-hidden="true" size={16} />
                  {t("editor.generate")}
                </button>
                <div className="cl-picker__sep" />
                {visible.length === 0 ? <p className="cl-picker__empty">{t("editor.pickerEmpty")}</p> : null}
                {/* 扁平清單＝無分類者；有分類者進收合區（本尊：先扁平可用清單、再分類收合區） */}
                <ul aria-label={kind === "section" ? t("editor.sectionPicker") : t("editor.addBlock")} className="cl-picker__items">
                  {(groups.find(([ key ]) => key === "")?.[1] ?? []).map(row)}
                </ul>
                {groups.filter(([ key ]) => key !== "").map(([ category, list ]) => (
                  <section key={category}>
                    <button
                      aria-expanded={!collapsed.has(category)}
                      className="cl-picker__group"
                      onClick={() => setCollapsed((current) => { const next = new Set(current); if (next.has(category)) next.delete(category); else next.add(category); return next; })}
                      type="button"
                    >
                      {category}
                      {collapsed.has(category) ? <ChevronDown aria-hidden="true" size={16} /> : <ChevronUp aria-hidden="true" size={16} />}
                    </button>
                    {collapsed.has(category) ? null : <ul aria-label={category} className="cl-picker__items">{list.map(row)}</ul>}
                  </section>
                ))}
              </>
            )}
          </div>
        </div>
        <div className="cl-picker__preview">
          {hovered && renderPreview ? (renderPreview(hovered) ?? t("editor.noPreview")) : t("editor.noPreview")}
        </div>
      </div>
    </Popover>
  );
}
