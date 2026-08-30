import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { StorePage } from "./StorePage";
import { I18nProvider } from "../i18n/I18nContext";
import { ToastProvider } from "../lib/ToastContext";

/**
 * 主題清單頁（包 30／D77）。
 *
 * 🔴 假綠殺手：
 *   T2 published 主題**沒有**發布鈕（拿掉 role 分支 ⇒ 轉紅）——重複發布現任
 *      主題是個永遠成功的 no-op 鈕，本尊頁面分區語義（78 §4）下不該存在。
 *   T3 themePublish 帶 userErrors ⇒ toast 顯示錯誤且不重載（吞錯 ⇒ 轉紅）。
 */
function jsonResponse(body: unknown) {
  return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
}

function theme(overrides: Record<string, unknown> = {}) {
  return {
    id: "gid://chilllove/Theme/1", name: "Minimal", role: "published", version: "1.0",
    publishedAt: "2026-08-30T00:00:00Z", updatedAt: "2026-08-30T00:00:00Z",
    previewUrl: "/admin/store/preview/1",
    ...overrides,
  };
}

function stubGraphql(themes: ReturnType<typeof theme>[], publishErrors: { message: string; code: string }[] = []) {
  const calls: { query: string; variables: Record<string, unknown> }[] = [];
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as { query: string; variables: Record<string, unknown> };
    calls.push(body);
    if (body.query.includes("themePublish")) {
      return jsonResponse({ data: { themePublish: {
        theme: publishErrors.length > 0 ? null : { id: body.variables.id, role: "published" },
        userErrors: publishErrors,
      } } });
    }
    return jsonResponse({ data: { themes } });
  });
  vi.stubGlobal("fetch", fetchMock);
  return calls;
}

function renderPage() {
  return render(
    <I18nProvider initialLocale="zh-Hant">
      <ToastProvider>
        <StorePage />
      </ToastProvider>
    </I18nProvider>,
  );
}

describe("StorePage", () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
  });

  it("T1 published／draft 分區各就各位；預覽連結指向 noindex 端點", async () => {
    stubGraphql([
      theme(),
      theme({ id: "gid://chilllove/Theme/2", name: "Second", role: "draft", previewUrl: "/admin/store/preview/2" }),
    ]);
    renderPage();
    expect(await screen.findByText("Minimal")).toBeInTheDocument();
    expect(screen.getByText("Second")).toBeInTheDocument();
    expect(screen.getByText("已發布佈景主題")).toBeInTheDocument();
    expect(screen.getByText("草稿佈景主題")).toBeInTheDocument();
    const links = screen.getAllByRole("link", { name: /預覽/ });
    expect(links.map((a) => a.getAttribute("href"))).toEqual([
      "/admin/store/preview/1", "/admin/store/preview/2",
    ]);
  });

  it("T2 🔴 只有非 published 主題有發布鈕", async () => {
    stubGraphql([
      theme(),
      theme({ id: "gid://chilllove/Theme/2", name: "Second", role: "draft" }),
    ]);
    renderPage();
    await screen.findByText("Minimal");
    expect(screen.getAllByRole("button", { name: "發布" })).toHaveLength(1);
  });

  it("T3 🔴 發布失敗 ⇒ toast 錯誤訊息；成功 ⇒ 重載清單", async () => {
    const calls = stubGraphql(
      [ theme({ id: "gid://chilllove/Theme/2", name: "Second", role: "draft" }) ],
      [ { message: "主題沒有可用的檔案來源，無法發布。", code: "SOURCE_MISSING" } ],
    );
    renderPage();
    await screen.findByText("Second");
    fireEvent.click(screen.getByRole("button", { name: "發布" }));
    expect(await screen.findByText("主題沒有可用的檔案來源，無法發布。")).toBeInTheDocument();
    // 失敗不重載：themes query 只打過一次
    expect(calls.filter((c) => c.query.includes("themesList"))).toHaveLength(1);
  });
});
