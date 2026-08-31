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

const AIRWALLEX_ROW = {
  provider: "airwallex",
  environment: "sandbox",
  status: "inactive",
  clientId: "cid_live_1",
  webhookId: null,
  apiSecretFingerprint: "3229db23516d9173",
  webhookSecretFingerprint: "c3efc2e0aca312a6",
  enabledMethods: [ "card", "alipayhk" ],
  availableMethods: [ "card", "alipayhk" ],
  capabilitiesSyncedAt: "2026-08-31T10:00:00Z",
};

const LIST = { data: { shopPaymentProviders: [ AIRWALLEX_ROW ] } };
const EMPTY_LIST = { data: { shopPaymentProviders: [] } };
const DICTIONARY = [
  { code: "card", label: "Credit Card (Visa / Mastercard / Amex)" },
  { code: "alipayhk", label: "AlipayHK" },
  { code: "fps", label: "FPS" },
];
const DETAIL = { data: { shopPaymentProviders: [ AIRWALLEX_ROW ], pspMethodDictionary: DICTIONARY } };

function renderAt(path: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// G6-3：主頁照 86 §1 三區；詳情頁照本尊 provider 頁形（憑證＋逐方法 toggle）。
describe("設定 › 付款（主頁）", () => {
  beforeEach(() => installCsrfMeta());

  it("三區都渲染：主收單（Airwallex）／其他服務商（PayPal）／付款設定清單", async () => {
    stubRoutedFetch([ { match: "query shopPaymentProviderList", body: EMPTY_LIST } ]);
    renderAt("/admin/settings/payments");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("Airwallex")).toBeVisible();
    expect(main.getByText("PayPal")).toBeVisible();
    expect(main.getByText("收單服務商")).toBeVisible();
    expect(main.getByText("其他付款服務商")).toBeVisible();
    expect(main.getByText("付款設定")).toBeVisible();
    expect(main.getByText("請款方式")).toBeVisible();
    expect(main.getAllByText("即將推出").length).toBe(2);
    expect(main.getAllByText("未設定").length).toBe(2);
  });

  it("已設定 sandbox 憑證 ⇒ 測試模式橫幅＋method chips＋「已儲存憑證」", async () => {
    stubRoutedFetch([ { match: "query shopPaymentProviderList", body: LIST } ]);
    renderAt("/admin/settings/payments");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText(/測試模式生效中/)).toBeVisible();
    expect(main.getByText("已儲存憑證")).toBeVisible();
    expect(main.getByText("card")).toBeVisible();
    expect(main.getByText("alipayhk")).toBeVisible();
  });
});

describe("設定 › 付款（provider 詳情頁）", () => {
  beforeEach(() => installCsrfMeta());

  it("渲染 About／憑證／付款方式三卡；toggle 反映 enabledMethods", async () => {
    stubRoutedFetch([ { match: "query shopPaymentProviderDetail", body: DETAIL } ]);
    renderAt("/admin/settings/payments/airwallex");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("關於")).toBeVisible();
    expect(main.getByText("憑證")).toBeVisible();
    expect(main.getByText("付款方式")).toBeVisible();
    expect(main.getByRole("switch", { name: "AlipayHK" })).toHaveAttribute("aria-checked", "true");
    expect(main.getByRole("switch", { name: "FPS" })).toHaveAttribute("aria-checked", "false");
    expect(main.getAllByText(/3229db23516d9173/).length).toBeGreaterThan(0);
  });

  it("🔴 祕密留空＝不送參數；enabledMethods 隨 toggle 更新後送出", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query shopPaymentProviderDetail", body: DETAIL },
      { match: "mutation shopPaymentProviderSet", body: { data: { shopPaymentProviderSet: { shopPaymentProvider: { provider: "airwallex" }, userErrors: [] } } } },
    ]);
    renderAt("/admin/settings/payments/airwallex");
    const main = within(await screen.findByRole("main"));
    await main.findByText("關於");

    // 關掉 alipayhk（可用且開啟中）；FPS 是帳號未開通 ⇒ disabled，另有專屬測試格
    await userEvent.click(main.getByRole("switch", { name: "AlipayHK" }));
    await userEvent.click(main.getByRole("button", { name: "儲存" }));

    const sets = callsTo(fetchMock, "shopPaymentProviderSet");
    expect(sets.length).toBe(1);
    const variables = (JSON.parse(String(sets[0].body)) as { variables: Record<string, unknown> }).variables;
    expect(variables.provider).toBe("airwallex");
    expect(variables.enabledMethods).toEqual([ "card" ]);
    expect("apiSecret" in variables).toBe(false);
    expect("webhookSecret" in variables).toBe(false);
  });

  it("填入祕密後儲存 ⇒ 送 apiSecret；成功後重載且輸入框清空", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query shopPaymentProviderDetail", body: DETAIL },
      { match: "mutation shopPaymentProviderSet", body: { data: { shopPaymentProviderSet: { shopPaymentProvider: { provider: "airwallex" }, userErrors: [] } } } },
    ]);
    renderAt("/admin/settings/payments/airwallex");
    const main = within(await screen.findByRole("main"));
    await main.findByText("關於");

    await userEvent.type(main.getByLabelText("API key"), "sk_new_1");
    await userEvent.click(main.getByRole("button", { name: "儲存" }));

    const variables = (JSON.parse(String(callsTo(fetchMock, "shopPaymentProviderSet")[0].body)) as { variables: Record<string, unknown> }).variables;
    expect(variables.apiSecret).toBe("sk_new_1");
    expect(callsTo(fetchMock, "query shopPaymentProviderDetail").length).toBe(2);
    expect((main.getByLabelText("API key") as HTMLInputElement).value).toBe("");
  });

  it("🔴 帳號未開通的方式：toggle disabled＋提示；「重新讀取」送 sync mutation", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query shopPaymentProviderDetail", body: DETAIL },
      { match: "mutation shopPaymentProviderSyncCapabilities", body: { data: { shopPaymentProviderSyncCapabilities: { shopPaymentProvider: { provider: "airwallex" }, userErrors: [] } } } },
    ]);
    renderAt("/admin/settings/payments/airwallex");
    const main = within(await screen.findByRole("main"));
    await main.findByText("關於");

    // FPS 不在 availableMethods（已同步）⇒ disabled＋帳號未開通提示
    expect(main.getByRole("switch", { name: "FPS" })).toBeDisabled();
    expect(main.getAllByText("你的服務商帳號尚未開通此方式").length).toBe(1);

    await userEvent.click(main.getByRole("button", { name: "重新讀取可用方式" }));
    expect(callsTo(fetchMock, "shopPaymentProviderSyncCapabilities").length).toBe(1);
    // 成功後重載
    expect(callsTo(fetchMock, "query shopPaymentProviderDetail").length).toBe(2);
  });

  it("未知 provider ⇒ 顯示錯誤與返回連結，不打 API", async () => {
    const fetchMock = stubRoutedFetch([]);
    renderAt("/admin/settings/payments/stripe");
    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("未知的付款服務商。")).toBeVisible();
    expect(fetchMock.mock.calls.length).toBe(0);
  });
});
