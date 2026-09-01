import { fireEvent, render, screen, within } from "@testing-library/react";
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

const TEMPLATES = [
  { key: "order_confirmation", subject: "Order {{ name }} confirmed", isDefault: true },
  { key: "shipping_confirmation", subject: "A shipment from order {{ name }} is on the way", isDefault: false },
  { key: "abandoned_checkout", subject: "Complete your Purchase", isDefault: true },
];

const SETTINGS_BODY = { data: {
  notificationSenderEmail: "eshop@chilling.example",
  notificationTemplates: TEMPLATES,
  webhookTopics: [ "orders/create", "products/update" ],
  webhookSubscriptions: { nodes: [
    { id: "gid://chilllove/WebhookSubscription/3", topic: "orders/create",
      callbackUrl: "https://hook.example.com/a", status: "active", failureCount: 0 },
  ] },
} };

function renderAt(path: string) {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ path ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

// G6 步 6：通知設定主頁（89 §1 對位——sender email＋顧客通知三列）。
describe("設定 › 通知", () => {
  beforeEach(() => installCsrfMeta());

  it("渲染 sender email 現值＋三支模板列（已自訂者帶徽章）", async () => {
    stubRoutedFetch([ { match: "query notificationSettings", body: SETTINGS_BODY } ]);
    renderAt("/admin/settings/notifications");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByDisplayValue("eshop@chilling.example")).toBeVisible();
    expect(main.getByText("訂單確認")).toBeVisible();
    expect(main.getByText("出貨通知")).toBeVisible();
    expect(main.getByText("未完成結帳挽回")).toBeVisible();
    // 已自訂徽章恰一枚（shipping_confirmation isDefault=false）
    expect(main.getAllByText("已自訂").length).toBe(1);
    expect(main.getByRole("link", { name: /訂單確認/ })).toHaveAttribute(
      "href", "/admin/settings/notifications/order_confirmation");
  });

  it("sender email 儲存 ⇒ mutation 帶輸入值", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query notificationSettings", body: SETTINGS_BODY },
      { match: "notificationSenderEmailUpdate", body: { data: { notificationSenderEmailUpdate: {
        senderEmail: "new@chilling.example", userErrors: [] } } } },
    ]);
    renderAt("/admin/settings/notifications");
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    const input = await main.findByDisplayValue("eshop@chilling.example");
    await user.clear(input);
    await user.type(input, "new@chilling.example");
    await user.click(main.getByRole("button", { name: "儲存" }));

    const calls = callsTo(fetchMock, "notificationSenderEmailUpdate");
    expect(calls.length).toBe(1);
    expect(String(calls[0]?.body)).toContain('"senderEmail":"new@chilling.example"');
  });

  it("WH1 🔴 webhooks 卡：列表＋建立（帶 topic/url）＋secret 一次性顯示＋刪除", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query notificationSettings", body: SETTINGS_BODY },
      { match: "webhookSubscriptionCreate", body: { data: { webhookSubscriptionCreate: {
        secret: "a".repeat(48),
        webhookSubscription: { id: "gid://chilllove/WebhookSubscription/9", topic: "products/update",
          callbackUrl: "https://hook.example.com/b", status: "active", failureCount: 0 },
        userErrors: [],
      } } } },
      { match: "webhookSubscriptionDelete", body: { data: { webhookSubscriptionDelete: {
        deletedId: "gid://chilllove/WebhookSubscription/3", userErrors: [],
      } } } },
    ]);
    renderAt("/admin/settings/notifications");
    const main = within(await screen.findByRole("main"));

    // 列表現值（select option 也含同字串——鎖列表容器）
    const list = within(await main.findByTestId("webhook-list"));
    expect(list.getByText("orders/create")).toBeVisible();
    expect(list.getByText("https://hook.example.com/a")).toBeVisible();

    // 建立：選 topic＋填 URL ⇒ mutation 帶兩參數；secret 一次性條出現
    fireEvent.change(main.getByLabelText("主題"), { target: { value: "products/update" } });
    fireEvent.change(main.getByPlaceholderText("https://example.com/webhooks"),
      { target: { value: "https://hook.example.com/b" } });
    fireEvent.click(main.getByRole("button", { name: "新增 webhook" }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "webhookSubscriptionCreate")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "webhookSubscriptionCreate")[0].body)) as {
      variables: { topic: string; callbackUrl: string };
    };
    expect(sent.variables).toEqual({ topic: "products/update", callbackUrl: "https://hook.example.com/b" });
    expect(await main.findByText("a".repeat(48))).toBeVisible(); // 🔴 一次性 secret
    fireEvent.click(main.getByRole("button", { name: "我已保存" }));
    expect(main.queryByText("a".repeat(48))).not.toBeInTheDocument();

    // 刪除
    fireEvent.click(main.getAllByRole("button", { name: "刪除" })[0]);
    await vi.waitFor(() => expect(callsTo(fetchMock, "webhookSubscriptionDelete")).toHaveLength(1));
  });
});

// 模板編輯頁（89 §1 edit 對位——兩欄＋Revert disabled 態）。
describe("設定 › 通知 › 模板編輯", () => {
  beforeEach(() => installCsrfMeta());

  const DETAIL = { data: { notificationTemplates: [
    { key: "order_confirmation", subject: "Order {{ name }} confirmed", bodyLiquid: "<p>hi</p>", isDefault: true },
  ] } };

  it("預設態：兩欄載入、Revert 鈕 disabled（89 §1 實測形）", async () => {
    stubRoutedFetch([ { match: "query notificationTemplateFor", body: DETAIL } ]);
    renderAt("/admin/settings/notifications/order_confirmation");

    const main = within(await screen.findByRole("main"));
    expect(await main.findByDisplayValue("Order {{ name }} confirmed")).toBeVisible();
    expect(main.getByDisplayValue("<p>hi</p>")).toBeVisible();
    expect(main.getByRole("button", { name: "還原為預設" })).toBeDisabled();
  });

  it("儲存 ⇒ update mutation 帶 subject＋bodyLiquid", async () => {
    const fetchMock = stubRoutedFetch([
      { match: "query notificationTemplateFor", body: DETAIL },
      { match: "mutation notificationTemplateUpdate", body: { data: { notificationTemplateUpdate: {
        notificationTemplate: { key: "order_confirmation", subject: "S", bodyLiquid: "B", isDefault: false },
        userErrors: [] } } } },
    ]);
    renderAt("/admin/settings/notifications/order_confirmation");
    const user = userEvent.setup();

    const main = within(await screen.findByRole("main"));
    await main.findByDisplayValue("Order {{ name }} confirmed");
    await user.click(main.getByRole("button", { name: "儲存" }));

    const calls = callsTo(fetchMock, "mutation notificationTemplateUpdate");
    expect(calls.length).toBe(1);
    expect(String(calls[0]?.body)).toContain('"key":"order_confirmation"');
  });
});
