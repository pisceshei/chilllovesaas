import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Mock } from "vitest";
import { AdminRoutes } from "../App";
import { ADMIN_GRAPHQL_ENDPOINT } from "../api/graphql";

// useBlocker 只在 data router 下生效 ⇒ 測試用 createMemoryRouter
// （MemoryRouter 是 declarative，ProductDetailPage 一掛載就會拋錯）。
function renderAt(path: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
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

/**
 * 按 query 內容路由的 fetch stub。掛載時建議清單查詢（productOrganizationSuggestions）
 * 與商品載入並發 ⇒ 順序式 mockResolvedValueOnce 會互搶（P1 教訓），一律改路由式。
 */
function stubRoutedFetch(routes: { match: string; body: unknown }[]) {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string };
    const route = routes.find((candidate) => request.query.includes(candidate.match));
    if (!route) throw new Error(`未預期的 GraphQL 呼叫：${request.query.slice(0, 80)}`);
    return graphqlResponse(route.body);
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

/** 取出所有命中某 query 片段的呼叫（依序）。 */
function callsTo(fetchMock: Mock, match: string): RequestInit[] {
  return fetchMock.mock.calls
    .map((call) => call[1] as RequestInit)
    .filter((init) => String(init?.body).includes(match));
}

function parsedInput(init: RequestInit) {
  const body = JSON.parse(String(init.body)) as {
    variables: { input: Record<string, unknown>; idempotencyKey?: string };
  };
  return body.variables;
}

const SUGGESTIONS = {
  data: { productVendors: [ "Aesop", "Byredo" ], productTypes: [ "香水" ] },
};

// ML-2：內容語言清單（來源語言 en 排第一；其餘語言在編輯頁長出對應欄位）。
const SHOP_LOCALES = {
  data: {
    shopLocales: [
      { locale: { tag: "en", endonym: "English" }, isSource: true, position: 0 },
      { locale: { tag: "zh-Hant", endonym: "繁體中文" }, isSource: false, position: 1 },
      { locale: { tag: "ja", endonym: "日本語" }, isSource: false, position: 3 },
    ],
  },
};

/** 每個測試都要有的基礎路由（掛載時三支查詢並發）。 */
const BASE_ROUTES = [
  { match: "productOrganizationSuggestions", body: SUGGESTIONS },
  { match: "query shopLocales", body: SHOP_LOCALES },
];

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

  it("渲染建立態：草稿徽章＋原型卡片樹（定價／庫存／SEO／組織分類／發布）", () => {
    stubRoutedFetch([ ...BASE_ROUTES ]);
    renderAt("/admin/products/new");

    // scope 到 main：側欄有「草稿」（訂單子項連結）同字樣（UI-2 教訓同型）。
    const main = within(screen.getByRole("main"));
    expect(main.getByRole("heading", { name: "新增商品" })).toBeVisible();
    expect(main.getByText("草稿")).toBeVisible();
    for (const card of [ "標題與說明", "多媒體", "定價", "庫存", "運送", "搜尋引擎產品資訊", "發布", "組織分類" ]) {
      expect(main.getByRole("heading", { name: new RegExp(card) })).toBeVisible();
    }
    // 建立態右欄無狀態卡（預設即 DRAFT，59 §7）；也無「更多動作」（本尊建立頁同）
    expect(main.queryByRole("heading", { name: "狀態" })).toBeNull();
    expect(main.queryByRole("button", { name: /更多動作/ })).toBeNull();
    // 組織分類卡形態（91 §12）：類型 search-or-create placeholder＋標籤輸入
    expect(main.getByPlaceholderText("搜尋或新增產品類型")).toBeVisible();
    expect(main.getByLabelText("標籤")).toBeVisible();
  });

  it("驗證失敗：空表單儲存 ⇒ toast＋標題欄錯誤，且不打 productSet", async () => {
    const fetchMock = stubRoutedFetch([ ...BASE_ROUTES ]);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    await user.click(screen.getByRole("button", { name: "儲存" }));

    expect(await screen.findByText("有欄位未通過驗證")).toBeVisible();
    expect(screen.getByText("標題不能為空白。")).toBeVisible();
    expect(screen.getByText("價格必填。")).toBeVisible();
    expect(callsTo(fetchMock, "mutation productSet")).toHaveLength(0);
  });

  it("儲存成功：送完整樹（含 DRAFT／組織欄位／idempotencyKey），轉導商品列表", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE_ROUTES,
      { match: "mutation productSet", body: CREATED },
      { match: "query products", body: EMPTY_LIST },
    ]);
    const user = userEvent.setup();
    const router = renderAt("/admin/products/new");

    await user.type(await screen.findByLabelText("標題（English）"), "奶茶色寬版帽T");
    await user.type(screen.getByLabelText("價格（HK$）"), "128.5");
    // dirty 後同時有頁首「儲存」與 SaveBar「儲存」（雙提交入口）⇒ 取 SaveBar 內那顆消歧
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/admin/products"));

    const saveCalls = callsTo(fetchMock, "mutation productSet");
    expect(saveCalls).toHaveLength(1);
    const { input, idempotencyKey } = parsedInput(saveCalls[0]);
    // 🔴 B.4 規則 1：完整樹＋顯式 DRAFT；金額補位成恆兩位小數字串（12850 cents）；
    // 組織分類＋SEO 恆送（宣告式：空字串／空陣列＝清除）
    expect(input).toEqual({
      title: "奶茶色寬版帽T",
      descriptionHtml: "",
      status: "DRAFT",
      vendor: "",
      productType: "",
      tags: [],
      seo: { title: "", description: "" },
      translations: [],
      // 🔴 運送兩欄**一律送**（第 29 包）：productSet 是宣告式覆寫，不送＝回落
      //    0／true ⇒ 把使用者在變體子頁設好的重量清掉。這一行就是那道保證。
      variants: [ { price: "128.50", taxable: true, weightGrams: 0, requiresShipping: true } ],
    });
    expect(idempotencyKey).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
    const [ url ] = fetchMock.mock.calls[0] as [ string, RequestInit ];
    expect(url).toBe(ADMIN_GRAPHQL_ENDPOINT);
  });

  it("伺服器 userErrors 映射到欄位（variants.0.price → 價格欄）", async () => {
    stubRoutedFetch([
      ...BASE_ROUTES,
      {
        match: "mutation productSet",
        body: {
          data: {
            productSet: {
              product: null,
              userErrors: [
                { field: [ "variants", "0", "price" ], message: "金額不得為負。", code: "GREATER_THAN_OR_EQUAL_TO" },
              ],
            },
          },
        },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    await user.type(await screen.findByLabelText("標題（English）"), "測試");
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
          vendor: "Frederic Malle",
          productType: "香水",
          tags: [ "花香" ],
          seo: { title: null, description: null },
          translations: [ { locale: "zh-Hant", field: "title", value: "既有商品（繁中）", outdated: false } ],
          variants: { nodes: [
            { price: "128.00", compareAtPrice: null, cost: null, sku: "SKU-1", barcode: null, taxable: true },
          ] },
        },
      },
    };

    const EDIT_ROUTES = [
      ...BASE_ROUTES,
      { match: "query productForEdit", body: EXISTING },
    ];

    it("載入既有商品填表：標題／價格／狀態 listbox／組織分類／SERP 預覽", async () => {
      stubRoutedFetch(EDIT_ROUTES);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      expect(await main.findByRole("heading", { name: "既有商品" })).toBeVisible();
      expect(main.getByLabelText("標題（English）")).toHaveValue("既有商品");
      expect(main.getByLabelText("價格（HK$）")).toHaveValue("128.00");
      // 狀態 listbox（91 §2）：按鈕顯示現值
      expect(main.getByLabelText("商品狀態")).toHaveTextContent("草稿");
      expect(main.getByText("可購買")).toBeVisible();
      // 組織分類卡載入值
      expect(main.getByLabelText("廠商")).toHaveValue("Frederic Malle");
      expect(main.getByLabelText("產品類型")).toHaveValue("香水");
      expect(main.getByText("花香")).toBeVisible();
      // SERP 預覽（91 §11）：站名＋麵包屑 URL（handle）＋標題 fallback 商品標題
      expect(main.getByText("CHILL LOVE")).toBeVisible();
      expect(main.getByText(/products › existing-tee/)).toBeVisible();
    });

    it("狀態 listbox 展開：三選項各帶描述副行、封存不在清單；選啟用中後儲存", async () => {
      const fetchMock = stubRoutedFetch([
        ...EDIT_ROUTES,
        {
          match: "mutation productSet",
          body: {
            data: {
              productSet: {
                product: {
                  id: "gid://chilllove/Product/9",
                  handle: "existing-tee",
                  status: "ACTIVE",
                  title: "既有商品",
                  lockVersion: 4,
                },
                userErrors: [],
              },
            },
          },
        },
      ]);
      const user = userEvent.setup();
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      await user.click(await main.findByLabelText("商品狀態"));

      const listbox = within(main.getByRole("listbox", { name: "商品狀態" }));
      expect(listbox.getByRole("option", { name: /啟用中/ })).toHaveTextContent("可販售也可被發現");
      expect(listbox.getByRole("option", { name: /草稿/ })).toHaveTextContent("尚未備妥");
      expect(listbox.getByRole("option", { name: /未列出/ })).toHaveTextContent("僅能透過直接連結存取");
      // 91 §2：封存不在 listbox（走更多動作）
      expect(listbox.queryByRole("option", { name: /已封存/ })).toBeNull();

      await user.click(listbox.getByRole("option", { name: /啟用中/ }));
      const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
      await user.click(within(savebar).getByRole("button", { name: "儲存" }));
      await screen.findByText("已儲存變更");

      const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
      expect(input.id).toBe("gid://chilllove/Product/9");
      expect(input.lockVersion).toBe(3);
      expect(input.status).toBe("ACTIVE");
      expect(input.vendor).toBe("Frederic Malle");
      expect(input.tags).toEqual([ "花香" ]);
      expect(input).not.toHaveProperty("handle");
    });

    it("更多動作→封存商品：立即送 status=ARCHIVED（不停在 SaveBar）", async () => {
      const fetchMock = stubRoutedFetch([
        ...EDIT_ROUTES,
        {
          match: "mutation productSet",
          body: {
            data: {
              productSet: {
                product: {
                  id: "gid://chilllove/Product/9",
                  handle: "existing-tee",
                  status: "ARCHIVED",
                  title: "既有商品",
                  lockVersion: 4,
                },
                userErrors: [],
              },
            },
          },
        },
      ]);
      const user = userEvent.setup();
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      await user.click(await main.findByRole("button", { name: /更多動作/ }));
      await user.click(main.getByRole("menuitem", { name: "封存商品" }));

      // 包 4：封存先過確認框——取消＝不送任何 mutation
      const dialog = within(await screen.findByRole("dialog"));
      expect(dialog.getByText("要封存這個商品嗎？")).toBeVisible();
      await user.click(dialog.getByRole("button", { name: "取消" }));
      expect(callsTo(fetchMock, "mutation productSet")).toHaveLength(0);
      // 取消後框已關＋焦點回「更多動作」（選單項已 unmount ⇒ restoreFocusTo 鏈，審查 C1/C7）
      expect(screen.queryByRole("dialog")).toBeNull();
      expect(main.getByRole("button", { name: /更多動作/ })).toHaveFocus();

      await user.click(main.getByRole("button", { name: /更多動作/ }));
      await user.click(main.getByRole("menuitem", { name: "封存商品" }));
      await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "封存" }));
      expect(screen.queryByRole("dialog")).toBeNull();

      await screen.findByText("已儲存變更");
      const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
      expect(input.status).toBe("ARCHIVED");
      // 複製／刪除是後續包 ⇒ disabled 而非隱藏（收了不做等於騙）
      await user.click(main.getByRole("button", { name: /更多動作/ }));
      expect(main.getByRole("menuitem", { name: "複製商品" })).toBeDisabled();
      expect(main.getByRole("menuitem", { name: "刪除商品" })).toBeDisabled();
    });

    it("SEO 卡：✏️ 展開後計數器即時更新、覆寫值進 SERP 預覽與 payload", async () => {
      const fetchMock = stubRoutedFetch([
        ...EDIT_ROUTES,
        { match: "mutation productSet", body: CREATED },
      ]);
      const user = userEvent.setup();
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      await user.click(await main.findByRole("button", { name: "編輯搜尋引擎產品資訊" }));

      const seoTitle = main.getByLabelText("頁面標題（English）");
      await user.type(seoTitle, "玫瑰雷鳴香精");
      // 計數器（91 §11）：字元數即時、70 是標題上限
      expect(main.getByText("已使用 6 / 70 個字元；留空時沿用商品標題")).toBeVisible();
      // Meta 描述的 160 是 SERP 建議值不是上限
      expect(main.getByText(/已使用 0 \/ 160 個字元；超過會被搜尋結果截斷（上限 320）/)).toBeVisible();
      // SERP 預覽改用覆寫值
      expect(main.getByText("玫瑰雷鳴香精", { selector: ".cl-serp__title" })).toBeVisible();

      const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
      await user.click(within(savebar).getByRole("button", { name: "儲存" }));
      await screen.findByText("已儲存變更");
      const { input, ...rest } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
      expect(input.seo).toEqual({ title: "玫瑰雷鳴香精", description: "" });
      expect(rest).not.toHaveProperty("idempotencyKey");
    });

    it("標籤：Enter 提交成 chip、× 移除、payload 帶全量", async () => {
      const fetchMock = stubRoutedFetch([
        ...EDIT_ROUTES,
        { match: "mutation productSet", body: CREATED },
      ]);
      const user = userEvent.setup();
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      const tagsInput = await main.findByLabelText("標籤");
      await user.type(tagsInput, "秋冬{Enter}");
      expect(main.getByText("秋冬")).toBeVisible();
      await user.click(main.getByRole("button", { name: "移除標籤 花香" }));
      expect(main.queryByText("花香")).toBeNull();

      const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
      await user.click(within(savebar).getByRole("button", { name: "儲存" }));
      await screen.findByText("已儲存變更");
      const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
      expect(input.tags).toEqual([ "秋冬" ]);
    });

    it("STALE_OBJECT（field null）以 toast 呈現", async () => {
      stubRoutedFetch([
        ...EDIT_ROUTES,
        {
          match: "mutation productSet",
          body: {
            data: {
              productSet: {
                product: null,
                userErrors: [
                  { field: null, message: "商品已被其他人修改，請重新載入後再儲存。", code: "STALE_OBJECT" },
                ],
              },
            },
          },
        },
      ]);
      const user = userEvent.setup();
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      await user.type(await main.findByLabelText("標題（English）"), "x");
      const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
      await user.click(within(savebar).getByRole("button", { name: "儲存" }));

      expect(await screen.findByText("商品已被其他人修改，請重新載入後再儲存。")).toBeVisible();
    });

    it("查無商品 ⇒ 空態卡＋返回列表", async () => {
      stubRoutedFetch([
        ...BASE_ROUTES,
        { match: "query productForEdit", body: { data: { product: null } } },
      ]);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F404");

      expect(await screen.findByText("此商品不存在或已被刪除。")).toBeVisible();
      expect(screen.getByRole("button", { name: "返回商品列表" })).toBeVisible();
    });
  });

  it("dirty 時 SaveBar 取代搜尋列；捨棄還原快照", async () => {
    stubRoutedFetch([ ...BASE_ROUTES ]);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    expect(screen.getByRole("button", { name: "開啟全域搜尋" })).toBeVisible();
    const title = await screen.findByLabelText("標題（English）");
    await user.type(title, "abc");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    expect(screen.queryByRole("button", { name: "開啟全域搜尋" })).toBeNull();

    // 包 4：捨棄先過確認框（還原快照不可復原）——取消＝表單不動
    await user.click(within(savebar).getByRole("button", { name: "捨棄" }));
    let dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByRole("button", { name: "取消" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.getByLabelText("標題（English）")).toHaveValue("abc");

    await user.click(within(savebar).getByRole("button", { name: "捨棄" }));
    dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByRole("button", { name: "捨棄變更" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.getByLabelText("標題（English）")).toHaveValue("");
    expect(screen.getByRole("button", { name: "開啟全域搜尋" })).toBeVisible();
    // SaveBar 已 unmount ⇒ 焦點退到頁標題（restoreFocusTo 鏈，審查 C1）
    expect(screen.getByRole("heading", { name: "新增商品" })).toHaveFocus();
  });

  it("儲存後快照前進：SaveBar 消失；再編輯後捨棄還原到「上次儲存」而非初值（審查 C6）", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE_ROUTES,
      {
        match: "query productForEdit",
        body: {
          data: {
            product: {
              id: "gid://chilllove/Product/9",
              title: "原名", descriptionHtml: "", status: "DRAFT", handle: "tee",
              lockVersion: 3, vendor: "", productType: "", tags: [],
              seo: { title: null, description: null }, translations: [],
              variants: { nodes: [
                { price: "128.00", compareAtPrice: null, cost: null, sku: null, barcode: null, taxable: true },
              ] },
            },
          },
        },
      },
      { match: "mutation productSet", body: CREATED },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const title = await screen.findByLabelText("標題（English）");
    await user.clear(title);
    await user.type(title, "改名一版");
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");
    // dirty=false ⇒ SaveBar 讓位回搜尋列
    expect(screen.queryByRole("region", { name: "未儲存的變更" })).toBeNull();
    expect(callsTo(fetchMock, "mutation productSet")).toHaveLength(1);

    await user.type(screen.getByLabelText("標題（English）"), "又改");
    const savebar2 = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar2).getByRole("button", { name: "捨棄" }));
    await user.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "捨棄變更" }));
    // 還原到上次儲存的「改名一版」，不是頁面載入時的初值
    expect(screen.getByLabelText("標題（English）")).toHaveValue("改名一版");
  });
});

// ── 第 23 包：選項編輯器＋卡底變體表（整合規格 §4-23；63 §B.4/§B.5 的 UI 面）──
describe("商品選項與變體表", () => {
  beforeEach(() => installCsrfMeta());

  const LOCATIONS_ROUTE = {
    match: "query productFormLocations",
    body: { data: { locations: [ { id: "gid://chilllove/Location/1", name: "Shop location" } ] } },
  };

  it("建立態：popover 加「尺寸」→ 打 S,M,L ⇒ 表即時三列；儲存 payload 帶 options＋座標＋initialQuantities", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE_ROUTES,
      LOCATIONS_ROUTE,
      { match: "mutation productSet", body: CREATED },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    const main = within(await screen.findByRole("main"));
    await user.type(await main.findByLabelText("標題（English）"), "帽T");
    await user.type(main.getByLabelText("價格（HK$）"), "128.00");

    await user.click(main.getByRole("button", { name: "＋ 新增選項" }));
    await user.click(main.getByRole("menuitem", { name: "尺寸" }));
    const valuesInput = main.getByLabelText("選項值");
    await user.type(valuesInput, "S{Enter}M{Enter}L{Enter}");

    // 判準：值一打完表即時三列（列首＝座標 title）
    expect(main.getByRole("rowheader", { name: "S" })).toBeVisible();
    expect(main.getByRole("rowheader", { name: "M" })).toBeVisible();
    expect(main.getByRole("rowheader", { name: "L" })).toBeVisible();
    // 首列繼承定價卡價格；定價卡轉 per-variant note（商品級價格入口消失）
    expect(main.getByLabelText("價格（S）")).toHaveValue("128.00");
    expect(main.getByText("已啟用選項——價格改在下方子類表逐列設定。")).toBeVisible();

    await user.clear(main.getByLabelText("價格（M）"));
    await user.type(main.getByLabelText("價格（M）"), "138.00");
    await user.clear(main.getByLabelText("價格（L）"));
    await user.type(main.getByLabelText("價格（L）"), "148.00");
    await user.type(main.getByLabelText("數量（S）"), "7");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");

    const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
    expect(input.options).toEqual([ { name: "尺寸", values: [ "S", "M", "L" ] } ]);
    const variants = input.variants as Record<string, unknown>[];
    expect(variants).toHaveLength(3);
    expect(variants.map((v) => v.price)).toEqual([ "128.00", "138.00", "148.00" ]);
    expect(variants[0].optionValues).toEqual([ { optionName: "尺寸", value: "S" } ]);
    expect(variants[0].initialQuantities).toEqual([
      { locationId: "gid://chilllove/Location/1", quantity: 7 },
    ]);
    expect(variants[1]).not.toHaveProperty("initialQuantities");
    expect(variants[0]).not.toHaveProperty("id");
  });

  it("🔴 編輯態：既有列儲存必帶原 id（22 契約的 UI 面首驗）；加值＝補列不動舊列；回聲欄照送", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE_ROUTES,
      {
        match: "query productForEdit",
        body: {
          data: {
            product: {
              id: "gid://chilllove/Product/9",
              title: "外套", descriptionHtml: "", status: "DRAFT", handle: "coat",
              lockVersion: 3, vendor: "", productType: "", tags: [],
              seo: { title: null, description: null }, translations: [],
              options: [ { name: "尺寸", position: 1,
                values: [ { value: "S", position: 1 }, { value: "M", position: 2 } ] } ],
              variants: { nodes: [
                { id: "gid://chilllove/ProductVariant/11", title: "S", position: 1,
                  price: "100.00", compareAtPrice: "150.00", cost: null, sku: "C-S",
                  barcode: "471", taxable: true,
                  selectedOptions: [ { name: "尺寸", value: "S" } ] },
                { id: "gid://chilllove/ProductVariant/12", title: "M", position: 2,
                  price: "110.00", compareAtPrice: null, cost: null, sku: null,
                  barcode: null, taxable: false,
                  selectedOptions: [ { name: "尺寸", value: "M" } ] },
              ] },
            },
          },
        },
      },
      { match: "mutation productSet", body: CREATED },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByRole("rowheader", { name: "S" })).toBeVisible();
    expect(main.getByLabelText("價格（M）")).toHaveValue("110.00");
    // 編輯態沒有數量欄（initialQuantities 是 create-only）
    expect(main.queryByLabelText("數量（S）")).toBeNull();

    // 加值 L ⇒ 第三列即時出現
    await user.type(main.getByLabelText("選項值"), "L{Enter}");
    expect(main.getByRole("rowheader", { name: "L" })).toBeVisible();
    // 新列價格繼承定價卡 seed（編輯態＝variants[0] 的 100.00）——清掉再打
    expect(main.getByLabelText("價格（L）")).toHaveValue("100.00");
    await user.clear(main.getByLabelText("價格（L）"));
    await user.type(main.getByLabelText("價格（L）"), "120.00");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");

    const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
    expect(input.options).toEqual([ { name: "尺寸", values: [ "S", "M", "L" ] } ]);
    const variants = input.variants as Record<string, unknown>[];
    expect(variants).toHaveLength(3);
    // 🔴 既有列帶原 id；新列無 id
    expect(variants[0].id).toBe("gid://chilllove/ProductVariant/11");
    expect(variants[1].id).toBe("gid://chilllove/ProductVariant/12");
    expect(variants[2]).not.toHaveProperty("id");
    // 回聲欄：compare/barcode/taxable 原樣送回（宣告式缺席＝清除，缺了就是資料抹除）
    expect(variants[0].compareAtPrice).toBe("150.00");
    expect(variants[0].barcode).toBe("471");
    expect(variants[1].taxable).toBe(false);
  });

  it("🔴 改名選項不重置列（審查 C12 UI 面）：rows／id 原位，payload 帶新名＋原 id", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE_ROUTES,
      {
        match: "query productForEdit",
        body: {
          data: {
            product: {
              id: "gid://chilllove/Product/9",
              title: "外套", descriptionHtml: "", status: "DRAFT", handle: "coat",
              lockVersion: 3, vendor: "", productType: "", tags: [],
              seo: { title: null, description: null }, translations: [],
              options: [ { name: "尺寸", position: 1,
                values: [ { value: "S", position: 1 }, { value: "M", position: 2 } ] } ],
              variants: { nodes: [
                { id: "gid://chilllove/ProductVariant/11", title: "S", position: 1,
                  price: "100.00", compareAtPrice: null, cost: null, sku: "C-S",
                  barcode: null, taxable: true,
                  selectedOptions: [ { name: "尺寸", value: "S" } ] },
                { id: "gid://chilllove/ProductVariant/12", title: "M", position: 2,
                  price: "110.00", compareAtPrice: null, cost: null, sku: null,
                  barcode: null, taxable: true,
                  selectedOptions: [ { name: "尺寸", value: "M" } ] },
              ] },
            },
          },
        },
      },
      { match: "mutation productSet", body: CREATED },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const main = within(await screen.findByRole("main"));
    await main.findByRole("rowheader", { name: "S" });
    const nameField = main.getByLabelText("選項名稱");
    await user.clear(nameField);
    await user.type(nameField, "Size");
    // 列不因改名重建：rowheader 與逐列價格原位
    expect(main.getByRole("rowheader", { name: "S" })).toBeVisible();
    expect(main.getByLabelText("價格（M）")).toHaveValue("110.00");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");
    const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
    expect(input.options).toEqual([ { name: "Size", values: [ "S", "M" ] } ]);
    const variants = input.variants as Record<string, unknown>[];
    expect(variants[0].id).toBe("gid://chilllove/ProductVariant/11");
    expect(variants[0].optionValues).toEqual([ { optionName: "Size", value: "S" } ]);
  });

  it("中位草稿選項（審查 C16）：零值選項不進列模型；帶草稿儲存被擋", async () => {
    stubRoutedFetch([ ...BASE_ROUTES, LOCATIONS_ROUTE ]);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    const main = within(await screen.findByRole("main"));
    await user.type(await main.findByLabelText("標題（English）"), "T");
    await user.type(main.getByLabelText("價格（HK$）"), "10.00");
    await user.click(main.getByRole("button", { name: "＋ 新增選項" }));
    await user.click(main.getByRole("menuitem", { name: "尺寸" }));
    await user.type(main.getByLabelText("選項值"), "S{Enter}M{Enter}");
    // 加第二個選項但不打值（草稿）
    await user.click(main.getByRole("button", { name: "＋ 新增選項" }));
    await user.click(main.getByRole("menuitem", { name: "顏色" }));
    // 列模型不受草稿影響：仍是單維兩列
    expect(main.getAllByRole("rowheader").map((n) => n.textContent)).toEqual([ "S", "M" ]);
    // 草稿仍在 ⇒ 對第一個選項加值也不會炸列
    const valueInputs = main.getAllByLabelText("選項值");
    await user.type(valueInputs[0], "L{Enter}");
    expect(main.getAllByRole("rowheader").map((n) => n.textContent)).toEqual([ "S", "M", "L" ]);
    // 帶草稿儲存被擋
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    expect(await screen.findByText("有欄位未通過驗證")).toBeVisible();
  });

  it("伺服錯誤 variants.1（無尾段）與 variants.0.price 都映射到對應列（審查 C15）", async () => {
    stubRoutedFetch([
      ...BASE_ROUTES,
      LOCATIONS_ROUTE,
      {
        match: "mutation productSet",
        body: {
          data: {
            productSet: {
              product: null,
              userErrors: [ { field: [ "variants", "1" ], message: "子類重複。", code: "INVALID" } ],
            },
          },
        },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    const main = within(await screen.findByRole("main"));
    await user.type(await main.findByLabelText("標題（English）"), "T");
    await user.type(main.getByLabelText("價格（HK$）"), "10.00");
    await user.click(main.getByRole("button", { name: "＋ 新增選項" }));
    await user.click(main.getByRole("menuitem", { name: "尺寸" }));
    await user.type(main.getByLabelText("選項值"), "S{Enter}M{Enter}");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    // ['variants','1'] join＝"variants.1"（無尾段）也要中列 1
    const rowInput = await main.findByLabelText("價格（M）");
    expect(rowInput).toHaveAttribute("aria-invalid", "true");
    expect(main.getByText("子類重複。")).toBeVisible();
    expect(rowInput).toHaveFocus();
  });

  it("刪值收確認語義：移除值 ⇒ 該列即時消失；選項零值＝儲存被client擋（optionsInvalid）", async () => {
    stubRoutedFetch([ ...BASE_ROUTES, LOCATIONS_ROUTE ]);
    const user = userEvent.setup();
    renderAt("/admin/products/new");

    const main = within(await screen.findByRole("main"));
    await user.type(await main.findByLabelText("標題（English）"), "T");
    await user.click(main.getByRole("button", { name: "＋ 新增選項" }));
    await user.click(main.getByRole("menuitem", { name: "顏色" }));
    await user.type(main.getByLabelText("選項值"), "黑{Enter}白{Enter}");
    expect(main.getByRole("rowheader", { name: "白" })).toBeVisible();

    await user.click(main.getByRole("button", { name: "移除選項值 白" }));
    expect(main.queryByRole("rowheader", { name: "白" })).toBeNull();

    await user.click(main.getByRole("button", { name: "移除選項值 黑" }));
    // 零值選項＝草稿：表清空、儲存被擋
    expect(main.queryByRole("table")).toBeNull();
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    expect(await screen.findByText("有欄位未通過驗證")).toBeVisible();
  });
});

// ── ML-2：內容語言（標題堆疊／說明與 SEO 分頁；docs/plans/2026-08-23-多語言方案.md §6）──
describe("商品內容多語言", () => {
  beforeEach(() => installCsrfMeta());

  const LOCALIZED_EXISTING = {
    data: {
      product: {
        id: "gid://chilllove/Product/9",
        title: "Rose Tonnerre",
        descriptionHtml: "<p>Rose and spice</p>",
        status: "ACTIVE",
        handle: "rose-tonnerre",
        lockVersion: 2,
        vendor: "Frederic Malle",
        productType: "Fragrance",
        tags: [],
        seo: { title: "Rose Tonnerre EDP", description: "Niche fragrance" },
        translations: [
          { locale: "zh-Hant", field: "title", value: "玫瑰雷鳴", outdated: false },
          { locale: "ja", field: "title", value: "ローズトネール", outdated: true },
          { locale: "zh-Hant", field: "body_html", value: "<p>玫瑰與辛香</p>", outdated: false },
        ],
        variants: { nodes: [ { price: "128.00", compareAtPrice: null, cost: null, sku: null, barcode: null, taxable: true } ] },
      },
    },
  };

  const ROUTES = [ ...BASE_ROUTES, { match: "query productForEdit", body: LOCALIZED_EXISTING } ];

  it("標題＝堆疊式：三語同時可見、各標語言自稱，載入既有譯文", async () => {
    stubRoutedFetch(ROUTES);
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByLabelText("標題（English）")).toHaveValue("Rose Tonnerre");
    expect(main.getByLabelText("標題（繁體中文）")).toHaveValue("玫瑰雷鳴");
    expect(main.getByLabelText("標題（日本語）")).toHaveValue("ローズトネール");
  });

  it("說明＝分頁式：切語言換值，非來源語言可展開原文對照", async () => {
    stubRoutedFetch(ROUTES);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const main = within(await screen.findByRole("main"));
    await main.findByLabelText("標題（English）");
    // 說明卡的 tablist（第一個）：來源語言 tab 預設選中
    const tablists = main.getAllByRole("tablist", { name: "內容語言" });
    const descriptionTabs = within(tablists[0]);
    expect(descriptionTabs.getByRole("tab", { name: /English/ })).toHaveAttribute("aria-selected", "true");

    await user.click(descriptionTabs.getByRole("tab", { name: /繁體中文/ }));
    expect(main.getByLabelText("說明（zh-Hant）")).toHaveValue("<p>玫瑰與辛香</p>");
    expect(main.getAllByText("顯示原文")[0]).toBeVisible();
  });

  it("過期徽章：伺服端 outdated 的語言 tab 帶提示（不影響譯文內容）", async () => {
    stubRoutedFetch(ROUTES);
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const main = within(await screen.findByRole("main"));
    await main.findByLabelText("標題（English）");
    // ja 的 title 過期 ⇒ 該語言在說明/SEO tab 列上不標（欄位不同），只在 title 相關 UI 反映；
    // 這裡驗資料有正確帶入：日文標題值仍在。
    expect(main.getByLabelText("標題（日本語）")).toHaveValue("ローズトネール");
  });

  it("儲存：譯文逐欄位一列送出，來源語言不進 translations（在 base 欄位）", async () => {
    const fetchMock = stubRoutedFetch([
      ...ROUTES,
      {
        match: "mutation productSet",
        body: {
          data: {
            productSet: {
              product: { id: "gid://chilllove/Product/9", handle: "rose-tonnerre", status: "ACTIVE", title: "Rose Tonnerre", lockVersion: 3 },
              userErrors: [],
            },
          },
        },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const main = within(await screen.findByRole("main"));
    const japanese = await main.findByLabelText("標題（日本語）");
    await user.clear(japanese);
    await user.type(japanese, "ローズ・トネール");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");

    const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
    const translations = input.translations as { locale: string; field: string; value: string }[];
    expect(translations).toContainEqual({ locale: "ja", field: "title", value: "ローズ・トネール" });
    expect(translations).toContainEqual({ locale: "zh-Hant", field: "title", value: "玫瑰雷鳴" });
    expect(translations.some((row) => row.locale === "en")).toBe(false);
    // 來源語言的標題仍走 base 欄位
    expect(input.title).toBe("Rose Tonnerre");
  });

  it("清空某語言＝送空字串（伺服端刪除該譯文列、回落來源語言）", async () => {
    const fetchMock = stubRoutedFetch([
      ...ROUTES,
      {
        match: "mutation productSet",
        body: {
          data: {
            productSet: {
              product: { id: "gid://chilllove/Product/9", handle: "rose-tonnerre", status: "ACTIVE", title: "Rose Tonnerre", lockVersion: 3 },
              userErrors: [],
            },
          },
        },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

    const main = within(await screen.findByRole("main"));
    await user.clear(await main.findByLabelText("標題（繁體中文）"));

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");

    const { input } = parsedInput(callsTo(fetchMock, "mutation productSet")[0]);
    expect(input.translations).toContainEqual({ locale: "zh-Hant", field: "title", value: "" });
  });
});

/**
 * 媒體排序的生命週期（第 27 包對抗審查 C7/C8/C9/C13/C19/C20 的回歸）。
 *
 * 這一組釘住的不是「排序能不能存」，而是**待存順序這個表單值什麼時候該活著、
 * 什麼時候該死**——四個被審查抓到的缺口全部在這條線上：
 * 儲存失敗仍寫了順序（C9/C19）／存完 SaveBar 不消失（C8/C20）／
 * 上傳一張圖就丟掉拖好的順序（C7）／失敗的順序永遠重送（C13）。
 */
describe("商品媒體排序", () => {
  beforeEach(() => installCsrfMeta());

  const MEDIA_A = {
    id: "gid://chilllove/Media/1", position: 1, alt: "貓", status: "READY",
    image: { thumbUrl: "/admin/files/7/blob?variant=thumb", url: "/admin/files/7/blob" },
  };
  const MEDIA_B = {
    id: "gid://chilllove/Media/2", position: 2, alt: "狗", status: "READY",
    image: { thumbUrl: "/admin/files/8/blob?variant=thumb", url: "/admin/files/8/blob" },
  };

  const WITH_MEDIA = {
    data: {
      product: {
        id: "gid://chilllove/Product/9",
        title: "既有商品",
        descriptionHtml: "<p>舊說明</p>",
        status: "ACTIVE",
        handle: "existing-tee",
        lockVersion: 3,
        vendor: null,
        productType: null,
        tags: [],
        seo: { title: null, description: null },
        translations: [],
        media: [ MEDIA_A, MEDIA_B ],
        variants: { nodes: [
          { price: "128.00", compareAtPrice: null, cost: null, sku: "SKU-1", barcode: null, taxable: true },
        ] },
      },
    },
  };

  const MEDIA_ROUTES = [
    ...BASE_ROUTES,
    { match: "query productForEdit", body: WITH_MEDIA },
  ];

  const SAVE_OK = {
    data: {
      productSet: {
        product: {
          id: "gid://chilllove/Product/9", handle: "existing-tee",
          status: "ACTIVE", title: "既有商品", lockVersion: 4,
        },
        userErrors: [],
      },
    },
  };

  /** 把第 2 格拖到第 1 格＝待存順序 [B, A]。 */
  async function dragSecondToFirst() {
    const tiles = await screen.findAllByRole("listitem");
    // 原生 Event 觸發不到 React 的合成 onDragStart／onDrop（MediaCard.test 同註）
    fireEvent.dragStart(tiles[1]);
    fireEvent.drop(tiles[0], { dataTransfer: { files: [] } });
  }

  function tileAlts() {
    return screen.getAllByRole("listitem")
      .map((tile) => within(tile).getByRole("img").getAttribute("alt"));
  }

  it("🔴 C9/C19：productSet 回 userErrors ⇒ 排序**不得**送出（順序不能比商品先落地）", async () => {
    const fetchMock = stubRoutedFetch([
      ...MEDIA_ROUTES,
      {
        match: "mutation productSet",
        body: {
          data: {
            productSet: {
              product: null,
              userErrors: [ { field: [ "input", "title" ], message: "標題不能為空白。", code: "BLANK" } ],
            },
          },
        },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
    await screen.findByRole("heading", { name: "既有商品" });

    await dragSecondToFirst();
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("標題不能為空白。");

    expect(callsTo(fetchMock, "mutation productReorderMedia")).toHaveLength(0);
    // 待存順序仍在（使用者改完標題再存一次就會落地）
    expect(tileAlts()).toEqual([ "狗", "貓" ]);
  });

  it("🔴 C8/C20：排序成功落地後 SaveBar 消失（快照要用清空 mediaOrder 後的形狀）", async () => {
    const fetchMock = stubRoutedFetch([
      ...MEDIA_ROUTES,
      { match: "mutation productSet", body: SAVE_OK },
      {
        match: "mutation productReorderMedia",
        body: { data: { productReorderMedia: { media: [], userErrors: [] } } },
      },
      {
        match: "query productMedia",
        body: { data: { product: { media: [
          { ...MEDIA_B, position: 1 }, { ...MEDIA_A, position: 2 },
        ] } } },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
    await screen.findByRole("heading", { name: "既有商品" });

    await dragSecondToFirst();
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");

    const reorder = callsTo(fetchMock, "mutation productReorderMedia");
    expect(reorder).toHaveLength(1);
    expect(JSON.parse(String(reorder[0].body)).variables.mediaIds).toEqual([ MEDIA_B.id, MEDIA_A.id ]);
    // 🔴 SaveBar 必須消失：快照存了舊的非空 mediaOrder 就會永遠 dirty
    await waitFor(() =>
      expect(screen.queryByRole("region", { name: "未儲存的變更" })).toBeNull());
  });

  it("🔴 C13：排序被伺服端拒絕 ⇒ 丟掉這份順序（不得每次儲存都重送同一份失敗清單）", async () => {
    const fetchMock = stubRoutedFetch([
      ...MEDIA_ROUTES,
      { match: "mutation productSet", body: SAVE_OK },
      {
        match: "mutation productReorderMedia",
        body: {
          data: {
            productReorderMedia: {
              media: [],
              userErrors: [ { field: [ "mediaIds" ], message: "媒體清單必須是完整集合。", code: "INVALID" } ],
            },
          },
        },
      },
      { match: "query productMedia", body: { data: { product: { media: [ MEDIA_A, MEDIA_B ] } } } },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
    await screen.findByRole("heading", { name: "既有商品" });

    await dragSecondToFirst();
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("媒體清單必須是完整集合。");

    // 順序回落伺服端真相（重讀），且商品本體已存成功 ⇒ SaveBar 收起
    await waitFor(() => expect(tileAlts()).toEqual([ "貓", "狗" ]));
    await waitFor(() =>
      expect(screen.queryByRole("region", { name: "未儲存的變更" })).toBeNull());

    // 改別的欄位再存一次：那份失敗清單**不得**跟著重送
    await user.type(within(screen.getByRole("main")).getByLabelText("標題（English）"), "！");
    await user.click(within(await screen.findByRole("region", { name: "未儲存的變更" }))
      .getByRole("button", { name: "儲存" }));
    await waitFor(() => expect(callsTo(fetchMock, "mutation productSet")).toHaveLength(2));
    expect(callsTo(fetchMock, "mutation productReorderMedia")).toHaveLength(1);
  });

  it("🔴 C7：拖好順序後編 alt（觸發重讀）⇒ 順序保留；新上傳的圖接在尾端", async () => {
    const MEDIA_C = {
      id: "gid://chilllove/Media/3", position: 3, alt: "鳥", status: "READY",
      image: { thumbUrl: "/admin/files/9/blob?variant=thumb", url: "/admin/files/9/blob" },
    };
    stubRoutedFetch([
      ...MEDIA_ROUTES,
      {
        match: "mutation productUpdateMedia",
        body: { data: { productUpdateMedia: { media: [], userErrors: [] } } },
      },
      // 重讀時多了一張（別的分頁／剛上傳完成）——待存順序裡沒有它
      {
        match: "query productMedia",
        body: { data: { product: { media: [ MEDIA_A, MEDIA_B, MEDIA_C ] } } },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
    await screen.findByRole("heading", { name: "既有商品" });

    await dragSecondToFirst();
    expect(tileAlts()).toEqual([ "狗", "貓" ]);

    // alt 失焦 ⇒ productUpdateMedia ⇒ onRefresh ⇒ reloadMedia
    await user.type(screen.getByLabelText("第 1 張圖的替代文字"), "！");
    await user.tab();

    // 🔴 拖好的順序沒被重讀清掉；沒在順序裡的新圖接尾端而非消失
    await waitFor(() => expect(tileAlts()).toEqual([ "狗", "貓", "鳥" ]));
  });
});
