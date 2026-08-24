import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ConfirmDialog } from "./ConfirmDialog";
import { I18nProvider } from "../i18n/I18nContext";

/**
 * ConfirmDialog（第 4 包）疊加在 Modal 上的雙鈕語義。
 * 焦點鎖／Escape／aria 屬 Modal 原語，Modal.test.tsx 已測，這裡不重測。
 */
function renderDialog(overrides: Partial<Parameters<typeof ConfirmDialog>[0]> = {}) {
  const onConfirm = vi.fn();
  const onCancel = vi.fn();
  render(
    <I18nProvider>
      <ConfirmDialog
        confirmLabel="封存"
        message="後果說明"
        onCancel={onCancel}
        onConfirm={onConfirm}
        open
        title="要封存嗎？"
        {...overrides}
      />
    </I18nProvider>,
  );
  return { onConfirm, onCancel };
}

describe("ConfirmDialog", () => {
  it("取消／確認各自呼叫 handler；取消鈕預設 common.cancel 文案", async () => {
    const user = userEvent.setup();
    const { onConfirm, onCancel } = renderDialog();
    await user.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onCancel).toHaveBeenCalledTimes(1);
    await user.click(screen.getByRole("button", { name: "封存" }));
    expect(onConfirm).toHaveBeenCalledTimes(1);
  });

  it("預設確認鈕是 primary；後果說明掛 aria-describedby", () => {
    renderDialog();
    expect(screen.getByRole("button", { name: "封存" })).toHaveClass("cl-button--primary");
    const dialog = screen.getByRole("dialog");
    const describedBy = dialog.getAttribute("aria-describedby");
    expect(describedBy).toBeTruthy();
    expect(document.getElementById(describedBy ?? "")).toHaveTextContent("後果說明");
  });

  it("danger=true 時確認鈕轉 critical", () => {
    renderDialog({ danger: true });
    expect(screen.getByRole("button", { name: "封存" })).toHaveClass("cl-button--critical");
  });

  it("初始焦點在面板本體——Enter 不會誤觸確認（安全預設）", async () => {
    const user = userEvent.setup();
    const { onConfirm, onCancel } = renderDialog({ danger: true });
    expect(screen.getByRole("dialog")).toHaveFocus();
    await user.keyboard("{Enter}");
    expect(onConfirm).not.toHaveBeenCalled();
    expect(onCancel).not.toHaveBeenCalled();
  });

  it("busy：雙鈕鎖定、確認鈕 loading、Escape 失效", async () => {
    const user = userEvent.setup();
    const { onConfirm, onCancel } = renderDialog({ busy: true });
    expect(screen.getByRole("button", { name: "Cancel" })).toBeDisabled();
    // loading 時 Button 換渲染 loadingLabel（common.processing）
    expect(screen.getByRole("button", { name: "Processing" })).toBeDisabled();
    await user.keyboard("{Escape}");
    expect(onCancel).not.toHaveBeenCalled();
    expect(onConfirm).not.toHaveBeenCalled();
  });
});
