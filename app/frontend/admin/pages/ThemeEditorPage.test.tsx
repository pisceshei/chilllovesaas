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

function stubFetch() {
  const fetchMock = vi.fn(async () => ({
    json: vi.fn().mockResolvedValue(BOOTSTRAP), ok: true, status: 200,
  } as unknown as Response));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
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
    const nodes = tree.getAllByRole("button");
    expect(nodes.map((node) => node.textContent?.trim())).toEqual([ "hero", "blocks-demo" ]);
    expect(tree.getByLabelText("已隱藏")).toBeInTheDocument(); // disabled 眼睛態
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

    fireEvent.click(tree.getByRole("button", { name: /hero/ }));
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByText("首頁英雄")).toBeInTheDocument();
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
    expect(await settings.findByText("首頁英雄")).toBeInTheDocument();
  });
});
