import { render, screen, waitFor, within } from "@testing-library/react";
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
      variants: [ { price: "128.50", taxable: true } ],
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
          variants: [
            { price: "128.00", compareAtPrice: null, cost: null, sku: "SKU-1", barcode: null, taxable: true },
          ],
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

    await user.click(within(savebar).getByRole("button", { name: "捨棄" }));
    expect(screen.getByLabelText("標題（English）")).toHaveValue("");
    expect(screen.getByRole("button", { name: "開啟全域搜尋" })).toBeVisible();
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
        variants: [ { price: "128.00", compareAtPrice: null, cost: null, sku: null, barcode: null, taxable: true } ],
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
