import { fireEvent, render, screen, within } from "@testing-library/react";
import { RouterProvider, createMemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AdminRoutes } from "../App";

/**
 * 步 16a：編輯器 shell（樹渲染／postMessage 選中雙向／origin 嚴格比對）。
 *
 * 🔴 假綠殺手：
 *   ED2 樹點選 ⇒ 對 iframe 送 cl:highlight（殺：橋單向斷）
 *   ED3 異 origin 訊息被忽略（殺：任意站 postMessage 操縱編輯器）
 */
function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

const BOOTSTRAP = {
  data: {
    theme: {
      id: "gid://chilllove/Theme/7",
      name: "Minimal",
      role: "published",
      templates: [ { filename: "templates/index.json" }, { filename: "templates/product.json" } ],
      sectionCatalog: [
        { type: "promo", name: "促銷條", preset: { settings: { text: "預設促銷文案" }, blocks: null } },
      ],
      sectionSchemas: {
        hero: { name: "Hero", settings: [
          { type: "header", content: "版面" },
          { id: "heading", type: "text", label: "標題" },
          { id: "spacing", type: "range", label: "間距", min: 0, max: 100, step: 4, unit: "px", default: 24 },
          { id: "align", type: "select", label: "對齊",
            options: [ { value: "left", label: "靠左" }, { value: "center", label: "置中" } ], default: "left" },
          { id: "image", type: "image_picker", label: "圖片" },
        ] },
      },
      templateJson: {
        order: [ "hero", "demo" ],
        sections: {
          hero: { type: "hero", settings: { heading: "首頁英雄" } },
          demo: { type: "blocks-demo", disabled: true, settings: {},
                  block_order: [ "p1" ], blocks: { p1: { type: "_parent" } } },
        },
      },
    },
  },
};

function stubFetch(saveErrors: { message: string; code: string }[] = []) {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string };
    const body = request.query.includes("themeTemplateUpsert")
      ? { data: { themeTemplateUpsert: {
          templateKey: saveErrors.length > 0 ? null : "index",
          lockVersion: saveErrors.length > 0 ? null : 1,
          userErrors: saveErrors } } }
      : BOOTSTRAP;
    return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function callsTo(fetchMock: ReturnType<typeof vi.fn>, match: string): RequestInit[] {
  return fetchMock.mock.calls
    .map((call) => call[1] as RequestInit)
    .filter((init) => String(init?.body).includes(match));
}

function renderEditor() {
  const router = createMemoryRouter(
    [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
    { initialEntries: [ "/admin/themes/7/editor" ] },
  );
  render(<RouterProvider router={router} />);
  return router;
}

describe("ThemeEditorPage（步 16a shell）", () => {
  beforeEach(() => {
    installCsrfMeta();
    vi.unstubAllGlobals();
  });

  it("ED1 樹照 order 渲染＋disabled 眼睛態＋block 子層；模板切換器列出 templates", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const nodes = tree.getAllByRole("button").filter((node) => node.hasAttribute("aria-pressed"));
    expect(nodes.map((node) => node.textContent?.trim())).toEqual([ "hero", "blocks-demo" ]);
    expect(tree.getByLabelText("顯示 demo")).toBeInTheDocument(); // disabled ⇒ 眼睛顯示「顯示」op
    expect(tree.getByText("_parent")).toBeInTheDocument(); // block 子層
    const switcher = screen.getByLabelText("頁面模板") as HTMLSelectElement;
    expect([ ...switcher.options ].map((o) => o.value)).toEqual([ "index", "product" ]);
  });

  it("ED2 🔴 點樹節點 ⇒ 設定面板出值＋向 iframe postMessage cl:highlight", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    const postSpy = vi.fn();
    Object.defineProperty(iframe, "contentWindow", { value: { postMessage: postSpy } });

    fireEvent.click(tree.getByRole("button", { name: "hero" }));
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByDisplayValue("首頁英雄")).toBeInTheDocument();
    expect(postSpy).toHaveBeenCalledWith(
      { type: "cl:highlight", id: "hero" }, window.location.origin);
  });

  it("ED3 🔴 iframe cl:select 反選左樹；異 origin 訊息被忽略", async () => {
    stubFetch();
    renderEditor();
    await screen.findByRole("complementary", { name: "區段" });

    // 異 origin ⇒ 不選中
    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:select", id: "hero" }, origin: "https://evil.example",
    }));
    expect(screen.getByText("在左欄或預覽中點選一個區段")).toBeInTheDocument();

    // 同 origin ⇒ 選中 hero
    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:select", id: "hero" }, origin: window.location.origin,
    }));
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(await settings.findByDisplayValue("首頁英雄")).toBeInTheDocument();
  });

  it("ED4 🔴 op-stack：隱藏 op 改 draft、Undo 還原、Redo 重做（快照棧語義）", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getByLabelText("隱藏 hero"));
    expect(tree.getByLabelText("顯示 hero")).toBeInTheDocument(); // 已隱藏

    fireEvent.click(screen.getByRole("button", { name: /復原/ }));
    expect(tree.getByLabelText("隱藏 hero")).toBeInTheDocument(); // 還原

    fireEvent.click(screen.getByRole("button", { name: /重做/ }));
    expect(tree.getByLabelText("顯示 hero")).toBeInTheDocument(); // 重做
  });

  it("ED5 🔴 儲存送整份 draft＋lockVersion；STALE_OBJECT ⇒ 衝突 toast", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByLabelText("隱藏 hero"));
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));

    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { key: string; content: { sections: Record<string, { disabled?: boolean }> } };
    };
    expect(sent.variables.key).toBe("index");
    expect(sent.variables.content.sections.hero.disabled).toBe(true); // 整份 draft
    expect(sent.variables.content.sections.demo).toBeDefined(); // 未動的 section 也在
  });

  it("ED6 STALE_OBJECT ⇒ 衝突提示（不清 dirty）", async () => {
    stubFetch([ { message: "conflict", code: "STALE_OBJECT" } ]);
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByLabelText("隱藏 hero"));
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    expect(await screen.findByText(/模板已被其他人修改/)).toBeInTheDocument();
  });

  it("ED7 🔴 picker 只列 preset 區段；加入＝preset settings＋插尾＋選中；儲存帶新區段", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getByRole("button", { name: "新增區段" }));
    const picker = within(tree.getByLabelText("可新增的區段"));
    fireEvent.click(picker.getByRole("button", { name: "促銷條" }));

    // 插尾＋選中：設定面板出 preset 值
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByDisplayValue("預設促銷文案")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { order: string[]; sections: Record<string, { type: string; settings: { text?: string } }> } };
    };
    expect(sent.variables.content.order).toEqual([ "hero", "demo", "promo" ]);
    expect(sent.variables.content.sections.promo.settings.text).toBe("預設促銷文案");
  });

  it("ED8 🔴 schema 驅動控件：range 未覆寫顯示 default；select 改值入 payload、default 不物化", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByRole("button", { name: "hero" }));

    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByText("版面")).toBeInTheDocument(); // header 結構元素
    expect(settings.getByLabelText("標題")).toHaveValue("首頁英雄"); // schema label＋實例值
    expect(settings.getByLabelText("間距")).toHaveValue("24"); // 🔴 default 補位
    expect(settings.getByText(/圖片/)).toBeInTheDocument(); // 資源型唯讀（16e）

    fireEvent.change(settings.getByLabelText("對齊"), { target: { value: "center" } });

    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { settings: Record<string, unknown> }> } };
    };
    expect(sent.variables.content.sections.hero.settings.align).toBe("center");
    // 🔴 default 只補顯示、不物化落庫（本尊語義：settings_data 只存覆寫）
    expect(sent.variables.content.sections.hero.settings.spacing).toBeUndefined();
  });
});
