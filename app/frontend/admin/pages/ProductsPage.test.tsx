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
    // 文案正典＝原型 P_STATUS 的 `bt` 欄（chilllove-admin-v2.html:3106）。
    // 本斷言原本是「使用中」——那是本專案自創的文案，與原型不符（鐵律 12）。
    expect(screen.getByText("啟用中")).toBeVisible();

    await user.type(screen.getByRole("searchbox", { name: "搜尋商品" }), "不存在");
    expect(await screen.findByRole("heading", { name: "找不到符合的商品" })).toBeVisible();

    await user.click(screen.getByRole("button", { name: "清除搜尋" }));
    expect(screen.getByText("經典長褲")).toBeVisible();
  });

  // 🔴 四態全部要能畫出來（13 §F1.2）。UNLISTED 是本輪新加進 GraphQL enum 的第四值——
  // 前端的 `statusPresentation` 早就有它，但**從來沒有任何測試證明它會被渲染**，
  // 而後端 enum 直到本輪都只回三值 ⇒ 這條路徑實際上從未被走過。
  it("四種商品狀態各自畫出原型 P_STATUS 的徽章文案", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      successfulResponse([
        { id: "gid://chilllove/Product/1", title: "啟用品", status: "ACTIVE" },
        { id: "gid://chilllove/Product/2", title: "未列出品", status: "UNLISTED" },
        { id: "gid://chilllove/Product/3", title: "草稿品", status: "DRAFT" },
        { id: "gid://chilllove/Product/4", title: "封存品", status: "ARCHIVED" },
      ]),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(
      <MemoryRouter initialEntries={["/admin/products"]}>
        <AdminRoutes brandName="測試品牌" />
      </MemoryRouter>,
    );

    expect(await screen.findByRole("table", { name: "商品列表" })).toBeVisible();
    // 文案逐字取自原型 P_STATUS 的 `bt` 欄（chilllove-admin-v2.html:3106-3113）。
    expect(screen.getByText("啟用中")).toBeVisible();
    expect(screen.getByText("未列出")).toBeVisible();
    expect(screen.getByText("草稿")).toBeVisible();
    expect(screen.getByText("已封存")).toBeVisible();

    // 🔴 pip 也要釘住，不是只釘文案。原型 P_STATUS 的 `pip` 欄：
    // ACTIVE=full、UNLISTED=''（裸圈⇒我方 empty）、DRAFT=''（同）、ARCHIVED=blocked。
    // UNLISTED 本檔原本寫 `half`（半圈＝進行中），語義上是錯的——它不是「進行中」，
    // 它是「啟用但不被發現」。文案斷言抓不到這種錯，只有 pip 斷言抓得到。
    const pipOf = (label: string) =>
      screen.getByText(label).parentElement?.querySelector("[class*='cl-badge__pip']")?.className;
    expect(pipOf("啟用中")).toContain("cl-badge__pip--full");
    expect(pipOf("未列出")).toContain("cl-badge__pip--empty");
    expect(pipOf("草稿")).toContain("cl-badge__pip--empty");
    // ⚠️ ARCHIVED 目前是 full，與原型的 `blocked` 不符——`23` §1 只定義三種 pip、
    // 沒有 blocked，補第四種是視覺語言變更，不夾在本輪。刻意斷言**現況**，
    // 讓之後真的去對齊時這條會紅，逼人回來讀上面這段。
    expect(pipOf("已封存")).toContain("cl-badge__pip--full");
  });

  // 未知狀態的 fallback：GraphQL enum 之後若再擴值，前端不得整頁炸掉。
  it("未知狀態退回顯示原始 token，不丟例外", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      successfulResponse([
        { id: "gid://chilllove/Product/9", title: "未來狀態", status: "SOMETHING_NEW" },
      ]),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(
      <MemoryRouter initialEntries={["/admin/products"]}>
        <AdminRoutes brandName="測試品牌" />
      </MemoryRouter>,
    );

    expect(await screen.findByRole("table", { name: "商品列表" })).toBeVisible();
    expect(screen.getByText("SOMETHING_NEW")).toBeVisible();
  });
});
