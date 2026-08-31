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

function customerNode(overrides: Record<string, unknown> = {}) {
  return {
    id: "gid://chilllove/Customer/1",
    displayName: "陳大文",
    email: "buyer@example.com",
    emailMarketingConsent: true,
    ordersCount: 3,
    amountSpent: { amount: "1480.00", currencyCode: "HKD" },
    lastOrderAt: "2026-08-31T00:00:00Z",
    defaultAddress: { city: "Central", province: null, countryCode: "HK" },
    ...overrides,
  };
}

function successfulResponse(nodes: unknown[] = []) {
  return {
    json: vi.fn().mockResolvedValue({
      data: {
        customers: {
          nodes,
          pageInfo: { endCursor: null, hasNextPage: false },
        },
      },
    }),
    ok: true,
    status: 200,
  } as unknown as Response;
}

function renderCustomers() {
  return render(
    <MemoryRouter initialEntries={["/admin/customers"]}>
      <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
    </MemoryRouter>,
  );
}

describe("顧客頁", () => {
  beforeEach(() => installCsrfMeta());

  it("以唯一 Admin GraphQL POST 載入後呈現顧客空狀態（鐵律 4 端點與憑證）", async () => {
    const fetchMock = vi.fn().mockResolvedValue(successfulResponse());
    vi.stubGlobal("fetch", fetchMock);

    renderCustomers();

    expect(screen.getByRole("status")).toHaveTextContent("正在載入顧客");
    expect(await screen.findByRole("heading", { name: "還沒有顧客" })).toBeVisible();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [endpoint, options] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(endpoint).toBe(ADMIN_GRAPHQL_ENDPOINT);
    expect(options.method).toBe("POST");
    expect(options.credentials).toBe("same-origin");
    expect(options.headers).toEqual(
      expect.objectContaining({
        "Content-Type": "application/json",
        "X-CSRF-Token": "csrf-test-token",
      }),
    );
    const body = JSON.parse(String(options.body)) as { query: string; variables: Record<string, unknown> };
    // 🔴 D48 教訓：$after 必須宣告在查詢文件本身，只放 variables 會被伺服端丟掉
    expect(body.query).toContain("customers(first: $first, after: $after, query: $query)");
    expect(body.query).toContain("$after");
    expect(body.variables).toEqual({ first: 50, after: null, query: null });
  });

  it("呈現 74 §1 五欄：名稱／email 訂閱 chip／地點／訂單／消費金額（MoneyV2 千分位）", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      successfulResponse([
        customerNode(),
        customerNode({
          id: "gid://chilllove/Customer/2",
          displayName: "guest@example.com",
          email: "guest@example.com",
          emailMarketingConsent: false,
          ordersCount: 1,
          amountSpent: { amount: "188.00", currencyCode: "HKD" },
          defaultAddress: null,
        }),
      ]),
    );
    vi.stubGlobal("fetch", fetchMock);

    renderCustomers();

    expect(await screen.findByText("陳大文")).toBeVisible();
    expect(screen.getByText("已訂閱")).toBeVisible();
    expect(screen.getByText("未訂閱")).toBeVisible();
    expect(screen.getByText("Central, HK")).toBeVisible();
    expect(screen.getByText("$1,480.00")).toBeVisible(); // 千分位＋兩位小數
    expect(screen.getByText("$188.00")).toBeVisible();
    // 表頭五欄
    for (const header of [ "顧客名稱", "電子郵件訂閱", "地點", "訂單", "消費金額" ]) {
      expect(screen.getByRole("columnheader", { name: header })).toBeVisible();
    }
  });

  it("搜尋以伺服器 query 參數送出（300ms 去抖）", async () => {
    const fetchMock = vi.fn().mockResolvedValue(successfulResponse([ customerNode() ]));
    vi.stubGlobal("fetch", fetchMock);

    renderCustomers();
    await screen.findByText("陳大文");

    const user = userEvent.setup();
    await user.type(screen.getByPlaceholderText("搜尋姓名、email、電話"), "chan");
    await waitFor(() => {
      const last = JSON.parse(String((fetchMock.mock.calls.at(-1)?.[1] as RequestInit).body)) as {
        variables: Record<string, unknown>;
      };
      expect(last.variables.query).toBe("chan");
    });
  });

  it("顯示可重試的錯誤狀態，重試後恢復", async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new Error("網路暫時中斷"))
      .mockResolvedValue(successfulResponse());
    vi.stubGlobal("fetch", fetchMock);

    renderCustomers();

    expect(await screen.findByRole("alert")).toHaveTextContent("顧客資料載入失敗");
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "重試" }));
    expect(await screen.findByRole("heading", { name: "還沒有顧客" })).toBeVisible();
  });
});
