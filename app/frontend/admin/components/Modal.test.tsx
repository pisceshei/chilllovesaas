import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { Modal } from "./Modal";
import { I18nProvider } from "../i18n/I18nContext";

/**
 * Modal 原語（第 4 包）的行為驗收：焦點鎖／Escape／aria／關閉途徑／dismissable 鎖／
 * 背景 inert。ConfirmDialog 疊加的雙鈕語義在 ConfirmDialog.test.tsx，這裡不重測。
 * 面板 portal 到 document.body ⇒ scrim 一律用 document.querySelector 取。
 */
function renderModal(ui: React.ReactElement) {
  return render(<I18nProvider>{ui}</I18nProvider>);
}

const scrim = () => document.querySelector(".cl-scrim");

describe("Modal", () => {
  it("open 時 role=dialog＋aria-modal＋aria-labelledby 指向標題；close=false 不渲染", () => {
    const { rerender } = renderModal(
      <Modal onClose={vi.fn()} open title="測試視窗">
        <p>內文</p>
      </Modal>,
    );
    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveAttribute("aria-modal", "true");
    const labelId = dialog.getAttribute("aria-labelledby");
    expect(labelId).toBeTruthy();
    expect(document.getElementById(labelId ?? "")).toHaveTextContent("測試視窗");

    rerender(
      <I18nProvider>
        <Modal onClose={vi.fn()} open={false} title="測試視窗">
          <p>內文</p>
        </Modal>
      </I18nProvider>,
    );
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("開啟時焦點移入面板；Escape、×、scrim 點擊都呼叫 onClose（dismissable 預設）", async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderModal(
      <Modal onClose={onClose} open title="測試視窗">
        <p>內文</p>
      </Modal>,
    );
    expect(screen.getByRole("dialog")).toHaveFocus();

    await user.keyboard("{Escape}");
    expect(onClose).toHaveBeenCalledTimes(1);

    await user.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalledTimes(2);

    await user.click(scrim() as Element);
    expect(onClose).toHaveBeenCalledTimes(3);
  });

  it("Escape 自巢狀可聚焦元素冒泡也關閉（不要求焦點在面板本體）", async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderModal(
      <Modal footer={<button type="button">動作</button>} onClose={onClose} open title="測試視窗">
        <p>內文</p>
      </Modal>,
    );
    screen.getByRole("button", { name: "動作" }).focus();
    await user.keyboard("{Escape}");
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("焦點鎖雙向：面板→Shift+Tab 繞到最後；最後→Tab 繞回第一；🔴 第一→Shift+Tab 繞到最後", async () => {
    const user = userEvent.setup();
    renderModal(
      <Modal
        footer={<button type="button">動作</button>}
        onClose={vi.fn()}
        open
        title="測試視窗"
      >
        <button type="button">內文鈕</button>
      </Modal>,
    );
    // 初始在面板：Shift+Tab 反向繞到最後一個（footer 動作鈕）
    await user.tab({ shift: true });
    expect(screen.getByRole("button", { name: "動作" })).toHaveFocus();
    // 最後一個再 Tab ⇒ 繞回第一個（標題列 ×）
    await user.tab();
    expect(screen.getByRole("button", { name: "Close" })).toHaveFocus();
    await user.tab();
    expect(screen.getByRole("button", { name: "內文鈕" })).toHaveFocus();
    // 🔴 第一個元素上 Shift+Tab ⇒ 繞到最後（active === first 分支，審查 C4）
    screen.getByRole("button", { name: "Close" }).focus();
    await user.tab({ shift: true });
    expect(screen.getByRole("button", { name: "動作" })).toHaveFocus();
  });

  it("[data-autofocus] 存在時初始焦點落它（第 23/28 包的入力框用法）", () => {
    renderModal(
      <Modal onClose={vi.fn()} open title="測試視窗">
        <input aria-label="名稱" data-autofocus type="text" />
      </Modal>,
    );
    expect(screen.getByRole("textbox", { name: "名稱" })).toHaveFocus();
  });

  it("關閉後焦點還原到開啟前的元素；觸發鈕已 unmount 時退到 restoreFocusTo", async () => {
    const user = userEvent.setup();
    function Host() {
      const [open, setOpen] = useState(false);
      return (
        <>
          <button onClick={() => setOpen(true)} type="button">
            開啟
          </button>
          <Modal onClose={() => setOpen(false)} open={open} title="測試視窗">
            <p>內文</p>
          </Modal>
        </>
      );
    }
    renderModal(<Host />);
    const trigger = screen.getByRole("button", { name: "開啟" });
    await user.click(trigger);
    expect(screen.getByRole("dialog")).toHaveFocus();
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();

    // 觸發鈕與開框同批 unmount（審查 C1 的形態）：還原退到 restoreFocusTo
    function VanishingTrigger() {
      const [open, setOpen] = useState(false);
      const [fallback, setFallback] = useState<HTMLElement | null>(null);
      return (
        <>
          <p ref={(node) => setFallback(node)} tabIndex={-1}>
            存活地標
          </p>
          {open ? null : (
            <button onClick={() => setOpen(true)} type="button">
              會消失的觸發鈕
            </button>
          )}
          <Modal
            onClose={() => setOpen(false)}
            open={open}
            restoreFocusTo={{ current: fallback }}
            title="測試視窗"
          >
            <p>內文</p>
          </Modal>
        </>
      );
    }
    renderModal(<VanishingTrigger />);
    await user.click(screen.getByRole("button", { name: "會消失的觸發鈕" }));
    await user.keyboard("{Escape}");
    expect(screen.getByText("存活地標")).toHaveFocus();
  });

  it("dismissable=false：Escape／scrim／× 全部失效；面板內零可聚焦時 Tab 釘在面板", async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderModal(
      <Modal dismissable={false} onClose={onClose} open title="儲存中">
        <p>內文</p>
      </Modal>,
    );
    await user.keyboard("{Escape}");
    await user.click(scrim() as Element);
    expect(screen.getByRole("button", { name: "Close" })).toBeDisabled();
    expect(onClose).not.toHaveBeenCalled();
    // × disabled ⇒ 面板內零可聚焦：Tab 不逃出面板
    expect(screen.getByRole("dialog")).toHaveFocus();
    await user.tab();
    expect(screen.getByRole("dialog")).toHaveFocus();
  });

  it("開啟期間 #admin-root 加 inert＋body 捲動鎖；關閉後還原（含非空初值）", () => {
    const appRoot = document.createElement("div");
    appRoot.id = "admin-root";
    document.body.append(appRoot);
    document.body.style.overflow = "scroll";
    try {
      const { rerender } = renderModal(
        <Modal onClose={vi.fn()} open title="測試視窗">
          <p>內文</p>
        </Modal>,
      );
      expect(appRoot).toHaveAttribute("inert");
      expect(document.body.style.overflow).toBe("hidden");
      rerender(
        <I18nProvider>
          <Modal onClose={vi.fn()} open={false} title="測試視窗">
            <p>內文</p>
          </Modal>
        </I18nProvider>,
      );
      expect(appRoot).not.toHaveAttribute("inert");
      // 還原到開啟前的 inline 值，不是清空（審查 C9 家族）
      expect(document.body.style.overflow).toBe("scroll");
    } finally {
      appRoot.remove();
      document.body.style.overflow = "";
    }
  });
});
