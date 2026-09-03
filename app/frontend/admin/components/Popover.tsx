import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import type { KeyboardEvent, ReactNode, RefObject } from "react";
import { createPortal } from "react-dom";

/**
 * Popover 原語（S6b-2 建立；S6c 的系列發布面與 S6d 的列表面共用）。
 *
 * ①這是什麼：錨定在某個觸發元素旁的浮層，**portal 到 `document.body`**。
 *   與 `Modal` 的差別：**不是模態**——沒有 scrim、不 inert 背景、沒有 focus trap，
 *   底下的內容仍可互動。
 *
 * ②🔴 **portal 是必要的不是偏好**：倉庫既有三份 inline popover 實作都寫在原地，
 *   而放在 `Modal` 或表格容器裡的浮層會被祖先的 `overflow` 裁切。本尊同樣把排程
 *   popover portal 到 modal 之外（`docs/research/82` §15.1 的判定式證據：
 *   `modalDialog.contains(popoverOverlay) === false`）。
 *
 * ③關閉語義**兩條分開裁定**（本尊實測見 `82` §15.2）：
 *   - **點外面**：本尊點 modal 內部時 popover **不關**，只能按 `Cancel`。
 *     ⇒ `dismissOnOutsideClick` 預設 `false`，**照抄本尊**（這是行為差異不是缺陷）。
 *   - 🔴 **Escape**：本尊按一次會把 popover **與外層 modal 一起關掉，且 modal 內
 *     未存的改動全被丟棄**（重現 2 次，無任何確認）。**我方刻意不照抄**——
 *     本元件的 Escape 會 `preventDefault()`，而 `Modal` 原語的 keydown 明文
 *     「Escape 尊重 `event.defaultPrevented`（內層 popover 先關自己）」
 *     ⇒ 只關 popover。照抄等於主動破壞既有的正確行為，且那是**資料遺失**形態。
 *
 * ④跨功能影響：`Modal`（Escape 的攔截順序）、S6c／S6d。
 *
 * ## 🔴 焦點管理：做，而且必須做（2026-08-27 審查推翻了「不做」那版）
 *
 * 初版明文寫「本元件不做焦點管理」，結果是**在 `Modal` 內鍵盤完全不可達**——
 * `Modal` 的 Tab trap 只用 `.cl-modal` 內的 focusables 算 first/last，走到 last 就
 * `preventDefault()` 折回 first；而本元件 portal 在 `.cl-modal` **之外**
 * ⇒ 焦點永遠進不來。審查實跑：Modal 內開 popover 後連按 Tab 12 次，
 * activeElement 在 modal 的兩個元素之間循環，`reached=false`。WCAG 2.1.1 Keyboard 失敗。
 *
 * ⇒ 三件事一起做：
 * - **開啟時把焦點移進面板**（`[data-autofocus]` → 面板本體，與 `Modal.tsx` 同慣例）。
 *   本尊那層有 `tabindex=-1` 的程式化焦點目標（`82` §15.1）；**它是否真的移入焦點
 *   ＝未取得** ⇒ 移入是 ours 裁定，理由是不移入就鍵盤不可達。
 * - **面板內 Tab 循環**。本尊的 popover 沒有 focus trap，但它在 modal 內、而 modal 有 trap
 *   ⇒ 本尊的 popover 內容**同樣進不去**（實測未測 Tab，這是我方的推論）。我方做 trap 是
 *   修正可及性缺陷，與下面 Escape 那條同性質。**登記為刻意偏離。**
 * - **關閉時焦點還給觸發元素**（`anchorRef`）。
 *
 * ## 🔴 Escape 用 **capture 階段的原生 listener**，不是 React 的 onKeyDown
 *
 * 初版把 handler 掛在面板的 `onKeyDown` 上。React 合成事件沿**fiber 樹**傳播，
 * 而觸發鈕的 fiber 在 `Modal` 子樹裡、不經過 portal 出去的本元件
 * ⇒ **焦點還停在觸發鈕時按 Escape，本元件的 handler 根本不執行**，事件直達 `Modal`
 * ⇒ 發布 modal 整個關掉、未存編輯全丟——正是本元件宣稱要避免的那個形態。
 * 審查實跑：`PROBE A onModalClose calls = 1`（焦點在觸發鈕）vs `calls = 0`（焦點已在面板內）。
 * ⇒ 改用 `document.addEventListener("keydown", …, true)`：capture 由外往內，
 * 早於 React 掛在 root container 的 listener，`stopPropagation` 才擋得住 `Modal`。
 *
 * @see docs/research/82-admin-channels.md §15.1／§15.2
 */
/** 面板內可聚焦元素（Tab 循環的集合）。與 `Modal.tsx` 同一份定義。 */
const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export interface PopoverProps {
  open: boolean;
  /** 錨定的觸發元素（浮層貼著它的下緣左對齊）。 */
  anchorRef: RefObject<HTMLElement | null>;
  onClose: () => void;
  children: ReactNode;
  /** 可及名稱（`aria-label`）。 */
  label: string;
  /** 點浮層外面是否關閉。預設 `false`（照本尊的排程 popover）。 */
  dismissOnOutsideClick?: boolean;
  /**
   * 擺放：`bottom-start`（預設；貼錨點下緣左對齊）或 `right-start`（E5：貼錨點右側、頂對齊——本尊 section／block
   * picker 貼左欄右緣、與該列同高，`docs/research/100` §4／§8.1）。超出視窗底時整體上移。
   */
  placement?: "bottom-start" | "right-start";
  /** `right-start` 時 x 改取此元素的右緣（本尊 picker 貼左欄卡片右緣，不是該列按鈕右緣；y 仍取錨點頂） */
  edgeRef?: RefObject<HTMLElement | null>;
}

export function Popover({
  open,
  anchorRef,
  onClose,
  children,
  label,
  dismissOnOutsideClick = false,
  placement = "bottom-start",
  edgeRef,
}: PopoverProps) {
  const panelRef = useRef<HTMLDivElement | null>(null);
  const [ position, setPosition ] = useState<{ top: number; left: number } | null>(null);

  // 🔴 `useLayoutEffect` 而非 `useEffect`：定位必須在瀏覽器繪製**之前**算完，
  //   否則浮層會先閃在 (0,0) 再跳到正確位置。
  useLayoutEffect(() => {
    if (!open) return;

    const place = () => {
      const anchor = anchorRef.current;
      const panel = panelRef.current;
      // 🔴 **anchor 缺席時不 return 就走**——初版在 effect 開頭 `if (!anchor) return`，
      //   `position` 停在 null ⇒ 面板**永遠 `visibility:hidden`**，而且沒有任何恢復路徑
      //   （ref 變化不觸發重渲染）。改成每次 `place` 各自判斷，之後任何一次
      //   scroll／resize／尺寸變化都能把它救回來。
      if (!anchor || !panel) return;

      const box = anchor.getBoundingClientRect();
      const width = panel.offsetWidth;
      const height = panel.offsetHeight;
      // 貼下緣左對齊；超出視窗就翻到另一側（不做完整的碰撞偵測，個位數情境夠用）
      if (placement === "right-start") {
        const edge = edgeRef?.current?.getBoundingClientRect();
        const left = Math.max(8, Math.min((edge ? edge.right : box.right) + 8, window.innerWidth - width - 8));
        const top = Math.max(8, Math.min(box.top, window.innerHeight - height - 8));
        setPosition({ top, left });
        return;
      }
      const left = Math.max(8, Math.min(box.left, window.innerWidth - width - 8));
      const top = box.bottom + height > window.innerHeight ? Math.max(8, box.top - height - 4) : box.bottom + 4;
      setPosition({ top, left });
    };

    place();
    // 捲動與縮放時重新定位；`true` ＝ 捕獲階段，才收得到祖先容器的捲動
    window.addEventListener("scroll", place, true);
    window.addEventListener("resize", place);

    // 🔴 **面板自己的尺寸變化也要重算**：初版只在開啟那一刻算一次，而「下方放不下就
    //   翻到上方」的判斷依賴面板高度——時間下拉一展開高度就變了，翻邊的決定卻不會跟著改。
    //   `ResizeObserver` 在 jsdom 不存在，缺席時退化成「只在開啟時算一次」。
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(place);
    if (observer && panelRef.current) observer.observe(panelRef.current);

    return () => {
      window.removeEventListener("scroll", place, true);
      window.removeEventListener("resize", place);
      observer?.disconnect();
    };
  }, [open, anchorRef, placement, edgeRef]);

  useEffect(() => {
    if (!open || !dismissOnOutsideClick) return;
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as Node;
      if (panelRef.current?.contains(target)) return;
      if (anchorRef.current?.contains(target)) return;      // 點觸發鈕由它自己 toggle
      onClose();
    };
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [open, dismissOnOutsideClick, onClose, anchorRef]);

  // 🔴 焦點入口與還原（見檔頭）。`open` 轉 true 時移入，關閉／unmount 時還給觸發元素。
  useEffect(() => {
    if (!open) return;
    const panel = panelRef.current;
    (panel?.querySelector<HTMLElement>("[data-autofocus]") ?? panel)?.focus();
    return () => {
      const anchor = anchorRef.current;
      if (anchor?.isConnected) anchor.focus();
    };
  }, [open, anchorRef]);

  // 🔴 Escape 走 **capture 階段的原生 listener**（見檔頭：React 合成事件沿 fiber 樹傳播，
  //   焦點還在觸發鈕時根本到不了本元件）。
  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      event.stopPropagation();
      onClose();
    };
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [open, onClose]);

  /** 面板內的 Tab 循環（見檔頭：不做的話 Tab 會逃出去落到 body，之後 Escape 也失效）。 */
  const handleTab = useCallback((event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key !== "Tab") return;
    const panel = panelRef.current;
    if (!panel) return;
    const focusables = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE));
    if (focusables.length === 0) { event.preventDefault(); return; }

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
  }, []);

  if (!open) return null;

  return createPortal(
    <div
      aria-label={label}
      className="cl-popover"
      onKeyDown={handleTab}
      ref={panelRef}
      role="group"
      tabIndex={-1}
      style={position ? { top: position.top, left: position.left } : { visibility: "hidden" }}
    >
      {children}
    </div>,
    document.body,
  );
}
