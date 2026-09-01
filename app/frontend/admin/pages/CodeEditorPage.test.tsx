import { fireEvent, render, screen, within } from "@testing-library/react";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AdminRoutes } from "../App";

/**
 * 步 16e2：code editor（官方形：per-file save／unsaved dot／檔案樹分型；
 * 取證 2026-09-01 help edit-theme-code＋dev code-editor）。
 *
 * 🔴 假綠殺手：
 *   CE2 儲存帶 lockVersion＋dot 清除（殺：save 不帶底版＝並發互蓋暗門）
 *   CE3 templates/*.json 唯讀（殺：雙真相源禁令的前端半場失守——後端
 *       白名單會拒，但前端可編輯＝使用者輸入被靜默丟棄）
 */
function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

const FILES = {
  data: {
    theme: {
      id: "gid://chilllove/Theme/7",
      name: "Minimal",
      files: [
        { filename: "layout/theme.liquid", size: 100 },
        { filename: "sections/hero.liquid", size: 80 },
        { filename: "templates/index.json", size: 40 },
      ],
    },
  },
};

const BODIES: Record<string, string> = {
  "sections/hero.liquid": "<h1>HERO-BODY</h1>",
  "templates/index.json": "{ \"sections\": {} }",
};

function stubFetch() {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string; variables?: { paths?: string[] } };
    let body: unknown = FILES;
    if (request.query.includes("themeFileUpsert")) {
      body = { data: { themeFileUpsert: { path: "sections/hero.liquid", lockVersion: 0, userErrors: [] } } };
    } else if (request.query.includes("codeEditorBody")) {
      const path = request.variables?.paths?.[0] ?? "";
      body = { data: { theme: {
        files: [ { filename: path, body: BODIES[path] ?? null } ],
        fileLockVersion: null,
      } } };
    }
    return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function callsTo(fetchMock: ReturnType<typeof vi.fn>, match: string): RequestInit[] {
  return fetchMock.mock.calls
    .map((call) => call[1] as RequestInit)
    .filter((init) => String(init?.body).includes(match));
}

function renderPage() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/themes/7/code" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

describe("CodeEditorPage（步 16e2）", () => {
  beforeEach(() => {
    installCsrfMeta();
    vi.unstubAllGlobals();
  });

  it("CE1 檔案樹分型資料夾；點檔開 tab、textarea 出內容", async () => {
    stubFetch();
    renderPage();
    const tree = within(await screen.findByRole("complementary", { name: "檔案" }));

    fireEvent.click(tree.getByRole("button", { name: /sections/ }));
    fireEvent.click(tree.getByRole("button", { name: /hero\.liquid/ }));

    expect(await screen.findByLabelText("sections/hero.liquid")).toHaveValue("<h1>HERO-BODY</h1>");
    expect(screen.getByRole("tab", { name: /hero\.liquid/ })).toBeInTheDocument();
  });

  it("CE2 🔴 編輯出 unsaved dot；儲存走 themeFileUpsert 帶 lockVersion；dot 清除", async () => {
    const fetchMock = stubFetch();
    renderPage();
    const tree = within(await screen.findByRole("complementary", { name: "檔案" }));
    fireEvent.click(tree.getByRole("button", { name: /sections/ }));
    fireEvent.click(tree.getByRole("button", { name: /hero\.liquid/ }));

    const textarea = await screen.findByLabelText("sections/hero.liquid");
    fireEvent.change(textarea, { target: { value: "<h1>EDITED</h1>" } });
    expect(screen.getByLabelText("未儲存")).toBeInTheDocument(); // 官方 unsaved dot 形

    fireEvent.click(screen.getByRole("button", { name: "儲存" }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeFileUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeFileUpsert")[0].body)) as {
      variables: { path: string; content: string; lockVersion: number | null };
    };
    expect(sent.variables.path).toBe("sections/hero.liquid");
    expect(sent.variables.content).toBe("<h1>EDITED</h1>");
    expect(sent.variables).toHaveProperty("lockVersion"); // 🔴 底版必送（null＝首存）

    await vi.waitFor(() => expect(screen.queryByLabelText("未儲存")).not.toBeInTheDocument());
  });

  it("CE3 🔴 templates/*.json 唯讀（雙真相源禁令前端半場）：textarea disabled＋提示＋儲存不可按", async () => {
    stubFetch();
    renderPage();
    const tree = within(await screen.findByRole("complementary", { name: "檔案" }));
    fireEvent.click(tree.getByRole("button", { name: /templates/ }));
    fireEvent.click(tree.getByRole("button", { name: /index\.json/ }));

    const textarea = await screen.findByLabelText("templates/index.json");
    expect(textarea).toBeDisabled();
    expect(screen.getByText(/模板 JSON 由主題編輯器管理/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "儲存" })).toBeDisabled();
  });
});
