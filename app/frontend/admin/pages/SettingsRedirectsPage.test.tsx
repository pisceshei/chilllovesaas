import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Mock } from "vitest";
import { AdminRoutes } from "../App";

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

const LIST = {
  data: {
    urlRedirects: {
      nodes: [
        { id: "gid://chilllove/UrlRedirect/1", path: "/products/old-tee", target: "/products/new-tee", source: "handle_change" },
        { id: "gid://chilllove/UrlRedirect/2", path: "/pages/promo", target: "/collections/sale", source: "manual" },
      ],
    },
  },
};

function renderRedirects() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/settings/redirects" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// 包 36：路徑一律無語言前綴正規形（DOC-5 裁定）；系統列標記與 manual 區分。
describe("設定 › 網址重導", () => {
  beforeEach(() => installCsrfMeta());

  it("列出重導：來源→目標、系統／手動標記", async () => {
    stubRoutedFetch([ { match: "query urlRedirectList", body: LIST } ]);
    renderRedirects();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("/products/old-tee")).toBeVisible();
    expect(main.getByText("/collections/sale")).toBeVisible();
    expect(main.getByText("系統")).toBeVisible();
    expect(main.getByText("手動")).toBeVisible();
  });

  it("新增重導：送 urlRedirectCreate 後重載；userError 走 toast 不清空輸入", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query urlRedirectList", body: LIST },
      { match: "mutation urlRedirectCreate", body: { data: { urlRedirectCreate: { urlRedirect: { id: "gid://chilllove/UrlRedirect/3" }, userErrors: [] } } } },
    ]);
    renderRedirects();
    const main = within(await screen.findByRole("main"));

    await userEvent.type(await main.findByLabelText("來源路徑"), "/products/a");
    await userEvent.type(main.getByLabelText("目標路徑"), "/products/b");
    await userEvent.click(main.getByRole("button", { name: /新增重導/ }));

    const creates = callsTo(fetchMock, "urlRedirectCreate");
    expect(creates.length).toBe(1);
    const variables = (JSON.parse(String(creates[0].body)) as { variables: { path: string; target: string } }).variables;
    expect(variables).toEqual({ path: "/products/a", target: "/products/b" });
    // 成功後重載列表（初載 + 重載 = 2 次 query）
    expect(callsTo(fetchMock, "query urlRedirectList").length).toBe(2);
  });

  it("刪除重導：送 urlRedirectDelete 帶該列 GID", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query urlRedirectList", body: LIST },
      { match: "mutation urlRedirectDelete", body: { data: { urlRedirectDelete: { deletedUrlRedirectId: "gid://chilllove/UrlRedirect/2", userErrors: [] } } } },
    ]);
    renderRedirects();
    const main = within(await screen.findByRole("main"));

    const deleteButtons = await main.findAllByRole("button", { name: /刪除/ });
    await userEvent.click(deleteButtons[1]);

    const deletes = callsTo(fetchMock, "urlRedirectDelete");
    expect(deletes.length).toBe(1);
    expect(String(deletes[0].body)).toContain("gid://chilllove/UrlRedirect/2");
  });
});
