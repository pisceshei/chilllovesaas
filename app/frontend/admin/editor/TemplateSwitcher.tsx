import {
  ChevronDown, ChevronLeft, ChevronRight, CircleAlert, FileText, Gift, House, LayoutGrid, Lock,
  PenLine, Plus, Search, ShoppingBag, Star, Tag,
} from "lucide-react";
import { useMemo, useRef, useState, type ReactNode } from "react";
import { Popover } from "../components/Popover";
import { useT } from "../i18n/I18nContext";

/**
 * 頂欄模板選擇器（E2；本尊 "Home page ⌄" popover，`docs/research/100` §1.1 值域窮舉）。
 *
 * ①這是什麼：搜尋框＋第一層清單（Home page／Products ›／Collections ›／Collections list／
 *   Gift card／—／Cart／—／Pages ›／Blogs ›／Blog posts ›／—／Search／Password／404 page）；
 *   有替代模板的資源型（product／collection／page／blog／article）進第二層：星形的
 *   "Default {type}"＋替代模板列，每列副標 "Assigned to N …"，底部 "+ Create template"。
 * ②資料：`templateKeys`（來源 ∪ DB）決定清單有哪些項；`assignments[type][suffix]` 給計數
 *   （鍵 ""＝預設）。清單只列主題實際擁有的模板（本尊同——沒有 gift_card.json 就不出現）。
 * ③行為：選項 ⇒ `onSelect(key)`；再開 popover 停在上次子清單（本尊實測形態，100 §1.1）；
 *   搜尋時跨兩層扁平過濾。"Checkout and customer accounts"／"Create metaobject template"
 *   兩個離開編輯器的入口本包不做（100 §V V6；worklog 登記）。
 * ④跨功能影響：`ThemeEditorPage`（`?template=` 狀態、`CreateTemplateDialog`）、
 *   `ThemeType.templateKeys`／`templateAssignments`。
 */
export interface TemplateSwitcherProps {
  templateKeys: string[];
  assignments: Record<string, Record<string, number>>;
  current: string;
  onSelect: (key: string) => void;
  onCreate: (type: string) => void;
}

/** 資源型（有替代模板＋指派計數）。 */
const GROUP_TYPES = [ "product", "collection", "page", "blog", "article" ] as const;
type GroupType = (typeof GROUP_TYPES)[number];

/** 第一層順序（本尊逐字順序；`null`＝分隔線）。 */
const TOP_LEVEL: (string | null)[] = [
  "index", "product", "collection", "list-collections", "gift_card", null,
  "cart", null, "page", "blog", "article", null, "search", "password", "404",
];

function iconFor(type: string, size = 14): ReactNode {
  switch (type) {
    case "index": return <House aria-hidden="true" size={size} />;
    case "product": return <Tag aria-hidden="true" size={size} />;
    case "collection": return <LayoutGrid aria-hidden="true" size={size} />;
    case "list-collections": return <LayoutGrid aria-hidden="true" size={size} />;
    case "gift_card": return <Gift aria-hidden="true" size={size} />;
    case "cart": return <ShoppingBag aria-hidden="true" size={size} />;
    case "page": return <FileText aria-hidden="true" size={size} />;
    case "blog": return <PenLine aria-hidden="true" size={size} />;
    case "article": return <PenLine aria-hidden="true" size={size} />;
    case "search": return <Search aria-hidden="true" size={size} />;
    case "password": return <Lock aria-hidden="true" size={size} />;
    case "404": return <CircleAlert aria-hidden="true" size={size} />;
    default: return <FileText aria-hidden="true" size={size} />;
  }
}

/** `product.custom` → { type: "product", suffix: "custom" }；`index` → { type: "index", suffix: "" } */
export function splitTemplateKey(key: string): { type: string; suffix: string } {
  const dot = key.indexOf(".");
  return dot < 0 ? { type: key, suffix: "" } : { type: key.slice(0, dot), suffix: key.slice(dot + 1) };
}

export function TemplateSwitcher({ templateKeys, assignments, current, onSelect, onCreate }: TemplateSwitcherProps) {
  const t = useT();
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const [ open, setOpen ] = useState(false);
  const [ query, setQuery ] = useState("");
  const [ submenu, setSubmenu ] = useState<GroupType | null>(null);

  const keySet = useMemo(() => new Set(templateKeys), [ templateKeys ]);
  const alternatesOf = (type: string) => templateKeys
    .filter((key) => key.startsWith(`${type}.`))
    .map((key) => splitTemplateKey(key).suffix)
    .sort();
  const hasType = (type: string) => keySet.has(type) || alternatesOf(type).length > 0;

  const typeLabel = (type: string) => t(`editor.tpl.${type}`);
  const isGroup = (type: string): type is GroupType => (GROUP_TYPES as readonly string[]).includes(type);
  const countOf = (type: string, suffix: string) => assignments[type]?.[suffix] ?? 0;
  const assignedLabel = (type: string, suffix: string) => t(`editor.assigned.${type}`, { count: countOf(type, suffix) });

  /** 觸發鈕文字：index → Home page；`type` → Default {type}／{type}；`type.suffix` → suffix。 */
  const currentLabel = (() => {
    const { type, suffix } = splitTemplateKey(current);
    if (suffix) return suffix;
    if (isGroup(type)) return t(`editor.tplDefault.${type}`);
    return typeLabel(type);
  })();

  const choose = (key: string) => {
    onSelect(key);
    setOpen(false);
  };

  const rowClass = (key: string) => `cl-editor__menuitem${key === current ? " is-current" : ""}`;

  // 搜尋：跨兩層扁平（本尊 "Search online store" 同形——輸入即顯示所有匹配模板）
  const flatMatches = query.trim()
    ? templateKeys.filter((key) => {
      const { type, suffix } = splitTemplateKey(key);
      const label = suffix || (isGroup(type) ? t(`editor.tplDefault.${type}`) : typeLabel(type));
      return `${label} ${key}`.toLowerCase().includes(query.trim().toLowerCase());
    })
    : null;

  return (
    <>
      <button
        aria-expanded={open}
        aria-haspopup="menu"
        aria-label={t("editor.templateSwitcher")}
        className="cl-editor__chipbtn"
        onClick={() => setOpen((on) => !on)}
        ref={anchorRef}
        type="button"
      >
        {iconFor(splitTemplateKey(current).type)}
        <span className="cl-editor__chiptext">{currentLabel}</span>
        <ChevronDown aria-hidden="true" size={12} />
      </button>
      <Popover anchorRef={anchorRef} dismissOnOutsideClick label={t("editor.templateSwitcher")} onClose={() => setOpen(false)} open={open}>
        <div className="cl-editor__menu" role="menu">
          <div className="cl-editor__menusearch">
            <Search aria-hidden="true" size={14} />
            <input
              aria-label={t("editor.searchOnlineStore")}
              data-autofocus
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("editor.searchOnlineStore")}
              value={query}
            />
          </div>
          {flatMatches ? (
            <ul className="cl-editor__menulist">
              {flatMatches.map((key) => {
                const { type, suffix } = splitTemplateKey(key);
                return (
                  <li key={key}>
                    <button className={rowClass(key)} onClick={() => choose(key)} role="menuitem" type="button">
                      {iconFor(type)}
                      <span className="cl-editor__menutext">
                        {suffix || (isGroup(type) ? t(`editor.tplDefault.${type}`) : typeLabel(type))}
                        {isGroup(type) ? <small>{assignedLabel(type, suffix)}</small> : null}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          ) : submenu ? (
            <ul className="cl-editor__menulist">
              <li>
                <button className="cl-editor__menuitem cl-editor__menuback" onClick={() => setSubmenu(null)} type="button">
                  <ChevronLeft aria-hidden="true" size={14} />
                  <span className="cl-editor__menutext">{typeLabel(submenu)}</span>
                </button>
              </li>
              {keySet.has(submenu) ? (
                <li>
                  <button className={rowClass(submenu)} onClick={() => choose(submenu)} role="menuitem" type="button">
                    <Star aria-hidden="true" size={14} />
                    <span className="cl-editor__menutext">
                      {t(`editor.tplDefault.${submenu}`)}
                      <small>{assignedLabel(submenu, "")}</small>
                    </span>
                  </button>
                </li>
              ) : null}
              {alternatesOf(submenu).map((suffix) => {
                const key = `${submenu}.${suffix}`;
                return (
                  <li key={key}>
                    <button className={rowClass(key)} onClick={() => choose(key)} role="menuitem" type="button">
                      <FileText aria-hidden="true" size={14} />
                      <span className="cl-editor__menutext">
                        {suffix}
                        <small>{assignedLabel(submenu, suffix)}</small>
                      </span>
                    </button>
                  </li>
                );
              })}
              <li className="cl-editor__menusep" role="separator" />
              <li>
                <button className="cl-editor__menuitem cl-editor__menuaction" onClick={() => { setOpen(false); onCreate(submenu); }} type="button">
                  <Plus aria-hidden="true" size={14} />
                  <span className="cl-editor__menutext">{t("editor.createTemplate")}</span>
                </button>
              </li>
            </ul>
          ) : (
            <ul className="cl-editor__menulist">
              {TOP_LEVEL.map((type, index) => {
                if (type === null) return <li className="cl-editor__menusep" key={`sep-${index}`} role="separator" />;
                if (!hasType(type)) return null;
                if (isGroup(type)) {
                  return (
                    <li key={type}>
                      <button aria-haspopup="menu" className="cl-editor__menuitem" onClick={() => setSubmenu(type)} role="menuitem" type="button">
                        {iconFor(type)}
                        <span className="cl-editor__menutext">{typeLabel(type)}</span>
                        <ChevronRight aria-hidden="true" size={14} />
                      </button>
                    </li>
                  );
                }
                return (
                  <li key={type}>
                    <button className={rowClass(type)} onClick={() => choose(type)} role="menuitem" type="button">
                      {iconFor(type)}
                      <span className="cl-editor__menutext">{typeLabel(type)}</span>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </Popover>
    </>
  );
}
