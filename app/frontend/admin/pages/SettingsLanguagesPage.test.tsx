import { render, screen, within } from "@testing-library/react";
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

const SETTINGS = {
  data: {
    shopLocales: [
      { locale: { tag: "en", endonym: "English", direction: "ltr" }, isSource: true, published: true, enabled: true, position: 0 },
      { locale: { tag: "zh-Hant", endonym: "繁體中文", direction: "ltr" }, isSource: false, published: true, enabled: true, position: 1 },
      { locale: { tag: "ja", endonym: "日本語", direction: "ltr" }, isSource: false, published: false, enabled: true, position: 3 },
      { locale: { tag: "de", endonym: "Deutsch", direction: "ltr" }, isSource: false, published: false, enabled: false, position: 5 },
    ],
    availableLocales: [
      { tag: "ko", endonym: "한국어", direction: "ltr" },
      { tag: "ar", endonym: "العربية", direction: "rtl" },
    ],
  },
};

function renderSettings() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/settings/languages" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// ML-4：新增語言＝插一列 shop_locales；停用＝保留譯文的狀態轉換（67 §A.2／§C.1）。
describe("設定 › 語言", () => {
  beforeEach(() => installCsrfMeta());

  it("列出已啟用語言：來源語言標記、發布狀態、停用區塊分開", async () => {
    stubRoutedFetch([ { match: "query localeSettings", body: SETTINGS } ]);
    renderSettings();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("English")).toBeVisible();
    expect(main.getByText("來源語言")).toBeVisible();
    expect(main.getAllByText("已發布").length).toBeGreaterThan(0);
    expect(main.getByText("未發布")).toBeVisible();
    // 停用中的語言在獨立區塊，可重新啟用
    expect(main.getByRole("heading", { name: "已停用的語言" })).toBeVisible();
    expect(main.getByRole("button", { name: /重新啟用/ })).toBeVisible();
  });

  it("新增語言：候選來自平台字典，送 shopLocaleEnable 後重載", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query localeSettings", body: SETTINGS },
      { match: "mutation shopLocaleEnable", body: { data: { shopLocaleEnable: { shopLocale: { locale: { tag: "ko" } }, userErrors: [] } } } },
    ]);
    const user = userEvent.setup();
    renderSettings();

    const main = within(await screen.findByRole("main"));
    const select = await main.findByLabelText("新增語言");
    // 候選含 RTL 語言（direction 欄位的存在意義）
    expect(within(select).getByRole("option", { name: /한국어/ })).toBeInTheDocument();
    expect(within(select).getByRole("option", { name: /العربية/ })).toBeInTheDocument();

    await user.selectOptions(select, "ko");
    await user.click(main.getByRole("button", { name: /^新增$/ }));

    await screen.findByText("已新增語言");
    const body = JSON.parse(String(callsTo(fetchMock, "shopLocaleEnable")[0].body)) as { variables: { locale: string } };
    expect(body.variables.locale).toBe("ko");
    // 重載讓畫面與 DB 同源
    expect(callsTo(fetchMock, "query localeSettings").length).toBeGreaterThan(1);
  });

  it("停用語言：伺服端回報保留譯文筆數，toast 說明譯文保留", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query localeSettings", body: SETTINGS },
      { match: "mutation shopLocaleDisable", body: { data: { shopLocaleDisable: { retainedTranslations: 12, userErrors: [] } } } },
    ]);
    const user = userEvent.setup();
    renderSettings();

    const main = within(await screen.findByRole("main"));
    // 「日本語」同時出現在語言列與 CSV 匯出下拉 ⇒ 用列表區塊收窄（同型教訓：查詢要指定容器）
    // 已啟用清單是第一個 list（第二個是「已停用的語言」）
    const list = within((await main.findAllByRole("list"))[0]);
    await list.findByText("日本語");
    await user.click(list.getAllByRole("button", { name: /停用/ })[0]);

    await screen.findByText("已停用；譯文保留");
    expect(callsTo(fetchMock, "shopLocaleDisable")).toHaveLength(1);
  });

  it("來源語言那一列沒有停用／取消發布按鈕（SOURCE_LOCALE_IMMUTABLE 的 UI 面）", async () => {
    stubRoutedFetch([ { match: "query localeSettings", body: SETTINGS } ]);
    renderSettings();

    const main = within(await screen.findByRole("main"));
    const sourceRow = (await main.findByText("English")).closest("li");
    expect(sourceRow).not.toBeNull();
    expect(within(sourceRow as HTMLElement).queryByRole("button")).toBeNull();
    expect(within(sourceRow as HTMLElement).getByText("商品欄位本身就以這個語言儲存")).toBeVisible();
  });

  it("伺服端 userErrors 以 toast 呈現，不靜默失敗", async () => {
    stubRoutedFetch([
      { match: "query localeSettings", body: SETTINGS },
      {
        match: "mutation shopLocaleEnable",
        body: { data: { shopLocaleEnable: { shopLocale: null, userErrors: [ { field: [ "locale" ], message: "已達每店語言數上限。", code: "LOCALE_LIMIT_EXCEEDED" } ] } } },
      },
    ]);
    const user = userEvent.setup();
    renderSettings();

    const main = within(await screen.findByRole("main"));
    await user.selectOptions(await main.findByLabelText("新增語言"), "ko");
    await user.click(main.getByRole("button", { name: /^新增$/ }));

    expect(await screen.findByText("已達每店語言數上限。")).toBeVisible();
  });
});
