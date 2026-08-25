import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { VariantImageSlot } from "./VariantImageSlot";
import { I18nProvider } from "../i18n/I18nContext";
import { ToastProvider } from "../lib/ToastContext";

/**
 * 變體圖格（第 29 包）。
 *
 * 🔴 本檔的重點是**錯誤路徑**，不是快樂路徑。審查 VIS-1：三個寫入 handler 原本
 *   只有 `try/finally` 沒有 `catch` ⇒ 鐵律 4 第②③層錯誤（THROTTLED、401、423、
 *   斷線）逸出成未處理的 promise rejection，而全樹沒有 `unhandledrejection`
 *   監聽器 ⇒ 使用者看到的是「按了沒反應」的畫面。
 */
function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

const IMAGE = { id: "gid://chilllove/ProductVariant/2", thumbUrl: "/blob?v=thumb", status: "READY", alt: "貓" };

function renderSlot(image: typeof IMAGE | null) {
  const onChange = vi.fn();
  render(
    <I18nProvider initialLocale="zh-Hant">
      <ToastProvider>
        <VariantImageSlot
          image={image}
          onChange={onChange}
          productGid="gid://chilllove/Product/9"
          variantGid="gid://chilllove/ProductVariant/2"
        />
      </ToastProvider>
    </I18nProvider>,
  );
  return onChange;
}

describe("變體圖格", () => {
  beforeEach(() => installCsrfMeta());

  it("🔴 卸圖時網路失敗 ⇒ 顯示訊息（不得是未處理的 rejection）", async () => {
    // 傳輸層直接爆——這正是 userErrors 接不到的那一類。
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("網路連線中斷")));
    const rejections: unknown[] = [];
    const onRejection = (event: PromiseRejectionEvent) => {
      rejections.push(event.reason);
      event.preventDefault();
    };
    window.addEventListener("unhandledrejection", onRejection);

    renderSlot(IMAGE);
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "移除變體圖" }));

    expect(await screen.findByText("網路連線中斷")).toBeVisible();
    // 給事件迴圈一拍，讓真的逸出的 rejection 有機會被記錄到
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(rejections).toHaveLength(0);
    window.removeEventListener("unhandledrejection", onRejection);
  });

  it("卸圖的 userErrors 走 toast（第①層錯誤）", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: vi.fn().mockResolvedValue({
        data: { productVariantAppendMedia: { media: [], userErrors: [ { message: "這張圖不屬於此商品" } ] } },
      }),
    } as unknown as Response));

    const onChange = renderSlot(IMAGE);
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "移除變體圖" }));

    expect(await screen.findByText("這張圖不屬於此商品")).toBeVisible();
    // 失敗就不要叫父層重讀——重讀會讓畫面閃一下卻什麼都沒變
    await waitFor(() => expect(onChange).not.toHaveBeenCalled());
  });

  it("未掛圖時顯示上傳與選取現有檔案兩個入口", () => {
    vi.stubGlobal("fetch", vi.fn());
    renderSlot(null);
    expect(screen.getByRole("button", { name: "上傳新檔案" })).toBeVisible();
    expect(screen.getByRole("button", { name: "選取現有檔案" })).toBeVisible();
  });
});
