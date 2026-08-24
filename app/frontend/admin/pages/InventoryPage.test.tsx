import { render, screen, waitFor, within } from "@testing-library/react";
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

const LIST_BODY = {
  data: {
    inventoryItems: {
      nodes: [
        {
          id: "gid://chilllove/InventoryItem/1",
          sku: "TOTE-01",
          tracked: true,
          productTitle: "帆布托特包",
          variantTitle: "Default Title",
          productId: "gid://chilllove/Product/1",
          locationId: "gid://chilllove/Location/1",
          quantities: { unavailable: 3, committed: 2, available: 9, onHand: 14, incoming: 0 },
        },
        {
          id: "gid://chilllove/InventoryItem/2",
          sku: null,
          tracked: false,
          productTitle: "未追蹤品",
          variantTitle: "Default Title",
          productId: "gid://chilllove/Product/2",
          locationId: "gid://chilllove/Location/1",
          quantities: { unavailable: 0, committed: 0, available: 0, onHand: 0, incoming: 0 },
        },
      ],
      pageInfo: { hasNextPage: false, endCursor: null },
    },
    locations: [
      { id: "gid://chilllove/Location/1", name: "Shop location" },
      { id: "gid://chilllove/Location/2", name: "Warehouse B" },
    ],
  },
};

/** 依 query 名分流的 fetch stub——第 18 包規格 §6-2：stub 照真實 payload 形狀。 */
function stubFetch(overrides: { match: string; body: unknown }[] = []) {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string };
    const override = overrides.find((entry) => request.query.includes(entry.match));
    if (override) return graphqlResponse(override.body);
    if (request.query.includes("query InventoryIndex")) return graphqlResponse(LIST_BODY);
    if (request.query.includes("mutation InventorySet")) {
      return graphqlResponse({ data: { inventorySetQuantities: { inventoryAdjustmentGroup: { id: "gid://chilllove/InventoryAdjustmentGroup/1" }, userErrors: [] } } });
    }
    if (request.query.includes("mutation InventoryAdjust")) {
      return graphqlResponse({ data: { inventoryAdjustQuantities: { inventoryAdjustmentGroup: { id: "gid://chilllove/InventoryAdjustmentGroup/2" }, userErrors: [] } } });
    }
    throw new Error(`unexpected GraphQL call: ${request.query.slice(0, 60)}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function bodiesOf(fetchMock: Mock, match: string) {
  return fetchMock.mock.calls
    .map((call) => JSON.parse(String((call[1] as RequestInit).body)) as { query: string; variables: Record<string, unknown> })
    .filter((body) => body.query.includes(match));
}

function renderAt(path: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

describe("庫存列表頁", () => {
  beforeEach(() => installCsrfMeta());

  it("八欄渲染：數量五欄取伺服器值；未追蹤品顯示「未追蹤」而不是 0", async () => {
    stubFetch();
    renderAt("/admin/inventory");

    const table = await screen.findByRole("table", { name: "庫存列表" });
    const scoped = within(table);
    expect(scoped.getByText("帆布托特包")).toBeVisible();
    expect(scoped.getByText("TOTE-01")).toBeVisible();
    // 不可售 3／已佔用 2／可售 9／現有 14（後兩者是 DB 導出值，前端不自行相加）
    expect(scoped.getByText("3")).toBeVisible();
    expect(scoped.getByText("2")).toBeVisible();
    expect(scoped.getByRole("button", { name: "9" })).toBeVisible();
    expect(scoped.getByRole("button", { name: "14" })).toBeVisible();
    // 🔴 未追蹤 ≠ 0（兩個真相）
    expect(scoped.getAllByText("未追蹤").length).toBe(2); // available 與 on hand 兩欄
  });

  it("可調欄位只有 Available 與 On hand（committed／incoming／unavailable 不可點）", async () => {
    stubFetch();
    renderAt("/admin/inventory");

    const table = await screen.findByRole("table", { name: "庫存列表" });
    const buttons = within(table).getAllByRole("button").map((button) => button.textContent);
    // 只有兩個數量按鈕（9 與 14）＋兩列的「檢視調整記錄」
    expect(buttons.filter((text) => text === "9" || text === "14").length).toBe(2);
    expect(buttons).not.toContain("3"); // unavailable 是導出值，不可點
  });

  it("調整器：模式二值、reason 七值全列（值域窮舉）", async () => {
    stubFetch();
    const user = userEvent.setup();
    renderAt("/admin/inventory");

    const table = await screen.findByRole("table", { name: "庫存列表" });
    await user.click(within(table).getByRole("button", { name: "9" }));

    const modes = within(screen.getByRole("combobox", { name: "調整方式" })).getAllByRole("option");
    expect(modes.map((option) => option.textContent)).toEqual([ "設為", "調整幅度" ]);

    const reasons = within(screen.getByRole("combobox", { name: "原因" })).getAllByRole("option");
    expect(reasons.map((option) => option.textContent)).toEqual([
      "更正", "盤點", "已收件", "退貨重新入庫", "損壞", "遭竊或遺失", "促銷或捐贈",
    ]);
  });

  it("🔴 兩段式：✓ 只標 pending（不打網路）、儲存格顯示 9 → 10、SaveBar 出現後才送出", async () => {
    const fetchMock = stubFetch();
    const user = userEvent.setup();
    renderAt("/admin/inventory");

    const table = await screen.findByRole("table", { name: "庫存列表" });
    await user.click(within(table).getByRole("button", { name: "9" }));
    await user.selectOptions(screen.getByRole("combobox", { name: "調整方式" }), "adjust");
    const quantity = screen.getByRole("textbox", { name: "數量" });
    await user.clear(quantity);
    await user.type(quantity, "1");
    await user.click(screen.getByRole("button", { name: "暫存調整" }));

    // ✓ 之後只有最初的列表查詢，沒有 mutation
    expect(bodiesOf(fetchMock, "mutation").length).toBe(0);
    // Available 與 On hand 兩欄同時預覽（實測形態）
    const refreshed = await screen.findByRole("table", { name: "庫存列表" });
    expect(within(refreshed).getByText(/9 →/)).toBeVisible();
    expect(within(refreshed).getByText(/14 →/)).toBeVisible();

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(bodiesOf(fetchMock, "mutation InventoryAdjust").length).toBe(1));
    const sent = bodiesOf(fetchMock, "mutation InventoryAdjust")[0].variables as {
      key: string;
      input: { name: string; reason: string; changes: { delta: number; changeFromQuantity: number; locationId: string }[] };
    };
    expect(sent.key).toMatch(/^[0-9a-f-]{36}$/); // G28：冪等鍵必填
    expect(sent.input.name).toBe("available");
    expect(sent.input.reason).toBe("correction"); // 預設 reason
    expect(sent.input.changes[0].delta).toBe(1);
    // 🔴 CAS 基準＝載入時的現值，原樣送伺服器
    expect(sent.input.changes[0].changeFromQuantity).toBe(9);
    expect(sent.input.changes[0].locationId).toBe("gid://chilllove/Location/1");
  });

  it("Set to：送 compareQuantity（＝載入值）與目標 quantity", async () => {
    const fetchMock = stubFetch();
    const user = userEvent.setup();
    renderAt("/admin/inventory");

    const table = await screen.findByRole("table", { name: "庫存列表" });
    await user.click(within(table).getByRole("button", { name: "9" }));
    const quantity = screen.getByRole("textbox", { name: "數量" });
    await user.clear(quantity);
    await user.type(quantity, "20");
    await user.click(screen.getByRole("button", { name: "暫存調整" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(bodiesOf(fetchMock, "mutation InventorySet").length).toBe(1));
    const sent = bodiesOf(fetchMock, "mutation InventorySet")[0].variables as {
      input: { changes: { quantity: number; compareQuantity: number }[] };
    };
    expect(sent.input.changes[0].quantity).toBe(20);
    expect(sent.input.changes[0].compareQuantity).toBe(9);
  });

  it("CAS stale：伺服端 userErrors 以 toast 呈現（前端不自行擋）", async () => {
    stubFetch([
      {
        match: "mutation InventorySet",
        body: {
          data: {
            inventorySetQuantities: {
              inventoryAdjustmentGroup: null,
              userErrors: [ { field: [ "changes", "0" ], message: "預期 9，但現值為 12。", code: "COMPARE_QUANTITY_STALE" } ],
            },
          },
        },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/inventory");

    const table = await screen.findByRole("table", { name: "庫存列表" });
    await user.click(within(table).getByRole("button", { name: "9" }));
    await user.click(screen.getByRole("button", { name: "暫存調整" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    expect(await screen.findByText("預期 9，但現值為 12。")).toBeVisible();
  });

  it("CSV 匯入匯出 disabled（D43 明文延後，不放可按卻沒反應的鈕）", async () => {
    stubFetch();
    renderAt("/admin/inventory");
    await screen.findByRole("table", { name: "庫存列表" });
    expect(screen.getByRole("button", { name: /匯出/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: /匯入/ })).toBeDisabled();
  });

  it("地點選擇器：列出全部地點，切換後以 locationId 重查", async () => {
    const fetchMock = stubFetch();
    const user = userEvent.setup();
    renderAt("/admin/inventory");

    await screen.findByRole("table", { name: "庫存列表" });
    const picker = screen.getByRole("combobox", { name: "地點" });
    expect(within(picker).getAllByRole("option").map((option) => option.textContent)).toEqual([
      "Shop location", "Warehouse B",
    ]);

    await user.selectOptions(picker, "gid://chilllove/Location/2");
    await waitFor(() => {
      const sent = bodiesOf(fetchMock, "query InventoryIndex").map((body) => body.variables.locationId);
      expect(sent).toContain("gid://chilllove/Location/2");
    });
  });
});

describe("調整記錄頁", () => {
  beforeEach(() => installCsrfMeta());

  const HISTORY_BODY = {
    data: {
      inventoryHistory: [
        {
          id: "gid://chilllove/InventoryHistoryRow/2",
          createdAt: "2026-08-24T04:00:00Z",
          reason: "received",
          mutationKind: "adjust",
          createdBy: "owner@chilllove.test",
          referenceDocumentUri: null,
          ledgerDocumentUri: null,
          changes: [
            { name: "available", delta: 1, quantityAfterChange: 10 },
            { name: "on_hand", delta: 1, quantityAfterChange: 10 },
          ],
        },
        {
          id: "gid://chilllove/InventoryHistoryRow/1",
          createdAt: "2026-08-23T04:00:00Z",
          reason: "cycle_count_available",
          mutationKind: "set",
          createdBy: "admin_web",
          referenceDocumentUri: "app://count/2026-08",
          ledgerDocumentUri: null,
          changes: [
            { name: "available", delta: 9, quantityAfterChange: 9 },
            { name: "on_hand", delta: 9, quantityAfterChange: 9 },
          ],
        },
      ],
    },
  };

  it("欄集 7 欄（無 incoming）；「(+1) 10」格式；Activity 標籤 i18n；參考文件顯示", async () => {
    stubFetch([ { match: "query InventoryHistory", body: HISTORY_BODY } ]);
    renderAt("/admin/inventory/gid%3A%2F%2Fchilllove%2FInventoryItem%2F1/history");

    const table = await screen.findByRole("table", { name: "調整記錄" });
    // 首欄是 IndexTable 的選取欄（空表頭），過濾掉再比對業務欄集
    const headers = within(table).getAllByRole("columnheader").map((cell) => cell.textContent).filter(Boolean);
    expect(headers).toEqual([ "日期", "活動", "建立者", "不可售", "已佔用", "可售", "現有庫存" ]);

    const scoped = within(table);
    expect(scoped.getByText("庫存已收件")).toBeVisible();   // Activity 標籤（非 reason 識別字）
    expect(scoped.getByText("庫存盤點")).toBeVisible();
    expect(scoped.getByText("owner@chilllove.test")).toBeVisible();
    // (+1) 出現兩次：available 與 on_hand 兩欄都顯示同一筆調整的 delta（本尊語義）
    expect(scoped.getAllByText("(+1)").length).toBe(2);
    expect(scoped.getByText("app://count/2026-08")).toBeVisible();
    expect(screen.getByText("僅顯示最近 180 天。")).toBeVisible();
  });

  it("incoming 有變動時才多一欄（條件性欄）", async () => {
    stubFetch([
      {
        match: "query InventoryHistory",
        body: {
          data: {
            inventoryHistory: [
              {
                ...HISTORY_BODY.data.inventoryHistory[0],
                changes: [ { name: "incoming", delta: 5, quantityAfterChange: 5 } ],
              },
            ],
          },
        },
      },
    ]);
    renderAt("/admin/inventory/gid%3A%2F%2Fchilllove%2FInventoryItem%2F1/history");

    const table = await screen.findByRole("table", { name: "調整記錄" });
    // 首欄是 IndexTable 的選取欄（空表頭），過濾掉再比對業務欄集
    const headers = within(table).getAllByRole("columnheader").map((cell) => cell.textContent).filter(Boolean);
    expect(headers).toContain("在途");
  });

  it("空態：沒有調整記錄時給返回入口", async () => {
    stubFetch([ { match: "query InventoryHistory", body: { data: { inventoryHistory: [] } } } ]);
    renderAt("/admin/inventory/gid%3A%2F%2Fchilllove%2FInventoryItem%2F1/history");

    expect(await screen.findByRole("heading", { name: "還沒有調整記錄" })).toBeVisible();
    expect(screen.getAllByRole("button", { name: "返回庫存" }).length).toBeGreaterThan(0);
  });
});
