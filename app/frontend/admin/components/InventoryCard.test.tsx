import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useParams, useSearchParams } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Mock } from "vitest";
import { InventoryCard } from "./InventoryCard";
import { I18nProvider } from "../i18n/I18nContext";
import { ToastProvider } from "../lib/ToastContext";

/**
 * 商品頁庫存卡（第 18 包 B 塊）的驗收測試。
 *
 * 🔴 這裡刻意**不**重測調整浮層的值域與 payload 形狀——A 塊的
 * `pages/InventoryPage.test.tsx` 已逐項窮舉，而兩處用的是**同一個**
 * `InventoryAdjustPopover`。重測會變成「同一件事兩份斷言」，其中一份改了另一份
 * 不會紅。本檔只測 B 塊獨有的三件事：Total 欄名、卡內自己的儲存鈕、歷程連結。
 */
function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

function graphqlResponse(body: unknown) {
  return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
}

const CARD_BODY = {
  data: {
    inventoryItems: {
      nodes: [
        {
          id: "gid://chilllove/InventoryItem/7",
          sku: "TEE-S",
          tracked: true,
          variantTitle: "S / 黑",
          locationId: "gid://chilllove/Location/1",
          quantities: { available: 25, onHand: 27 },
        },
        {
          id: "gid://chilllove/InventoryItem/8",
          sku: null,
          tracked: false,
          variantTitle: "M / 黑",
          locationId: "gid://chilllove/Location/1",
          quantities: { available: 0, onHand: 0 },
        },
      ],
    },
    locations: [ { id: "gid://chilllove/Location/1", name: "Shop location" } ],
  },
};

function stubFetch(multiLocation = false) {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string };
    if (request.query.includes("query ProductInventory")) {
      if (!multiLocation) return graphqlResponse(CARD_BODY);
      return graphqlResponse({
        data: {
          ...CARD_BODY.data,
          locations: [
            { id: "gid://chilllove/Location/1", name: "Shop location" },
            { id: "gid://chilllove/Location/2", name: "Warehouse B" },
          ],
        },
      });
    }
    if (request.query.includes("mutation ProductInventoryAdjust")) {
      return graphqlResponse({
        data: { inventoryAdjustQuantities: { inventoryAdjustmentGroup: { id: "gid://chilllove/InventoryAdjustmentGroup/9" }, userErrors: [] } },
      });
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

/** 歷程頁的替身：只印出它收到的 :itemId，用來斷言連結真的帶對品項。 */
function HistoryProbe() {
  const params = useParams<{ itemId: string }>();
  const [search] = useSearchParams();
  return (
    <>
      <p>歷程 {decodeURIComponent(params.itemId ?? "")}</p>
      <p>地點 {search.get("locationId") ?? "（未帶）"}</p>
    </>
  );
}

function renderCard() {
  render(
    <MemoryRouter initialEntries={[ "/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F3" ]}>
      <I18nProvider initialLocale="zh-Hant">
        <ToastProvider>
          <Routes>
            <Route element={<InventoryCard productId="gid://chilllove/Product/3" />} path="/admin/products/:id" />
            <Route element={<HistoryProbe />} path="/admin/inventory/:itemId/history" />
          </Routes>
        </ToastProvider>
      </I18nProvider>
    </MemoryRouter>,
  );
}

describe("商品頁庫存卡", () => {
  beforeEach(() => installCsrfMeta());

  it("按 productId 取該商品的變體庫存；on_hand 欄名是 Total（本尊商品頁用語，94 §2b⑤）", async () => {
    const fetchMock = stubFetch();
    renderCard();

    await waitFor(() => expect(screen.getByText("S / 黑")).toBeTruthy());
    const headers = Array.from(document.querySelectorAll("thead th")).map((cell) => cell.textContent);
    expect(headers).toEqual([ "變體", "可售", "總計", "記錄" ]);

    // 查詢一定帶 productId——B 塊不靠標題搜尋（會撈到同名的別的商品）
    const [ query ] = bodiesOf(fetchMock, "query ProductInventory");
    expect(query.variables.productId).toBe("gid://chilllove/Product/3");

    // 未追蹤變體顯示「未追蹤」，不是 0
    expect(screen.getAllByText("未追蹤").length).toBe(2);
    // 且未追蹤的兩格不可點（沒有按鈕形態）
    expect(screen.queryAllByRole("button", { name: "0" })).toEqual([]);
  });

  it("兩段式：✓ 只 stage 不打 API，卡內儲存鈕才送出一次 adjust", async () => {
    const fetchMock = stubFetch();
    const user = userEvent.setup();
    renderCard();

    await waitFor(() => expect(screen.getByText("S / 黑")).toBeTruthy());
    await user.click(screen.getByRole("button", { name: "25" }));
    // 預設模式是「設為」；本例要測 adjust 路徑，明示切換
    await user.selectOptions(screen.getByRole("combobox", { name: "調整方式" }), "adjust");
    const quantity = screen.getByRole("textbox", { name: "數量" });
    await user.clear(quantity);
    await user.type(quantity, "1");
    await user.click(screen.getByRole("button", { name: "暫存調整" }));

    // stage 後畫面顯示 25 → 26，且尚未有任何 mutation
    await waitFor(() => expect(screen.getByText("26")).toBeTruthy());
    expect(bodiesOf(fetchMock, "mutation")).toEqual([]);

    await user.click(screen.getByRole("button", { name: "儲存庫存" }));

    await waitFor(() => expect(bodiesOf(fetchMock, "mutation ProductInventoryAdjust").length).toBe(1));
    const [ mutation ] = bodiesOf(fetchMock, "mutation ProductInventoryAdjust");
    const input = mutation.variables.input as { changes: Record<string, unknown>[]; name: string; reason: string };
    // CAS 基準＝畫面上看到的那個值，原封不動送出（不是後端再讀一次）
    expect(input.changes[0]).toEqual({
      changeFromQuantity: 25,
      delta: 1,
      inventoryItemId: "gid://chilllove/InventoryItem/7",
      locationId: "gid://chilllove/Location/1",
    });
    expect(input.name).toBe("available");
    expect(String(mutation.variables.key)).toMatch(/^[0-9a-f-]{36}$/);
    // 儲存後一律重讀（寫入後的真值來自伺服器，不本地推算）
    await waitFor(() => expect(bodiesOf(fetchMock, "query ProductInventory").length).toBe(2));
  });

  it("歷程連結**逐列**且必帶 locationId（歷程是 (品項, 地點) 的帳）", async () => {
    stubFetch();
    renderCard();

    await waitFor(() => expect(screen.getByText("S / 黑")).toBeTruthy());
    const user = userEvent.setup();

    // 🔴 每一列各有自己的連結：原本整張卡共用一顆鈕、永遠指 rows[0]，
    // 多變體商品必定指錯變體（對抗式複查 2026-08-24 抓到）。
    const links = screen.getAllByRole("button", { name: "檢視調整記錄" });
    expect(links.length).toBe(2);

    // 點第二列 ⇒ 必須是第二列的品項，不是 rows[0]
    await user.click(links[1]);
    await waitFor(() => expect(screen.getByText("歷程 gid://chilllove/InventoryItem/8")).toBeTruthy());
    // 且帶著地點——不帶的話後端退回 priority 序第一個地點，看到別的倉庫的帳
    expect(screen.getByText("地點 gid://chilllove/Location/1")).toBeTruthy();
  });

  it("換地點一律丟棄 pending，並且說出來（不得靜默）", async () => {
    stubFetch(true);
    const user = userEvent.setup();
    renderCard();

    await waitFor(() => expect(screen.getByText("S / 黑")).toBeTruthy());
    await user.click(screen.getByRole("button", { name: "25" }));
    await user.selectOptions(screen.getByRole("combobox", { name: "調整方式" }), "adjust");
    const quantity = screen.getByRole("textbox", { name: "數量" });
    await user.clear(quantity);
    await user.type(quantity, "1");
    await user.click(screen.getByRole("button", { name: "暫存調整" }));
    await waitFor(() => expect(screen.getByText("26")).toBeTruthy());

    // 🔴 換地點：pending 的 compareAgainst 是**舊地點**看到的值，
    // 若留著，儲存時會用 A 倉的 CAS 基準寫進 B 倉（同值時 CAS 還會通過）。
    await user.selectOptions(screen.getByRole("combobox", { name: "地點" }), "gid://chilllove/Location/2");

    await waitFor(() => expect(screen.getByText("已切換地點，未儲存的調整已捨棄。")).toBeTruthy());
    // 儲存鈕消失＝真的沒有 pending 了
    expect(screen.queryByRole("button", { name: "儲存庫存" })).toBeNull();
  });
});
