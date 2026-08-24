import { X } from "lucide-react";
import { useCallback, useEffect, useId, useRef } from "react";
import type { KeyboardEvent, ReactNode, RefObject } from "react";
import { createPortal } from "react-dom";
import { useT } from "../i18n/I18nContext";

/**
 * Modal／Dialog 原語（第 4 包）——tokens 的 `--z-scrim`／`--z-dialog`／`--scrim`／
 * `--sh-modal` 四顆預留值的第一個消費者。
 *
 * ①這是什麼：全後台唯一的模態浮層原語——scrim＋面板＋標題列＋可選 footer，
 *   portal 到 `document.body`。
 * ②行為契約（排程第 4 包判準：焦點鎖・Escape・a11y）：
 *   - 🔴 背景隔離＝**`#admin-root` 加 `inert`**（開啟期間；模組級計數器支援疊層）
 *     ——單靠 keydown trap 擋不住螢幕閱讀器虛擬游標與 AT 發起的焦點移動，
 *     `aria-modal` 各家支援又不一 ⇒ inert 才是把背景真正移出無障礙樹的那道門。
 *     portal 是它的前提：面板必須在 root 外才不會被自己 inert 掉。
 *   - 焦點鎖：開啟時焦點移入面板內的 `[data-autofocus]`（無則面板本體——
 *     確認框刻意落在面板，Enter 不會誤觸任何按鈕）；Tab／Shift+Tab 面板內循環
 *     （inert 之上的第二道防線，jsdom 不實作 inert、測試靠這道驗）。
 *   - 焦點還原優先鏈：`restoreFocusTo`（顯式宣告優先）→ 開啟前的
 *     activeElement（body 不算）——兩者都要仍在 DOM（`isConnected`）。
 *     觸發鈕或其容器會隨關框 unmount 的消費者（選單項、SaveBar）必須傳
 *     `restoreFocusTo` 指向會存活的元素。
 *   - 關閉途徑三條：Escape／scrim 點擊／標題列 ×。`dismissable=false`
 *     （如儲存進行中）時三條全鎖，只能由呼叫端改 `open`。
 *   - Escape 尊重 `event.defaultPrevented`（內層 popover 先關自己）。
 *   - aria：`role="dialog"`＋`aria-modal="true"`＋`aria-labelledby`＝標題＋
 *     可選 `describedById`（確認框的後果說明掛這裡）。
 *   - body 捲動鎖與 inert 同一個計數器：最後一個 modal 關閉才還原。
 * ③怎麼做出來：focus trap 自寫 keydown 循環（jsdom 對原生
 *   `<dialog>.showModal()` 的 top-layer／inert 支援不齊＝測不到＝不用）。
 * ④跨功能影響：ConfirmDialog（本包）、第 23 包選項 popover、第 27 包刪除確認、
 *   第 28 包選檔 modal 都以本原語為底——props 接口異動先對齊整合規格 §1.7。
 *   ⚠️ inert 期間 root 內的 toast 對 AT 靜默（aria-live 在 inert 樹內不播）；
 *   modal 開著時的訊息要進 modal 本體，不要射 toast。
 */
export interface ModalProps {
  /** 是否顯示（false 時不渲染任何 DOM）。 */
  open: boolean;
  /** 標題，同時是 aria-labelledby 的來源。 */
  title: string;
  /** 關閉請求（Escape／scrim／×）——由呼叫端據此改 `open`。 */
  onClose: () => void;
  /** 內文。 */
  children: ReactNode;
  /** 底部動作列；無則不渲染 footer。 */
  footer?: ReactNode;
  /** false＝鎖死所有關閉途徑（進行中狀態防中途逃逸）。預設 true。 */
  dismissable?: boolean;
  /** 開啟前焦點元素已 unmount 時的還原目標（見上方優先鏈）。 */
  restoreFocusTo?: RefObject<HTMLElement | null>;
  /** aria-describedby 目標 id（後果說明段落）。 */
  describedById?: string;
}

/** 面板內可聚焦元素（focus trap 的循環集合）。 */
const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/** SPA 掛載節點（entrypoints/admin.tsx）；modal portal 在它外面、inert 蓋它。 */
const APP_ROOT_ID = "admin-root";

// 模組級計數：疊層 modal 只鎖一次、最後一個關閉才還原（非 LIFO 關閉也正確）。
let openModalCount = 0;
let savedBodyOverflow = "";

function lockBackground() {
  openModalCount += 1;
  if (openModalCount > 1) return;
  savedBodyOverflow = document.body.style.overflow;
  document.body.style.overflow = "hidden";
  document.getElementById(APP_ROOT_ID)?.setAttribute("inert", "");
}

function unlockBackground() {
  openModalCount -= 1;
  if (openModalCount > 0) return;
  document.body.style.overflow = savedBodyOverflow;
  document.getElementById(APP_ROOT_ID)?.removeAttribute("inert");
}

/**
 * 呈現模態對話框。
 *
 * @param props - 顯示狀態、標題、關閉 handler 與內容。
 * @returns open 時 portal 到 body 的 scrim＋面板；否則 null。
 */
export function Modal({
  open,
  title,
  onClose,
  children,
  footer,
  dismissable = true,
  restoreFocusTo,
  describedById,
}: ModalProps) {
  const t = useT();
  const titleId = useId();
  const panelRef = useRef<HTMLDivElement | null>(null);
  const restoreRef = useRef<HTMLElement | null>(null);
  const restoreFocusToRef = useRef(restoreFocusTo);
  restoreFocusToRef.current = restoreFocusTo;

  useEffect(() => {
    if (!open) return;
    const active = document.activeElement;
    // body 不是有意義的還原目標（觸發鈕與開框同批 unmount 時 activeElement 已落 body）
    restoreRef.current = active instanceof HTMLElement && active !== document.body ? active : null;
    const panel = panelRef.current;
    (panel?.querySelector<HTMLElement>("[data-autofocus]") ?? panel)?.focus();
    lockBackground();
    return () => {
      unlockBackground();
      // 🔴 顯式 restoreFocusTo 優先於捕捉值：捕捉到的元素可能「此刻還連著、
      //    下一個 commit 才 unmount」（SaveBar 確認捨棄即此形態）——顯式目標
      //    是呼叫端對「誰會存活」的宣告，勝過時點運氣。
      const target = [ restoreFocusToRef.current?.current, restoreRef.current ]
        .find((node) => node?.isConnected);
      target?.focus();
    };
  }, [open]);

  const handleKeyDown = useCallback(
    (event: KeyboardEvent<HTMLDivElement>) => {
      if (event.defaultPrevented) return;
      if (event.key === "Escape") {
        if (dismissable) {
          event.stopPropagation();
          onClose();
        }
        return;
      }
      if (event.key !== "Tab") return;
      const panel = panelRef.current;
      if (!panel) return;
      const focusables = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE));
      if (focusables.length === 0) {
        // 面板內無可聚焦元素（dismissable=false 時 × 也 disabled）：焦點釘在面板
        event.preventDefault();
        return;
      }
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement;
      if (event.shiftKey && (active === first || active === panel)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      }
    },
    [dismissable, onClose],
  );

  if (!open) return null;

  return createPortal(
    <div className="cl-modal-root" onKeyDown={handleKeyDown}>
      {/* scrim＝純 div＋mousedown preventDefault（點擊不奪焦、不把焦點洩到 body）；
          aria-hidden 合法因為它非互動角色——曾是 <button>：click 會把 DOM 焦點
          送進 aria-hidden 元素（ARIA 禁止形態） */}
      <div
        aria-hidden="true"
        className="cl-scrim"
        onClick={dismissable ? onClose : undefined}
        onMouseDown={(event) => event.preventDefault()}
      />
      <div
        aria-describedby={describedById}
        aria-labelledby={titleId}
        aria-modal="true"
        className="cl-modal"
        ref={panelRef}
        role="dialog"
        tabIndex={-1}
      >
        <header className="cl-modal__header">
          <h2 className="cl-modal__title" id={titleId}>
            {title}
          </h2>
          <button
            aria-label={t("common.close")}
            className="cl-modal__close"
            disabled={!dismissable}
            onClick={onClose}
            type="button"
          >
            <X aria-hidden="true" size={16} />
          </button>
        </header>
        <div className="cl-modal__body">{children}</div>
        {footer ? <footer className="cl-modal__footer">{footer}</footer> : null}
      </div>
    </div>,
    document.body,
  );
}
