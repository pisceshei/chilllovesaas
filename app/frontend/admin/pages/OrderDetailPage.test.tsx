import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AdminRoutes } from "../App";

function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

const ORDER = {
  id: "gid://chilllove/Order/77",
  name: "#1001",
  status: "open",
  email: "buyer@example.com",
  note: null,
  tags: [],
  processedAt: "2026-09-01T00:00:00Z",
  displayFinancialStatus: "PENDING",
  displayFulfillmentStatus: "UNFULFILLED",
  itemCount: 2,
  currencyCode: "HKD",
  subtotalPriceSet: { shopMoney: { amount: "148.00", currencyCode: "HKD" } },
  totalShippingPriceSet: { shopMoney: { amount: "20.00", currencyCode: "HKD" } },
  totalDiscountsSet: { shopMoney: { amount: "0.00", currencyCode: "HKD" } },
  totalPriceSet: { shopMoney: { amount: "168.00", currencyCode: "HKD" } },
  lineItems: [ {
    id: "gid://chilllove/LineItem/1", title: "測品", variantTitle: null, sku: "SKU-1",
    quantity: 2, fulfillableQuantity: 2,
    unitPriceSet: { shopMoney: { amount: "74.00", currencyCode: "HKD" } },
    totalSet: { shopMoney: { amount: "148.00", currencyCode: "HKD" } },
  } ],
  fulfillmentOrders: [ { id: "gid://chilllove/FulfillmentOrder/9", status: "open" } ],
  fulfillments: [],
  refunds: [],
  transactions: [ {
    id: "gid://chilllove/OrderTransaction/1", kind: "SALE", status: "PENDING",
    gateway: "manual_bank_deposit",
    amountSet: { shopMoney: { amount: "168.00", currencyCode: "HKD" } },
  } ],
  customer: null,
  shippingAddress: {
    firstName: "測", lastName: "買", address1: "1 Queen's Road", address2: null,
    city: "Central", province: null, postalCode: null, countryCode: "HK", phone: null,
  },
  billingAddress: null,
};

function renderDetail(fetchMock: ReturnType<typeof vi.fn>) {
  vi.stubGlobal("fetch", fetchMock);
  return render(
    <MemoryRouter initialEntries={["/admin/orders/77"]}>
      <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
    </MemoryRouter>,
  );
}

describe("訂單詳情頁", () => {
  beforeEach(() => installCsrfMeta());

  it("載入後呈現 88 §3 骨架：badges/行項/金額列/地址；PENDING+open 出標記付款鈕", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      json: vi.fn().mockResolvedValue({ data: { order: ORDER } }),
      ok: true, status: 200,
    } as unknown as Response);
    renderDetail(fetchMock);

    expect(await screen.findByRole("heading", { name: "#1001" })).toBeVisible();
    expect(screen.getByText("測品")).toBeVisible();
    expect(screen.getByText("SKU: SKU-1")).toBeVisible();
    expect(screen.getByText("$74.00 × 2")).toBeVisible();
    expect(screen.getAllByText("$168.00").length).toBeGreaterThan(0);
    expect(screen.getByText("1 Queen's Road")).toBeVisible();
    expect(screen.getByText("未提供地址")).toBeVisible(); // billing null 空態
    expect(screen.getByRole("button", { name: "標記為已付款" })).toBeVisible();
  });

  it("標記付款：確認框 → mutation 帶 idempotencyKey → 成功 toast＋重載", async () => {
    const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as { query: string; variables: Record<string, unknown> };
      if (body.query.includes("orderMarkAsPaid")) {
        expect(typeof body.variables.idempotencyKey).toBe("string");
        expect((body.variables.idempotencyKey as string).length).toBeGreaterThan(8);
        return {
          json: vi.fn().mockResolvedValue({ data: { orderMarkAsPaid: {
            order: { id: ORDER.id, displayFinancialStatus: "PAID" }, userErrors: [],
          } } }),
          ok: true, status: 200,
        } as unknown as Response;
      }
      return {
        json: vi.fn().mockResolvedValue({ data: { order: ORDER } }),
        ok: true, status: 200,
      } as unknown as Response;
    });
    renderDetail(fetchMock);
    await screen.findByRole("heading", { name: "#1001" });

    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "標記為已付款" }));
    expect(await screen.findByText("標記為已付款？")).toBeVisible();
    // 確認框內的動詞鈕（同名——取對話框內那顆）
    const dialogButtons = screen.getAllByRole("button", { name: "標記為已付款" });
    await user.click(dialogButtons[dialogButtons.length - 1]);

    await waitFor(() => {
      expect(screen.getByText("訂單已標記為已付款。")).toBeVisible();
    });
    // mutation 之後重載詳情（fetch 次數 ≥ 3：載入＋mutation＋重載）
    expect(fetchMock.mock.calls.length).toBeGreaterThanOrEqual(3);
  });
});
