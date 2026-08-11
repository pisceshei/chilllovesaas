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

function successfulResponse(nodes: unknown[] = []) {
  return {
    json: vi.fn().mockResolvedValue({
      data: {
        products: {
          nodes,
          pageInfo: { endCursor: null, hasNextPage: false },
        },
      },
    }),
    ok: true,
    status: 200,
  } as unknown as Response;
}

describe("商品頁", () => {
  beforeEach(() => installCsrfMeta());

  it("以唯一 Admin GraphQL POST 載入後呈現商品空狀態", async () => {
    const fetchMock = vi.fn().mockResolvedValue(successfulResponse());
    vi.stubGlobal("fetch", fetchMock);

    render(
      <MemoryRouter initialEntries={["/admin/products"]}>
        <AdminRoutes brandName="測試品牌" />
      </MemoryRouter>,
    );

    expect(screen.getByRole("status")).toHaveTextContent("正在載入商品");
    expect(await screen.findByRole("heading", { name: "還沒有商品" })).toBeVisible();
    expect(screen.getByText("建立第一項商品，開始整理你的商店目錄。")).toBeVisible();
    expect(screen.getAllByText("測試品牌").length).toBeGreaterThan(0);

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
    expect(JSON.parse(String(options.body))).toEqual(
      expect.objectContaining({
        query: expect.stringContaining("products(first: $first)"),
        variables: { first: 50 },
      }),
    );
  });

  it("顯示可重試的錯誤狀態，重試後回到空狀態", async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new Error("網路暫時中斷"))
      .mockResolvedValueOnce(successfulResponse());
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();

    render(
      <MemoryRouter initialEntries={["/admin/products"]}>
        <AdminRoutes brandName="測試品牌" />
      </MemoryRouter>,
    );

    expect(await screen.findByRole("alert")).toHaveTextContent("網路暫時中斷");
    await user.click(screen.getByRole("button", { name: "再試一次" }));

    expect(await screen.findByRole("heading", { name: "還沒有商品" })).toBeVisible();
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    for (const [endpoint, options] of fetchMock.mock.calls as [string, RequestInit][]) {
      expect(endpoint).toBe(ADMIN_GRAPHQL_ENDPOINT);
      expect(options.method).toBe("POST");
    }
  });

  it("呈現商品資料表，並可從搜尋空結果清除條件", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      successfulResponse([
        { id: "gid://chilllove/Product/1", title: "夏日上衣", status: "DRAFT" },
        { id: "gid://chilllove/Product/2", title: "經典長褲", status: "ACTIVE" },
      ]),
    );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();

    render(
      <MemoryRouter initialEntries={["/admin/products"]}>
        <AdminRoutes brandName="測試品牌" />
      </MemoryRouter>,
    );

    expect(await screen.findByRole("table", { name: "商品列表" })).toBeVisible();
    expect(screen.getByText("夏日上衣")).toBeVisible();
    expect(screen.getByText("草稿")).toBeVisible();
    expect(screen.getByText("使用中")).toBeVisible();

    await user.type(screen.getByRole("searchbox", { name: "搜尋商品" }), "不存在");
    expect(await screen.findByRole("heading", { name: "找不到符合的商品" })).toBeVisible();

    await user.click(screen.getByRole("button", { name: "清除搜尋" }));
    expect(screen.getByText("經典長褲")).toBeVisible();
  });
});
