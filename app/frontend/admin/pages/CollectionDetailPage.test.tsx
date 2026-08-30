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

function stubRoutedFetch(routes: { match: string; body: unknown }[]) {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string };
    const route = routes.find((candidate) => request.query.includes(candidate.match));
    if (!route) throw new Error(`unexpected GraphQL call: ${request.query.slice(0, 80)}`);
    return graphqlResponse(route.body);
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function callsTo(fetchMock: Mock, match: string): RequestInit[] {
  return fetchMock.mock.calls
    .map((call) => call[1] as RequestInit)
    .filter((init) => String(init?.body).includes(match));
}

const SHOP_LOCALES = {
  data: {
    shopLocales: [
      { locale: { tag: "en", endonym: "English" }, isSource: true, position: 0 },
      { locale: { tag: "zh-Hant", endonym: "繁體中文" }, isSource: false, position: 1 },
      { locale: { tag: "ja", endonym: "日本語" }, isSource: false, position: 3 },
    ],
  },
};

const EXISTING = {
  data: {
    collection: {
      id: "gid://chilllove/Collection/7",
      title: "Spring Picks",
      handle: "spring-picks",
      descriptionHtml: "<p>Fresh</p>",
      collectionType: "manual",
      sortOrder: "manual",
      lockVersion: 2,
      seo: { title: null, description: null },
      translations: [ { locale: "zh-Hant", field: "title", value: "春季精選", outdated: true } ],
      resourcePublicationsV2: [
        // S6c：Online Store 已發布（＝本尊測試店的初始形態，82 §17）
        { isPublished: true, publishDate: "2026-07-14T13:40:55Z",
          publication: { id: "gid://chilllove/Publication/1", title: "線上商店", supportsFuturePublishing: true } },
      ],
    },
  },
};

// S6c：本店管道清單（含一個 handle=null 的 app——salesChannelsOf 必須把它濾掉，
// 濾不掉的話 popover 會多一列非管道 app；與商品 modal 同一條守衛）
const CHANNELS = {
  data: {
    publications: [
      { id: "gid://chilllove/Publication/1", title: "線上商店", handle: "online_store", supportsFuturePublishing: true },
      { id: "gid://chilllove/Publication/2", title: "門市 POS", handle: "pos", supportsFuturePublishing: false },
      { id: "gid://chilllove/Publication/3", title: "Shop", handle: "shop", supportsFuturePublishing: false },
      { id: "gid://chilllove/Publication/9", title: "報表 App", handle: null, supportsFuturePublishing: false },
    ],
    shop: { ianaTimezone: "Asia/Hong_Kong" },
  },
};

const BASE = [
  { match: "query shopLocales", body: SHOP_LOCALES },
  { match: "query collectionForEdit", body: EXISTING },
  { match: "query collectionChannels", body: CHANNELS },
];

function renderAt(path: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// ML-3：Collection 與商品共用 LocalizedField／SaveBar／譯文列形態（語義必須一模一樣）。
describe("商品系列編輯頁", () => {
  beforeEach(() => installCsrfMeta());

  it("載入既有系列：標題三語堆疊、既有譯文填入、系列型別與排序讀值", async () => {
    stubRoutedFetch(BASE);
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByLabelText("標題（English）")).toHaveValue("Spring Picks");
    expect(main.getByLabelText("標題（繁體中文）")).toHaveValue("春季精選");
    expect(main.getByLabelText("標題（日本語）")).toHaveValue("");
    expect(main.getByLabelText("類型")).toHaveValue("manual");
    expect(main.getByLabelText("排序方式")).toHaveValue("manual");
    // 第 6 包：handle 在編輯態**可改**（與商品同一條紀律：改名同 txn 落 301）
    expect(main.getByLabelText("網址 handle")).toBeEnabled();
  });

  it("儲存：譯文逐欄位一列、不含來源語言、帶 id＋lockVersion", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE,
      {
        match: "mutation collectionSet",
        body: { data: { collectionSet: { collection: { id: "gid://chilllove/Collection/7", handle: "spring-picks", lockVersion: 3, title: "Spring Picks" }, userErrors: [] } } },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");

    const main = within(await screen.findByRole("main"));
    await user.type(await main.findByLabelText("標題（日本語）"), "春のおすすめ");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");

    const body = JSON.parse(String(callsTo(fetchMock, "collectionSet")[0].body)) as { variables: { input: Record<string, unknown> } };
    const input = body.variables.input;
    expect(input.id).toBe("gid://chilllove/Collection/7");
    expect(input.lockVersion).toBe(2);
    const translations = input.translations as { locale: string; field: string; value: string }[];
    expect(translations).toContainEqual({ locale: "ja", field: "title", value: "春のおすすめ" });
    expect(translations).toContainEqual({ locale: "zh-Hant", field: "title", value: "春季精選" });
    expect(translations.some((row) => row.locale === "en")).toBe(false);
    expect(input.title).toBe("Spring Picks");
  });

  it("智慧系列：**建立頁**選 smart 時顯示「成員由規則決定」而不是假裝能編條件", async () => {
    stubRoutedFetch(BASE);
    const user = userEvent.setup();
    // 🔴 這一格原本開既有系列頁翻下拉——2026-08-26 起型別建立後不可變、
    //    下拉在既有系列上停用，改在建立頁測（可翻的那一態）。
    renderAt("/admin/collections/new");

    const main = within(await screen.findByRole("main"));
    await user.selectOptions(await main.findByLabelText("類型"), "smart");
    expect(main.getByText(/成員由規則決定/)).toBeVisible();
  });

  it("🔴 既有系列：型別下拉停用、hint 說明不可變、存檔 payload 不帶 collectionType", async () => {
    // 伺服端自 2026-08-26 起硬拒改型別（本尊官方語義）。前端若照舊送出，被拒的值會
    // 留在表單狀態裡，之後每一次存檔都被同一個 INVALID 擋下（delta 審查 F4 的死路）。
    const fetchMock = stubRoutedFetch([
      ...BASE,
      {
        match: "mutation collectionSet",
        body: { data: { collectionSet: { collection: { id: "gid://chilllove/Collection/7", handle: "spring-picks", lockVersion: 3, title: "Spring Picks" }, userErrors: [] } } },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");

    const main = within(await screen.findByRole("main"));
    const typeSelect = await main.findByLabelText("類型");
    expect(typeSelect).toBeDisabled();
    expect(typeSelect).toHaveValue("manual");
    expect(main.getByText(/型別建立後不可變更/)).toBeVisible();

    await user.type(main.getByLabelText("標題（日本語）"), "春のおすすめ");
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));
    await screen.findByText("已儲存變更");

    const body = JSON.parse(String(callsTo(fetchMock, "collectionSet")[0].body)) as { variables: { input: Record<string, unknown> } };
    expect(body.variables.input).not.toHaveProperty("collectionType");
  });

  it("建立頁：型別下拉可用，且存檔 payload 帶 collectionType", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE,
      {
        match: "mutation collectionSet",
        body: { data: { collectionSet: { collection: { id: "gid://chilllove/Collection/9", handle: "new-one", lockVersion: 1, title: "新系列" }, userErrors: [] } } },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/collections/new");

    const main = within(await screen.findByRole("main"));
    const typeSelect = await main.findByLabelText("類型");
    expect(typeSelect).toBeEnabled();
    await user.selectOptions(typeSelect, "smart");
    await user.type(main.getByLabelText("標題（English）"), "新系列");

    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    const body = JSON.parse(String(callsTo(fetchMock, "collectionSet")[0].body)) as { variables: { input: Record<string, unknown> } };
    expect(body.variables.input.collectionType).toBe("smart");
  });

  it("伺服端 userErrors 以 toast 呈現（STALE_OBJECT 等）", async () => {
    stubRoutedFetch([
      ...BASE,
      {
        match: "mutation collectionSet",
        body: { data: { collectionSet: { collection: null, userErrors: [ { field: null, message: "系列已被其他人修改，請重新載入後再儲存。", code: "STALE_OBJECT" } ] } } },
      },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");

    const main = within(await screen.findByRole("main"));
    await user.type(await main.findByLabelText("標題（日本語）"), "x");
    const savebar = await screen.findByRole("region", { name: "未儲存的變更" });
    await user.click(within(savebar).getByRole("button", { name: "儲存" }));

    expect(await screen.findByText("系列已被其他人修改，請重新載入後再儲存。")).toBeVisible();
  });

  it("S6c 管道 popover：觸發鈕計數、三列開關態、排程入口只在 supportsFuturePublishing 列", async () => {
    stubRoutedFetch(BASE);
    const user = userEvent.setup();
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");
    // 觸發鈕文案＝伺服器已發布數（1）；App（handle=null）不算管道
    const trigger = await screen.findByRole("button", { name: "管理銷售管道：已發布至 1 個管道" });
    expect(trigger).toHaveTextContent("1 個管道");
    await user.click(trigger);
    // 三列：線上商店開、其餘關；總開關 mixed
    const dialog = screen.getByRole("group", { name: "銷售管道" });
    const rows = within(dialog).getAllByRole("switch");
    expect(rows.map((node) => node.getAttribute("aria-checked"))).toEqual([ "true", "false", "false" ]);
    expect(within(dialog).getByRole("checkbox").getAttribute("aria-checked")).toBe("mixed");
    // 🔴 排程入口恰一顆（Online Store）；POS／Shop 沒有（82 §12.3 同款實測）
    expect(within(dialog).getAllByRole("button", { name: /排程/ })).toHaveLength(1);
  });

  it("S6c toggle＝表單級 dirty：開 Shop → 儲存 → collectionSet 之後才送 publishablePublish", async () => {
    const fetchMock = stubRoutedFetch([
      ...BASE,
      { match: "mutation collectionSet",
        body: { data: { collectionSet: { collection: { id: "gid://chilllove/Collection/7", handle: "spring-picks", lockVersion: 3, title: "Spring Picks" }, userErrors: [] } } } },
      { match: "mutation collectionPublishing",
        body: { data: { publishablePublish: { userErrors: [] } } } },
      { match: "query collectionPublications",
        body: { data: { collection: { resourcePublicationsV2: EXISTING.data.collection.resourcePublicationsV2 } } } },
    ]);
    const user = userEvent.setup();
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");
    await user.click(await screen.findByRole("button", { name: "管理銷售管道：已發布至 1 個管道" }));
    const dialog = screen.getByRole("group", { name: "銷售管道" });
    await user.click(within(dialog).getByRole("switch", { name: "Shop" }));
    // 觸發鈕即時反映（本尊 82 §17：aria 立即變 2）；此刻**還沒有任何 mutation**
    expect(screen.getByRole("button", { name: "管理銷售管道：已發布至 2 個管道" })).toBeInTheDocument();
    expect(callsTo(fetchMock, "mutation collectionPublishing")).toHaveLength(0);
    // 儲存
    await user.click(screen.getAllByRole("button", { name: "儲存" })[0]);
    await waitFor(() => expect(callsTo(fetchMock, "mutation collectionPublishing")).toHaveLength(1));
    const pubCall = JSON.parse(String(callsTo(fetchMock, "mutation collectionPublishing")[0].body)) as {
      variables: { id: string; publicationsToPublish: unknown[]; shouldPublish: boolean; shouldUnpublish: boolean };
    };
    expect(pubCall.variables.id).toBe("gid://chilllove/Collection/7");
    expect(pubCall.variables.publicationsToPublish).toEqual([ { publicationId: "gid://chilllove/Publication/3" } ]);
    expect(pubCall.variables.shouldPublish).toBe(true);
    expect(pubCall.variables.shouldUnpublish).toBe(false);
    // 🔴 順序：collectionSet 在 publishing 之前（S6b 的先例：主體先存，發布後送）
    const bodies = fetchMock.mock.calls.map((call) => String((call[1] as RequestInit).body));
    expect(bodies.findIndex((body) => body.includes("mutation collectionSet")))
      .toBeLessThan(bodies.findIndex((body) => body.includes("mutation collectionPublishing")));
  });

  it("S6c 總開關循環：mixed → 全開 → 全關（82 §17 實測語義）", async () => {
    stubRoutedFetch(BASE);
    const user = userEvent.setup();
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");
    await user.click(await screen.findByRole("button", { name: "管理銷售管道：已發布至 1 個管道" }));
    const dialog = screen.getByRole("group", { name: "銷售管道" });
    const master = within(dialog).getByRole("checkbox");
    await user.click(master); // mixed → 全開
    expect(master.getAttribute("aria-checked")).toBe("true");
    expect(screen.getByRole("button", { name: "管理銷售管道：已發布至 3 個管道" })).toBeInTheDocument();
    await user.click(master); // 全開 → 全關
    expect(master.getAttribute("aria-checked")).toBe("false");
    expect(screen.getByRole("button", { name: "管理銷售管道：已發布至 0 個管道" })).toBeInTheDocument();
  });

  it("S6c 捨棄：toggle 後 Discard 還原計數且零 mutation", async () => {
    const fetchMock = stubRoutedFetch(BASE);
    const user = userEvent.setup();
    renderAt("/admin/collections/gid%3A%2F%2Fchilllove%2FCollection%2F7");
    await user.click(await screen.findByRole("button", { name: "管理銷售管道：已發布至 1 個管道" }));
    const dialog = screen.getByRole("group", { name: "銷售管道" });
    await user.click(within(dialog).getByRole("switch", { name: "Shop" }));
    // SaveBar 出現（表單級 dirty——本尊 82 §17 的核心語義）
    await user.click(await screen.findByRole("button", { name: "捨棄" }));
    expect(screen.getByRole("button", { name: "管理銷售管道：已發布至 1 個管道" })).toBeInTheDocument();
    expect(callsTo(fetchMock, "mutation collectionPublishing")).toHaveLength(0);
  });

  it("列表頁：智慧系列商品數顯示 — 而不是 0（未知與零是兩件事）", async () => {
    stubRoutedFetch([
      { match: "query shopLocales", body: SHOP_LOCALES },
      {
        match: "query collectionsList",
        body: {
          data: {
            collections: {
              nodes: [
                { id: "gid://chilllove/Collection/7", title: "Spring Picks", handle: "spring-picks", collectionType: "manual", productsCount: 3 },
                { id: "gid://chilllove/Collection/8", title: "Auto Sale", handle: "auto-sale", collectionType: "smart", productsCount: null },
              ],
              pageInfo: { hasNextPage: false, endCursor: null },
            },
          },
        },
      },
    ]);
    renderAt("/admin/collections");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("Spring Picks")).toBeVisible();
    expect(main.getByText("3 件")).toBeVisible();
    expect(main.getByText("—")).toBeVisible();
    expect(main.getByText("智慧")).toBeVisible();
  });
});
