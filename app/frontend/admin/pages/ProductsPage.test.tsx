import { render, screen, waitFor, within } from "@testing-library/react";
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
        <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
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
        query: expect.stringContaining("products(first: $first, query: $query)"),
        variables: { first: 50, query: null },
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
        <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
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

  // ML-P1：搜尋改打伺服器（Products::SearchScope）。stub 依 query 變數分流——
  // 這正是「記憶體過濾」與「伺服器過濾」的可測差異：前者無論打什麼字 fetch 都只有一次。
  it("搜尋打在伺服器：query 變數送達、空結果可清除條件", async () => {
    const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as { variables: { query: string | null } };
      if (body.variables.query?.includes("不存在")) return successfulResponse([]);
      return successfulResponse([
        { id: "gid://chilllove/Product/1", title: "夏日上衣", status: "DRAFT", totalInventory: 9 },
        { id: "gid://chilllove/Product/2", title: "經典長褲", status: "ACTIVE", totalInventory: null },
      ]);
    });
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();

    render(
      <MemoryRouter initialEntries={["/admin/products"]}>
        <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
      </MemoryRouter>,
    );

    // 🔴 狀態文案的斷言 scope 到表格內：側欄導覽有「草稿」（訂單子項）這類同字
    // 樣的連結（UI-2 對齊原型 NAV 之後），全文件 getByText 會撞到多重命中。
    const table = await screen.findByRole("table", { name: "商品列表" });
    expect(table).toBeVisible();
    expect(within(table).getByText("夏日上衣")).toBeVisible();
    expect(within(table).getByText("草稿")).toBeVisible();
    // 文案正典＝原型 P_STATUS 的 `bt` 欄（chilllove-admin-v2.html:3106）。
    expect(within(table).getByText("啟用中")).toBeVisible();
    // 第 16 包：庫存欄兩個真相——數字（9 件）與 null（未追蹤）各自有渲染，不得合併。
    // 這條路徑在 totalInventory 落地前恆 undefined，從未被走過。
    expect(within(table).getByText("9 件")).toBeVisible();
    expect(within(table).getByText("未追蹤")).toBeVisible();

    await user.type(screen.getByRole("searchbox", { name: "搜尋商品" }), "不存在");
    // 300ms 去抖後才發出帶 query 的第二發（findBy 的預設等待涵蓋它）
    expect(await screen.findByRole("heading", { name: "找不到符合的商品" })).toBeVisible();
    const queried = fetchMock.mock.calls
      .map((call) => (JSON.parse(String((call[1] as RequestInit).body)) as { variables: { query: string | null } }).variables.query)
      .filter(Boolean);
    expect(queried).toContain("不存在");

    await user.click(screen.getByRole("button", { name: "清除搜尋" }));
    expect(await within(await screen.findByRole("table", { name: "商品列表" })).findByText("經典長褲")).toBeVisible();
  });

  // 值域窮舉：狀態下拉必須四值全列（ARCHIVED 不得省略），且送出的是 status:<小寫> 語法。
  it("狀態篩選：四值全列、選取後以 status: 語法打伺服器", async () => {
    const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as { variables: { query: string | null } };
      if (body.variables.query === "status:draft") {
        return successfulResponse([{ id: "gid://chilllove/Product/1", title: "草稿品", status: "DRAFT" }]);
      }
      return successfulResponse([
        { id: "gid://chilllove/Product/1", title: "草稿品", status: "DRAFT" },
        { id: "gid://chilllove/Product/2", title: "上架品", status: "ACTIVE" },
      ]);
    });
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();

    render(
      <MemoryRouter initialEntries={["/admin/products"]}>
        <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
      </MemoryRouter>,
    );

    const table = await screen.findByRole("table", { name: "商品列表" });
    expect(within(table).getByText("上架品")).toBeVisible();

    const select = screen.getByRole("combobox", { name: "依狀態篩選" });
    const options = within(select).getAllByRole("option").map((option) => option.textContent);
    expect(options).toEqual(["全部狀態", "啟用中", "草稿", "已封存", "未列出"]);

    await user.selectOptions(select, "DRAFT");
    await waitFor(() => {
      const sent = fetchMock.mock.calls
        .map((call) => (JSON.parse(String((call[1] as RequestInit).body)) as { variables: { query: string | null } }).variables.query);
      expect(sent).toContain("status:draft");
    });
    const filtered = await screen.findByRole("table", { name: "商品列表" });
    await waitFor(() => expect(within(filtered).queryByText("上架品")).toBeNull());
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
        <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
      </MemoryRouter>,
    );

    const table = await screen.findByRole("table", { name: "商品列表" });
    expect(table).toBeVisible();
    // 文案逐字取自原型 P_STATUS 的 `bt` 欄（chilllove-admin-v2.html:3106-3113）。
    // scope 到表格內，理由同上一個測試（側欄的「草稿」連結會造成多重命中）。
    expect(within(table).getByText("啟用中")).toBeVisible();
    expect(within(table).getByText("未列出")).toBeVisible();
    expect(within(table).getByText("草稿")).toBeVisible();
    expect(within(table).getByText("已封存")).toBeVisible();

    // 🔴 pip 也要釘住，不是只釘文案。原型 P_STATUS 的 `pip` 欄：
    // ACTIVE=full、UNLISTED=''（裸圈⇒我方 empty）、DRAFT=''（同）、ARCHIVED=blocked。
    // UNLISTED 本檔原本寫 `half`（半圈＝進行中），語義上是錯的——它不是「進行中」，
    // 它是「啟用但不被發現」。文案斷言抓不到這種錯，只有 pip 斷言抓得到。
    const pipOf = (label: string) =>
      within(table).getByText(label).parentElement?.querySelector("[class*='cl-badge__pip']")
        ?.className;
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
        <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" />
      </MemoryRouter>,
    );

    expect(await screen.findByRole("table", { name: "商品列表" })).toBeVisible();
    expect(screen.getByText("SOMETHING_NEW")).toBeVisible();
  });
});
