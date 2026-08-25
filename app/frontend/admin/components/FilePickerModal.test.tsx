import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { FilePickerModal } from "./FilePickerModal";
import { I18nProvider } from "../i18n/I18nContext";
import { ToastProvider } from "../lib/ToastContext";

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
      <ToastProvider>
        <FilePickerModal maxSelectable={5} onClose={onClose} onSelect={onSelect} open {...overrides} />
      </ToastProvider>
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

  it("🔴 D48：空檔案庫時**上傳鈕就在 modal 底部**（本尊的 picker 有 Upload new）", async () => {
    stubFiles([]);
    renderPicker();

    expect(await screen.findByText("檔案庫是空的")).toBeVisible();
    // 空態本身仍不放 CTA（避免與底部那顆重複），但底部動作列一定有上傳
    expect(screen.getByRole("button", { name: "上傳新檔案" })).toBeEnabled();
  });

  it("🔴 D48：modal 內上傳完的檔直接進網格**並自動選取**（按上傳就是要用它）", async () => {
    const created = {
      id: "gid://chilllove/File/9", filename: "new.png", contentType: "image/png",
      byteSize: 1024, status: "READY", alt: null, url: "/admin/files/9/blob",
      thumbUrl: "/admin/files/9/blob?variant=thumb", previewUrl: null, usageCount: 0,
      processingError: null, createdAt: "2026-08-25T00:00:00Z",
    };
    const fetchMock = vi.fn(async (url: unknown, init?: RequestInit) => {
      const endpoint = String(url);
      if (!endpoint.includes("graphql")) return jsonResponse({});
      const q = (JSON.parse(String(init?.body)) as { query: string }).query;
      if (q.includes("stagedUploadsCreate")) {
        return jsonResponse({ data: { stagedUploadsCreate: {
          stagedTargets: [ { url: "/admin/uploads/staged", resourceUrl: "https://x/y",
                             parameters: [ { name: "key", value: "k" } ] } ],
          userErrors: [] } } });
      }
      if (q.includes("fileCreate")) {
        return jsonResponse({ data: { fileCreate: { files: [ created ], userErrors: [] } } });
      }
      return jsonResponse({ data: { files: { nodes: NODES, pageInfo: { hasNextPage: false, endCursor: null } } } });
    });
    vi.stubGlobal("fetch", fetchMock);

    const { onSelect } = renderPicker();
    const user = userEvent.setup();
    await screen.findByRole("button", { name: /cat\.png/ });

    await user.upload(screen.getByLabelText("上傳新檔案"),
      new File([ "PNG" ], "new.png", { type: "image/png" }));

    // 進網格
    expect(await screen.findByRole("button", { name: /new\.png/ })).toBeVisible();
    // 且已自動選取 ⇒ 確認鈕數到 1
    await waitFor(() => expect(screen.getByRole("button", { name: "加入 1 個" })).toBeEnabled());
    await user.click(screen.getByRole("button", { name: "加入 1 個" }));
    expect(onSelect).toHaveBeenCalledWith([ created.id ]);
  });

  it("🔴 審查：達選取上限時上傳的檔**要明說**沒被選（不然看起來像上傳失敗）", async () => {
    const created = {
      id: "gid://chilllove/File/9", filename: "extra.png", contentType: "image/png",
      byteSize: 1024, status: "UPLOADED", alt: null, url: "/admin/files/9/blob",
      thumbUrl: null, previewUrl: null, usageCount: 0,
      processingError: null, createdAt: "2026-08-25T00:00:00Z",
    };
    vi.stubGlobal("fetch", vi.fn(async (url: unknown, init?: RequestInit) => {
      const q = String(url).includes("graphql")
        ? (JSON.parse(String(init?.body)) as { query: string }).query : "";
      if (q.includes("stagedUploadsCreate")) {
        return jsonResponse({ data: { stagedUploadsCreate: {
          stagedTargets: [ { url: "/admin/uploads/staged", resourceUrl: "https://x/y",
                             parameters: [ { name: "key", value: "k" } ] } ], userErrors: [] } } });
      }
      if (q.includes("fileCreate")) {
        return jsonResponse({ data: { fileCreate: { files: [ created ], userErrors: [] } } });
      }
      return jsonResponse({ data: { files: { nodes: NODES, pageInfo: { hasNextPage: false, endCursor: null } } } });
    }));

    renderPicker({ maxSelectable: 1 });
    const user = userEvent.setup();
    // 先把唯一的名額用掉
    await user.click(await screen.findByRole("button", { name: /cat\.png/ }));

    await user.upload(screen.getByLabelText("上傳新檔案"),
      new File([ "PNG" ], "extra.png", { type: "image/png" }));

    expect(await screen.findByText(/已上傳到檔案庫，但因為已達選取上限/)).toBeVisible();
    // 檔案仍進了網格（它確實被建立了），只是沒被選
    expect(screen.getByRole("button", { name: /extra\.png/ })).toBeVisible();
    expect(screen.getByRole("button", { name: "加入 1 個" })).toBeEnabled();
  });

  it("🔴 審查：搜尋讓剛上傳的檔離開網格時，選取要跟著收斂（不得留幽靈 id）", async () => {
    const created = {
      id: "gid://chilllove/File/9", filename: "ghost.png", contentType: "image/png",
      byteSize: 1024, status: "UPLOADED", alt: null, url: "/admin/files/9/blob",
      thumbUrl: null, previewUrl: null, usageCount: 0,
      processingError: null, createdAt: "2026-08-25T00:00:00Z",
    };
    vi.stubGlobal("fetch", vi.fn(async (url: unknown, init?: RequestInit) => {
      const q = String(url).includes("graphql")
        ? (JSON.parse(String(init?.body)) as { query: string }).query : "";
      if (q.includes("stagedUploadsCreate")) {
        return jsonResponse({ data: { stagedUploadsCreate: {
          stagedTargets: [ { url: "/admin/uploads/staged", resourceUrl: "https://x/y",
                             parameters: [ { name: "key", value: "k" } ] } ], userErrors: [] } } });
      }
      if (q.includes("fileCreate")) {
        return jsonResponse({ data: { fileCreate: { files: [ created ], userErrors: [] } } });
      }
      // 重讀一律只回舊的兩筆（模擬搜尋後新檔不在結果裡）
      return jsonResponse({ data: { files: { nodes: NODES, pageInfo: { hasNextPage: false, endCursor: null } } } });
    }));

    const { onSelect } = renderPicker();
    const user = userEvent.setup();
    await screen.findByRole("button", { name: /cat\.png/ });
    await user.upload(screen.getByLabelText("上傳新檔案"),
      new File([ "PNG" ], "ghost.png", { type: "image/png" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "加入 1 個" })).toBeEnabled());

    // 打字觸發重讀 ⇒ 新檔不在結果裡
    await user.type(screen.getByLabelText("搜尋檔名"), "cat");
    await waitFor(() => expect(screen.queryByRole("button", { name: /ghost\.png/ })).toBeNull());

    // 🔴 選取必須跟著收斂：否則按確認會送出一個畫面上不存在的 id
    await waitFor(() => expect(screen.getByRole("button", { name: "加入 0 個" })).toBeDisabled());
    expect(onSelect).not.toHaveBeenCalled();
  });

  it("🔴 型別／大小不合的檔連簽都不發（modal 內的上傳同樣要有預檢）", async () => {
    const fetchMock = vi.fn(async () => jsonResponse({
      data: { files: { nodes: NODES, pageInfo: { hasNextPage: false, endCursor: null } } },
    }));
    vi.stubGlobal("fetch", fetchMock);
    renderPicker();
    const user = userEvent.setup();
    await screen.findByRole("button", { name: /cat\.png/ });
    const before = fetchMock.mock.calls.length;

    await user.upload(screen.getByLabelText("上傳新檔案"),
      new File([ "x" ], "notes.txt", { type: "text/plain" }));

    expect(fetchMock.mock.calls.length).toBe(before);
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
