import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { FilesPage } from "./FilesPage";
import { I18nProvider } from "../i18n/I18nContext";
import { ToastProvider } from "../lib/ToastContext";

/**
 * 檔案庫頁（第 28 包）。
 *
 * 🔴 最重要的一條＝**刪除確認必須先講會影響幾個商品**。官方語義是刪檔會連帶
 *   拿掉商品上的圖（取證 2026-08-25），確認框只寫「確定刪除？」等於讓使用者
 *   在不知情下弄壞商品頁。
 */
function jsonResponse(body: unknown) {
  return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
}

function file(overrides: Record<string, unknown> = {}) {
  return {
    id: "gid://chilllove/File/1", filename: "cat.png", contentType: "image/png",
    byteSize: 2048, status: "READY", alt: "貓", url: "/admin/files/1/blob",
    thumbUrl: "/admin/files/1/blob?variant=thumb", previewUrl: null,
    usageCount: 0, processingError: null, createdAt: "2026-08-25T00:00:00Z",
    ...overrides,
  };
}

function stubGraphql(nodes: ReturnType<typeof file>[]) {
  const calls: { query: string; variables: Record<string, unknown> }[] = [];
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as { query: string; variables: Record<string, unknown> };
    calls.push(body);
    if (body.query.includes("fileDelete")) {
      return jsonResponse({ data: { fileDelete: { deletedFileIds: [], userErrors: [] } } });
    }
    if (body.query.includes("fileUpdate")) {
      return jsonResponse({ data: { fileUpdate: { files: [], userErrors: [] } } });
    }
    return jsonResponse({ data: { files: { nodes, pageInfo: { hasNextPage: false, endCursor: null } } } });
  });
  vi.stubGlobal("fetch", fetchMock);
  return calls;
}

function renderPage() {
  render(
    <I18nProvider initialLocale="zh-Hant">
      <ToastProvider>
        <FilesPage />
      </ToastProvider>
    </I18nProvider>,
  );
}

describe("檔案庫頁", () => {
  beforeEach(() => vi.unstubAllGlobals());

  it("列表帶引用數；0 顯示「未使用」而不是 0（那是可安全刪除的訊號）", async () => {
    stubGraphql([ file(), file({ id: "gid://chilllove/File/2", filename: "dog.png", usageCount: 3, byteSize: 5_242_880 }) ]);
    renderPage();

    expect(await screen.findByText("cat.png")).toBeVisible();
    // 🔴 scope 到表格：「未使用」在篩選下拉裡也是一個選項，不 scope 會撞名
    const table = within(screen.getByRole("table"));
    expect(table.getByText("未使用")).toBeVisible();
    expect(table.getByText("3 個商品")).toBeVisible();
    expect(table.getByText("2.0 KB")).toBeVisible();
    expect(table.getByText("5.0 MB")).toBeVisible();
  });

  it("🔴 刪除確認明講會影響幾個商品（不是只說「確定刪除？」）", async () => {
    stubGraphql([ file({ usageCount: 2 }) ]);
    renderPage();
    const user = userEvent.setup();

    await screen.findByText("cat.png");
    await user.click(screen.getByRole("checkbox", { name: "選取 cat.png" }));
    await user.click(screen.getByRole("button", { name: "刪除 1 個檔案" }));

    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveTextContent("1 個檔案正被使用中（共 2 處）");
    expect(dialog).toHaveTextContent("那些商品的圖片會一併消失");
    expect(dialog).toHaveTextContent("剩下的圖片會自動遞補位置");
  });

  it("沒有任何引用時，確認框說得出「沒有被使用」（不嚇使用者）", async () => {
    stubGraphql([ file({ usageCount: 0 }) ]);
    renderPage();
    const user = userEvent.setup();

    await screen.findByText("cat.png");
    await user.click(screen.getByRole("checkbox", { name: "選取 cat.png" }));
    await user.click(screen.getByRole("button", { name: "刪除 1 個檔案" }));

    expect(screen.getByRole("dialog")).toHaveTextContent("目前沒有被任何商品使用");
  });

  it("取消＝零請求；確認才送 fileDelete", async () => {
    const calls = stubGraphql([ file() ]);
    renderPage();
    const user = userEvent.setup();

    await screen.findByText("cat.png");
    await user.click(screen.getByRole("checkbox", { name: "選取 cat.png" }));
    await user.click(screen.getByRole("button", { name: "刪除 1 個檔案" }));
    await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "取消" }));
    expect(calls.some((call) => call.query.includes("fileDelete"))).toBe(false);

    await user.click(screen.getByRole("button", { name: "刪除 1 個檔案" }));
    await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "刪除檔案" }));
    await waitFor(() => expect(calls.some((call) => call.query.includes("fileDelete"))).toBe(true));
  });

  it("篩選走伺服端：狀態與引用各自帶參數", async () => {
    const calls = stubGraphql([ file() ]);
    renderPage();
    const user = userEvent.setup();

    await screen.findByText("cat.png");
    await user.selectOptions(screen.getByLabelText("狀態"), "FAILED");
    await waitFor(() => expect(calls.at(-1)?.variables.status).toBe("FAILED"));

    await user.selectOptions(screen.getByLabelText("使用中"), "NONE");
    await waitFor(() => expect(calls.at(-1)?.variables.usedIn).toBe("NONE"));
  });

  it("alt 失焦送 fileUpdate；非 READY 的檔不給編輯（官方要求 ready）", async () => {
    const calls = stubGraphql([
      file(),
      file({ id: "gid://chilllove/File/2", filename: "busy.png", status: "PROCESSING", alt: null }),
    ]);
    renderPage();
    const user = userEvent.setup();

    await screen.findByText("cat.png");
    expect(screen.getByLabelText("busy.png 的替代文字")).toBeDisabled();

    await user.type(screen.getByLabelText("cat.png 的替代文字"), "咪");
    await user.tab();
    await waitFor(() => expect(calls.some((call) => call.query.includes("fileUpdate"))).toBe(true));
  });

  it("空態：有篩選時說「沒有符合」且不給上傳 CTA；無篩選才給", async () => {
    stubGraphql([]);
    renderPage();
    const user = userEvent.setup();

    expect(await screen.findByText("還沒有任何檔案")).toBeVisible();
    // 空態 CTA ＋ 頁首鈕＝兩顆
    expect(screen.getAllByRole("button", { name: "上傳檔案" })).toHaveLength(2);

    await user.type(screen.getByLabelText("搜尋檔名"), "zzz");
    expect(await screen.findByText("沒有符合的檔案")).toBeVisible();
    expect(screen.getAllByRole("button", { name: "上傳檔案" })).toHaveLength(1);
  });
});
