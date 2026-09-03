/**
 * 主題編輯器快捷鍵表（E2；`docs/research/100` §6 快捷鍵對話框逐字＋§V V3）。
 *
 * ①這是什麼：唯一一份快捷鍵定義——tooltip 鍵帽、快捷鍵對話框、鍵盤綁定三處共用。
 * ②鍵位取捨：本尊表上帶 `⊞` 的組合（Sections／Theme Settings／App Embeds／Preview mode）
 *   實際鍵位未取得（100 §V V3）；我方採 Ctrl+Alt+N／Ctrl+Alt+I——避開 Chrome 保留的
 *   Ctrl+1..8（切分頁）與 Ctrl+I（無保留但富文本慣用斜體）。不帶 `⊞` 的照本尊逐字。
 * ③匹配：`shortcutFor(event)` 回 id；`meta`（⌘）與 `ctrl` 同等對待（Mac 使用者）。
 *   Ctrl+Shift+Z 與 Ctrl+Y 都是 redo（本尊表列 Ctrl+Y；既有測試 ED17 用 Ctrl+Shift+Z）。
 * ④跨功能影響：`useEditorHotkeys`（綁定）、`ShortcutsDialog`（列表）、`EditorTopBar`（鍵帽）。
 *   E3 加樹的 expand/collapse/select-next，E6 加 inspector 語義——都只改這張表。
 */
export type ShortcutGroup = "general" | "tools" | "navigation" | "sections";

export type ShortcutId =
  | "undo" | "redo" | "save" | "seeAll"
  | "previewInspector" | "previewMode"
  | "sections" | "themeSettings" | "appEmbeds"
  | "hideShow" | "remove" | "deselect"
  | "selectPrev" | "selectNext" | "openSelected" | "expandAll" | "collapseAll";

export interface ShortcutDef {
  id: ShortcutId;
  group: ShortcutGroup;
  /** i18n key（對話框列標籤）。 */
  labelKey: string;
  /** 鍵帽（展示用；匹配邏輯在 `shortcutFor`）。 */
  keys: string[];
}

export const EDITOR_SHORTCUTS: ShortcutDef[] = [
  { id: "undo", group: "general", labelKey: "editor.undo", keys: [ "Ctrl", "Z" ] },
  { id: "redo", group: "general", labelKey: "editor.redo", keys: [ "Ctrl", "Y" ] },
  { id: "save", group: "general", labelKey: "common.save", keys: [ "Ctrl", "S" ] },
  { id: "seeAll", group: "general", labelKey: "editor.shortcuts.seeAll", keys: [ "Ctrl", "/" ] },
  { id: "previewInspector", group: "tools", labelKey: "editor.shortcuts.previewInspector", keys: [ "Ctrl", "Shift", "I" ] },
  { id: "previewMode", group: "tools", labelKey: "editor.shortcuts.previewMode", keys: [ "Ctrl", "Alt", "I" ] },
  { id: "sections", group: "navigation", labelKey: "editor.panelSections", keys: [ "Ctrl", "Alt", "1" ] },
  { id: "themeSettings", group: "navigation", labelKey: "editor.themeSettings", keys: [ "Ctrl", "Alt", "2" ] },
  { id: "appEmbeds", group: "navigation", labelKey: "editor.panelApps", keys: [ "Ctrl", "Alt", "3" ] },
  { id: "hideShow", group: "sections", labelKey: "editor.shortcuts.hideShow", keys: [ "Ctrl", "Shift", "H" ] },
  { id: "remove", group: "sections", labelKey: "editor.shortcuts.remove", keys: [ "Shift", "⌫" ] },
  { id: "selectPrev", group: "sections", labelKey: "editor.shortcuts.selectPrev", keys: [ "Shift", "↑" ] },
  { id: "selectNext", group: "sections", labelKey: "editor.shortcuts.selectNext", keys: [ "Shift", "↓" ] },
  { id: "openSelected", group: "sections", labelKey: "editor.shortcuts.openSelected", keys: [ "Shift", "Enter" ] },
  { id: "expandAll", group: "sections", labelKey: "editor.shortcuts.expandAll", keys: [ "Ctrl", "Shift", "O" ] },
  { id: "collapseAll", group: "sections", labelKey: "editor.shortcuts.collapseAll", keys: [ "Ctrl", "Shift", "P" ] },
  { id: "deselect", group: "sections", labelKey: "editor.shortcuts.deselect", keys: [ "Esc" ] },
];

export const SHORTCUT_GROUPS: { group: ShortcutGroup; labelKey: string }[] = [
  { group: "general", labelKey: "editor.shortcuts.general" },
  { group: "tools", labelKey: "editor.shortcuts.tools" },
  { group: "navigation", labelKey: "editor.shortcuts.navigation" },
  { group: "sections", labelKey: "editor.shortcuts.sections" },
];

/** 由某 id 取鍵帽（tooltip 用）。 */
export function keysOf(id: ShortcutId): string[] {
  return EDITOR_SHORTCUTS.find((def) => def.id === id)?.keys ?? [];
}

/** 是否在文字輸入中（輸入框內不攔 undo/redo/remove 這類會與原生編輯衝突的鍵）。 */
export function isTypingTarget(target: EventTarget | null): boolean {
  const element = target as HTMLElement | null;
  const tag = element?.tagName ?? "";
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || Boolean(element?.isContentEditable);
}

/**
 * 把 keydown 事件對映到快捷鍵 id；不匹配回 null。
 * 🔴 只看 `event.key`（小寫化）與修飾鍵，不看 `code`——jsdom 與各鍵盤配置對 `code` 的
 * 支援不一，`key` 是兩邊都穩定的那個。
 */
export function shortcutFor(event: KeyboardEvent): ShortcutId | null {
  const mod = event.ctrlKey || event.metaKey;
  const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
  if (key === "Escape" && !mod && !event.altKey) return "deselect";
  if (!mod && !event.altKey && event.shiftKey) {
    if (key === "Backspace") return "remove";
    if (key === "ArrowUp") return "selectPrev";
    if (key === "ArrowDown") return "selectNext";
    if (key === "Enter") return "openSelected";
  }
  if (!mod) return null;
  if (event.altKey) {
    if (key === "1") return "sections";
    if (key === "2") return "themeSettings";
    if (key === "3") return "appEmbeds";
    if (key === "i") return "previewMode";
    return null;
  }
  if (event.shiftKey) {
    if (key === "z") return "redo";
    if (key === "i") return "previewInspector";
    if (key === "h") return "hideShow";
    if (key === "o") return "expandAll";
    if (key === "p") return "collapseAll";
    return null;
  }
  if (key === "z") return "undo";
  if (key === "y") return "redo";
  if (key === "s") return "save";
  if (key === "/") return "seeAll";
  return null;
}
