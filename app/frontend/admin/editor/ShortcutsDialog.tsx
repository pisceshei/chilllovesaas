import { Modal } from "../components/Modal";
import { useT } from "../i18n/I18nContext";
import { EDITOR_SHORTCUTS, SHORTCUT_GROUPS } from "./editorShortcuts";

/**
 * 快捷鍵對話框（E2；本尊 "Keyboard Shortcuts" modal，`docs/research/100` §6）。
 *
 * ①這是什麼：兩欄四組（General／Tools／Navigation／Sections & blocks），每列＝標籤＋鍵帽。
 * ②資料源：`EDITOR_SHORTCUTS` 單一表——對話框列什麼、鍵盤就綁什麼（沒有第二份清單）。
 * ③開啟途徑：頂欄「…」→ Keyboard shortcuts，或 Ctrl+/。
 * ④跨功能影響：`editorShortcuts.ts`（表）、`ThemeEditorPage`（開關狀態）。
 */
export function ShortcutsDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const t = useT();
  return (
    <Modal onClose={onClose} open={open} title={t("editor.keyboardShortcuts")}>
      <div className="cl-editor__shortcuts">
        {SHORTCUT_GROUPS.map(({ group, labelKey }) => (
          <section className="cl-editor__shortcut-group" key={group}>
            <h3 className="cl-editor__shortcut-title">{t(labelKey)}</h3>
            <ul className="cl-editor__shortcut-list">
              {EDITOR_SHORTCUTS.filter((def) => def.group === group).map((def) => (
                <li className="cl-editor__shortcut" key={def.id}>
                  <span>{t(def.labelKey)}</span>
                  <span className="cl-editor__keys">
                    {def.keys.map((key) => <kbd key={key}>{key}</kbd>)}
                  </span>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </Modal>
  );
}
