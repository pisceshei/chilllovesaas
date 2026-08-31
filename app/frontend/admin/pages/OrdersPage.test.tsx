import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AdminRoutes } from "../App";
import { ADMIN_GRAPHQL_ENDPOINT } from "../api/graphql";

function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

function orderNode(overrides: Record<string, unknown> = {}) {
  return {
    id: "gid://chilllove/Order/1",
    name: "#1001",
    processedAt: "2026-09-01T00:00:00Z",
    displayFinancialStatus: "PENDING",
    displayFulfillmentStatus: "UNFULFILLED",
    itemCount: 2,
    totalPriceSet: { shopMoney: { amount: "168.00", currencyCode: "HKD" } },
    customer: { displayName: "陳大文" },
    ...overrides,
  };
}

function successfulResponse(nodes: unknown[] = []) {
  return {
    json: vi.fn().mockResolvedValue({
      data: {
        orders: { nodes, pageInfo: { endCursor: null, hasNextPage: false } },
      },
    }),
    ok: true,
    status: 200,
  } as unknown as Response;
}

function renderOrders() {
  return render(
    <MemoryRouter initialEntries={["/admin/orders"]}>
      <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
    </MemoryRouter>,
  );
}

describe("訂單頁", () => {
  beforeEach(() => installCsrfMeta());

  it("以唯一 Admin GraphQL POST 載入後呈現空狀態（鐵律 4 端點契約＋$after 進文件）", async () => {
    const fetchMock = vi.fn().mockResolvedValue(successfulResponse());
    vi.stubGlobal("fetch", fetchMock);

    renderOrders();

    expect(screen.getByRole("status")).toHaveTextContent("正在載入訂單");
    expect(await screen.findByRole("heading", { name: "還沒有訂單" })).toBeVisible();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [endpoint, options] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(endpoint).toBe(ADMIN_GRAPHQL_ENDPOINT);
    expect(options.method).toBe("POST");
    const body = JSON.parse(String(options.body)) as { query: string; variables: Record<string, unknown> };
    // 🔴 D48 教訓：$after 必須宣告在查詢文件本身
    expect(body.query).toContain("orders(first: $first, after: $after, query: $query)");
    expect(body.variables).toEqual({ first: 50, after: null, query: null });
  });

  it("呈現列（單號/顧客/總計/雙狀態 badge/商品數）並支援列點擊導航", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      successfulResponse([
        orderNode(),
        orderNode({
          id: "gid://chilllove/Order/2", name: "#1002",
          displayFinancialStatus: "PAID", displayFulfillmentStatus: "FULFILLED",
          customer: null, itemCount: 9,
          totalPriceSet: { shopMoney: { amount: "109250.00", currencyCode: "JPY" } },
        }),
      ]),
    );
    vi.stubGlobal("fetch", fetchMock);

    renderOrders();

    expect(await screen.findByText("#1001")).toBeVisible();
    expect(screen.getByText("陳大文")).toBeVisible();
    expect(screen.getByText("無顧客")).toBeVisible();
    expect(screen.getByText("$168.00")).toBeVisible();
    expect(screen.getByText("¥109,250.00")).toBeVisible();
    expect(screen.getAllByText("待付款").length).toBeGreaterThan(0); // 篩選 option 同字樣
    expect(screen.getAllByText("已付款").length).toBeGreaterThan(0); // 篩選 option 同字樣
    expect(screen.getAllByText("未出貨").length).toBeGreaterThan(0); // 篩選 option 同字樣
    expect(screen.getAllByText("已出貨").length).toBeGreaterThan(0); // 篩選 option 同字樣
    expect(screen.getByText("9 件")).toBeVisible();
  });

  it("付款狀態篩選（八值窮舉）以 financial_status: 併入伺服器 query", async () => {
    const fetchMock = vi.fn().mockResolvedValue(successfulResponse([ orderNode() ]));
    vi.stubGlobal("fetch", fetchMock);

    renderOrders();
    await screen.findByText("#1001");

    const select = screen.getByLabelText("依付款狀態篩選");
    expect([ ...select.querySelectorAll("option") ].map((o) => o.value))
      .toEqual([ "", "PENDING", "AUTHORIZED", "PAID", "PARTIALLY_PAID",
        "PARTIALLY_REFUNDED", "REFUNDED", "VOIDED", "EXPIRED" ]); // 值域窮舉（88 §7）
    const user = userEvent.setup();
    await user.selectOptions(select, "PAID");
    await waitFor(() => {
      const last = JSON.parse(String((fetchMock.mock.calls.at(-1)?.[1] as RequestInit).body)) as {
        variables: Record<string, unknown>;
      };
      expect(last.variables.query).toBe("financial_status:paid");
    });
  });
});
