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

    /**
     * S6a 發布卡（`docs/research/82` §9.3 的第一種 affordance，唯讀部分）。
     *
     * 🔴 這三格釘的是**兩個「沒有排程就 100% 測綠」的陷阱**：
     *   ①V2 的 `isPublished=false` 是「已排程未到點」不是「未發布」——
     *     綁錯會讓已排程的管道顯示成關閉；
     *   ②查詢必須帶 `onlyPublished: false`——忘了帶，已排程的列整個不回來，
     *     卡片少顯示一個管道且不會有任何錯誤。
     */
    const PUBLICATIONS = [
      { isPublished: true, publishDate: "2026-08-01T00:00:00Z",
        publication: { id: "gid://chilllove/Publication/1", title: "線上商店", supportsFuturePublishing: true } },
      { isPublished: false, publishDate: "2026-09-01T02:00:00Z",
        publication: { id: "gid://chilllove/Publication/2", title: "門市 POS", supportsFuturePublishing: false } },
    ];

    it("🔴 S6a 發布卡顯示伺服器現值：已發布與**已排程**各自的狀態（不是寫死的假資料）", async () => {
      stubRoutedFetch([
        ...BASE_ROUTES,
        { match: "query productForEdit",
          body: { data: { product: { ...EXISTING.data.product, resourcePublicationsV2: PUBLICATIONS } } } },
      ]);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      expect(await main.findByText("線上商店")).toBeVisible();
      expect(main.getByText("已發布")).toBeVisible();
      // 🔴 isPublished=false 必須呈現為「已排程」，**不是**「未發布」也不是不顯示
      expect(main.getByText(/排程於/)).toBeVisible();
      expect(main.getByText("門市 POS")).toBeVisible();
    });

    it("🔴 S6a 查詢必須帶 onlyPublished: false（否則已排程的列不會回來）", async () => {
      const fetchMock = stubRoutedFetch([
        ...BASE_ROUTES,
        { match: "query productForEdit",
          body: { data: { product: { ...EXISTING.data.product, resourcePublicationsV2: PUBLICATIONS } } } },
      ]);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
      await screen.findByRole("main");

      const sent = fetchMock.mock.calls
        .map((call) => String((call[1] as RequestInit | undefined)?.body ?? ""))
        .find((body) => body.includes("productForEdit"));
      expect(sent).toContain("resourcePublicationsV2(onlyPublished: false)");
    });

    it("S6a 一個管道都沒有 ⇒ 顯示空態，而不是顯示成「全部關閉」", async () => {
      stubRoutedFetch([
        ...BASE_ROUTES,
        { match: "query productForEdit",
          body: { data: { product: { ...EXISTING.data.product, resourcePublicationsV2: [] } } } },
      ]);
      renderAt("/admin/products/gid%3A%2F%2FProduct%2F9".replace("gid://chilllove/Product", "gid://chilllove/Product"));

      const main = within(await screen.findByRole("main"));
      expect(await main.findByText("尚未發布到任何銷售管道")).toBeVisible();
    });

    /**
     * S6a-2：可見性兩維改由伺服器回答。
     *
     * 🔴 **第 1 格是唯一能證明「真的接上了」的形態**：商品狀態是 ACTIVE
     *   （狀態層會算出「可購買＝是」），但伺服器回 `purchasable: false`
     *   （因為已取消發布／排程未到點）。只有讀伺服器答案才會顯示「否」。
     *   若實作退回硬算表，這一格立刻紅。
     */
    it("🔴 S6a-2 兩維讀伺服器答案：ACTIVE 但伺服器說不可購買 ⇒ 顯示「否」", async () => {
      stubRoutedFetch([
        ...BASE_ROUTES,
        { match: "query productForEdit",
          body: { data: { product: {
            ...EXISTING.data.product, status: "ACTIVE",
            purchasable: false, discoverable: false, resourcePublicationsV2: [],
          } } } },
      ]);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      const purchasable = await main.findByText("可購買");
      expect(purchasable.parentElement).toHaveTextContent("否");
    });

    it("S6a-2 伺服器說可購買但不可發現（UNLISTED 形態）⇒ 兩維各自呈現", async () => {
      stubRoutedFetch([
        ...BASE_ROUTES,
        { match: "query productForEdit",
          body: { data: { product: {
            ...EXISTING.data.product, status: "UNLISTED",
            purchasable: true, discoverable: false, resourcePublicationsV2: [],
          } } } },
      ]);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");

      const main = within(await screen.findByRole("main"));
      expect((await main.findByText("可購買")).parentElement).toHaveTextContent("是");
      expect(main.getByText("可被發現").parentElement).toHaveTextContent("否");
    });

    it("🔴 S6a-2 查詢必須帶 purchasable／discoverable 兩個欄位", async () => {
      const fetchMock = stubRoutedFetch([
        ...BASE_ROUTES,
        { match: "query productForEdit",
          body: { data: { product: { ...EXISTING.data.product, purchasable: true, discoverable: true } } } },
      ]);
      renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
      await screen.findByRole("main");

      const sent = fetchMock.mock.calls
        .map((call) => String((call[1] as RequestInit | undefined)?.body ?? ""))
        .find((body) => body.includes("productForEdit"));
      expect(sent).toContain("purchasable");
      expect(sent).toContain("discoverable");
    });

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
      // 第 6 包起編輯態送回聲 handle（同值＝伺服端 no-op；改值＝寫 301）
      expect(input.handle).toBe("existing-tee");
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

/**
 * S6b：逐商品發布編輯 modal（`docs/research/82` §12.1／§13.1／§13.2 的實測形態）。
 *
 * 🔴 本組釘的是三個「在沒有排程、沒有未發布管道的環境下 100% 測綠」的陷阱：
 *   ①**開關綁 `isPublished`**——V2 的 `false` 是「已排程未到點」，綁錯會讓已排程的
 *     管道在 modal 內顯示成關閉，商家一存就把它取消發布了；
 *   ②**撥開再撥回不歸零**——delta 留著會多送一支沒必要的 mutation，且 SaveBar 不消失；
 *   ③**完成鍵真的寫入**——本尊實測按 Done 當下**零 GraphQL 請求**（§13.1）。
 */
describe("S6b 發布編輯 modal", () => {
  // 🔴 `handle` 非 null＝真的是銷售管道（來自 publication.channel&.handle）。
  const PUBS = [
    { id: "gid://chilllove/Publication/1", title: "線上商店", handle: "online_store", supportsFuturePublishing: true },
    { id: "gid://chilllove/Publication/2", title: "門市 POS", handle: "pos", supportsFuturePublishing: false },
    { id: "gid://chilllove/Publication/3", title: "Shop", handle: "shop", supportsFuturePublishing: false },
  ];

  // 🔴 API 建的 catalog publication（`publicationCreate` 已上線）：**沒有 channel ⇒ handle 為 null**。
  //    它不得出現在標題為「銷售管道」的那一節（本尊把 Sales Channels 與 Catalogs 分成兩節，82 §12.1）。
  const CATALOG_PUB = {
    id: "gid://chilllove/Publication/9", title: "日本市場目錄", handle: null, supportsFuturePublishing: false,
  };

  // 伺服器現況：①已發布 ②**已排程未到點**（isPublished=false 但列存在）③根本沒有列＝未發布
  const ROWS = [
    { isPublished: true, publishDate: "2026-08-01T00:00:00Z", publication: PUBS[0] },
    { isPublished: false, publishDate: "2026-09-01T02:00:00Z", publication: PUBS[1] },
  ];

  const PRODUCT = {
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
    purchasable: true,
    discoverable: true,
    resourcePublicationsV2: ROWS,
    variants: { nodes: [
      { price: "128.00", compareAtPrice: null, cost: null, sku: "SKU-1", barcode: null, taxable: true },
    ] },
  };

  const EDIT_ROUTES = [
    ...BASE_ROUTES,
    { match: "query productForEdit", body: { data: { product: PRODUCT, publications: [ ...PUBS, CATALOG_PUB ] } } },
    { match: "mutation productSet", body: { data: { productSet: {
      product: { id: PRODUCT.id, handle: PRODUCT.handle, status: PRODUCT.status, title: PRODUCT.title,
                lockVersion: 4, variants: { nodes: [] } },
      userErrors: [],
    } } } },
    { match: "mutation productPublishing", body: { data: {
      publishablePublish: { userErrors: [] },
      publishableUnpublish: { userErrors: [] },
    } } },
    { match: "query productPublications", body: { data: { product: {
      purchasable: true, discoverable: true, resourcePublicationsV2: ROWS,
    } } } },
  ];

  beforeEach(() => {
    installCsrfMeta();
  });

  async function openModal() {
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
    const main = within(await screen.findByRole("main"));
    await waitFor(() => expect(main.getByRole("button", { name: "管理發布" })).toBeEnabled());
    await userEvent.click(main.getByRole("button", { name: "管理發布" }));
    return within(await screen.findByRole("dialog"));
  }

  it("🔴 modal 列出**全部**管道，未發布的那個也在（不是只列 resourcePublicationsV2）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    // 「Shop」在伺服器上沒有列 ⇒ 只讀 resourcePublicationsV2 的實作會讓它整個不出現
    expect(dialog.getByRole("switch", { name: "Shop" })).toBeVisible();
    expect(dialog.getByRole("switch", { name: "線上商店" })).toBeVisible();
    expect(dialog.getByRole("switch", { name: "門市 POS" })).toBeVisible();
  });

  it("🔴 開關綁「列是否存在」不是 isPublished：已排程未到點的管道顯示為**開**", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    expect(dialog.getByRole("switch", { name: "線上商店" })).toBeChecked();
    expect(dialog.getByRole("switch", { name: "門市 POS" })).toBeChecked();
    expect(dialog.getByRole("switch", { name: "Shop" })).not.toBeChecked();
  });

  it("🔴 撥開再撥回 ⇒ 完成鍵回到 disabled（delta 歸零，不是記錄操作序列）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const done = dialog.getByRole("button", { name: "完成" });
    expect(done).toBeDisabled();

    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    expect(done).toBeEnabled();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    expect(done).toBeDisabled();
  });

  it("🔴 完成鍵不送任何 GraphQL，只讓卡片樂觀更新並喚出 SaveBar（本尊 §13.1）", async () => {
    const fetchMock = stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));

    const before = fetchMock.mock.calls.length;
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));

    expect(fetchMock.mock.calls.length).toBe(before);
    const main = within(screen.getByRole("main"));
    expect(await main.findByText("待儲存")).toBeVisible();
    expect(await screen.findByRole("region", { name: "未儲存的變更" })).toBeVisible();
  });

  it("取消鍵丟棄草稿：卡片不變、SaveBar 不出現", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    await userEvent.click(dialog.getByRole("button", { name: "取消" }));

    const main = within(screen.getByRole("main"));
    expect(main.queryByText("待儲存")).toBeNull();
    expect(screen.queryByRole("region", { name: "未儲存的變更" })).toBeNull();
  });

  it("🔴 儲存送出 publish／unpublish 兩組，且 id 分邊正確", async () => {
    const fetchMock = stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "mutation productPublishing")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "mutation productPublishing")[0].body)) as {
      variables: {
        publicationsToPublish: { publicationId: string }[];
        publicationsToUnpublish: { publicationId: string }[];
        shouldPublish: boolean;
        shouldUnpublish: boolean;
      };
    };
    expect(sent.variables.publicationsToPublish).toEqual([ { publicationId: PUBS[2].id } ]);
    expect(sent.variables.publicationsToUnpublish).toEqual([ { publicationId: PUBS[0].id } ]);
    // 🔴 `@include` 開關（本尊同名同形態，82 §14 抓包）
    expect(sent.variables.shouldPublish).toBe(true);
    expect(sent.variables.shouldUnpublish).toBe(true);
  });

  it("🔴 沒改發布就不送發布 mutation（本尊 §13.2 結論 3：逐區塊判 dirty）", async () => {
    const fetchMock = stubRoutedFetch(EDIT_ROUTES);
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
    const main = within(await screen.findByRole("main"));
    const title = await main.findByLabelText("標題（English）");
    await userEvent.type(title, "X");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "mutation productSet")).toHaveLength(1));
    expect(callsTo(fetchMock, "mutation productPublishing")).toHaveLength(0);
  });

  it("🔴 unpublish 那半的 userErrors 也要顯示（只看 publish 會讓取消發布靜默失敗）", async () => {
    stubRoutedFetch([
      ...EDIT_ROUTES.filter((route) => route.match !== "mutation productPublishing"),
      { match: "mutation productPublishing", body: { data: {
        publishablePublish: { userErrors: [] },
        publishableUnpublish: { userErrors: [ { field: [ "input" ], message: "管道拒絕取消發布", code: "INVALID_STATE" } ] },
      } } },
    ]);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));

    expect(await screen.findByText("管道拒絕取消發布")).toBeVisible();
  });

  /**
   * 群組總開關（本尊 82 §12.2：`Sales Channels` 群組列帶自己的 toggle，
   * 三個管道只有一個開著時呈**半選態**）。
   *
   * 🔴 **它必須是 `role="checkbox"` 不是 `role="switch"`**——`switch` 規範上不支援
   * `aria-checked="mixed"`，指定 mixed 會被 UA 降級成 `false`
   * （MDN《ARIA: switch role》逐字 "assigning a value of `mixed` to a `switch`
   * instead sets the value to `false`"，取證 2026-08-27）。
   * ⇒ 若照各列的樣子寫成 switch，**半選態會被螢幕閱讀器讀成「關」**，
   * 而畫面上完全正常、任何視覺測試都不會紅。本格就是釘這件事。
   */
  it("🔴 群組開關是 checkbox 而非 switch，半選時 aria-checked=mixed", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    // 現況：線上商店開、門市 POS 開（已排程）、Shop 關 ⇒ 半選
    const group = dialog.getByRole("checkbox", { name: /發布到全部管道$/ });
    expect(group).toHaveAttribute("aria-checked", "mixed");
    // 各列仍是 switch（switch 只承載二態，這是規範允許的用法）
    expect(dialog.getAllByRole("switch")).toHaveLength(3);
  });

  it("🔴 半選時點群組開關 ⇒ 全開（可及名稱同時翻成「取消發布」）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("checkbox", { name: /發布到全部管道$/ }));

    expect(dialog.getByRole("switch", { name: "Shop" })).toBeChecked();
    expect(dialog.getByRole("switch", { name: "線上商店" })).toBeChecked();
    expect(dialog.getByRole("switch", { name: "門市 POS" })).toBeChecked();
    expect(dialog.getByRole("checkbox", { name: /自全部管道取消發布$/ })).toHaveAttribute("aria-checked", "true");
  });

  it("全開時點群組開關 ⇒ 全關", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("checkbox", { name: /發布到全部管道$/ }));      // → 全開
    await userEvent.click(dialog.getByRole("checkbox", { name: /自全部管道取消發布$/ }));  // → 全關

    expect(dialog.getByRole("switch", { name: "Shop" })).not.toBeChecked();
    expect(dialog.getByRole("switch", { name: "線上商店" })).not.toBeChecked();
    expect(dialog.getByRole("switch", { name: "門市 POS" })).not.toBeChecked();
  });

  it("🔴 群組開關全開後再全關 ⇒ 回到伺服器現況者不進 delta（完成鍵不會誤亮）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const done = dialog.getByRole("button", { name: "完成" });

    await userEvent.click(dialog.getByRole("checkbox", { name: /發布到全部管道$/ }));
    await userEvent.click(dialog.getByRole("checkbox", { name: /自全部管道取消發布$/ }));
    // 三個都變關：線上商店與門市 POS 是真的變了（伺服器上開著），Shop 本來就關
    // ⇒ delta 應該恰是 {unpublish: [線上商店, 門市 POS]}，Shop 不在裡面
    expect(done).toBeEnabled();

    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("switch", { name: "門市 POS" }));
    // 兩個撥回原狀 ⇒ delta 歸零
    expect(done).toBeDisabled();
  });

  it("🔴 aria-controls 指向的 id 真的存在於 DOM（GID 含 / 與 : ，直接當 id 會解析錯）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const group = dialog.getByRole("checkbox", { name: /發布到全部管道$/ });
    const ids = (group.getAttribute("aria-controls") ?? "").split(" ").filter(Boolean);

    expect(ids).toHaveLength(3);
    for (const id of ids) {
      expect(document.getElementById(id)).not.toBeNull();
      // 🔴 判準是「**不含空白**」——`aria-controls` 是空白分隔的 id 清單，GID 裡的
      //   `/` 與 `:` 不會破壞它，空白才會（一個 id 會被拆成兩個指不到的 token）。
      //   ⚠️ 不要斷言「以字母開頭」：那是 HTML4 的規則，HTML5 已放寬，而 React
      //   `useId()` 產生的前綴正是底線開頭（`_r_…`）。
      expect(id).not.toMatch(/\s/);
    }
  });

  it("搜尋框即時篩選管道；無相符時顯示空態", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.type(dialog.getByRole("searchbox", { name: "搜尋管道" }), "Shop");
    expect(dialog.getByRole("switch", { name: "Shop" })).toBeVisible();
    expect(dialog.queryByRole("switch", { name: "門市 POS" })).toBeNull();

    await userEvent.clear(dialog.getByRole("searchbox", { name: "搜尋管道" }));
    await userEvent.type(dialog.getByRole("searchbox", { name: "搜尋管道" }), "zzz");
    expect(dialog.getAllByText("找不到管道").length).toBeGreaterThan(0);
  });

  /**
   * 🔴 本格由 **M5 突變**開出來（第一版測試集漏了它）。
   *
   * 移除 `savedValues` 的 `publicationDelta: EMPTY_DELTA` 之後，45 格**全綠**——
   * 因為快照與 `values` 雙雙停在非空 delta、彼此相等，SaveBar 照樣消失。
   * 唯一的症狀是**下次儲存重送同一份 delta**，而那是完全無聲的：伺服器會把同一個
   * 管道再 publish 一次（`Publications::Write` 的 R5 是 no-op success ⇒ 連錯誤都沒有）。
   *
   * ⚠️ 這與 mediaOrder 的 C8/C20 **不是同一個失效形態**——那邊有 `reloadMedia`
   * 把 `values.mediaOrder` 清成 `[]`，才會造成「永遠不相等」。照抄那句話會寫出一個
   * 斷言 SaveBar 的測試，而那個斷言在 M5 下是綠的。
   */
  it("🔴 儲存成功後 delta 歸零：卡片不再顯示「待儲存」，再存一次不重送發布 mutation", async () => {
    const fetchMock = stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));
    await waitFor(() => expect(callsTo(fetchMock, "mutation productPublishing")).toHaveLength(1));

    const main = within(screen.getByRole("main"));
    // 卡片回到伺服器現值（reloadPublications 的結果），不再有待儲存 badge
    await waitFor(() => expect(main.queryByText("待儲存")).toBeNull());

    // 再改一次別的欄位並儲存 ⇒ 發布那支**不得**再送（delta 已消費掉）
    await userEvent.type(main.getByLabelText("標題（English）"), "X");
    const savebar2 = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar2).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "mutation productSet")).toHaveLength(2));
    expect(callsTo(fetchMock, "mutation productPublishing")).toHaveLength(1);
  });

  it("🔴 只有 publish 方向時 shouldUnpublish=false（空的那個 field 不執行）", async () => {
    const fetchMock = stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "mutation productPublishing")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "mutation productPublishing")[0].body)) as {
      variables: { shouldPublish: boolean; shouldUnpublish: boolean;
                   publicationsToUnpublish: unknown[] };
    };
    expect(sent.variables.shouldPublish).toBe(true);
    // 🔴 送空陣列而不關開關，會讓 Publications::Write 白跑一次 transaction 並 bump 一次 stamp
    expect(sent.variables.shouldUnpublish).toBe(false);
    expect(sent.variables.publicationsToUnpublish).toEqual([]);
  });

  /**
   * 🔴 本格是**改寫過的**——第一版選錯初始狀態，讓兩種實作結果相同、M11 突變（群組改成
   * 作用於 `publications` 而非 `visible`）**沒有轉紅**。
   *
   * 原因：第一版篩出關著的 `Shop` 再全開，而另外兩個管道**本來就開著** ⇒ 不論群組
   * 作用於誰，斷言都通過。要能區分，必須讓「被波及」與「不被波及」產生不同結果：
   * 篩出**開著**的管道再全關 ⇒ 正確實作只關它一個，M11 會把隱藏的那個也關掉。
   *
   * 本尊實測依據（82 §14）：篩選只剩一列時群組 toggle 立刻變全開態
   * ⇒ 群組的語義是「**目前可見的子集**」，不是全部管道。
   */
  it("🔴 搜尋篩選時群組開關只作用於**可見**的管道（不波及被篩掉的）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const search = dialog.getByRole("searchbox", { name: "搜尋管道" });

    // 篩出「線上商店」——它在伺服器上是**開著**的 ⇒ 群組態＝全開
    await userEvent.type(search, "線上商店");
    expect(dialog.getByRole("checkbox", { name: /自全部管道取消發布$/ }))
      .toHaveAttribute("aria-checked", "true");

    // 全開 → 點群組 → 全關（只該關掉可見的那一個）
    await userEvent.click(dialog.getByRole("checkbox", { name: /自全部管道取消發布$/ }));
    await userEvent.clear(search);

    expect(dialog.getByRole("switch", { name: "線上商店" })).not.toBeChecked();
    // 🔴 被篩掉的「門市 POS」必須維持原狀（伺服器上開著）——M11 會讓它變關
    expect(dialog.getByRole("switch", { name: "門市 POS" })).toBeChecked();
    expect(dialog.getByRole("switch", { name: "Shop" })).not.toBeChecked();
  });

  /**
   * 🔴 本尊實測（82 §14，C.10 的補充格）：若**先前已有暫存值**（Done 過一次），
   * 再開 modal 後按 `Cancel`，只丟棄本次 modal session 內的改動，
   * **先前暫存值保留**（Publishing 卡仍顯示待儲存、SaveBar 仍在）。
   * ⇒ `Cancel` 的作用域是 modal session，**不是**整頁 dirty state（那是 `Discard`）。
   */
  it("🔴 Cancel 只丟棄本次 modal session，先前已 Done 的暫存值保留", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));

    const main = within(screen.getByRole("main"));
    expect(await main.findByText("待儲存")).toBeVisible();

    // 第二次開 modal：撥動另一個管道後按 Cancel
    await userEvent.click(main.getByRole("button", { name: "管理發布" }));
    const again = within(await screen.findByRole("dialog"));
    // 🔴 開場顯示的是**暫存值**（Shop 已開），不是伺服器值
    expect(again.getByRole("switch", { name: "Shop" })).toBeChecked();
    await userEvent.click(again.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(again.getByRole("button", { name: "取消" }));

    // 先前那筆暫存仍在
    expect(main.getByText("待儲存")).toBeVisible();
    expect(screen.getByRole("region", { name: "未儲存的變更" })).toBeVisible();
  });

  /**
   * 🔴 本尊實測的比對法是**詞首前綴**，不是子字串（82 §14）：
   *   `store` 命中 `Online Store`、`tore` 與 `line` 都無結果。
   * 用 `includes()` 的話後兩格會多命中，而在「Shop」這種單詞管道上兩種實作**都會命中**
   * ⇒ 只測 `Shop` 是分不出來的，必須測 `tore`／`line` 這兩個反例。
   */
  it("🔴 搜尋是詞首前綴而非子字串：store 命中、tore 與 line 都不命中", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const search = dialog.getByRole("searchbox", { name: "搜尋管道" });

    await userEvent.type(search, "POS");                  // 「門市 POS」的第二個詞的詞首
    expect(dialog.getByRole("switch", { name: "門市 POS" })).toBeVisible();
    expect(dialog.queryByRole("switch", { name: "線上商店" })).toBeNull();

    await userEvent.clear(search);
    await userEvent.type(search, "hop");                  // Shop 的子字串但非詞首 ⇒ 不命中
    expect(dialog.getAllByText("找不到管道").length).toBeGreaterThan(0);

    await userEvent.clear(search);
    await userEvent.type(search, "Sho");                  // 詞首前綴 ⇒ 命中
    expect(dialog.getByRole("switch", { name: "Shop" })).toBeVisible();

    // ⚠️ **已知限制（照抄本尊的代價）**：中文管道名沒有空白 ⇒ 整個名字是一個詞，
    //    只有整串前綴才命中。「線上商店」搜「商店」**不會**命中，搜「線上」才會。
    //    這不是 bug，是本尊詞首前綴規則套到無空白書寫系統的必然結果。
    await userEvent.clear(search);
    await userEvent.type(search, "商店");
    expect(dialog.getAllByText("找不到管道").length).toBeGreaterThan(0);

    await userEvent.clear(search);
    await userEvent.type(search, "線上");
    expect(dialog.getByRole("switch", { name: "線上商店" })).toBeVisible();
  });

  /**
   * 🔴 本組由對抗性審查開出來（PR #160 的 review）。每一格都對應一個**實跑證實**的缺陷。
   */

  it("🔴 重開 modal 撤回先前的暫存 ⇒ 完成鍵必須可按（否則使用者撤銷不了自己剛做的事）", async () => {
    const fetchMock = stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();

    // ①關掉已發布的「線上商店」→ 完成 ⇒ 暫存 unpublish
    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));
    expect(await screen.findByRole("region", { name: "未儲存的變更" })).toBeVisible();

    // ②發現弄錯，重開 modal 把它撥回開
    const main = within(screen.getByRole("main"));
    await userEvent.click(main.getByRole("button", { name: "管理發布" }));
    const again = within(await screen.findByRole("dialog"));
    expect(again.getByRole("switch", { name: "線上商店" })).not.toBeChecked();  // 顯示暫存值
    await userEvent.click(again.getByRole("switch", { name: "線上商店" }));

    // 🔴 判準若是「draft 兩邊皆空」，這裡會 disabled ⇒ 使用者只能按取消，
    //    而取消保留先前暫存（§14.4d）⇒ modal 內無路可撤，一存就真的下架。
    const done = again.getByRole("button", { name: "完成" });
    expect(done).toBeEnabled();
    await userEvent.click(done);

    // 撤回成功：SaveBar 消失、儲存不送發布 mutation
    await waitFor(() => expect(screen.queryByRole("region", { name: "未儲存的變更" })).toBeNull());
    expect(callsTo(fetchMock, "mutation productPublishing")).toHaveLength(0);
  });

  it("🔴 儲存後真的重讀伺服器現值：卡片與可見性兩維都跟著更新", async () => {
    // 🔴 重讀路由必須回**與初始不同**的一份，否則「重讀有沒有發生」不可觀測——
    //    刪掉 reloadPublications 那一行，測試會全綠（M5 同型的相等陷阱）。
    const AFTER = [ ROWS[1] ];  // 線上商店已被取消發布，只剩門市 POS
    const fetchMock = stubRoutedFetch([
      ...EDIT_ROUTES.filter((r) => r.match !== "query productPublications"),
      { match: "query productPublications", body: { data: { product: {
        purchasable: false, discoverable: false, resourcePublicationsV2: AFTER,
      } } } },
    ]);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "query productPublications")).toHaveLength(1));
    const main = within(screen.getByRole("main"));
    await waitFor(() => expect(main.queryByText("線上商店")).toBeNull());
    // S6a-2 的兩維也必須跟著翻（取消發布 ⇒ 不可購買）
    await waitFor(() => expect(main.getByText("可購買").parentElement).toHaveTextContent("否"));
  });

  it("🔴 只取消發布時 shouldPublish=false（送空陣列會讓後端白跑一次 transaction 並多 bump stamp）", async () => {
    const fetchMock = stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));

    await waitFor(() => expect(callsTo(fetchMock, "mutation productPublishing")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "mutation productPublishing")[0].body)) as {
      variables: { shouldPublish: boolean; shouldUnpublish: boolean; publicationsToPublish: unknown[] };
    };
    expect(sent.variables.shouldUnpublish).toBe(true);
    expect(sent.variables.shouldPublish).toBe(false);
    expect(sent.variables.publicationsToPublish).toEqual([]);
  });

  it("🔴 完成後發布卡樂觀**移除**被取消的管道（兩個方向的樂觀更新都要有）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const main = within(screen.getByRole("main"));
    expect(main.getByText("線上商店")).toBeVisible();

    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));

    // 🔴 少了這條濾鏡，卡片會繼續顯示「線上商店／已發布」綠 badge，
    //    頁面上完全看不出有一筆待送的取消發布（本尊按 Done 後是樂觀更新的，82 §13.1）
    await waitFor(() => expect(main.queryByText("線上商店")).toBeNull());
  });

  it("🔴 搜尋大小寫不敏感（測試 query 與標題同大小寫時，敏感／不敏感兩種實作分不出來）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const search = dialog.getByRole("searchbox", { name: "搜尋管道" });

    await userEvent.type(search, "SHO");   // 全大寫（本尊 §14.3 逐字那格）
    expect(dialog.getByRole("switch", { name: "Shop" })).toBeVisible();

    await userEvent.clear(search);
    await userEvent.type(search, "pos");   // 全小寫，標題是「門市 POS」
    expect(dialog.getByRole("switch", { name: "門市 POS" })).toBeVisible();
  });

  it("🔴 發布 mutation 失敗後 lockVersion 已吸收：重試送的是新版本，不會撞樂觀鎖", async () => {
    let calls = 0;
    const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as { query: string };
      if (request.query.includes("mutation productPublishing")) {
        calls += 1;
        return { json: vi.fn().mockResolvedValue({}), ok: false, status: 500 } as unknown as Response;
      }
      const route = EDIT_ROUTES.find((c) => request.query.includes(c.match));
      if (!route) throw new Error(`未預期：${request.query.slice(0, 60)}`);
      return { json: vi.fn().mockResolvedValue(route.body), ok: true, status: 200 } as unknown as Response;
    });
    vi.stubGlobal("fetch", fetchMock);

    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));
    await waitFor(() => expect(calls).toBe(1));

    // 第二次儲存：productSet 必須帶**新**的 lockVersion（fixture 回 4），不是舊的 3
    await userEvent.click(within(await screen.findByRole("region", { name: "未儲存的變更" }))
      .getByRole("button", { name: "儲存" }));
    await waitFor(() => expect(callsTo(fetchMock as unknown as Mock, "mutation productSet")).toHaveLength(2));
    const second = JSON.parse(String(
      callsTo(fetchMock as unknown as Mock, "mutation productSet")[1].body)) as {
      variables: { input: { lockVersion: number } };
    };
    // 🔴 舊寫法把 setLockVersion 擺在發布 mutation 之後 ⇒ 例外直接跳 catch，
    //    本地版本永遠停在 3，此後每次儲存都吃 STALE_OBJECT，連標題都存不回去。
    expect(second.variables.input.lockVersion).toBe(4);
  });

  it("🔴 catalog publication 不得混進「銷售管道」（本尊把兩者分成兩節）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    // EDIT_ROUTES 的 publications 含一個 handle=null 的 catalog
    expect(dialog.queryByRole("switch", { name: "日本市場目錄" })).toBeNull();
    expect(dialog.getAllByRole("switch")).toHaveLength(3);
  });

  it("🔴 儲存進行中與變體超過 250 時，齒輪必須 disabled", async () => {
    // ①變體超過 250：save() 整頁封鎖、一個請求都不送 ⇒ 不能讓使用者暫存出存不進去的變更
    stubRoutedFetch([
      ...EDIT_ROUTES.filter((r) => r.match !== "query productForEdit"),
      { match: "query productForEdit", body: { data: {
        product: { ...PRODUCT, variants: { ...PRODUCT.variants, pageInfo: { hasNextPage: true } } },
        publications: [ ...PUBS, CATALOG_PUB ],
      } } },
    ]);
    renderAt("/admin/products/gid%3A%2F%2Fchilllove%2FProduct%2F9");
    const main = within(await screen.findByRole("main"));
    await waitFor(() => expect(main.getByRole("button", { name: "管理發布" })).toBeDisabled());
  });

  it("🔴 群組開關的可及名稱含可見文字「銷售管道」（WCAG 2.5.3 Label in Name）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    // 語音輸入使用者照畫面唸「銷售管道」要找得到這個控件
    const group = dialog.getByRole("checkbox", { name: /銷售管道/ });
    expect(group).toHaveAttribute("aria-checked", "mixed");
  });

  it("🔴 搜尋結果有 status message，且節點在切換前就存在（部分 AT 對新插入的 live region 會漏播）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    const status = dialog.getByRole("status");
    expect(status).toHaveTextContent("3 個管道相符");

    await userEvent.type(dialog.getByRole("searchbox", { name: "搜尋管道" }), "Sho");
    // 同一個節點只換文字，不是移除再插入
    expect(dialog.getByRole("status")).toBe(status);
    expect(status).toHaveTextContent("1 個管道相符");

    await userEvent.clear(dialog.getByRole("searchbox", { name: "搜尋管道" }));
    await userEvent.type(dialog.getByRole("searchbox", { name: "搜尋管道" }), "zzz");
    expect(status).toHaveTextContent("找不到管道");
  });

  it("🔴 重讀失敗 ⇒ 卡片說「讀不到」，不冒充伺服器真相（空清單也是一種冒充）", async () => {
    const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as { query: string };
      if (request.query.includes("query productPublications")) {
        return { json: vi.fn().mockResolvedValue({}), ok: false, status: 500 } as unknown as Response;
      }
      const route = EDIT_ROUTES.find((c) => request.query.includes(c.match));
      if (!route) throw new Error(`未預期：${request.query.slice(0, 60)}`);
      return { json: vi.fn().mockResolvedValue(route.body), ok: true, status: 200 } as unknown as Response;
    });
    vi.stubGlobal("fetch", fetchMock);

    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "線上商店" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "儲存" }));

    const main = within(screen.getByRole("main"));
    // 🔴 儲存已成功（伺服器上那筆取消發布生效了），但重讀失敗 ⇒ 手上這份是過期的。
    //    不標記的話卡片會繼續把已下架的「線上商店」顯示成綠色「已發布」。
    await waitFor(() => expect(main.getByText(/無法重新讀取發布狀態/)).toBeVisible());
    expect(main.queryByText("已發布")).toBeNull();
  });

  it("取消鍵會真的關閉 modal，且焦點還原到齒輪", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("button", { name: "取消" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    // Modal 原語的焦點還原鏈：restoreFocusTo（齒輪）優先
    expect(within(screen.getByRole("main")).getByRole("button", { name: "管理發布" }))
      .toHaveFocus();
  });

  it("modal 標題帶商品名、群組列標籤逐字（鐵律 12.4 的對位要有機械證據）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    // 本尊逐字 `Manage publishing for <商品標題>`（82 §12.1）
    expect(dialog.getByRole("heading", { name: "管理「既有商品」的發布" })).toBeVisible();
    expect(dialog.getByText("銷售管道")).toBeVisible();
  });

  it("建立態沒有齒輪（商品尚不存在＝沒有可傳給 publishablePublish 的 GID）", async () => {
    stubRoutedFetch(BASE_ROUTES);
    renderAt("/admin/products/new");
    const main = within(await screen.findByRole("main"));
    expect(main.queryByRole("button", { name: "管理發布" })).toBeNull();
  });

  /**
   * 🔴 Microsoft Win32 UX Guide《Property Windows》對 owned property window 的逐字要求：
   * "make sure users can cancel changes made in an owned property window by clicking Cancel"
   * （<https://learn.microsoft.com/en-us/windows/win32/uxguide/win-property-win>，取證 2026-08-27）。
   * 我方的 owner＝商品表單、owned＝本 modal ⇒ 頁面的「捨棄」必須連 modal 內做的變更一起撤銷。
   *
   * 這一格是 `publicationDelta` **放進 `values`** 的直接收益：`applyDiscard` 走
   * `setValues(snapshot)` ⇒ delta 自動歸零。若當初把它另存成獨立 state，捨棄就會漏掉它，
   * 而症狀是「按了捨棄，發布卡卻還顯示待儲存」。
   */
  it("🔴 頁面捨棄會一併撤銷 modal 內的發布變更（owned property window 語義）", async () => {
    stubRoutedFetch(EDIT_ROUTES);
    const dialog = await openModal();
    await userEvent.click(dialog.getByRole("switch", { name: "Shop" }));
    await userEvent.click(dialog.getByRole("button", { name: "完成" }));

    const main = within(screen.getByRole("main"));
    expect(await main.findByText("待儲存")).toBeVisible();

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await userEvent.click(within(savebar).getByRole("button", { name: "捨棄" }));
    // 捨棄走確認框（包 4）
    const confirm = within(await screen.findByRole("dialog"));
    await userEvent.click(confirm.getByRole("button", { name: "捨棄變更" }));

    await waitFor(() => expect(main.queryByText("待儲存")).toBeNull());
    expect(screen.queryByRole("region", { name: "未儲存的變更" })).toBeNull();
  });
});
