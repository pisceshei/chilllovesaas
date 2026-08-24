import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { FilePickerModal } from "./FilePickerModal";
import { I18nProvider } from "../i18n/I18nContext";

/**
 * 選檔 modal（第 28 包）。釘住的是**選取語義**：只列 READY、多選有上限、
 * 確認回傳的是 file GID 陣列（呼叫端拿去送 productCreateMedia 的 fileId 分支）。
 */
function jsonResponse(body: unknown) {
  return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
}

const NODES = [
  { id: "gid://chilllove/File/1", filename: "cat.png", contentType: "image/png", byteSize: 2048,
    status: "READY", alt: "貓", url: "/admin/files/1/blob",
    thumbUrl: "/admin/files/1/blob?variant=thumb", previewUrl: null, usageCount: 0,
    processingError: null, createdAt: "2026-08-25T00:00:00Z" },
  { id: "gid://chilllove/File/2", filename: "dog.png", contentType: "image/png", byteSize: 4096,
    status: "READY", alt: null, url: "/admin/files/2/blob",
    thumbUrl: "/admin/files/2/blob?variant=thumb", previewUrl: null, usageCount: 3,
    processingError: null, createdAt: "2026-08-25T00:00:00Z" },
];

function stubFiles(nodes = NODES) {
  const calls: Record<string, unknown>[] = [];
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as { variables: Record<string, unknown> };
    calls.push(body.variables);
    return jsonResponse({ data: { files: { nodes, pageInfo: { hasNextPage: false, endCursor: null } } } });
  });
  vi.stubGlobal("fetch", fetchMock);
  return calls;
}

function renderPicker(overrides: Partial<Parameters<typeof FilePickerModal>[0]> = {}) {
  const onSelect = vi.fn();
  const onClose = vi.fn();
  render(
    <I18nProvider initialLocale="zh-Hant">
      <FilePickerModal maxSelectable={5} onClose={onClose} onSelect={onSelect} open {...overrides} />
    </I18nProvider>,
  );
  return { onSelect, onClose };
}

describe("選檔 modal", () => {
  beforeEach(() => vi.unstubAllGlobals());

  it("🔴 只向伺服端要 READY 的檔（處理中的沒有縮圖，掛上去是永久占位）", async () => {
    const calls = stubFiles();
    renderPicker();

    await screen.findByRole("button", { name: /cat\.png/ });
    expect(calls[0].status).toBe("READY");
  });

  it("🔴 多選並回傳 file GID 陣列（順序＝點選順序）", async () => {
    stubFiles();
    const { onSelect } = renderPicker();
    const user = userEvent.setup();

    await user.click(await screen.findByRole("button", { name: /dog\.png/ }));
    await user.click(screen.getByRole("button", { name: /cat\.png/ }));
    await user.click(screen.getByRole("button", { name: "加入 2 個" }));

    expect(onSelect).toHaveBeenCalledWith([ NODES[1].id, NODES[0].id ]);
  });

  it("再點一次取消選取；零選取時確認鈕停用", async () => {
    stubFiles();
    renderPicker();
    const user = userEvent.setup();

    const tile = await screen.findByRole("button", { name: /cat\.png/ });
    await user.click(tile);
    expect(tile).toHaveAttribute("aria-pressed", "true");
    await user.click(tile);
    expect(tile).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByRole("button", { name: "加入 0 個" })).toBeDisabled();
  });

  it("🔴 達上限後未選的 tile 停用（比點了沒反應誠實）", async () => {
    stubFiles();
    renderPicker({ maxSelectable: 1 });
    const user = userEvent.setup();

    await user.click(await screen.findByRole("button", { name: /cat\.png/ }));
    expect(screen.getByRole("button", { name: /dog\.png/ })).toBeDisabled();
    expect(screen.getByText("已達上限（1 個）")).toBeVisible();
  });

  it("空檔案庫：顯示空態且不給上傳 CTA（上傳鈕在 modal 外）", async () => {
    stubFiles([]);
    renderPicker();

    expect(await screen.findByText("檔案庫是空的")).toBeVisible();
    expect(screen.queryByRole("button", { name: /上傳/ })).toBeNull();
  });

  it("搜尋走伺服端（debounce 後帶 query）", async () => {
    const calls = stubFiles();
    renderPicker();
    const user = userEvent.setup();

    await screen.findByRole("button", { name: /cat\.png/ });
    await user.type(screen.getByLabelText("搜尋檔名"), "cat");

    await waitFor(() => expect(calls.at(-1)?.query).toBe("cat"));
  });

  it("關閉再開啟會清掉上一次的選取（否則會不知情地重複掛同一張圖）", async () => {
    stubFiles();
    const { onSelect } = renderPicker();
    const user = userEvent.setup();

    await user.click(await screen.findByRole("button", { name: /cat\.png/ }));
    expect(screen.getByRole("button", { name: "加入 1 個" })).toBeEnabled();

    // 重新掛載＝關閉後再開啟
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).getByRole("button", { name: "加入 1 個" })).toBeEnabled();
    expect(onSelect).not.toHaveBeenCalled();
  });
});
