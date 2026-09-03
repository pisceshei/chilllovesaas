import type { ButtonHTMLAttributes, ReactNode } from "react";

/**
 * 主題編輯器頂欄的 icon 鈕（E2；`docs/research/100` §1 頂欄表）。
 *
 * ①這是什麼：32×32 的無邊框 icon 鈕，hover／focus 時在下方出現 tooltip（名稱＋鍵帽），
 *   toggle 型（inspector／手機檢視／面板切換器）帶 `aria-pressed` 與啟用底色。
 * ②行為：tooltip 純 CSS（`.cl-editor__tip-wrap:hover`／`:focus-within`），不做 portal——
 *   頂欄是最上層容器、不會被 overflow 裁切；鍵帽只是展示，實際綁定在
 *   `useEditorHotkeys`（同一張 `EDITOR_SHORTCUTS` 表，避免兩份漂移）。
 * ③怎麼做：`label` 同時餵 `aria-label` 與 tooltip 文字；`shortcut` 每一鍵一個 `<kbd>`。
 * ④跨功能影響：`EditorTopBar`（全部 icon 鈕）、`ShortcutsDialog`（同表）。
 */
export interface EditorIconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "aria-pressed"> {
  /** 可及名稱＝tooltip 文字。 */
  label: string;
  /** tooltip 內的鍵帽（如 `["Ctrl", "1"]`）。 */
  shortcut?: string[];
  /** toggle 鈕的按下態（`aria-pressed`＋啟用底色）。 */
  pressed?: boolean;
  children: ReactNode;
}

export function EditorIconButton({ label, shortcut, pressed, className = "", children, ...props }: EditorIconButtonProps) {
  const classes = [ "cl-editor__iconbtn", pressed ? "is-active" : "", className ].filter(Boolean).join(" ");
  return (
    <span className="cl-editor__tip-wrap">
      <button
        {...props}
        aria-label={label}
        aria-pressed={pressed === undefined ? undefined : pressed}
        className={classes}
        type="button"
      >
        {children}
      </button>
      <span aria-hidden="true" className="cl-editor__tip">
        {label}
        {shortcut?.map((key) => <kbd key={key}>{key}</kbd>)}
      </span>
    </span>
  );
}
