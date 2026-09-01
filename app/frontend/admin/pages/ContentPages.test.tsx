import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Mock } from "vitest";
import { AdminRoutes } from "../App";

/**
 * 步 14b：內容線三頁（頁面／部落格貼文／選單）。
 *
 * 🔴 假綠殺手（鐵律 20.2⑤）：
 *   PG2 建立送 isPublished（殺：可見性 radio 沒接線 ⇒ 恆預設）
 *   BL2 commentPolicy 三值送出（殺：select 沒接 mutation）
 *   MN2 menuUpdate 整棵替換 payload（殺：只送新增項 ⇒ 舊項在後端被清）
 */
function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

function graphqlResponse(body: unknown) {
  return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
}

function stubRoutedFetch(routes: { match: string; body: unknown }[]) {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string };
    const route = routes.find((candidate) => request.query.includes(candidate.match));
    if (!route) throw new Error(`unexpected GraphQL call: ${request.query.slice(0, 80)}`);
    return graphqlResponse(route.body);
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function callsTo(fetchMock: Mock, match: string): RequestInit[] {
  return fetchMock.mock.calls
    .map((call) => call[1] as RequestInit)
    .filter((init) => String(init?.body).includes(match));
}

function renderAt(path: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

const PAGES_LIST = {
  data: {
    pages: {
      nodes: [
        { id: "gid://chilllove/Page/1", title: "關於我們", handle: "about-us", isPublished: true, updatedAt: "2026-09-01T00:00:00Z", body: "<p>hi</p>", templateSuffix: null },
        { id: "gid://chilllove/Page/2", title: "隱藏頁", handle: "hidden", isPublished: false, updatedAt: "2026-09-01T00:00:00Z", body: "", templateSuffix: null },
      ],
    },
  },
};

const BLOG_LIST = {
  data: {
    blogs: [
      { id: "gid://chilllove/Blog/1", title: "News", handle: "news", commentPolicy: "CLOSED" },
    ],
    articles: {
      nodes: [
        { id: "gid://chilllove/Article/9", blogId: "gid://chilllove/Blog/1", title: "首篇", handle: "first", authorName: "KEN", tags: [ "hot" ], isPublished: true, updatedAt: "2026-09-01T00:00:00Z", body: "<p>b</p>", summary: null },
      ],
    },
  },
};

const MENU_LIST = {
  data: {
    menus: [
      { id: "gid://chilllove/Menu/1", title: "Main menu", handle: "main-menu", isDefault: true,
        items: [ { id: "gid://chilllove/MenuItem/1", title: "Home", type: "FRONTPAGE", url: null, resourceId: null, items: [] } ] },
      { id: "gid://chilllove/Menu/2", title: "側欄", handle: "sidebar", isDefault: false, items: [] },
    ],
  },
};

describe("內容線三頁（步 14b）", () => {
  beforeEach(() => installCsrfMeta());

  it("PG1 頁面列表：標題＋顯示/隱藏徽章；PG2 🔴 建立送出可見性 radio 值", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query pageList", body: PAGES_LIST },
      { match: "mutation pageCreate", body: { data: { pageCreate: { page: { id: "gid://chilllove/Page/3" }, userErrors: [] } } } },
    ]);
    renderAt("/admin/pages");
    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("關於我們")).toBeVisible();
    expect(main.getByText("隱藏頁")).toBeVisible();
    expect(main.getAllByText("隱藏").length).toBeGreaterThan(0);

    await userEvent.type(main.getByLabelText("標題"), "新頁");
    await userEvent.click(main.getByLabelText("隱藏"));
    await userEvent.click(main.getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "mutation pageCreate")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "mutation pageCreate")[0].body)) as {
      variables: { title: string; isPublished: boolean };
    };
    expect(sent.variables.title).toBe("新頁");
    expect(sent.variables.isPublished).toBe(false); // radio 真的接線
  });

  it("BL1 貼文＋部落格列；BL2 🔴 commentPolicy select 送 blogUpdate 三值之一", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query blogContent", body: BLOG_LIST },
      { match: "mutation blogUpdate", body: { data: { blogUpdate: { blog: { id: "gid://chilllove/Blog/1", commentPolicy: "MODERATED" }, userErrors: [] } } } },
    ]);
    renderAt("/admin/content/blog");
    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("首篇")).toBeVisible();
    // CLOSED 對映（select option＋徽章各一 ⇒ 至少兩處）
    expect(main.getAllByText("已停用留言").length).toBeGreaterThanOrEqual(2);

    await userEvent.selectOptions(main.getByLabelText("News 的留言設定"), "MODERATED");
    await waitFor(() => expect(callsTo(fetchMock, "mutation blogUpdate")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "mutation blogUpdate")[0].body)) as {
      variables: { commentPolicy: string };
    };
    expect(sent.variables.commentPolicy).toBe("MODERATED");
  });

  it("MN1 選單列（預設選單無刪除鈕）；MN2 🔴 儲存送整棵（含既有項＋新項）", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query menuList", body: MENU_LIST },
      { match: "mutation menuUpdate", body: { data: { menuUpdate: { menu: { id: "gid://chilllove/Menu/1" }, userErrors: [] } } } },
    ]);
    renderAt("/admin/content/menus");
    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("Main menu")).toBeVisible();
    expect(main.getByText("預設選單")).toBeVisible();
    // 預設選單列不出刪除；非預設（側欄）那列有
    expect(main.getAllByRole("button", { name: /刪除/ }).length).toBe(1);

    await userEvent.click(main.getByRole("button", { name: /Main menu/ }));
    await userEvent.click(await main.findByRole("button", { name: "新增項目" }));
    const titles = main.getAllByLabelText("名稱");
    await userEvent.type(titles[titles.length - 1], "搜尋頁");
    const types = main.getAllByLabelText("連結類型");
    await userEvent.selectOptions(types[types.length - 1], "SEARCH");
    await userEvent.click(main.getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "mutation menuUpdate")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "mutation menuUpdate")[0].body)) as {
      variables: { items: { title: string; type: string }[] };
    };
    // 🔴 整棵替換：既有 Home 必須仍在 payload（漏了＝後端清掉它）
    expect(sent.variables.items.map((item) => item.title)).toEqual([ "Home", "搜尋頁" ]);
    expect(sent.variables.items[1].type).toBe("SEARCH");
  });
});
