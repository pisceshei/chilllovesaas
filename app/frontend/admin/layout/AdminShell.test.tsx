import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
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

/** 按 query 路由的 fetch stub（並發請求不搶順序——ProductDetailPage.test 的教訓）。 */
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

const EMPTY_LIST = { data: { products: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } } } };

function renderAt(path: string, uiLocale: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale={uiLocale} /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// 67 §E.1：介面語言＝員工屬性、平台 bundle；切換先持久化（staffLocaleUpdate）再換畫面。
describe("介面語言（AdminShell 切換器）", () => {
  beforeEach(() => installCsrfMeta());

  it("初值由 Rails 注入：en 時側欄與頁標題是英文，<html lang> 同步", async () => {
    stubRoutedFetch([ { match: "query products", body: EMPTY_LIST } ]);
    renderAt("/admin/products", "en");

    const nav = within(await screen.findByRole("navigation", { name: "Main navigation" }));
    expect(nav.getByRole("link", { name: "Products" })).toBeVisible();
    expect(nav.getByRole("link", { name: "Orders" })).toBeVisible();
    expect(document.documentElement.lang).toBe("en");
    expect(screen.getByRole("heading", { name: "Products" })).toBeVisible();
  });

  it("切到日本語：先打 staffLocaleUpdate，成功後整個 shell 換語言並 toast", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query products", body: EMPTY_LIST },
      { match: "mutation staffLocaleUpdate", body: { data: { staffLocaleUpdate: { locale: "ja", userErrors: [] } } } },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products", "zh-Hant");

    await screen.findByRole("navigation", { name: "主要導覽" });
    await user.selectOptions(screen.getByLabelText("介面語言"), "ja");

    await screen.findByText("表示言語を更新しました");
    expect(screen.getByRole("navigation", { name: "メインナビゲーション" })).toBeVisible();
    expect(within(screen.getByRole("navigation", { name: "メインナビゲーション" })).getByRole("link", { name: "商品" })).toBeVisible();
    expect(document.documentElement.lang).toBe("ja");

    const call = fetchMock.mock.calls.find((entry) => String((entry[1] as RequestInit).body).includes("staffLocaleUpdate"));
    const body = JSON.parse(String((call?.[1] as RequestInit).body)) as { variables: { locale: string } };
    expect(body.variables.locale).toBe("ja");
  });

  it("持久化失敗（userErrors）⇒ 不切語言，顯示伺服端訊息", async () => {
    stubRoutedFetch([
      { match: "query products", body: EMPTY_LIST },
      {
        match: "mutation staffLocaleUpdate",
        body: { data: { staffLocaleUpdate: { locale: null, userErrors: [ { field: [ "locale" ], message: "不支援的介面語言。", code: "INVALID" } ] } } },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products", "zh-Hant");

    await screen.findByRole("navigation", { name: "主要導覽" });
    await user.selectOptions(screen.getByLabelText("介面語言"), "fr");

    await screen.findByText("不支援的介面語言。");
    await waitFor(() => expect(screen.getByRole("navigation", { name: "主要導覽" })).toBeVisible());
    expect(document.documentElement.lang).toBe("zh-Hant");
  });
});
