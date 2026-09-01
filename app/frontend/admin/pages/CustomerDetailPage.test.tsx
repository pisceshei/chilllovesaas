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

const CUSTOMER = {
  id: "gid://chilllove/Customer/42",
  email: "darren@example.com",
  firstName: "Darren",
  lastName: "Darren",
  displayName: "Darren Darren",
  phone: "+61044859",
  locale: null,
  note: null,
  tags: [ "vip" ],
  taxExempt: false,
  emailMarketingState: "NOT_SUBSCRIBED",
  smsMarketingState: "NOT_SUBSCRIBED",
  redactionScheduledAt: null,
  anonymizedAt: null,
  ordersCount: 1,
  amountSpent: { amount: "109250.00", currencyCode: "HKD" },
  lastOrderAt: "2026-08-21T21:39:00Z",
  createdAt: "2026-08-27T12:08:00Z",
  addresses: [ { id: "gid://chilllove/CustomerAddress/1", firstName: "Darren", lastName: "Darren",
    address1: "1 Way", address2: null, city: "Drouin", province: "Victoria", postalCode: "3818",
    countryCode: "AU", phone: null, default: true } ],
  lastOrder: {
    id: "gid://chilllove/Order/9", name: "E8219", financialStatus: "paid",
    fulfillmentStatus: "fulfilled", processedAt: "2026-08-21T21:39:00Z",
    totalPriceSet: { shopMoney: { amount: "109250.00", currencyCode: "HKD" } },
    lineItems: [ { id: "gid://chilllove/LineItem/1", title: "Prada Paradoxe", quantity: 3 } ],
  },
};

function renderPage() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/customers/42" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// G6 步 8b：顧客詳情頁（74 §4＋g6-customer-mutations.md §5 實測對位）。
describe("顧客詳情頁", () => {
  beforeEach(() => installCsrfMeta());

  it("KPI 四格＋最近訂單卡＋右欄骨架渲染", async () => {
    stubRoutedFetch([ { match: "query customerDetail", body: { data: { customer: CUSTOMER } } } ]);
    renderPage();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("消費總額")).toBeVisible();
    expect(main.getByText("RFM 群組")).toBeVisible();
    expect(main.getByText("E8219")).toBeVisible();
    expect(main.getByText(/Prada Paradoxe × 3/)).toBeVisible();
    expect(main.getByText("darren@example.com")).toBeVisible();
    expect(main.getByText("聯絡資訊")).toBeVisible();
  });

  it("More actions 選單：合併/清除/刪除三動作（未排程抹除態）", async () => {
    stubRoutedFetch([ { match: "query customerDetail", body: { data: { customer: CUSTOMER } } } ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    await user.click(await main.findByRole("button", { name: /更多動作/ }));
    const items = screen.getAllByRole("menuitem");
    expect(items.map((item) => item.textContent)).toEqual([
      "合併顧客", "清除個人資料", "刪除顧客",
    ]);
  });

  it("行銷 modal：email 勾選 ⇒ consent mutation（SUBSCRIBED）", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query customerDetail", body: { data: { customer: CUSTOMER } } },
      { match: "customerEmailMarketingConsentUpdate", body: { data: { customerEmailMarketingConsentUpdate: {
        customer: { id: CUSTOMER.id, emailMarketingState: "SUBSCRIBED" }, userErrors: [] } } } },
    ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    await user.click(await main.findByRole("button", { name: "編輯行銷設定" }));
    const dialog = within(await screen.findByRole("dialog"));
    const checkboxes = dialog.getAllByRole("checkbox");
    await user.click(checkboxes[0]);

    const calls = callsTo(fetchMock, "customerEmailMarketingConsentUpdate");
    expect(calls.length).toBe(1);
    expect(String(calls[0]?.body)).toContain('"marketingState":"SUBSCRIBED"');
  });
});
