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

const ROW = {
  id: "gid://chilllove/AbandonedCheckout/42",
  email: "probe@example.com",
  customerName: "Probe Buyer",
  region: "United States",
  createdAt: "2026-08-31T07:56:00Z",
  abandonedAt: "2026-08-31T08:10:00Z",
  totalPriceSet: { shopMoney: { amount: "1119.00", currencyCode: "HKD" } },
  lineItemsCount: 1,
  recoveryEmailSentAt: null,
  recovered: false,
};

function listBody(nodes: unknown[]) {
  return { data: { abandonedCheckouts: { nodes, pageInfo: { hasNextPage: false, endCursor: null } } } };
}

function renderPage() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/orders/abandoned" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// G6 步 7：未完成結帳列表（89 §8 七欄＋每列寄送動作）。
describe("訂單 › 未完成結帳", () => {
  beforeEach(() => installCsrfMeta());

  it("渲染七欄與徽章（未寄出／未挽回）＋金額", async () => {
    stubRoutedFetch([ { match: "query abandonedCheckoutList", body: listBody([ ROW ]) } ]);
    renderPage();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("#42")).toBeVisible();
    expect(main.getByText("Probe Buyer")).toBeVisible();
    expect(main.getByText("United States")).toBeVisible();
    expect(main.getByText("未寄出")).toBeVisible();
    expect(main.getByText("未挽回")).toBeVisible();
    expect(main.getByText(/1,119/)).toBeVisible();
  });

  it("寄送挽回信 ⇒ mutation 帶 gid；已挽回列的按鈕 disabled", async () => {
    const recoveredRow = { ...ROW, id: "gid://chilllove/AbandonedCheckout/43", recovered: true };
    const fetchMock = stubRoutedFetch([
      { match: "query abandonedCheckoutList", body: listBody([ ROW, recoveredRow ]) },
      { match: "abandonedCheckoutSendRecovery", body: { data: { abandonedCheckoutSendRecovery: {
        abandonedCheckout: { id: ROW.id, recoveryEmailSentAt: "2026-09-01T00:00:00Z" },
        userErrors: [] } } } },
    ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    const buttons = await main.findAllByRole("button", { name: "寄送挽回信" });
    expect(buttons.length).toBe(2);
    expect(buttons[1]).toBeDisabled(); // recovered 列

    await user.click(buttons[0]);
    const calls = callsTo(fetchMock, "abandonedCheckoutSendRecovery");
    expect(calls.length).toBe(1);
    expect(String(calls[0]?.body)).toContain('"id":"gid://chilllove/AbandonedCheckout/42"');
  });

  it("空清單 ⇒ 空態（10 分鐘判定說明）", async () => {
    stubRoutedFetch([ { match: "query abandonedCheckoutList", body: listBody([]) } ]);
    renderPage();
    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("目前沒有未完成結帳")).toBeVisible();
  });
});
