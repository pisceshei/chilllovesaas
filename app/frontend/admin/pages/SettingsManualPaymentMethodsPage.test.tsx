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

const BANK_ROW = {
  id: "gid://chilllove/ShopPaymentMethod/1",
  methodType: "bank_deposit",
  name: "Bank Deposit",
  additionalDetails: "轉帳到以下帳戶",
  paymentInstructions: "附上單號",
  active: true,
  position: 1,
};

function listBody(rows: unknown[]) {
  return { data: { shopPaymentMethods: rows } };
}

function renderPage() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/settings/payments/manual-payment-methods" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// G6-3 步 2：manual payment methods 子頁（86 §3——⊕ 選單四值、已存在內建消失、
// deactivate 確認逐字語義）。
describe("設定 › 付款 › 手動付款方式", () => {
  beforeEach(() => installCsrfMeta());

  it("空清單 ⇒ 空態＋⊕ 選單四值（custom 第一）", async () => {
    stubRoutedFetch([ { match: "query manualPaymentMethods", body: listBody([]) } ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText(/尚未新增手動付款方式/)).toBeVisible();

    await user.click(main.getByRole("button", { name: /新增手動付款方式/ }));
    const items = screen.getAllByRole("menuitem");
    expect(items.map((item) => item.textContent)).toEqual([
      "建立自訂付款方式", "銀行轉帳", "匯票", "貨到付款（COD）",
    ]);
  });

  it("🔴 已存在的內建型別從 ⊕ 選單消失（86 §3：每店至多一列）", async () => {
    stubRoutedFetch([ { match: "query manualPaymentMethods", body: listBody([ BANK_ROW ]) } ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("Bank Deposit")).toBeVisible();

    await user.click(main.getByRole("button", { name: /新增手動付款方式/ }));
    const items = screen.getAllByRole("menuitem");
    expect(items.map((item) => item.textContent)).toEqual([
      "建立自訂付款方式", "匯票", "貨到付款（COD）",
    ]);
  });

  it("停用走確認框（逐字：資料保留、隨時可重新啟用）→ deactivate mutation", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query manualPaymentMethods", body: listBody([ BANK_ROW ]) },
      { match: "shopPaymentMethodDeactivate", body: { data: { shopPaymentMethodDeactivate: {
        shopPaymentMethod: { id: BANK_ROW.id, active: false }, userErrors: [] } } } },
    ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    await user.click(await main.findByRole("button", { name: "停用" }));

    const dialog = within(await screen.findByRole("dialog"));
    expect(dialog.getByText(/你的帳戶資料會保留，隨時可以重新啟用 Bank Deposit/)).toBeVisible();
    await user.click(dialog.getByRole("button", { name: "停用" }));

    expect(callsTo(fetchMock, "shopPaymentMethodDeactivate").length).toBe(1);
  });

  it("編輯表單恰兩欄（helper 逐字譯）＋儲存送 update", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query manualPaymentMethods", body: listBody([ BANK_ROW ]) },
      { match: "mutation shopPaymentMethodUpdate", body: { data: { shopPaymentMethodUpdate: {
        shopPaymentMethod: { id: BANK_ROW.id }, userErrors: [] } } } },
    ]);
    renderPage();
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    await user.click(await main.findByRole("button", { name: "編輯" }));

    const dialog = within(await screen.findByRole("dialog"));
    expect(dialog.getByText(/顧客在選擇付款方式時會看到這段文字/)).toBeVisible();
    expect(dialog.getByText(/顧客以此方式下單後會看到這段文字/)).toBeVisible();
    // 內建型別無 name 欄（86 §3：兩欄表單；name 是 custom 專屬）。
    expect(dialog.queryByLabelText(/自訂付款方式名稱/)).toBeNull();

    await user.click(dialog.getByRole("button", { name: "儲存" }));
    expect(callsTo(fetchMock, "mutation shopPaymentMethodUpdate").length).toBe(1);
  });
});
