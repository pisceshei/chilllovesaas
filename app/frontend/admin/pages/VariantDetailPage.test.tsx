import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AdminRoutes } from "../App";

/**
 * 變體子頁（第 29 包）。
 *
 * 🔴 本檔最重要的一條＝**存一個變體不得刪掉其他變體**。`productSet` 是宣告式全量，
 *   沒列在 `variants` 裡的會被刪除。子頁只編一列，但必須整份回送——
 *   這個錯誤的症狀是「改了 M 的價格，L 和 XL 不見了」，而且沒有任何錯誤訊息。
 */
function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

function jsonResponse(body: unknown) {
  return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
}

const PRODUCT_GID = "gid://chilllove/Product/9";
const V = (n: number, title: string, extra: Record<string, unknown> = {}) => ({
  id: `gid://chilllove/ProductVariant/${n}`,
  title,
  position: n,
  price: `${100 + n}.00`,
  compareAtPrice: null,
  cost: null,
  sku: `SKU-${title}`,
  barcode: null,
  taxable: true,
  weightGrams: 0,
  requiresShipping: true,
  selectedOptions: [ { name: "尺寸", value: title } ],
  image: null,
  inventoryLevels: [],
  ...extra,
});

const PRODUCT = {
  id: PRODUCT_GID,
  title: "帽T",
  status: "ACTIVE",
  handle: "tee",
  lockVersion: 3,
  featuredImage: null,
  options: [ { name: "尺寸", position: 1, values: [
    { value: "S", position: 1 }, { value: "M", position: 2 }, { value: "L", position: 3 },
  ] } ],
  variants: { nodes: [ V(1, "S"), V(2, "M"), V(3, "L") ] },
};

function stubGraphql(product: unknown = PRODUCT) {
  const calls: { query: string; variables: Record<string, unknown> }[] = [];
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as { query: string; variables: Record<string, unknown> };
    calls.push(body);
    if (body.query.includes("mutation productSet")) {
      return jsonResponse({ data: { productSet: {
        product: { id: PRODUCT_GID, lockVersion: 4 }, userErrors: [],
      } } });
    }
    if (body.query.includes("productVariantAppendMedia")) {
      return jsonResponse({ data: { productVariantAppendMedia: { media: [], userErrors: [] } } });
    }
    return jsonResponse({ data: { product } });
  });
  vi.stubGlobal("fetch", fetchMock);
  return calls;
}

function renderAt(variantNumber: number) {
  const path = `/admin/products/${encodeURIComponent(PRODUCT_GID)}`
    + `/variants/${encodeURIComponent(`gid://chilllove/ProductVariant/${variantNumber}`)}`;
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

describe("變體子頁", () => {
  beforeEach(() => installCsrfMeta());

  it("載入：麵包屑、標題、左欄變體清單（當前高亮）", async () => {
    stubGraphql();
    renderAt(2);

    expect(await screen.findByRole("heading", { name: "M" })).toBeVisible();
    const crumb = within(screen.getByRole("navigation", { name: "階層導覽" }));
    expect(crumb.getByRole("link", { name: "帽T" })).toBeVisible();

    const list = within(screen.getByRole("list", { name: "變體清單" }));
    expect(list.getAllByRole("button")).toHaveLength(3);
    // 當前變體帶 aria-current
    expect(list.getByRole("button", { current: "page" })).toHaveTextContent("M");
  });

  it("🔴 存一個變體要**整份回送**——其他變體不得從 payload 裡消失", async () => {
    const calls = stubGraphql();
    renderAt(2);
    const user = userEvent.setup();

    const price = await screen.findByLabelText("價格（HK$）");
    await user.clear(price);
    await user.type(price, "199.00");
    await user.click(screen.getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(true));
    const input = calls.find((c) => c.query.includes("mutation productSet"))!
      .variables.input as { variants: { id: string; price: string }[]; options: unknown[] };

    // 🔴 三個變體都在（不是只送被編的那一個）
    expect(input.variants).toHaveLength(3);
    expect(input.variants.map((v) => v.id)).toEqual([
      "gid://chilllove/ProductVariant/1",
      "gid://chilllove/ProductVariant/2",
      "gid://chilllove/ProductVariant/3",
    ]);
    // 被編的那一個帶新價，其他原樣
    expect(input.variants[1].price).toBe("199.00");
    expect(input.variants[0].price).toBe("101.00");
    expect(input.variants[2].price).toBe("103.00");
    // 🔴 options 樹也要回送——缺了它後端會把選項連同座標一起清掉
    expect(input.options).toHaveLength(1);
  });

  it("🔴 運送欄一律回送（不送＝把重量清成 0）", async () => {
    const calls = stubGraphql({
      ...PRODUCT,
      variants: { nodes: [ V(1, "S", { weightGrams: 1250, requiresShipping: true }), V(2, "M") ] },
    });
    renderAt(2);
    const user = userEvent.setup();

    await screen.findByRole("heading", { name: "M" });
    await user.click(screen.getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(true));
    const input = calls.find((c) => c.query.includes("mutation productSet"))!
      .variables.input as { variants: { weightGrams: number; requiresShipping: boolean }[] };
    // 沒被編的 S 保住它的 1250——這正是回聲欄要防的事
    expect(input.variants[0].weightGrams).toBe(1250);
    expect(input.variants[1].weightGrams).toBe(0);
    expect(input.variants.every((v) => typeof v.requiresShipping === "boolean")).toBe(true);
  });

  it("變體間導航：第一個沒有「上一個」，最後一個沒有「下一個」", async () => {
    stubGraphql();
    renderAt(1);

    await screen.findByRole("heading", { name: "S" });
    expect(screen.getByRole("button", { name: "上一個變體" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "下一個變體" })).toBeEnabled();
  });

  it("左欄搜尋過濾變體清單", async () => {
    stubGraphql();
    renderAt(1);
    const user = userEvent.setup();

    await screen.findByRole("heading", { name: "S" });
    await user.type(screen.getByLabelText("搜尋變體"), "L");

    const list = within(screen.getByRole("list", { name: "變體清單" }));
    expect(list.getAllByRole("button")).toHaveLength(1);
    expect(list.getByRole("button")).toHaveTextContent("L");
  });

  it("🔴 庫存卡唯讀：顯示各地點數量，且明說要去哪裡調整", async () => {
    stubGraphql({
      ...PRODUCT,
      variants: { nodes: [ V(1, "S", { inventoryLevels: [ {
        inventoryItemId: "gid://chilllove/InventoryItem/1",
        location: { id: "gid://chilllove/Location/1", name: "倉庫甲" },
        quantities: { available: 12, onHand: 15, committed: 3 },
      } ] }) ] },
    });
    renderAt(1);

    await screen.findByRole("heading", { name: "S" });
    const table = within(screen.getByRole("table", { name: "各地點的庫存數量" }));
    expect(table.getByText("倉庫甲")).toBeVisible();
    expect(table.getByText("12")).toBeVisible();
    // 🔴 沒有任何可編輯的庫存輸入框——庫存只能經 inventoryAdjustQuantities（D43）
    expect(screen.getByText(/庫存只能在庫存頁或商品頁的庫存卡調整/)).toBeVisible();
  });

  // ── 對抗式審查（2026-08-25）確認後補的守衛 ──────────────────────────
  // 🔴 全部是**缺席的測試**：把下面每一道守衛刪掉，上面七條會全綠。

  it("🔴 變體超過載入上限 ⇒ 封鎖儲存（否則第 251 個之後會被宣告式刪掉）", async () => {
    const calls = stubGraphql({
      ...PRODUCT,
      variants: { pageInfo: { hasNextPage: true }, nodes: [ V(1, "S"), V(2, "M") ] },
    });
    renderAt(2);
    const user = userEvent.setup();

    await screen.findByRole("heading", { name: "M" });
    await user.click(screen.getByRole("button", { name: "儲存" }));

    expect(await screen.findByText(/此頁編輯已鎖定/)).toBeVisible();
    expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(false);
  });

  it("🔴 比較價／成本打錯 ⇒ 擋下（不得靜默轉成「清除該金額」）", async () => {
    const calls = stubGraphql();
    renderAt(2);
    const user = userEvent.setup();

    const compare = await screen.findByLabelText("原價（劃線價）");
    await user.clear(compare);
    await user.type(compare, "abc");
    await user.click(screen.getByRole("button", { name: "儲存" }));

    expect(await screen.findByText(/請輸入有效金額/)).toBeVisible();
    expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(false);
  });

  it("🔴 改選項值 ⇒ 送出的 options 樹要含新值（否則後端一律 reject）", async () => {
    const calls = stubGraphql();
    renderAt(2);
    const user = userEvent.setup();

    const coord = await screen.findByLabelText("尺寸");
    await user.clear(coord);
    await user.type(coord, "Medium");
    await user.click(screen.getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(true));
    const input = calls.find((c) => c.query.includes("mutation productSet"))!
      .variables.input as {
        options: { name: string; values: string[] }[];
        variants: { optionValues: { optionName: string; value: string }[] }[];
      };
    // 舊版照抄伺服器的 options（S/M/L），新值 Medium 不在裡面 ⇒ 後端必拒。
    expect(input.options[0].values).toContain("Medium");
    // 且不再含被改掉的舊值（沒有別的變體用 M）——這就是「重新命名」的語義。
    expect(input.options[0].values).not.toContain("M");
    // options.values 必須涵蓋每個變體的座標，否則兩者不一致
    const declared = new Set(input.options[0].values);
    for (const variant of input.variants) {
      expect(declared.has(variant.optionValues[0].value)).toBe(true);
    }
  });

  it("🔴 改成與別的變體相同的座標 ⇒ 前端先擋（後端只會回通用唯一鍵錯誤）", async () => {
    const calls = stubGraphql();
    renderAt(2);
    const user = userEvent.setup();

    const coord = await screen.findByLabelText("尺寸");
    await user.clear(coord);
    await user.type(coord, "L"); // 與第三個變體撞號

    await user.click(screen.getByRole("button", { name: "儲存" }));
    expect(await screen.findByText(/每個選項都要有不重複的名稱與至少一個值/)).toBeVisible();
    expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(false);
  });

  it("🔴 變體不存在 ⇒ 顯示錯誤與回商品頁的出口（不得永遠轉圈）", async () => {
    stubGraphql();
    renderAt(99); // 不在 nodes 裡

    expect(await screen.findByText(/找不到這個變體/)).toBeVisible();
    expect(screen.getByRole("link", { name: "回到商品" })).toBeVisible();
  });

  it("🔴 有未存編輯時切換變體 ⇒ 先攔一次（不得靜默丟掉）", async () => {
    stubGraphql();
    renderAt(2);
    const user = userEvent.setup();

    const price = await screen.findByLabelText("價格（HK$）");
    await user.clear(price);
    await user.type(price, "888.00");

    const list = within(screen.getByRole("list", { name: "變體清單" }));
    await user.click(list.getByRole("button", { name: /L/ }));

    // 攔截：仍停在 M，且輸入還在
    expect(await screen.findByText(/有未儲存的變更/)).toBeVisible();
    expect(screen.getByRole("heading", { name: "M" })).toBeVisible();
    expect(screen.getByLabelText("價格（HK$）")).toHaveValue("888.00");
  });

  it("四張卡的標題是看得見的標題（不是 title 屬性 tooltip）", async () => {
    stubGraphql();
    renderAt(2);

    await screen.findByRole("heading", { name: "M" });
    for (const name of [ "選項值", "定價", "庫存", "運送" ]) {
      expect(screen.getByRole("heading", { name })).toBeVisible();
    }
  });

  it("非實體商品：重量欄不顯示，且不因此擋住儲存", async () => {
    const calls = stubGraphql({
      ...PRODUCT,
      variants: { nodes: [ V(1, "S"), V(2, "M", { requiresShipping: false, weightGrams: 0 }) ] },
    });
    renderAt(2);
    const user = userEvent.setup();

    await screen.findByRole("heading", { name: "M" });
    expect(screen.queryByLabelText("商品重量（公克）")).toBeNull();
    await user.click(screen.getByRole("button", { name: "儲存" }));
    await waitFor(() => expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(true));
  });

  it("重量非整數 ⇒ 擋在前端，不打 productSet", async () => {
    const calls = stubGraphql();
    renderAt(2);
    const user = userEvent.setup();

    const weight = await screen.findByLabelText("商品重量（公克）");
    await user.clear(weight);
    await user.type(weight, "1.5");
    await user.click(screen.getByRole("button", { name: "儲存" }));

    expect(await screen.findByText(/重量必須是 0 或正整數/)).toBeVisible();
    expect(calls.some((c) => c.query.includes("mutation productSet"))).toBe(false);
  });
});
