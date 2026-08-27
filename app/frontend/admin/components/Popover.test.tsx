import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useRef, useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { Modal } from "./Modal";
import { Popover } from "./Popover";
import { I18nProvider } from "../i18n/I18nContext";

/**
 * Popover 原語（S6b-2a）。
 *
 * 🔴 本檔大半由 2026-08-27 的對抗性審查開出來——原語當初**沒有自己的測試檔**，
 * 三條 🔴 因此全部躲過：①在 `Modal` 內鍵盤完全不可達 ②焦點還在觸發鈕時按 Escape
 * 會關掉外層 `Modal` ③Tab 會逃出 `Modal` 的焦點鎖。下面每一格都對應其中一條。
 */
function Harness({
  dismissOnOutsideClick = false,
  onClose = vi.fn(),
}: {
  dismissOnOutsideClick?: boolean;
  onClose?: () => void;
}) {
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const [ open, setOpen ] = useState(false);
  return (
    <I18nProvider initialLocale="zh-Hant">
      <button onClick={() => setOpen(true)} ref={anchorRef} type="button">開啟</button>
      <button type="button">外面的鈕</button>
      {open ? (
        <Popover
          anchorRef={anchorRef}
          dismissOnOutsideClick={dismissOnOutsideClick}
          label="測試浮層"
          onClose={() => { setOpen(false); onClose(); }}
          open
        >
          <button type="button">浮層內第一顆</button>
          <button type="button">浮層內第二顆</button>
        </Popover>
      ) : null}
    </I18nProvider>
  );
}

/** 把 Popover 放進 Modal——這是它在 S6b-2 的真實使用形態。 */
function InModalHarness({ onModalClose = vi.fn() }: { onModalClose?: () => void }) {
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const [ open, setOpen ] = useState(false);
  return (
    <I18nProvider initialLocale="zh-Hant">
      <div id="admin-root">
        <Modal onClose={onModalClose} open title="外層對話框">
          <button type="button">modal 內的欄位</button>
          <button onClick={() => setOpen(true)} ref={anchorRef} type="button">日曆</button>
          {open ? (
            <Popover anchorRef={anchorRef} label="測試浮層" onClose={() => setOpen(false)} open>
              <button type="button">浮層內第一顆</button>
              <button type="button">浮層內第二顆</button>
            </Popover>
          ) : null}
        </Modal>
      </div>
    </I18nProvider>
  );
}

describe("Popover 基本語義", () => {
  it("open=false 時不渲染任何 DOM", () => {
    render(<Harness />);
    expect(screen.queryByRole("group", { name: "測試浮層" })).toBeNull();
  });

  it("🔴 portal 到 document.body，不在呼叫端的 DOM 子樹裡（否則會被祖先 overflow 裁切）", async () => {
    const { container } = render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "開啟" }));

    const panel = screen.getByRole("group", { name: "測試浮層" });
    expect(panel).toBeVisible();
    expect(container.contains(panel)).toBe(false);
    expect(document.body.contains(panel)).toBe(true);
  });

  it("點外面預設**不關**（照本尊的排程 popover，82 §15.2）", async () => {
    const onClose = vi.fn();
    render(<Harness onClose={onClose} />);
    await userEvent.click(screen.getByRole("button", { name: "開啟" }));

    await userEvent.click(screen.getByRole("button", { name: "外面的鈕" }));
    expect(onClose).not.toHaveBeenCalled();
    expect(screen.getByRole("group", { name: "測試浮層" })).toBeVisible();
  });

  it("dismissOnOutsideClick 時點外面會關", async () => {
    const onClose = vi.fn();
    render(<Harness dismissOnOutsideClick onClose={onClose} />);
    await userEvent.click(screen.getByRole("button", { name: "開啟" }));

    await userEvent.click(screen.getByRole("button", { name: "外面的鈕" }));
    await waitFor(() => expect(onClose).toHaveBeenCalledTimes(1));
  });
});

describe("Popover 焦點與鍵盤（審查開出的三條 🔴）", () => {
  it("🔴 開啟時焦點移進面板（不移入的話在 Modal 內完全不可達）", async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "開啟" }));

    const panel = screen.getByRole("group", { name: "測試浮層" });
    await waitFor(() => expect(panel).toHaveFocus());
  });

  it("關閉時焦點還給觸發元素", async () => {
    render(<Harness />);
    const trigger = screen.getByRole("button", { name: "開啟" });
    await userEvent.click(trigger);
    await userEvent.keyboard("{Escape}");

    await waitFor(() => expect(trigger).toHaveFocus());
  });

  it("🔴 面板內 Tab 循環（不循環的話會逃出 Modal 的焦點鎖，落到 body 後 Escape 全失效）", async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "開啟" }));

    const first = screen.getByRole("button", { name: "浮層內第一顆" });
    const last = screen.getByRole("button", { name: "浮層內第二顆" });

    first.focus();
    await userEvent.tab();
    expect(last).toHaveFocus();
    await userEvent.tab();
    expect(first).toHaveFocus();          // 循環回第一顆，不是跑到 body
  });

  /**
   * 🔴 審查實跑：`PROBE A onModalClose calls = 1`。
   * React 合成事件沿 **fiber 樹**傳播，而觸發鈕的 fiber 在 `Modal` 子樹裡、
   * 不經過 portal 出去的 `Popover` ⇒ 掛在面板 `onKeyDown` 的 handler 根本不執行，
   * 事件直達 `Modal` ⇒ 發布 modal 整個關掉、未存編輯全丟。
   * 修法是把 Escape 改成 **document capture 階段的原生 listener**。
   */
  it("🔴 焦點還在觸發鈕時按 Escape：只關 popover，外層 Modal 不動", async () => {
    const onModalClose = vi.fn();
    render(<InModalHarness onModalClose={onModalClose} />);

    const trigger = screen.getByRole("button", { name: "日曆" });
    await userEvent.click(trigger);
    trigger.focus();                       // 刻意把焦點移回觸發鈕
    await userEvent.keyboard("{Escape}");

    await waitFor(() => expect(screen.queryByRole("group", { name: "測試浮層" })).toBeNull());
    expect(onModalClose).not.toHaveBeenCalled();
    expect(screen.getByRole("dialog")).toBeVisible();
  });

  /**
   * 🔴 審查實跑：Modal 內開 popover 後連按 Tab 12 次，activeElement 只在 modal 的兩個
   * 元素之間循環（`reached=false`）——`Modal` 的 Tab trap 只用 `.cl-modal` 內的
   * focusables 算 first/last，而 popover portal 在它之外。WCAG 2.1.1 Keyboard 失敗。
   */
  it("🔴 在 Modal 內：開啟後焦點就在 popover 內，鍵盤到得了它的按鈕", async () => {
    render(<InModalHarness />);
    await userEvent.click(screen.getByRole("button", { name: "日曆" }));

    const panel = screen.getByRole("group", { name: "測試浮層" });
    await waitFor(() => expect(panel).toHaveFocus());

    await userEvent.tab();
    expect(screen.getByRole("button", { name: "浮層內第一顆" })).toHaveFocus();
  });
});
