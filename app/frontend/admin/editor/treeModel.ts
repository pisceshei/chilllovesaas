/**
 * 左樹資料模型（E3；`docs/research/100` §2）。
 *
 * ①這是什麼：模板／群組 JSON 的巢狀 block 型別、路徑存取、可視列扁平化（鍵盤 Shift+↑↓ 用）、
 *   block 摘要文字與 icon 種類判定——純函式，無 React。
 * ②路徑：block 以 `BlockPath`（自 section 起的 id 陣列）定位；URL `block=` 以 `__` 串接
 *   （本尊 `section__static__block` 形，100 §6）。
 * ③巢狀上限 8 層（help 逐字 "Eight levels maximum for nested blocks"，100 §9.1）——與引擎
 *   `ordered_block_drops` 的 depth 守衛同值。
 * ④跨功能影響：`SectionsTree`、`ThemeEditorPage`（op 走 `getContainer`）、E5 picker。
 */
export interface SettingDefLite {
  id?: string;
  type: string;
  label?: string;
}

export interface BlockEntry {
  type: string;
  /** 使用者改名（本尊 Rename 寫進 JSON `name`；Ella 匯出可見）。 */
  name?: string;
  disabled?: boolean;
  settings?: Record<string, unknown>;
  blocks?: Record<string, BlockEntry>;
  block_order?: string[];
}

export interface SectionEntry extends BlockEntry {
  custom_css?: string;
}

export interface TemplateJson {
  sections?: Record<string, SectionEntry>;
  order?: string[];
}

export type BlockPath = string[];

export const MAX_BLOCK_DEPTH = 8;

export function orderOf(tpl: TemplateJson): string[] {
  return tpl.order ?? Object.keys(tpl.sections ?? {});
}

export function blockOrderOf(container: BlockEntry): string[] {
  return container.block_order ?? Object.keys(container.blocks ?? {});
}

/** 依路徑取 block；`[]` 回 section 本身。找不到回 null。 */
export function getBlock(section: SectionEntry, path: BlockPath): BlockEntry | null {
  let node: BlockEntry | undefined = section;
  for (const id of path) {
    node = node?.blocks?.[id];
    if (!node) return null;
  }
  return node ?? null;
}

/** 路徑的容器（父）：`[]` 無父 ⇒ null；`[a]` ⇒ section；`[a,b]` ⇒ block a。 */
export function getContainer(section: SectionEntry, path: BlockPath): BlockEntry | null {
  if (path.length === 0) return null;
  return getBlock(section, path.slice(0, -1));
}

export function encodeBlockPath(path: BlockPath): string {
  return path.join("__");
}

export function decodeBlockPath(value: string | null): BlockPath | null {
  if (!value) return null;
  const parts = value.split("__").filter(Boolean);
  return parts.length > 0 ? parts : null;
}

/** 在 section 內找葉 block id 的完整路徑（預覽點選只回葉 id）。 */
export function findBlockPath(section: SectionEntry, leafId: string): BlockPath | null {
  const walk = (container: BlockEntry, prefix: BlockPath, depth: number): BlockPath | null => {
    if (depth > MAX_BLOCK_DEPTH) return null;
    for (const id of blockOrderOf(container)) {
      const child = container.blocks?.[id];
      if (!child) continue;
      if (id === leafId) return [ ...prefix, id ];
      const hit = walk(child, [ ...prefix, id ], depth + 1);
      if (hit) return hit;
    }
    return null;
  };
  return walk(section, [], 0);
}

const TEXT_TYPES = new Set([ "text", "textarea", "richtext", "inline_richtext", "html" ]);

/** block 列摘要（本尊 "Heading – Menu"）：第一個有值的文字型設定，去標籤、截 40 字。 */
export function summaryOf(entry: BlockEntry, defs: SettingDefLite[] | undefined): string | null {
  for (const def of defs ?? []) {
    if (!def.id || !TEXT_TYPES.has(def.type)) continue;
    const raw = entry.settings?.[def.id];
    if (typeof raw !== "string") continue;
    const text = raw.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    if (!text) continue;
    return text.length > 40 ? `${text.slice(0, 40)}…` : text;
  }
  return null;
}

export type IconKind = "section" | "group" | "image" | "heading" | "text" | "link" | "button" | "video" | "block";

/** 依 block 型別／名稱推 icon 種類（本尊依 schema 內建 icon；我方以關鍵字對映，100 §2.2）。 */
export function iconKindFor(type: string, name: string | undefined): IconKind {
  const key = `${type} ${name ?? ""}`.toLowerCase();
  if (/group|container|column|row|layout/.test(key)) return "group";
  if (/image|media|logo|picture|photo/.test(key)) return "image";
  if (/video/.test(key)) return "video";
  if (/heading|title/.test(key)) return "heading";
  if (/menu|link|nav/.test(key)) return "link";
  if (/button|cta/.test(key)) return "button";
  if (/text|paragraph|announcement|rich|caption|description/.test(key)) return "text";
  return "block";
}

export interface TreeBand {
  band: string;
  label: string;
  /** "before"＝Template 帶上方（header 類群組）；"after"＝下方（footer 類）。 */
  position: "before" | "after" | "template";
  /** 群組 JSON 的 `type`（enabled_on.groups 的比對鍵）；template 帶無。 */
  groupType?: string;
  tpl: TemplateJson | null;
}

export interface TreeRow {
  band: string;
  sectionId: string;
  path: BlockPath;
  depth: number;
}

export function rowKey(band: string, sectionId: string, path: BlockPath): string {
  return `${band}:${sectionId}:${path.join("/")}`;
}

/** 可視列扁平化（展開狀態以 rowKey 集合表示）——Shift+↑↓ 與「全部展開／收合」共用。 */
export function flattenRows(bands: TreeBand[], expanded: Set<string>): TreeRow[] {
  const rows: TreeRow[] = [];
  const walk = (band: string, sectionId: string, container: BlockEntry, prefix: BlockPath, depth: number) => {
    if (depth > MAX_BLOCK_DEPTH) return;
    for (const id of blockOrderOf(container)) {
      const child = container.blocks?.[id];
      if (!child) continue;
      const path = [ ...prefix, id ];
      rows.push({ band, sectionId, path, depth });
      if (expanded.has(rowKey(band, sectionId, path))) walk(band, sectionId, child, path, depth + 1);
    }
  };
  for (const item of bands) {
    if (!item.tpl) continue;
    for (const sectionId of orderOf(item.tpl)) {
      const section = item.tpl.sections?.[sectionId];
      if (!section) continue;
      rows.push({ band: item.band, sectionId, path: [], depth: 0 });
      if (expanded.has(rowKey(item.band, sectionId, []))) walk(item.band, sectionId, section, [], 1);
    }
  }
  return rows;
}

/** 全部可展開列的 key（Ctrl+Shift+O）。 */
export function allExpandableKeys(bands: TreeBand[]): string[] {
  const keys: string[] = [];
  const walk = (band: string, sectionId: string, container: BlockEntry, prefix: BlockPath, depth: number) => {
    if (depth > MAX_BLOCK_DEPTH) return;
    for (const id of blockOrderOf(container)) {
      const child = container.blocks?.[id];
      if (!child) continue;
      const path = [ ...prefix, id ];
      keys.push(rowKey(band, sectionId, path));
      walk(band, sectionId, child, path, depth + 1);
    }
  };
  for (const item of bands) {
    if (!item.tpl) continue;
    for (const sectionId of orderOf(item.tpl)) {
      const section = item.tpl.sections?.[sectionId];
      if (!section) continue;
      keys.push(rowKey(item.band, sectionId, []));
      walk(item.band, sectionId, section, [], 1);
    }
  }
  return keys;
}

/** 從資源模板 key 與 `enabled_on`／`disabled_on` 判斷某 section 型別可否加進某帶。 */
export function sectionAllowedIn(
  availability: { enabled_on?: { templates?: string[]; groups?: string[] } | null;
                  disabled_on?: { templates?: string[]; groups?: string[] } | null } | undefined,
  target: { templateType?: string; groupType?: string },
): boolean {
  const enabled = availability?.enabled_on;
  const disabled = availability?.disabled_on;
  if (target.groupType) {
    if (disabled?.groups?.includes(target.groupType) || disabled?.groups?.includes("*")) return false;
    if (enabled) return Boolean(enabled.groups?.includes(target.groupType) || enabled.groups?.includes("*"));
    return true;
  }
  const tpl = target.templateType ?? "";
  if (disabled?.templates?.includes(tpl) || disabled?.templates?.includes("*")) return false;
  if (enabled) return Boolean(enabled.templates?.includes(tpl) || enabled.templates?.includes("*"));
  return true;
}
