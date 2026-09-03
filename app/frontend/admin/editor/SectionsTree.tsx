import {
  AlignLeft, ChevronDown, ChevronRight, CirclePlus, Code2, Eye, EyeOff, Folder, GripVertical, Lock, Heading, Image, Link2,
  MousePointer, PanelTop, Pencil, SquareDashed, Trash2, Video,
} from "lucide-react";
import { useEffect, useRef, useState, type MouseEvent as ReactMouseEvent, type ReactNode } from "react";
import { useT } from "../i18n/I18nContext";
import {
  visibleBlockIds, iconKindFor, orderOf, rowKey, summaryOf, type BlockEntry, type BlockPath, type IconKind,
  type SectionEntry, type SettingDefLite, type TreeBand,
} from "./treeModel";

/**
 * 左樹（E3；`docs/research/100` §2 逐格）。
 *
 * ①這是什麼：群組小標＋"⊕ Add section"、section 列與遞迴的 block 列（chevron／type icon／名稱＋摘要／
 *   hover 動作：drag handle 取代 icon、垃圾桶、眼睛）、展開後首個子列 "⊕ Add block"、右鍵選單
 *   （Paste（灰）／Rename／Hide／Add section before／Add section after／Edit code）。
 * ②狀態：選中列＝實心底（`aria-pressed`）；隱藏列＝灰字＋眼睛斜線常駐；展開狀態由呼叫端持有
 *   （`expanded` rowKey 集合，Ctrl+Shift+O／P 與鍵盤導航要共用）。
 * ③拖曳：HTML5 DnD，section 只在同帶、block 只在同容器（本尊同帶語義）；handle 是視覺，整列可拖。
 * ④跨功能影響：`ThemeEditorPage`（全部 op 與選取）、`treeModel`、E5 picker（`onAddSection`／`onAddBlock`
 *   先開既有清單，E5 換兩欄 picker）。
 */
export interface BlockDefLite {
  type: string;
  name?: string;
  limit?: number;
  settings?: SettingDefLite[];
}

export interface TreeSelection {
  band: string;
  sectionId: string;
  path: BlockPath;
}

export interface SectionsTreeProps {
  bands: TreeBand[];
  sectionName: (type: string) => string;
  /** 實例 `name` 的 `t:` 鍵翻譯（E3b）；未給＝原樣顯示。 */
  translateName?: (value: string | undefined) => string | undefined;
  /** 依容器（section 或 block）解析某 block 的定義（名稱／設定／可接受子型別）。 */
  blockDef: (sectionType: string, path: BlockPath, blockType: string) => BlockDefLite | undefined;
  /** 某容器可新增的 block 定義（空陣列＝不顯示 Add block）。 */
  addBlockOptions: (band: string, sectionId: string, parentPath: BlockPath) => BlockDefLite[];
  selection: TreeSelection | null;
  expanded: Set<string>;
  onToggleExpand: (key: string) => void;
  onSelect: (band: string, sectionId: string, path: BlockPath) => void;
  onToggleDisabled: (band: string, sectionId: string, path: BlockPath) => void;
  onRemove: (band: string, sectionId: string, path: BlockPath) => void;
  onMove: (band: string, sectionId: string, path: BlockPath, targetIndex: number) => void;
  onAddBlock: (band: string, sectionId: string, parentPath: BlockPath, def: BlockDefLite) => void;
  onAddSection: (band: string, atIndex: number | null) => void;
  onRename: (band: string, sectionId: string, path: BlockPath) => void;
  onEditCode: (band: string, sectionId: string, path: BlockPath) => void;
}

interface DragState { band: string; sectionId: string; parent: string; id: string }

function iconFor(kind: IconKind): ReactNode {
  const size = 14;
  switch (kind) {
    case "section": return <PanelTop aria-hidden="true" size={size} />;
    case "group": return <Folder aria-hidden="true" size={size} />;
    case "image": return <Image aria-hidden="true" size={size} />;
    case "video": return <Video aria-hidden="true" size={size} />;
    case "heading": return <Heading aria-hidden="true" size={size} />;
    case "text": return <AlignLeft aria-hidden="true" size={size} />;
    case "link": return <Link2 aria-hidden="true" size={size} />;
    case "button": return <MousePointer aria-hidden="true" size={size} />;
    default: return <SquareDashed aria-hidden="true" size={size} />;
  }
}

export function SectionsTree(props: SectionsTreeProps) {
  const t = useT();
  const dragRef = useRef<DragState | null>(null);
  const [ menu, setMenu ] = useState<{ x: number; y: number; band: string; sectionId: string; path: BlockPath; disabled: boolean } | null>(null);
  const [ addOpen, setAddOpen ] = useState<string | null>(null);

  useEffect(() => {
    if (!menu) return;
    const close = () => setMenu(null);
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") { event.preventDefault(); setMenu(null); } };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", onKey, true);
    return () => { document.removeEventListener("pointerdown", close); document.removeEventListener("keydown", onKey, true); };
  }, [ menu ]);

  const openMenu = (event: ReactMouseEvent, band: string, sectionId: string, path: BlockPath, disabled: boolean) => {
    event.preventDefault();
    setMenu({ x: event.clientX, y: event.clientY, band, sectionId, path, disabled });
  };

  const renderAddBlock = (band: string, sectionId: string, parentPath: BlockPath, depth: number) => {
    const options = props.addBlockOptions(band, sectionId, parentPath);
    if (options.length === 0) return null;
    const key = `${rowKey(band, sectionId, parentPath)}:add`;
    return (
      <li className="cl-tree__addrow" style={{ paddingLeft: depth * 16 }}>
        <button
          aria-expanded={addOpen === key}
          className="cl-tree__add"
          onClick={() => setAddOpen((current) => (current === key ? null : key))}
          type="button"
        >
          <CirclePlus aria-hidden="true" size={14} />
          {t("editor.addBlock")}
        </button>
        {addOpen === key ? (
          <ul aria-label={t("editor.addBlock")} className="cl-tree__addlist">
            {options.map((def) => (
              <li key={def.type}>
                <button
                  className="cl-tree__addoption"
                  onClick={() => { props.onAddBlock(band, sectionId, parentPath, def); setAddOpen(null); }}
                  type="button"
                >
                  ＋ {def.name ?? def.type}
                </button>
              </li>
            ))}
          </ul>
        ) : null}
      </li>
    );
  };

  const renderBlockRows = (band: string, sectionId: string, sectionType: string, container: BlockEntry,
    prefix: BlockPath, depth: number): ReactNode => {
    const order = visibleBlockIds(container);
    const parentKey = prefix.join("/");
    return (
      <ul className="cl-tree__children">
        {renderAddBlock(band, sectionId, prefix, depth)}
        {order.map((blockId, index) => {
          const block = container.blocks?.[blockId];
          if (!block) return null;
          const path = [ ...prefix, blockId ];
          const key = rowKey(band, sectionId, path);
          const def = props.blockDef(sectionType, path, block.type);
          const label = (props.translateName ? props.translateName(block.name) : block.name) ?? def?.name ?? block.type;
          const summary = summaryOf(block, def?.settings);
          const hasChildren = visibleBlockIds(block).length > 0 || props.addBlockOptions(band, sectionId, path).length > 0;
          const isOpen = props.expanded.has(key);
          const isActive = props.selection?.band === band && props.selection.sectionId === sectionId
            && props.selection.path.join("/") === path.join("/");
          return (
            <li
              className="cl-tree__item"
              draggable={!block.static}
              key={blockId}
              onDragOver={(event) => {
                const drag = dragRef.current;
                if (!block.static && drag && drag.band === band && drag.sectionId === sectionId && drag.parent === parentKey) {
                  event.preventDefault();
                  event.stopPropagation();
                }
              }}
              onDragStart={(event) => {
                event.stopPropagation();
                dragRef.current = { band, sectionId, parent: parentKey, id: blockId };
              }}
              onDrop={(event) => {
                event.preventDefault();
                event.stopPropagation();
                const drag = dragRef.current;
                dragRef.current = null;
                if (block.static || !drag || drag.band !== band || drag.sectionId !== sectionId || drag.parent !== parentKey || drag.id === blockId) return;
                props.onMove(band, sectionId, [ ...prefix, drag.id ], index);
              }}
            >
              <div
                className={[ "cl-tree__row", isActive ? "is-active" : "", block.disabled ? "is-hidden" : "" ].filter(Boolean).join(" ")}
                onContextMenu={(event) => openMenu(event, band, sectionId, path, Boolean(block.disabled))}
                style={{ paddingLeft: depth * 16 }}
              >
                {hasChildren ? (
                  <button
                    aria-expanded={isOpen}
                    aria-label={`${isOpen ? t("editor.collapse") : t("editor.expand")} ${label}`}
                    className="cl-tree__chevron"
                    onClick={() => props.onToggleExpand(key)}
                    type="button"
                  >
                    {isOpen ? <ChevronDown aria-hidden="true" size={14} /> : <ChevronRight aria-hidden="true" size={14} />}
                  </button>
                ) : <span className="cl-tree__chevron cl-tree__chevron--empty" />}
                <span className="cl-tree__icon">
                  <span className="cl-tree__typeicon">{iconFor(iconKindFor(block.type, def?.name))}</span>
                  {block.static
                    ? <Lock aria-label={t("editor.staticBlock")} className="cl-tree__grip cl-tree__lock" role="img" size={14} />
                    : <GripVertical aria-hidden="true" className="cl-tree__grip" size={14} />}
                </span>
                <button
                  aria-pressed={isActive}
                  className="cl-tree__label"
                  onClick={() => props.onSelect(band, sectionId, path)}
                  type="button"
                >
                  <span className="cl-tree__name">{label}</span>
                  {summary ? <span className="cl-tree__summary"> – {summary}</span> : null}
                </button>
                <span className="cl-tree__actions">
                  {block.static ? null : (
                    <button aria-label={t("editor.blockRemove", { id: blockId })} className="cl-tree__op" onClick={() => props.onRemove(band, sectionId, path)} type="button"><Trash2 size={14} /></button>
                  )}
                  <button aria-label={block.disabled ? t("editor.show", { id: blockId }) : t("editor.hide", { id: blockId })} className={`cl-tree__op${block.disabled ? " is-persistent" : ""}`} onClick={() => props.onToggleDisabled(band, sectionId, path)} type="button">
                    {block.disabled ? <EyeOff size={14} /> : <Eye size={14} />}
                  </button>
                </span>
              </div>
              {isOpen ? renderBlockRows(band, sectionId, sectionType, block, path, depth + 1) : null}
            </li>
          );
        })}
      </ul>
    );
  };

  const renderSectionRows = (item: TreeBand) => {
    const rows = item.tpl ? orderOf(item.tpl) : [];
    return (
      <ul className="cl-tree__sections">
        {rows.map((sectionId, index) => {
          const entry = item.tpl?.sections?.[sectionId];
          if (!entry) return null;
          const key = rowKey(item.band, sectionId, []);
          const label = (props.translateName ? props.translateName(entry.name) : entry.name) ?? props.sectionName(entry.type);
          const isOpen = props.expanded.has(key);
          const isActive = props.selection?.band === item.band && props.selection.sectionId === sectionId && props.selection.path.length === 0;
          const hasChildren = visibleBlockIds(entry).length > 0 || props.addBlockOptions(item.band, sectionId, []).length > 0;
          return (
            <li
              className="cl-tree__item"
              draggable
              key={`${item.band}:${sectionId}`}
              onDragOver={(event) => {
                const drag = dragRef.current;
                if (drag && drag.band === item.band && drag.parent === "" && drag.sectionId === "") event.preventDefault();
              }}
              onDragStart={() => { dragRef.current = { band: item.band, sectionId: "", parent: "", id: sectionId }; }}
              onDrop={(event) => {
                event.preventDefault();
                const drag = dragRef.current;
                dragRef.current = null;
                if (!drag || drag.band !== item.band || drag.sectionId !== "" || drag.id === sectionId) return;
                props.onMove(item.band, drag.id, [], index);
              }}
            >
              <div
                className={[ "cl-tree__row", isActive ? "is-active" : "", entry.disabled ? "is-hidden" : "" ].filter(Boolean).join(" ")}
                onContextMenu={(event) => openMenu(event, item.band, sectionId, [], Boolean(entry.disabled))}
              >
                {hasChildren ? (
                  <button
                    aria-expanded={isOpen}
                    aria-label={`${isOpen ? t("editor.collapse") : t("editor.expand")} ${label}`}
                    className="cl-tree__chevron"
                    onClick={() => props.onToggleExpand(key)}
                    type="button"
                  >
                    {isOpen ? <ChevronDown aria-hidden="true" size={14} /> : <ChevronRight aria-hidden="true" size={14} />}
                  </button>
                ) : <span className="cl-tree__chevron cl-tree__chevron--empty" />}
                <span className="cl-tree__icon">
                  <span className="cl-tree__typeicon">{iconFor("section")}</span>
                  <GripVertical aria-hidden="true" className="cl-tree__grip" size={14} />
                </span>
                <button
                  aria-pressed={isActive}
                  className="cl-tree__label"
                  onClick={() => props.onSelect(item.band, sectionId, [])}
                  type="button"
                >
                  <span className="cl-tree__name">{label}</span>
                </button>
                <span className="cl-tree__actions">
                  <button aria-label={t("editor.removeOp", { id: sectionId })} className="cl-tree__op" onClick={() => props.onRemove(item.band, sectionId, [])} type="button"><Trash2 size={14} /></button>
                  <button aria-label={entry.disabled ? t("editor.show", { id: sectionId }) : t("editor.hide", { id: sectionId })} className={`cl-tree__op${entry.disabled ? " is-persistent" : ""}`} onClick={() => props.onToggleDisabled(item.band, sectionId, [])} type="button">
                    {entry.disabled ? <EyeOff size={14} /> : <Eye size={14} />}
                  </button>
                </span>
              </div>
              {isOpen ? renderBlockRows(item.band, sectionId, entry.type, entry, [], 1) : null}
            </li>
          );
        })}
      </ul>
    );
  };

  const renderAddSection = (item: TreeBand) => (
    <button
      aria-label={item.position === "template" ? t("editor.addSection") : `${t("editor.addSection")}：${item.label}`}
      className="cl-tree__add cl-tree__addsection"
      onClick={() => props.onAddSection(item.band, null)}
      type="button"
    >
      <CirclePlus aria-hidden="true" size={14} />
      {t("editor.addSection")}
    </button>
  );

  return (
    <div className="cl-tree">
      {props.bands.map((item) => (
        <section className="cl-tree__band" key={item.band}>
          <h4 className="cl-tree__heading">{item.label}</h4>
          {/* 本尊：footer 類群組的 Add section 在最上面（新 section 插在 footer 之前，100 §2） */}
          {item.position === "after" ? renderAddSection(item) : null}
          {item.tpl && orderOf(item.tpl).length > 0 ? renderSectionRows(item) : (
            item.position === "template" ? <p className="cl-card-note">{t("editor.noSections")}</p> : null
          )}
          {item.position !== "after" ? renderAddSection(item) : null}
        </section>
      ))}

      {menu ? (
        <ul
          className="cl-tree__menu"
          onPointerDown={(event) => event.stopPropagation()}
          role="menu"
          style={{ left: menu.x, top: menu.y }}
        >
          <li><button className="cl-tree__menuitem" disabled role="menuitem" type="button">{t("editor.paste")}</button></li>
          <li><button className="cl-tree__menuitem" onClick={() => { props.onRename(menu.band, menu.sectionId, menu.path); setMenu(null); }} role="menuitem" type="button"><Pencil aria-hidden="true" size={14} />{t("editor.rename")}</button></li>
          <li>
            <button className="cl-tree__menuitem" onClick={() => { props.onToggleDisabled(menu.band, menu.sectionId, menu.path); setMenu(null); }} role="menuitem" type="button">
              {menu.disabled ? <Eye aria-hidden="true" size={14} /> : <EyeOff aria-hidden="true" size={14} />}
              {menu.disabled ? t("editor.shortcuts.show") : t("editor.shortcuts.hide")}
              <kbd>Ctrl</kbd><kbd>Shift</kbd><kbd>H</kbd>
            </button>
          </li>
          {menu.path.length === 0 ? (
            <>
              <li className="cl-tree__menusep" role="separator" />
              <li><button className="cl-tree__menuitem" onClick={() => { props.onAddSection(menu.band, indexOfSection(props.bands, menu.band, menu.sectionId)); setMenu(null); }} role="menuitem" type="button"><CirclePlus aria-hidden="true" size={14} />{t("editor.addSectionBefore")}</button></li>
              <li><button className="cl-tree__menuitem" onClick={() => { props.onAddSection(menu.band, indexOfSection(props.bands, menu.band, menu.sectionId) + 1); setMenu(null); }} role="menuitem" type="button"><CirclePlus aria-hidden="true" size={14} />{t("editor.addSectionAfter")}</button></li>
            </>
          ) : null}
          <li className="cl-tree__menusep" role="separator" />
          <li><button className="cl-tree__menuitem" onClick={() => { props.onEditCode(menu.band, menu.sectionId, menu.path); setMenu(null); }} role="menuitem" type="button"><Code2 aria-hidden="true" size={14} />{t("store.themes.editCode")}</button></li>
        </ul>
      ) : null}
    </div>
  );
}

function indexOfSection(bands: TreeBand[], band: string, sectionId: string): number {
  const item = bands.find((b) => b.band === band);
  return item?.tpl ? Math.max(0, orderOf(item.tpl).indexOf(sectionId)) : 0;
}

export type { SectionEntry, BlockEntry };
