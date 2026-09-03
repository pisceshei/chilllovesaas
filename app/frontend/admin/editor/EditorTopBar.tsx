import {
  Code2, Ellipsis, Eye, Keyboard, LayoutTemplate, LogOut, MousePointerClick, Palette, PanelsTopLeft, Redo2, Smartphone,
  Undo2,
} from "lucide-react";
import { useRef, useState } from "react";
import { Button } from "../components/Button";
import { Popover } from "../components/Popover";
import { useT } from "../i18n/I18nContext";
import { EditorIconButton } from "./EditorIconButton";
import { keysOf } from "./editorShortcuts";
import { MarketSwitcher } from "./MarketSwitcher";
import { TemplateSwitcher } from "./TemplateSwitcher";

/**
 * 主題編輯器頂欄（E2；`docs/research/100` §1 頂欄表逐格）。
 *
 * ①這是什麼：三區——左＝Exit｜分隔線｜面板切換器（Sections／Theme settings／App embeds）；
 *   中＝主題 chip（名稱＋Draft/Live 徽章）＋市場選擇器＋模板選擇器；右＝inspector 切換、
 *   手機檢視、Undo、Redo、「…」（Edit code／Preview／Keyboard shortcuts）、Publish、Save。
 * ②行為：面板切換器再點已啟用的那顆 ⇒ `onFullscreen`（收合兩側欄，100 §1 左 2–4）；Undo／
 *   Redo 無可用時灰；Save 無變更時灰、儲存中鎖；Publish 走呼叫端的確認框。
 * ③不在本包：Sidekick（AI，100 §V V13）、View documentation／Get support（無目標頁）。
 * ④跨功能影響：`ThemeEditorPage`（全部狀態源）、`EditorIconButton`／`TemplateSwitcher`／
 *   `MarketSwitcher`（子元件）、`editorShortcuts`（鍵帽）。
 */
export type EditorPanel = "sections" | "theme" | "apps";

export interface EditorTopBarProps {
  themeName: string;
  role: string;
  panel: EditorPanel;
  fullscreen: boolean;
  onPanel: (panel: EditorPanel) => void;
  onFullscreen: () => void;
  templateKeys: string[];
  assignments: Record<string, Record<string, number>>;
  templateKey: string;
  onTemplate: (key: string) => void;
  onCreateTemplate: (type: string) => void;
  inspector: boolean;
  onInspector: () => void;
  mobile: boolean;
  onMobile: () => void;
  canUndo: boolean;
  canRedo: boolean;
  onUndo: () => void;
  onRedo: () => void;
  dirty: boolean;
  saving: boolean;
  onSave: () => void;
  onPublish: () => void;
  onExit: () => void;
  onShortcuts: () => void;
  codeHref: string;
  previewHref: string;
}

export function EditorTopBar(props: EditorTopBarProps) {
  const t = useT();
  const moreRef = useRef<HTMLButtonElement | null>(null);
  const [ moreOpen, setMoreOpen ] = useState(false);
  const panelButton = (id: EditorPanel, label: string, icon: React.ReactNode, shortcut: string[]) => (
    <EditorIconButton
      label={label}
      onClick={() => (props.panel === id && !props.fullscreen ? props.onFullscreen() : props.onPanel(id))}
      pressed={props.panel === id && !props.fullscreen}
      shortcut={shortcut}
    >
      {icon}
    </EditorIconButton>
  );

  return (
    <header className="cl-editor__topbar">
      <div className="cl-editor__zone">
        <EditorIconButton label={t("editor.exit")} onClick={props.onExit}>
          <LogOut aria-hidden="true" size={16} />
        </EditorIconButton>
        <span aria-hidden="true" className="cl-editor__divider" />
        {panelButton("sections", t("editor.panelSections"), <PanelsTopLeft aria-hidden="true" size={16} />, keysOf("sections"))}
        {panelButton("theme", t("editor.themeSettings"), <Palette aria-hidden="true" size={16} />, keysOf("themeSettings"))}
        {panelButton("apps", t("editor.panelApps"), <LayoutTemplate aria-hidden="true" size={16} />, keysOf("appEmbeds"))}
      </div>

      <div className="cl-editor__zone cl-editor__zone--center">
        <span className="cl-editor__chip" title={props.themeName}>
          <span className="cl-editor__chiptext">{props.themeName}</span>
          {props.role === "published" ? (
            <span className="cl-editor__badge cl-editor__badge--live">{t("editor.active")}</span>
          ) : (
            <span className="cl-editor__badge cl-editor__badge--draft">{t("editor.draftBadge")}</span>
          )}
        </span>
        <MarketSwitcher />
        <TemplateSwitcher
          assignments={props.assignments}
          current={props.templateKey}
          onCreate={props.onCreateTemplate}
          onSelect={props.onTemplate}
          templateKeys={props.templateKeys}
        />
      </div>

      <div className="cl-editor__zone cl-editor__zone--right">
        <EditorIconButton
          label={props.inspector ? t("editor.inspectorOff") : t("editor.inspectorOn")}
          onClick={props.onInspector}
          pressed={props.inspector}
          shortcut={keysOf("previewInspector")}
        >
          <MousePointerClick aria-hidden="true" size={16} />
        </EditorIconButton>
        <EditorIconButton
          label={props.mobile ? t("editor.showDesktop") : t("editor.showMobile")}
          onClick={props.onMobile}
          pressed={props.mobile}
          shortcut={keysOf("previewMode")}
        >
          <Smartphone aria-hidden="true" size={16} />
        </EditorIconButton>
        <EditorIconButton disabled={!props.canUndo} label={t("editor.undo")} onClick={props.onUndo} shortcut={keysOf("undo")}>
          <Undo2 aria-hidden="true" size={16} />
        </EditorIconButton>
        <EditorIconButton disabled={!props.canRedo} label={t("editor.redo")} onClick={props.onRedo} shortcut={keysOf("redo")}>
          <Redo2 aria-hidden="true" size={16} />
        </EditorIconButton>
        <span className="cl-editor__tip-wrap">
          <button
            aria-expanded={moreOpen}
            aria-haspopup="menu"
            aria-label={t("editor.more")}
            className="cl-editor__iconbtn"
            onClick={() => setMoreOpen((on) => !on)}
            ref={moreRef}
            type="button"
          >
            <Ellipsis aria-hidden="true" size={16} />
          </button>
        </span>
        <Popover anchorRef={moreRef} dismissOnOutsideClick label={t("editor.more")} onClose={() => setMoreOpen(false)} open={moreOpen}>
          <ul className="cl-editor__menu cl-editor__menulist" role="menu">
            <li>
              <a className="cl-editor__menuitem" href={props.codeHref} role="menuitem">
                <Code2 aria-hidden="true" size={14} />
                <span className="cl-editor__menutext">{t("store.themes.editCode")}</span>
              </a>
            </li>
            <li>
              <a className="cl-editor__menuitem" href={props.previewHref} rel="noreferrer" role="menuitem" target="_blank">
                <Eye aria-hidden="true" size={14} />
                <span className="cl-editor__menutext">{t("editor.previewStore")}</span>
              </a>
            </li>
            <li className="cl-editor__menusep" role="separator" />
            <li>
              <button className="cl-editor__menuitem" onClick={() => { setMoreOpen(false); props.onShortcuts(); }} role="menuitem" type="button">
                <Keyboard aria-hidden="true" size={14} />
                <span className="cl-editor__menutext">{t("editor.keyboardShortcuts")}</span>
              </button>
            </li>
          </ul>
        </Popover>
        <Button disabled={props.saving} onClick={props.onPublish} size="small">
          {t("editor.publish")}
        </Button>
        <span className="cl-editor__tip-wrap">
          <Button disabled={!props.dirty || props.saving} onClick={props.onSave} size="small" variant="primary">
            {t("common.save")}
          </Button>
          <span aria-hidden="true" className="cl-editor__tip">
            {t("common.save")}
            {keysOf("save").map((key) => <kbd key={key}>{key}</kbd>)}
          </span>
        </span>
      </div>
    </header>
  );
}
