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

const EMPTY_LIST = { data: { shopPaymentProviders: [] } };
const CONFIGURED_LIST = {
  data: {
    shopPaymentProviders: [
      {
        provider: "airwallex",
        environment: "production",
        status: "inactive",
        clientId: "cid_live_1",
        webhookId: null,
        apiSecretFingerprint: "3229db23516d9173",
        webhookSecretFingerprint: null,
      },
    ],
  },
};

function renderPayments() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/settings/payments" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// G6-3 前半：祕密 write-only（37 §6.3——後端只回指紋；留空＝省略參數＝保持不變）。
describe("設定 › 付款", () => {
  beforeEach(() => installCsrfMeta());

  it("兩個 provider 卡都渲染；未設定顯示「未設定」", async () => {
    stubRoutedFetch([ { match: "query shopPaymentProviderList", body: EMPTY_LIST } ]);
    renderPayments();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("Airwallex")).toBeVisible();
    expect(main.getByText("PayPal")).toBeVisible();
    expect(main.getAllByText("未設定").length).toBe(2);
  });

  it("已設定：顯示指紋提示與「已儲存憑證」；test mode 反映 production", async () => {
    stubRoutedFetch([ { match: "query shopPaymentProviderList", body: CONFIGURED_LIST } ]);
    renderPayments();

    const main = within(await screen.findByRole("main"));
    expect(await main.findByText("已儲存憑證")).toBeVisible();
    expect(main.getAllByText(/3229db23516d9173/).length).toBeGreaterThan(0);
    // production 列的 test mode 開關為關（sandbox=false）
    const switches = main.getAllByRole("switch", { name: /測試模式/ });
    expect(switches[0]).toHaveAttribute("aria-checked", "false");
    expect(switches[1]).toHaveAttribute("aria-checked", "true");
  });

  it("🔴 祕密留空＝不送該參數（write-only：不得把既有 key 清掉）", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query shopPaymentProviderList", body: CONFIGURED_LIST },
      { match: "mutation shopPaymentProviderSet", body: { data: { shopPaymentProviderSet: { shopPaymentProvider: { provider: "airwallex" }, userErrors: [] } } } },
    ]);
    renderPayments();
    const main = within(await screen.findByRole("main"));
    await main.findByText("Airwallex");

    const saveButtons = main.getAllByRole("button", { name: "儲存" });
    await userEvent.click(saveButtons[0]);

    const sets = callsTo(fetchMock, "shopPaymentProviderSet");
    expect(sets.length).toBe(1);
    const variables = (JSON.parse(String(sets[0].body)) as { variables: Record<string, unknown> }).variables;
    expect(variables.provider).toBe("airwallex");
    expect(variables.environment).toBe("production");
    expect(variables.clientId).toBe("cid_live_1");
    expect("apiSecret" in variables).toBe(false);
    expect("webhookSecret" in variables).toBe(false);
  });

  it("填入祕密後儲存：送出 apiSecret，成功後重載且輸入框清空", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query shopPaymentProviderList", body: EMPTY_LIST },
      { match: "mutation shopPaymentProviderSet", body: { data: { shopPaymentProviderSet: { shopPaymentProvider: { provider: "airwallex" }, userErrors: [] } } } },
    ]);
    renderPayments();
    const main = within(await screen.findByRole("main"));
    await main.findByText("Airwallex");

    await userEvent.type(main.getAllByLabelText("Client ID")[0], "cid_test");
    await userEvent.type(main.getByLabelText("API key"), "sk_test_123");
    await userEvent.click(main.getAllByRole("button", { name: "儲存" })[0]);

    const sets = callsTo(fetchMock, "shopPaymentProviderSet");
    expect(sets.length).toBe(1);
    const variables = (JSON.parse(String(sets[0].body)) as { variables: Record<string, unknown> }).variables;
    expect(variables.apiSecret).toBe("sk_test_123");
    expect(variables.environment).toBe("sandbox");
    // 成功後重載（初載＋重載＝2 次 query），祕密輸入框回空
    expect(callsTo(fetchMock, "query shopPaymentProviderList").length).toBe(2);
    expect((main.getByLabelText("API key") as HTMLInputElement).value).toBe("");
  });

  it("userError 走 toast，不重載列表", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query shopPaymentProviderList", body: EMPTY_LIST },
      { match: "mutation shopPaymentProviderSet", body: { data: { shopPaymentProviderSet: { shopPaymentProvider: null, userErrors: [ { field: [ "provider" ], message: "provider 不在平台 pack 字典內", code: "PROVIDER_UNKNOWN" } ] } } } },
    ]);
    renderPayments();
    const main = within(await screen.findByRole("main"));
    await main.findByText("Airwallex");

    await userEvent.click(main.getAllByRole("button", { name: "儲存" })[0]);
    expect(await screen.findByText("provider 不在平台 pack 字典內")).toBeVisible();
    expect(callsTo(fetchMock, "query shopPaymentProviderList").length).toBe(1);
  });
});
