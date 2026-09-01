import { render, screen, within } from "@testing-library/react";
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

const ROW = {
  id: "gid://chilllove/Discount/7",
  title: "夏季九折",
  code: "SUMMER10",
  method: "code",
  discountClass: "order",
  valueType: "percentage",
  basisPoints: 1000,
  valueCents: null,
  usageLimit: 100,
  timesUsed: 3,
  status: "active",
};

function listBody(nodes: unknown[]) {
  return { data: { discounts: { nodes, pageInfo: { hasNextPage: false, endCursor: null } } } };
}

function renderPage() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/discounts" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// G6 步 9b：折扣列表（實測 2026-09-01 空態＋型別選擇四值對位）。
describe("折扣列表", () => {
  beforeEach(() => installCsrfMeta());

  it("列渲染：code 主顯＋Used 欄 n/limit＋Active 徽章", async () => {
    stubRoutedFetch([ { match: "query discountList", body: listBody([ ROW ]) } ]);
    renderPage();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("SUMMER10")).toBeVisible();
    expect(main.getByText("3/100")).toBeVisible();
    expect(main.getByText("進行中")).toBeVisible();
  });

  it("空態＋建立 → 型別選擇 modal 恰四值（BxGy disabled）", async () => {
    stubRoutedFetch([ { match: "query discountList", body: listBody([]) } ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("管理折扣與促銷")).toBeVisible();
    await user.click(main.getAllByRole("button", { name: "建立折扣" })[0]); // 頂部＋空態 CTA 各一枚

    const dialog = within(await screen.findByRole("dialog"));
    const items = dialog.getAllByRole("button").filter((el) => el.className.includes("cl-menu-list__item"));
    expect(items.length).toBe(4);
    const bxgy = items.find((el) => el.textContent?.includes("買 X 送 Y"));
    expect(bxgy).toBeDisabled();
  });
});
