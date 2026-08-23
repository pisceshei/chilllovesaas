import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AdminRoutes } from "../App";
import { ADMIN_GRAPHQL_ENDPOINT } from "../api/graphql";

// useBlocker 只在 data router 下生效 ⇒ 測試用 createMemoryRouter
// （MemoryRouter 是 declarative，ProductDetailPage 一掛載就會拋錯）。
function renderAt(path: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

function graphqlResponse(body: unknown) {
  return {
    json: vi.fn().mockResolvedValue(body),
    ok: true,
    status: 200,
  } as unknown as Response;
}

const CREATED = {
  data: {
    productSet: {
      product: {
        id: "gid://chilllove/Product/9",
        handle: "tee",
        status: "DRAFT",
        title: "帽T",
        lockVersion: 0,
      },
      userErrors: [],
    },
  },
};

const EMPTY_LIST = {
  data: { products: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } } },
};

describe("新增商品頁", () => {
  beforeEach(() => installCsrfMeta());

  it("渲染建立態：草稿徽章＋原型卡片樹（定價／庫存／SEO／發布）", () => {
    renderAt("/admin/products/new");

    // scope 到 main：側欄有「草稿」（訂單子項連結）同字樣（UI-2 教訓同型）。
    const main = within(screen.getByRole("main"));
    expect(main.getByRole("heading", { name: "新增商品" })).toBeVisible();
    expect(main.getByText("草稿")).toBeVisible();
    for (const card of [ "標題與說明", "多媒體", "定價", "庫存", "運送", "搜尋引擎產品資訊", "發布" ]) {
      expect(main.getByRole("heading", { name: new RegExp(card) })).toBeVisible();
    }
    // 建立態右欄只有發布卡；狀態卡不出現（預設即 DRAFT，59 §7）
    expect(main.queryByRole("heading", { name: "狀態" })).toBeNull();
  });

  it("驗證失敗：空表單儲存 ⇒ toast＋標題欄錯誤，且不打 API", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    await user.click(screen.getByRole("button", { name: "儲存" }));

    expect(await screen.findByText("有欄位未通過驗證")).toBeVisible();
    expect(screen.getByText("標題不能為空白。")).toBeVisible();
    expect(screen.getByText("價格必填。")).toBeVisible();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("儲存成功：送完整樹（含 DRAFT／兩位小數金額／idempotencyKey），轉導商品列表", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(graphqlResponse(CREATED))
      .mockResolvedValue(graphqlResponse(EMPTY_LIST));
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    const router = renderAt("/admin/products/new");

    await user.type(screen.getByLabelText("標題"), "奶茶色寬版帽T");
    await user.type(screen.getByLabelText("價格（HK$）"), "128.5");
    // dirty 後同時有頁首「儲存」與 SaveBar「儲存」（雙提交入口）⇒ 取 SaveBar 內那顆消歧
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/admin/products"));

    const [ url, init ] = fetchMock.mock.calls[0] as [ string, RequestInit ];
    expect(url).toBe(ADMIN_GRAPHQL_ENDPOINT);
    const body = JSON.parse(String(init.body)) as {
      variables: { input: Record<string, unknown>; idempotencyKey: string };
    };
    // 🔴 B.4 規則 1：完整樹＋顯式 DRAFT；金額補位成恆兩位小數字串（12850 cents）
    expect(body.variables.input).toEqual({
      title: "奶茶色寬版帽T",
      descriptionHtml: "",
      status: "DRAFT",
      variants: [ { price: "128.50", taxable: true } ],
    });
    expect(body.variables.idempotencyKey).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
  });

  it("伺服器 userErrors 映射到欄位（variants.0.price → 價格欄）", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      graphqlResponse({
        data: {
          productSet: {
            product: null,
            userErrors: [
              { field: [ "variants", "0", "price" ], message: "金額不得為負。", code: "GREATER_THAN_OR_EQUAL_TO" },
            ],
          },
        },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    await user.type(screen.getByLabelText("標題"), "測試");
    await user.type(screen.getByLabelText("價格（HK$）"), "1.00");
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    expect(await screen.findByText("金額不得為負。")).toBeVisible();
  });

  describe("編輯態（/admin/products/:id）", () => {
    const EXISTING = {
      data: {
        product: {
          id: "gid://chilllove/Product/9",
          title: "既有商品",
          descriptionHtml: "<p>舊說明</p>",
          status: "DRAFT",
          handle: "existing-tee",
          lockVersion: 3,
          variants: [
            { price: "128.00", compareAtPrice: null, cost: null, sku: "SKU-1", barcode: null, taxable: true },
          ],
        },
      },
    };

    it("載入既有商品填表：標題／價格／handle（唯讀）／狀態卡兩維讀值", async () => {
      const fetchMock = vi.fn().mockResolvedValue(graphqlResponse(EXISTING));
      vi.stubGlobal("fetch", fetchMock);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      expect(await main.findByRole("heading", { name: "既有商品" })).toBeVisible();
      expect(main.getByLabelText("標題")).toHaveValue("既有商品");
      expect(main.getByLabelText("價格（HK$）")).toHaveValue("128.00");
      expect(main.getByLabelText("網址 handle")).toHaveValue("existing-tee");
      expect(main.getByLabelText("網址 handle")).toBeDisabled();
      expect(main.getByLabelText("商品狀態")).toHaveValue("DRAFT");
      expect(main.getByText("可購買")).toBeVisible();
    });

    it("儲存送 id＋lockVersion、不帶 idempotencyKey；成功後留在頁上", async () => {
      const fetchMock = vi
        .fn()
        .mockResolvedValueOnce(graphqlResponse(EXISTING))
        .mockResolvedValue(
          graphqlResponse({
            data: {
              productSet: {
                product: {
                  id: "gid://chilllove/Product/9",
                  handle: "existing-tee",
                  status: "ACTIVE",
                  title: "改名",
                  lockVersion: 4,
                },
                userErrors: [],
              },
            },
          }),
        );
      vi.stubGlobal("fetch", fetchMock);
      const user = userEvent.setup();
      const router = renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      const title = await main.findByLabelText("標題");
      await user.clear(title);
      await user.type(title, "改名");
      await user.selectOptions(main.getByLabelText("商品狀態"), "ACTIVE");

      const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
      await user.click(within(savebar).getByRole("button", { name: "儲存" }));

      await screen.findByText("已儲存變更");
      // 留在編輯頁（不轉導）
      expect(router.state.location.pathname).toContain("/admin/products/gid");

      const [ , init ] = fetchMock.mock.calls[1] as [ string, RequestInit ];
      const body = JSON.parse(String(init.body)) as { variables: Record<string, unknown> };
      const input = body.variables.input as Record<string, unknown>;
      expect(input.id).toBe("gid://chilllove/Product/9");
      expect(input.lockVersion).toBe(3);
      expect(input.status).toBe("ACTIVE");
      expect(input).not.toHaveProperty("handle");
      expect(body.variables).not.toHaveProperty("idempotencyKey");
    });

    it("STALE_OBJECT（field null）以 toast 呈現", async () => {
      const fetchMock = vi
        .fn()
        .mockResolvedValueOnce(graphqlResponse(EXISTING))
        .mockResolvedValue(
          graphqlResponse({
            data: {
              productSet: {
                product: null,
                userErrors: [
                  { field: null, message: "商品已被其他人修改，請重新載入後再儲存。", code: "STALE_OBJECT" },
                ],
              },
            },
          }),
        );
      vi.stubGlobal("fetch", fetchMock);
      const user = userEvent.setup();
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      await user.type(await main.findByLabelText("標題"), "x");
      const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
      await user.click(within(savebar).getByRole("button", { name: "儲存" }));

      expect(await screen.findByText("商品已被其他人修改，請重新載入後再儲存。")).toBeVisible();
    });

    it("查無商品 ⇒ 空態卡＋返回列表", async () => {
      const fetchMock = vi.fn().mockResolvedValue(graphqlResponse({ data: { product: null } }));
      vi.stubGlobal("fetch", fetchMock);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F404");

      expect(await screen.findByText("此商品不存在或已被刪除。")).toBeVisible();
      expect(screen.getByRole("button", { name: "返回商品列表" })).toBeVisible();
    });
  });

  it("dirty 時 SaveBar 取代搜尋列；捨棄還原快照", async () => {
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    expect(screen.getByRole("button", { name: "開啟全域搜尋" })).toBeVisible();
    const title = screen.getByLabelText("標題");
    await user.type(title, "abc");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    expect(screen.queryByRole("button", { name: "開啟全域搜尋" })).toBeNull();

    await user.click(within(savebar).getByRole("button", { name: "捨棄" }));
    expect(screen.getByLabelText("標題")).toHaveValue("");
    expect(screen.getByRole("button", { name: "開啟全域搜尋" })).toBeVisible();
  });
});
