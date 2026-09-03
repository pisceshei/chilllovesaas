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
      // E2：模板選擇器資料（product.custom 只在 DB；指派計數鍵 ""＝預設）
      templateKeys: [ "index", "product", "product.custom" ],
      templateAssignments: { product: { "": 3 }, collection: {}, page: {}, blog: {}, article: {} },
      sectionGroups: [
        { name: "header-group", path: "sections/header-group.json",
          json: { sections: { gh: { type: "hero", settings: { heading: "群組頁首" } } }, order: [ "gh" ] },
          lockVersion: null },
      ],
      sectionCatalog: [
        { type: "promo", name: "促銷條", preset: { settings: { text: "預設促銷文案" }, blocks: null } },
      ],
      settingsSchema: [
        { name: "Colors", settings: [
          { id: "brand_color", type: "color", label: "品牌色", default: "#000000" },
        ] },
      ],
      themeSettingsJson: { brand_color: "#a9502c" },
      themeSettingsLockVersion: null,
      sectionSchemas: {
        "blocks-demo": { name: "Blocks demo", settings: [], max_blocks: 3, blocks: [
          { type: "_parent", name: "父塊", settings: [
            { id: "label", type: "text", label: "標籤", default: "P" } ] },
        ] },
        hero: { name: "Hero", settings: [
          { type: "header", content: "版面" },
          { id: "heading", type: "text", label: "標題" },
          { id: "spacing", type: "range", label: "間距", min: 0, max: 100, step: 4, unit: "px", default: 24 },
          { id: "align", type: "select", label: "對齊",
            options: [ { value: "left", label: "靠左" }, { value: "center", label: "居中" } ], default: "left" }, // 2 個短選項 ⇒ 分段（E10）
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

function stubFetch(saveErrors: { message: string; code: string }[] = [], bootstrap: typeof BOOTSTRAP = BOOTSTRAP) {
  const fetchMock = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body)) as { query: string };
    if (request.query.includes("themeFileUpsert")) {
      const fileBody = { data: { themeFileUpsert: {
        path: "sections/header-group.json", lockVersion: 0, userErrors: [] } } };
      return { json: vi.fn().mockResolvedValue(fileBody), ok: true, status: 200 } as unknown as Response;
    }
    // E2：發布與「建立模板」的 base 讀取
    if (request.query.includes("themePublish")) {
      const publishBody = { data: { themePublish: { theme: { id: "gid://chilllove/Theme/7", role: "published" }, userErrors: [] } } };
      return { json: vi.fn().mockResolvedValue(publishBody), ok: true, status: 200 } as unknown as Response;
    }
    // E3：Preview 資源列（PreviewResourceRow）的產品查詢
    if (request.query.includes("editorPreviewProducts")) {
      const productsBody = { data: { products: { nodes: [ { id: "gid://chilllove/Product/1", title: "Acme Tee", handle: "acme-tee" } ] } } };
      return { json: vi.fn().mockResolvedValue(productsBody), ok: true, status: 200 } as unknown as Response;
    }
    // E4：image_picker 的檔案庫查詢
    if (request.query.includes("editorImagePicker")) {
      const filesBody = { data: { files: { edges: [
        { node: { id: "gid://chilllove/File/1", filename: "hero.png", thumbUrl: "/media/1/hero.png?width=160", previewUrl: null, width: 1200, height: 800 } },
        { node: { id: "gid://chilllove/File/2", filename: "logo.svg", thumbUrl: null, previewUrl: null, width: null, height: null } },
      ] } } };
      return { json: vi.fn().mockResolvedValue(filesBody), ok: true, status: 200 } as unknown as Response;
    }
    if (request.query.includes("themeEditorBaseTemplate")) {
      const baseBody = { data: { theme: { templateJson: { sections: { base: { type: "hero", settings: {} } }, order: [ "base" ] } } } };
      return { json: vi.fn().mockResolvedValue(baseBody), ok: true, status: 200 } as unknown as Response;
    }
    const body = request.query.includes("themeTemplateUpsert")
      ? { data: { themeTemplateUpsert: {
          templateKey: saveErrors.length > 0 ? null : "index",
          lockVersion: saveErrors.length > 0 ? null : 1,
          userErrors: saveErrors } } }
      : request.query.includes("themeSettingsUpsert")
        ? { data: { themeSettingsUpsert: { lockVersion: 0, userErrors: [] } } }
        : bootstrap;
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
    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" })); // E3：section 預設收合
    const nodes = tree.getAllByRole("button").filter((node) => node.hasAttribute("aria-pressed"));
    // PR-5 三帶＋PR-6 block 節點：頁首帶 hero ＋ 範本帶 hero/blocks-demo（含其 _parent block）；E3 顯示名＝schema name
    expect(nodes.map((node) => node.querySelector(".cl-tree__name")?.textContent?.trim())).toEqual([ "Hero", "Hero", "Blocks demo", "父塊" ]);
    expect(tree.getByLabelText("顯示 demo")).toBeInTheDocument(); // disabled ⇒ 眼睛顯示「顯示」op
    expect(tree.getByText("父塊")).toBeInTheDocument(); // block 子層
    // E2：模板選擇器＝popover（100 §1.1）：第一層列 Home page／Products ›；Products 進子清單
    fireEvent.click(screen.getByRole("button", { name: "頁面模板" }));
    const menu = within(screen.getByRole("menu"));
    expect(menu.getByRole("menuitem", { name: /首頁/ })).toBeInTheDocument();
    expect(menu.queryByText("購物車")).toBeNull(); // 主題沒有 cart.json ⇒ 不列
    fireEvent.click(menu.getByRole("menuitem", { name: /^商品$/ }));
    expect(menu.getByText("預設商品模板")).toBeInTheDocument();
    expect(menu.getByText("已指派給 3 個商品")).toBeInTheDocument(); // assignments[product][""]
    expect(menu.getByText("custom")).toBeInTheDocument();           // DB-only 替代模板
    expect(menu.getByText("已指派給 0 個商品")).toBeInTheDocument(); // 無指派補 0
  });

  it("ED2 🔴 點樹節點 ⇒ 設定面板出值＋向 iframe postMessage cl:highlight", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    const postSpy = vi.fn();
    Object.defineProperty(iframe, "contentWindow", { value: { postMessage: postSpy } });

    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]); // 範本帶（頁首帶在前）
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByDisplayValue("首頁英雄")).toBeInTheDocument();
    expect(postSpy).toHaveBeenCalledWith(
      { type: "cl:highlight", id: "hero", blockId: null }, window.location.origin); // PR-17 起帶 blockId
  });

  it("ED3 🔴 iframe cl:select 反選左樹；異 origin 訊息被忽略", async () => {
    stubFetch();
    renderEditor();
    await screen.findByRole("complementary", { name: "區段" });

    // 異 origin ⇒ 不選中（E2：無選取時右欄不掛載——本尊兩欄形態）
    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:select", id: "hero" }, origin: "https://evil.example",
    }));
    expect(screen.queryByRole("complementary", { name: "設定" })).toBeNull();

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
    const picker = within(screen.getByRole("list", { name: "可新增的區段" })); // E5：picker portal 在樹外
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
    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]); // 範本帶（頁首帶在前）

    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByText("版面")).toBeInTheDocument(); // header 結構元素
    expect(settings.getByLabelText("標題")).toHaveValue("首頁英雄"); // schema label＋實例值
    expect(settings.getByLabelText("間距")).toHaveValue(24); // 🔴 default 補位（E4：滑桿＋數字框，取數字框）
    expect(settings.getByText("圖片", { selector: "label" })).toBeInTheDocument(); // image_picker：標籤＋Select 虛線框（E4）
    expect(settings.getByRole("button", { name: "圖片" })).toHaveTextContent("選取"); // label for ⇒ 可及名稱＝圖片

    fireEvent.click(settings.getByRole("radio", { name: "居中" })); // E10：短選項 select＝分段控制（官方三條件）

    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { settings: Record<string, unknown> }> } };
    };
    expect(sent.variables.content.sections.hero.settings.align).toBe("center");
    // 🔴 default 只補顯示、不物化落庫（本尊語義：settings_data 只存覆寫）
    expect(sent.variables.content.sections.hero.settings.spacing).toBeUndefined();
  });

  it("ED9 🔴 佈景設定：入口開分組面板、改值 Save 走 themeSettingsUpsert 整份", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(screen.getByRole("button", { name: "佈景主題設定" })); // E2：頂欄面板切換器

    const settings = within(screen.getByRole("complementary", { name: "佈景主題設定" }));
    expect(settings.getByText("Colors")).toBeInTheDocument();
    const control = settings.getByLabelText("品牌色");
    expect(control).toHaveTextContent("#A9502C"); // 生效值（DB/檔案 current）；E4：色票鈕顯示 HEX

    fireEvent.click(control); // E4：開 popover → HEX 欄 → blur 寫回
    const hex = screen.getByLabelText("Hex");
    fireEvent.change(hex, { target: { value: "123456" } });
    fireEvent.blur(hex);
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeSettingsUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeSettingsUpsert")[0].body)) as {
      variables: { settings: Record<string, unknown>; lockVersion: number | null };
    };
    expect(sent.variables.settings.brand_color).toBe("#123456");
    // 模板未動 ⇒ 不應多發 templateUpsert
    expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(0);
  });

  it("ED10 🔴 三帶樹：頁首帶出群組 section；點選出群組設定面板", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    expect(tree.getByText("Header group")).toBeInTheDocument();
    expect(tree.getByText("範本")).toBeInTheDocument();

    // 頁首帶的 hero 列（與範本帶的 hero 區分：取第一個＝頁首帶在前）
    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[0]);
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByDisplayValue("群組頁首")).toBeInTheDocument();
  });

  it("ED11 🔴 群組編輯：改值→undo 復原→redo→Save 走 themeFileUpsert（模板不發）", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[0]);

    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    const input = settings.getByDisplayValue("群組頁首");
    fireEvent.change(input, { target: { value: "改過的頁首" } });
    expect(settings.getByDisplayValue("改過的頁首")).toBeInTheDocument();

    // 跨帶 undo/redo（群組與模板同一棧）
    fireEvent.click(screen.getByRole("button", { name: /復原|Undo/i }));
    expect(settings.getByDisplayValue("群組頁首")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /重做|Redo/i }));
    expect(settings.getByDisplayValue("改過的頁首")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeFileUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeFileUpsert")[0].body)) as {
      variables: { path: string; content: string; lockVersion: number | null };
    };
    expect(sent.variables.path).toBe("sections/header-group.json");
    expect(JSON.parse(sent.variables.content).sections.gh.settings.heading).toBe("改過的頁首");
    expect(sent.variables.lockVersion).toBeNull();
    expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(0); // 模板未動不發
  });

  it("ED12 🔴 block 級：選 block 出 def 面板；改值＋add-block 帶 default；save 全入 payload", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    // 既有 _parent block（blocks-demo 之下）
    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" })); // E3：section 預設收合
    fireEvent.click(tree.getByRole("button", { name: "父塊" }));
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByRole("heading", { name: "父塊" })).toBeInTheDocument(); // E4：標題列＝type icon＋顯示名
    const labelInput = settings.getByLabelText("標籤");
    fireEvent.change(labelInput, { target: { value: "改標籤" } });

    // add-block（＋父塊）——def default 帶入新 block
    fireEvent.click(tree.getByRole("button", { name: "新增區塊" })); // E3：先開 Add block 列（E5：開 block picker）
    fireEvent.click(within(screen.getByRole("list", { name: "新增區塊" })).getByRole("button", { name: "父塊" }));

    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, {
        blocks?: Record<string, { type: string; settings?: Record<string, unknown> }>;
        block_order?: string[] } > } };
    };
    const demo = sent.variables.content.sections.demo;
    const blockIds = demo.block_order ?? [];
    expect(blockIds.length).toBe(2); // 原 _parent ＋ 新增
    const original = demo.blocks?.[blockIds[0]];
    const added = demo.blocks?.[blockIds[1]];
    expect(original?.settings?.label).toBe("改標籤");     // 🔴 block 設定寫入
    expect(added?.type).toBe("_parent");
    expect(added?.settings?.label).toBe("P");            // 🔴 add-block 帶 def default
  });

  it("ED13 🔴 即時預覽：改設定 → debounce 後 POST draft_section → cl:replace 進 iframe", async () => {
    const fetchMock = stubFetch();
    fetchMock.mockImplementation(async (url: unknown, init?: RequestInit) => {
      if (String(url).includes("/draft_section")) {
        return { ok: true, status: 200,
                 text: vi.fn().mockResolvedValue('<div id="shopify-section-hero">RE-RENDERED</div>'),
                 json: vi.fn() } as unknown as Response;
      }
      const request = JSON.parse(String(init?.body)) as { query: string };
      void request;
      return { json: vi.fn().mockResolvedValue(BOOTSTRAP), ok: true, status: 200 } as unknown as Response;
    });
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    const postSpy = vi.fn();
    Object.defineProperty(iframe, "contentWindow", { value: { postMessage: postSpy } });

    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]); // 範本帶
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    fireEvent.change(settings.getByLabelText("標題"), { target: { value: "即時標題" } });

    await vi.waitFor(() => {
      const calls = fetchMock.mock.calls.filter((c) => String(c[0]).includes("/draft_section"));
      expect(calls.length).toBeGreaterThanOrEqual(1);
      const body = JSON.parse(String((calls[0][1] as RequestInit).body)) as {
        section_id: string; entry: { settings: { heading: string } } };
      expect(body.section_id).toBe("hero");
      expect(body.entry.settings.heading).toBe("即時標題"); // 🔴 未儲存 draft 值
    }, { timeout: 2000 });
    await vi.waitFor(() => {
      expect(postSpy).toHaveBeenCalledWith(
        expect.objectContaining({ type: "cl:replace", id: "hero" }), window.location.origin);
    }, { timeout: 2000 });
  });

  it("ED14 🔴 全頁草稿刷新：改佈景設定 → debounce 後 POST draft_page（帶 settings）→ 取 token → iframe 以真實 URL（?editor=1&draft=token）重載，不用 srcdoc", async () => {
    const fetchMock = stubFetch();
    fetchMock.mockImplementation(async (url: unknown, init?: RequestInit) => {
      if (String(url).includes("/draft_page")) {
        return { ok: true, status: 200,
                 text: vi.fn().mockResolvedValue("<html><body>DRAFT-PAGE</body></html>"),
                 json: vi.fn().mockResolvedValue({ token: "tok-DRAFT-PAGE" }) } as unknown as Response;
      }
      void init;
      return { json: vi.fn().mockResolvedValue(BOOTSTRAP), ok: true, status: 200 } as unknown as Response;
    });
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    Object.defineProperty(iframe, "contentWindow", { value: { postMessage: vi.fn(), scrollY: 0 } });

    fireEvent.click(screen.getByRole("button", { name: "佈景主題設定" })); // E2：頂欄面板切換器
    const settings = within(screen.getByRole("complementary", { name: "佈景主題設定" }));
    fireEvent.click(settings.getByLabelText("品牌色")); // E4：色票鈕 → popover HEX
    const hex = screen.getByLabelText("Hex");
    fireEvent.change(hex, { target: { value: "123456" } });
    fireEvent.blur(hex);

    await vi.waitFor(() => {
      const calls = fetchMock.mock.calls.filter((c) => String(c[0]).includes("/draft_page"));
      expect(calls.length).toBeGreaterThanOrEqual(1);
      const body = JSON.parse(String((calls[0][1] as RequestInit).body)) as {
        path: string; settings: Record<string, unknown> };
      expect(body.settings.brand_color).toBe("#123456"); // 🔴 未儲存佈景設定值進通道
      expect(body.path).toBe("/"); // index 無樣本路徑 ⇒ 回落首頁
    }, { timeout: 3000 });
    await vi.waitFor(() => {
      // 🔴 E9：srcdoc 會繼承 admin 嚴格 CSP ⇒ 必須是真實 URL 重載
      expect(iframe.getAttribute("src")).toContain("?editor=1&draft=tok-DRAFT-PAGE");
      expect(iframe.srcdoc).toBe("");
    }, { timeout: 3000 });
  });

  it("ED15 🔴 undo 也驅動全頁刷新（快照棧 → draftsVersion bump）", async () => {
    const fetchMock = stubFetch();
    fetchMock.mockImplementation(async (url: unknown, init?: RequestInit) => {
      if (String(url).includes("/draft_page") || String(url).includes("/draft_section")) {
        return { ok: true, status: 200,
                 text: vi.fn().mockResolvedValue("<html><body>X</body></html>"),
                 json: vi.fn() } as unknown as Response;
      }
      void init;
      return { json: vi.fn().mockResolvedValue(BOOTSTRAP), ok: true, status: 200 } as unknown as Response;
    });
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    Object.defineProperty(iframe, "contentWindow", { value: { postMessage: vi.fn(), scrollY: 0 } });

    // 一個結構 op（隱藏 hero）→ undo：兩次都應觸發 draft_page
    fireEvent.click(tree.getByLabelText("隱藏 hero"));
    await vi.waitFor(() => {
      expect(fetchMock.mock.calls.filter((c) => String(c[0]).includes("/draft_page")).length)
        .toBeGreaterThanOrEqual(1);
    }, { timeout: 3000 });
    const before = fetchMock.mock.calls.filter((c) => String(c[0]).includes("/draft_page")).length;

    fireEvent.click(screen.getByRole("button", { name: /復原/ }));
    await vi.waitFor(() => {
      expect(fetchMock.mock.calls.filter((c) => String(c[0]).includes("/draft_page")).length)
        .toBeGreaterThan(before); // 🔴 undo 驅動預覽（fleet 軸③）
    }, { timeout: 3000 });
  });

  it("ED20 🔴 block 錨點：cl:select 帶 blockId ⇒ 直開 block 面板；樹選 block ⇒ highlight 帶 blockId", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    const postSpy = vi.fn();
    Object.defineProperty(iframe, "contentWindow", { value: { postMessage: postSpy } });

    // 預覽點 block（demo 的 p1）⇒ 選中 section＋block，面板出 block def 控件
    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:select", id: "demo", blockId: "p1" }, origin: window.location.origin,
    }));
    const settings = within(await screen.findByRole("complementary", { name: "設定" }));
    expect(await settings.findByLabelText("標籤")).toBeInTheDocument(); // _parent def 的控件

    // 樹選 block ⇒ highlight postMessage 帶 blockId（橋縮到 block 元素）
    fireEvent.click(tree.getByRole("button", { name: "父塊" }));
    await vi.waitFor(() => {
      expect(postSpy).toHaveBeenCalledWith(
        expect.objectContaining({ type: "cl:highlight", id: "demo", blockId: "p1" }),
        window.location.origin);
    });
  });

  it("ED21 🔴 Custom CSS：面板底部輸入 ⇒ 進 draft 與 save payload（官方 section properties 底部）", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]); // 範本帶
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    fireEvent.click(settings.getByRole("button", { name: "自訂 CSS" })); // E4：收合區預設收起
    fireEvent.change(settings.getByLabelText("自訂 CSS"), {
      target: { value: "p { color: red; }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));

    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { custom_css?: string }> } };
    };
    expect(sent.variables.content.sections.hero.custom_css).toBe("p { color: red; }");
  });

  it("ED22 🔴 theme 級 Custom CSS：佈景設定面板底部輸入 ⇒ save payload 帶 platform_customizations", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(screen.getByRole("button", { name: "佈景主題設定" })); // E2：頂欄面板切換器

    const panel = within(screen.getByRole("complementary", { name: "佈景主題設定" }));
    fireEvent.change(panel.getByLabelText("自訂 CSS"), {
      target: { value: "body { color: blue; }" },
    });
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));

    await vi.waitFor(() => expect(callsTo(fetchMock, "themeSettingsUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeSettingsUpsert")[0].body)) as {
      variables: { settings: { platform_customizations?: { custom_css?: string } } };
    };
    expect(sent.variables.settings.platform_customizations?.custom_css).toBe("body { color: blue; }");
  });

  it("ED23 picker 搜尋：無匹配隱藏、匹配顯示（⑤a）", async () => {
    stubFetch();
    renderEditor();
    await screen.findByRole("complementary", { name: "區段" });
    fireEvent.click(screen.getByRole("button", { name: "新增區段" }));

    const picker = within(screen.getByRole("list", { name: "可新增的區段" }));
    expect(picker.getByText("促銷條")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("搜尋區段"), { target: { value: "zzz" } }); // E5：搜尋框在清單外
    expect(picker.queryByText("促銷條")).toBeNull();

    fireEvent.change(screen.getByLabelText("搜尋區段"), { target: { value: "促銷" } });
    expect(picker.getByText("促銷條")).toBeInTheDocument();
  });

  it("ED24 🔴 預覽內導航：cl:navigate 換 iframe src＋左欄模板同步（不逃出編輯器）", async () => {
    stubFetch();
    const router = renderEditor();
    await screen.findByRole("complementary", { name: "區段" });
    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;

    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:navigate", path: "/products/rose-serum" }, origin: window.location.origin,
    }));
    expect(iframe.src).toContain("/admin/store/preview/7/products/rose-serum?editor=1");
    expect(router.state.location.search).toContain("template=product"); // 路徑→模板推斷

    // 異 origin 不處理（ED3 同軸）
    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:navigate", path: "/cart" }, origin: "https://evil.example",
    }));
    expect(iframe.src).not.toContain("/cart");
  });

  it("ED25 🔴 拖放重排：同帶 drop 重排 order（undo 可還原）；跨帶 drop 忽略", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    const nodeText = () => tree.getAllByRole("button")
      .filter((node) => node.hasAttribute("aria-pressed"))
      .map((node) => node.querySelector(".cl-tree__name")?.textContent?.trim());
    expect(nodeText()).toEqual([ "Hero", "Hero", "Blocks demo" ]);

    // 範本帶：把 demo（blocks-demo）拖到 hero 的位置 ⇒ 範本帶序反轉
    const demoRow = tree.getByText("Blocks demo").closest("li")!;
    const heroRow = tree.getAllByRole("button", { name: "Hero" })[1].closest("li")!;
    fireEvent.dragStart(demoRow);
    fireEvent.dragOver(heroRow);
    fireEvent.drop(heroRow);
    expect(nodeText()).toEqual([ "Hero", "Blocks demo", "Hero" ]);

    fireEvent.click(screen.getByRole("button", { name: /復原/ }));
    expect(nodeText()).toEqual([ "Hero", "Hero", "Blocks demo" ]); // undo 還原

    // 跨帶：把範本帶 hero 拖到頁首帶列 ⇒ 忽略（本尊同帶語義）
    const headerRow = tree.getAllByRole("button", { name: "Hero" })[0].closest("li")!;
    fireEvent.dragStart(heroRow);
    fireEvent.drop(headerRow);
    expect(nodeText()).toEqual([ "Hero", "Hero", "Blocks demo" ]);
  });

  it("ED26 🔴 block 拖放重排：同 section 內重排 block_order；跨 section 忽略", async () => {
    const twoBlocks = JSON.parse(JSON.stringify(BOOTSTRAP)) as typeof BOOTSTRAP;
    const demo = twoBlocks.data.theme!.templateJson!.sections!.demo as {
      block_order?: string[]; blocks?: Record<string, { type: string }> };
    demo.block_order = [ "p1", "p2" ];
    demo.blocks = { p1: { type: "_parent" }, p2: { type: "_parent" } };
    stubFetch([], twoBlocks);
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    const rows = () => tree.getAllByRole("button")
      .filter((node) => node.hasAttribute("aria-pressed"))
      .map((node) => node.querySelector(".cl-tree__name")?.textContent?.trim());
    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" })); // E3：section 預設收合
    expect(rows()).toEqual([ "Hero", "Hero", "Blocks demo", "父塊", "父塊" ]);

    const blockLis = tree.getAllByText("父塊").map((node) => node.closest("li")!);
    // p2 拖到 p1 位置 ⇒ block_order 反轉（可視面：眼睛序不變、但 payload 序變——
    // 以 Save payload 斷言真序）
    fireEvent.dragStart(blockLis[1]);
    fireEvent.dragOver(blockLis[0]);
    fireEvent.drop(blockLis[0]);

    // 跨 section 嘗試（儲存前）：拖到 hero 的 section 列 ⇒ 忽略——若誤動，
    // 下面單次 Save 的 payload 會露餡
    const heroRow = tree.getAllByRole("button", { name: "Hero" })[1].closest("li")!;
    fireEvent.dragStart(blockLis[0]);
    fireEvent.drop(heroRow);

    const fetchMock = window.fetch as ReturnType<typeof vi.fn>;
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { block_order?: string[] }> } };
    };
    expect(sent.variables.content.sections.demo.block_order).toEqual([ "p2", "p1" ]); // 🔴 真重排＋跨區無汙染
  });

  it("ED27 🔴 預覽 hover 工具列 cl:op：remove/duplicate 映射既有 op（undo 可還原）；異 origin 忽略", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const nodeText = () => tree.getAllByRole("button")
      .filter((node) => node.hasAttribute("aria-pressed"))
      .map((node) => node.querySelector(".cl-tree__name")?.textContent?.trim());
    expect(nodeText()).toEqual([ "Hero", "Hero", "Blocks demo" ]);

    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:op", op: "remove", id: "demo" }, origin: window.location.origin,
    }));
    expect(nodeText()).toEqual([ "Hero", "Hero" ]); // demo（含其 block）移除

    fireEvent.click(screen.getByRole("button", { name: /復原/ }));
    expect(nodeText()).toEqual([ "Hero", "Hero", "Blocks demo" ]); // applyOp ⇒ undo 直達

    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:op", op: "duplicate", id: "hero" }, origin: window.location.origin,
    }));
    expect(nodeText()?.filter((x) => x === "Hero")).toHaveLength(3); // 範本帶 hero 複本

    // 異 origin ⇒ 忽略（ED3 同軸）
    fireEvent(window, new MessageEvent("message", {
      data: { type: "cl:op", op: "remove", id: "hero" }, origin: "https://evil.example",
    }));
    expect(nodeText()?.filter((x) => x === "Hero")).toHaveLength(3);
  });

  it("ED16 行動版切換：iframe 收窄 390px、再按還原；published 出「作用中」badge", async () => {
    stubFetch();
    renderEditor();
    await screen.findByRole("complementary", { name: "區段" });
    expect(screen.getByText("作用中")).toBeInTheDocument(); // 24 §1.1 badge

    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    fireEvent.click(screen.getByRole("button", { name: /行動版/ }));
    expect(iframe.style.width).toBe("390px"); // 24 §1.1 📱 行動版
    expect(iframe.className).toContain("cl-editor__iframe--mobile");
    // E2：本尊 tooltip 逐字 "Show mobile view"／"Show desktop view" 隨狀態切換（100 §1 右 3）
    fireEvent.click(screen.getByRole("button", { name: /桌面版/ }));
    expect(iframe.style.width).toBe("");
  });

  it("ED17 🔴 Ctrl+Z/Ctrl+Shift+Z＝undo/redo（輸入框內不攔）", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getByLabelText("隱藏 hero"));
    expect(tree.getByLabelText("顯示 hero")).toBeInTheDocument();

    fireEvent.keyDown(window, { key: "z", ctrlKey: true });
    expect(tree.getByLabelText("隱藏 hero")).toBeInTheDocument(); // undo

    fireEvent.keyDown(window, { key: "z", ctrlKey: true, shiftKey: true });
    expect(tree.getByLabelText("顯示 hero")).toBeInTheDocument(); // redo
  });

  it("ED18 🔴 狀態 URL 化：點選 section 帶 ?section=；佈景設定帶 ?context=theme（24 §1.1）", async () => {
    stubFetch();
    const router = renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]);
    expect(router.state.location.search).toContain("section=hero");

    fireEvent.click(screen.getByRole("button", { name: "佈景主題設定" })); // E2：頂欄面板切換器
    expect(router.state.location.search).toContain("context=theme");
    expect(router.state.location.search).not.toContain("section=hero");
  });

  it("ED19 設定面板底部「移除區段」：移除選中 section 並清選取", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]); // 範本帶 hero
    fireEvent.click(screen.getByRole("button", { name: /移除區段/ }));

    // 範本帶只剩 blocks-demo（頁首帶的 hero 不受影響）
    const nodes = tree.getAllByRole("button").filter((node) => node.hasAttribute("aria-pressed"));
    expect(nodes.map((node) => node.querySelector(".cl-tree__name")?.textContent?.trim())).toEqual([ "Hero", "Blocks demo" ]);
    expect(screen.queryByRole("complementary", { name: "設定" })).toBeNull(); // E2：清選取 ⇒ 右欄收起
  });

  // ── E2（D79 shell＋頂欄；`docs/research/100` §1／§5／§6／§7 對位）──
  // 🔴 假綠殺手：
  //   ED28 面板切換器＝三面板互斥＋再點已啟用者 ⇒ 全寬（殺：fullscreen 不寫 URL／不收兩欄）
  //   ED29 建立模板＝base 模板 JSON → upsert(`type.name`) → 切到新 key（殺：空內容／不切模板）
  //   ED30 右欄只在選取時掛載，× 清 URL section（殺：常駐右欄）
  //   ED31 離開有未存變更必經確認框，Stay 不離開（殺：靜默丟棄）
  //   ED32 Publish＝先存再 themePublish（殺：未存就發布 ⇒ 顧客看到舊版）
  //   ED33 快捷鍵單一表：Ctrl+S／Ctrl+/／Ctrl+Alt+2／Ctrl+Alt+I／Ctrl+Shift+H／Esc／Shift+⌫
  //   ED34 block 選取寫 `block=`；ED35 佈景設定手風琴寫 `category=`
  it("ED28 🔴 面板切換器：apps 面板＋context=apps；再點已啟用的 Sections ⇒ 全寬預覽（previewMode=fullscreen）", async () => {
    stubFetch();
    const router = renderEditor();
    await screen.findByRole("complementary", { name: "區段" });

    fireEvent.click(screen.getByRole("button", { name: "應用程式嵌入" }));
    expect(screen.getByRole("complementary", { name: "應用程式嵌入" })).toBeInTheDocument();
    expect(screen.getByText("尚未安裝任何提供嵌入的應用程式。")).toBeInTheDocument();
    expect(router.state.location.search).toContain("context=apps");
    expect(screen.queryByRole("complementary", { name: "區段" })).toBeNull(); // 三面板互斥

    fireEvent.click(screen.getByRole("button", { name: "區段" }));
    expect(screen.getByRole("complementary", { name: "區段" })).toBeInTheDocument();
    expect(router.state.location.search).not.toContain("context=");

    fireEvent.click(screen.getByRole("button", { name: "區段" })); // 再點已啟用者 ⇒ 全寬
    expect(screen.queryByRole("complementary")).toBeNull();
    expect(router.state.location.search).toContain("previewMode=fullscreen");
    expect(screen.getByTitle("主題預覽")).toBeInTheDocument(); // 預覽仍在

    fireEvent.click(screen.getByRole("button", { name: "區段" })); // 再點 ⇒ 還原
    expect(screen.getByRole("complementary", { name: "區段" })).toBeInTheDocument();
    expect(router.state.location.search).not.toContain("previewMode");
  });

  it("ED29 🔴 模板選擇器：選替代模板寫 ?template=；Create template ⇒ base JSON → upsert(product.name) → 切到新模板", async () => {
    const fetchMock = stubFetch();
    const router = renderEditor();
    await screen.findByRole("complementary", { name: "區段" });

    fireEvent.click(screen.getByRole("button", { name: "頁面模板" }));
    fireEvent.click(within(screen.getByRole("menu")).getByRole("menuitem", { name: /^商品$/ }));
    fireEvent.click(within(screen.getByRole("menu")).getByRole("menuitem", { name: /custom/ }));
    expect(router.state.location.search).toContain("template=product.custom");
    expect(screen.getByRole("button", { name: "頁面模板" })).toHaveTextContent("custom"); // 觸發鈕文字＝替代名

    fireEvent.click(screen.getByRole("button", { name: "頁面模板" }));
    fireEvent.click(within(screen.getByRole("menu")).getByRole("button", { name: "建立模板" }));
    const dialog = within(await screen.findByRole("dialog", { name: "建立模板" }));
    expect(dialog.getByRole("button", { name: "建立模板" })).toBeDisabled(); // 名稱空 ⇒ 灰
    fireEvent.change(dialog.getByLabelText("名稱"), { target: { value: "custom" } });
    expect(dialog.getByRole("alert")).toHaveTextContent("已有同名模板。");          // 同名擋
    fireEvent.change(dialog.getByLabelText("名稱"), { target: { value: "promo" } });
    fireEvent.click(dialog.getByRole("button", { name: "建立模板" }));

    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { key: string; content: { order: string[] }; lockVersion: number | null };
    };
    expect(sent.variables.key).toBe("product.promo");
    expect(sent.variables.content.order).toEqual([ "base" ]); // 🔴 內容＝base 模板 JSON（themeEditorBaseTemplate）
    expect(sent.variables.lockVersion).toBeNull();
    await vi.waitFor(() => expect(router.state.location.search).toContain("template=product.promo"));
  });

  it("ED30 🔴 右欄只在選取時掛載；× 關閉 ⇒ 清選取＋URL 去 section", async () => {
    stubFetch();
    const router = renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    expect(screen.queryByRole("complementary", { name: "設定" })).toBeNull();

    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]);
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByRole("heading", { name: "Hero" })).toBeInTheDocument(); // 面板標題＝schema name
    fireEvent.click(settings.getByRole("button", { name: "關閉" }));
    expect(screen.queryByRole("complementary", { name: "設定" })).toBeNull();
    expect(router.state.location.search).not.toContain("section=");
  });

  it("ED31 🔴 Exit：無變更直接離開；有未存變更 ⇒ 「離開頁面並放棄未儲存的變更？」Stay 留下、Leave page 離開", async () => {
    stubFetch();
    const router = renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getByLabelText("隱藏 hero")); // dirty
    fireEvent.click(screen.getByRole("button", { name: "離開" }));
    const dialog = within(await screen.findByRole("dialog", { name: "離開頁面並放棄未儲存的變更？" }));
    expect(dialog.getByText("離開此頁會刪除所有未儲存的變更。")).toBeInTheDocument();
    fireEvent.click(dialog.getByRole("button", { name: "留在此頁" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(router.state.location.pathname).toBe("/admin/themes/7/editor"); // 沒離開

    fireEvent.click(screen.getByRole("button", { name: "離開" }));
    fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "離開頁面" }));
    await vi.waitFor(() => expect(router.state.location.pathname).toBe("/admin/store"));
  });

  it("ED32 🔴 Publish：「儲存並發布 Minimal？」確認 ⇒ 有變更先 themeTemplateUpsert 再 themePublish", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByLabelText("隱藏 hero"));

    fireEvent.click(screen.getByRole("button", { name: "發布" }));
    const dialog = within(await screen.findByRole("dialog", { name: "儲存並發布 Minimal？" }));
    expect(dialog.getByText("顧客造訪線上商店時會看到此主題。")).toBeInTheDocument();
    fireEvent.click(dialog.getByRole("button", { name: "發布" }));

    await vi.waitFor(() => expect(callsTo(fetchMock, "themePublish")).toHaveLength(1));
    const order = fetchMock.mock.calls.map((call) => String((call[1] as RequestInit)?.body ?? ""));
    const saveIndex = order.findIndex((body) => body.includes("themeTemplateUpsert"));
    const publishIndex = order.findIndex((body) => body.includes("themePublish"));
    expect(saveIndex).toBeGreaterThan(-1);
    expect(saveIndex).toBeLessThan(publishIndex); // 🔴 先存再發布
    expect(await screen.findByText("主題已發布。")).toBeInTheDocument();
  });

  it("ED33 🔴 快捷鍵（單一表）：Ctrl+S 存、Ctrl+/ 開表、Ctrl+Alt+2 面板、Ctrl+Alt+I 手機、Ctrl+Shift+H 隱藏、Esc 取消選取、Shift+⌫ 移除", async () => {
    const fetchMock = stubFetch();
    const router = renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;

    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]);
    fireEvent.keyDown(window, { key: "h", ctrlKey: true, shiftKey: true });
    expect(tree.getByLabelText("顯示 hero")).toBeInTheDocument(); // Ctrl+Shift+H 隱藏選中

    fireEvent.keyDown(window, { key: "s", ctrlKey: true });
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1)); // Ctrl+S

    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByRole("complementary", { name: "設定" })).toBeNull(); // Esc 取消選取
    expect(router.state.location.search).not.toContain("section=");

    fireEvent.keyDown(window, { key: "i", ctrlKey: true, altKey: true });
    expect(iframe.style.width).toBe("390px"); // Ctrl+Alt+I 手機檢視

    fireEvent.keyDown(window, { key: "2", ctrlKey: true, altKey: true });
    expect(screen.getByRole("complementary", { name: "佈景主題設定" })).toBeInTheDocument(); // Ctrl+Alt+2

    fireEvent.keyDown(window, { key: "/", ctrlKey: true });
    const dialog = within(await screen.findByRole("dialog", { name: "鍵盤快捷鍵" }));
    expect(dialog.getByText("區段與區塊")).toBeInTheDocument();
    expect(dialog.getByText("查看所有快捷鍵")).toBeInTheDocument();

    // modal 開著時快捷鍵全部不攔（#admin-root inert）：Ctrl+Alt+1 不切面板
    fireEvent.keyDown(window, { key: "1", ctrlKey: true, altKey: true });
    expect(screen.getByRole("complementary", { name: "佈景主題設定" })).toBeInTheDocument();
  });

  it("ED33b 🔴 Shift+⌫ 移除選中 section（輸入框內不攔）", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]);

    // 輸入框內按 Shift+⌫ ⇒ 不移除（原生文字編輯先行）
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    fireEvent.keyDown(settings.getByLabelText("標題"), { key: "Backspace", shiftKey: true });
    expect(tree.getAllByRole("button", { name: "Hero" })).toHaveLength(2);

    fireEvent.keyDown(window, { key: "Backspace", shiftKey: true });
    expect(tree.getAllByRole("button", { name: "Hero" })).toHaveLength(1); // 範本帶 hero 移除
    expect(screen.queryByRole("complementary", { name: "設定" })).toBeNull();
  });

  it("ED34 🔴 block 選取寫 ?block=；佈景設定手風琴展開寫 ?category=", async () => {
    stubFetch();
    const router = renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" })); // E3：section 預設收合
    fireEvent.click(tree.getByRole("button", { name: "父塊" }));
    expect(router.state.location.search).toContain("section=demo");
    expect(router.state.location.search).toContain("block=p1");

    fireEvent.click(screen.getByRole("button", { name: "佈景主題設定" }));
    expect(router.state.location.search).not.toContain("block="); // 切面板 ⇒ 清選取
    const panel = within(screen.getByRole("complementary", { name: "佈景主題設定" }));
    const details = panel.getByText("Colors").closest("details") as HTMLDetailsElement;
    details.open = true;
    fireEvent(details, new Event("toggle"));
    expect(router.state.location.search).toContain("category=Colors");
  });
  // ── E3：左樹（docs/research/100 §2）──
  const nodeNames = (tree: { getAllByRole: (role: "button") => HTMLElement[] }) => tree.getAllByRole("button")
    .filter((node: HTMLElement) => node.hasAttribute("aria-pressed"))
    .map((node: HTMLElement) => node.querySelector(".cl-tree__name")?.textContent?.trim());

  function renderEditorAt(path: string) {
    const router = createMemoryRouter(
      [ { path: "*", element: <AdminRoutes brandName="測試品牌" uiLocale="zh-Hant" /> } ],
      { initialEntries: [ path ] },
    );
    render(<RouterProvider router={router} />);
    return router;
  }

  it("ED35 🔴 巢狀 block：theme block 子層展開／選取寫 ?block=p1__l1；容器內新增子 block 進 save payload", async () => {
    const nested = JSON.parse(JSON.stringify(BOOTSTRAP)) as typeof BOOTSTRAP;
    const theme = nested.data.theme as unknown as Record<string, unknown>;
    theme.themeBlocks = {
      _parent: { type: "_parent", name: "父塊", settings: [ { id: "label", type: "text", label: "標籤", default: "P" } ], blocks: [ "_leaf" ] },
      _leaf: { type: "_leaf", name: "葉塊", settings: [ { id: "txt", type: "text", label: "文字" } ], blocks: [] },
    };
    const demo = (theme.templateJson as { sections: Record<string, { blocks?: Record<string, unknown>; block_order?: string[] }> }).sections.demo;
    demo.blocks = { p1: { type: "_parent", blocks: { l1: { type: "_leaf", settings: { txt: "葉子文字" } } }, block_order: [ "l1" ] } };
    const fetchMock = stubFetch([], nested);
    const router = renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" }));
    fireEvent.click(tree.getByRole("button", { name: "展開 父塊" }));
    expect(nodeNames(tree)).toEqual([ "Hero", "Hero", "Blocks demo", "父塊", "葉塊" ]);

    // 葉塊列＝名稱＋summary（第一個文字設定）；選取 ⇒ 路徑以 __ 串進 URL、面板出葉塊控件
    fireEvent.click(tree.getByRole("button", { name: /^葉塊/ }));
    expect(router.state.location.search).toContain("block=p1__l1");
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByDisplayValue("葉子文字")).toBeInTheDocument();

    // 容器（父塊）自己的「新增區塊」列只列它接受的子型別
    const p1Li = tree.getByRole("button", { name: "父塊" }).closest("li")!;
    fireEvent.click(within(p1Li).getByRole("button", { name: "新增區塊" }));
    fireEvent.click(within(screen.getByRole("list", { name: "新增區塊" })).getByRole("button", { name: "葉塊" })); // E5：picker
    expect(nodeNames(tree)).toEqual([ "Hero", "Hero", "Blocks demo", "父塊", "葉塊", "葉塊" ]);

    fireEvent.keyDown(window, { key: "s", ctrlKey: true });
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { blocks: Record<string, { blocks: Record<string, unknown>; block_order: string[] }> }> } } };
    const p1 = sent.variables.content.sections.demo.blocks.p1;
    expect(p1.block_order).toEqual([ "l1", "_leaf" ]);
    expect(Object.keys(p1.blocks)).toEqual([ "l1", "_leaf" ]);
  });

  it("ED36 🔴 右鍵選單：Paste 灰化／Hide⇄Show／Rename 寫 JSON name／Add section after 插到指定位置／Edit code", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.contextMenu(tree.getAllByRole("button", { name: "Hero" })[1]); // 範本帶 hero
    let menu = within(screen.getByRole("menu"));
    expect(menu.getByRole("menuitem", { name: "貼上" })).toBeDisabled();
    expect(menu.getByRole("menuitem", { name: /編輯代碼/ })).toBeInTheDocument();
    fireEvent.click(menu.getByRole("menuitem", { name: /隱藏/ }));
    expect(screen.queryByRole("menu")).toBeNull(); // 點項目即關
    expect(tree.getByLabelText("顯示 hero")).toBeInTheDocument();

    fireEvent.contextMenu(tree.getAllByRole("button", { name: "Hero" })[1]);
    menu = within(screen.getByRole("menu"));
    expect(menu.getByRole("menuitem", { name: /顯示/ })).toBeInTheDocument(); // 隱藏態 ⇒ 反轉為 Show
    fireEvent.click(menu.getByRole("menuitem", { name: "重新命名" }));
    const nameInput = screen.getByLabelText("名稱") as HTMLInputElement;
    expect(nameInput.value).toBe("Hero"); // 預設＝schema name
    fireEvent.change(nameInput, { target: { value: "主視覺" } });
    fireEvent.keyDown(nameInput, { key: "Enter" });
    expect(tree.getByRole("button", { name: "主視覺" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "主視覺" })).toBeInTheDocument(); // 面板標題同步

    fireEvent.contextMenu(tree.getByRole("button", { name: "主視覺" }));
    fireEvent.click(within(screen.getByRole("menu")).getByRole("menuitem", { name: "在後面新增區段" }));
    fireEvent.click(within(screen.getByRole("list", { name: "可新增的區段" })).getByRole("button", { name: "促銷條" }));
    expect(nodeNames(tree)).toEqual([ "Hero", "主視覺", "promo", "Blocks demo" ]); // 插在 hero 之後、demo 之前

    fireEvent.keyDown(window, { key: "s", ctrlKey: true });
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { name?: string; disabled?: boolean }>; order: string[] } } };
    expect(sent.variables.content.order).toEqual([ "hero", "promo", "demo" ]);
    expect(sent.variables.content.sections.hero).toMatchObject({ name: "主視覺", disabled: true });
  });

  it("ED37 🔴 鍵盤：Shift+↓/↑ 沿可視列移動選取（收合的 block 跳過）；Shift+Enter 聚焦面板；Ctrl+Shift+O/P 展開／收合全部", async () => {
    stubFetch();
    const router = renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.keyDown(window, { key: "ArrowDown", shiftKey: true }); // 無選取 ⇒ 第一列（頁首帶 gh）
    expect(within(screen.getByRole("complementary", { name: "設定" })).getByDisplayValue("群組頁首")).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "ArrowDown", shiftKey: true }); // 範本帶 hero
    expect(within(screen.getByRole("complementary", { name: "設定" })).getByDisplayValue("首頁英雄")).toBeInTheDocument();

    fireEvent.keyDown(window, { key: "Enter", shiftKey: true }); // 開啟選中元素 ⇒ 焦點進第一個控件
    expect(document.activeElement).toBe(within(screen.getByRole("complementary", { name: "設定" })).getByLabelText("標題"));

    fireEvent.keyDown(window, { key: "ArrowDown", shiftKey: true }); // demo（收合 ⇒ 其 block 不在可視列）
    expect(tree.getByRole("button", { name: "Blocks demo" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.keyDown(window, { key: "ArrowDown", shiftKey: true }); // 末列 ⇒ 停住
    expect(tree.getByRole("button", { name: "Blocks demo" })).toHaveAttribute("aria-pressed", "true");
    fireEvent.keyDown(window, { key: "ArrowUp", shiftKey: true });
    expect(tree.getAllByRole("button", { name: "Hero" })[1]).toHaveAttribute("aria-pressed", "true");

    fireEvent.keyDown(window, { key: "o", ctrlKey: true, shiftKey: true }); // 展開全部
    expect(tree.getByRole("button", { name: "父塊" })).toBeInTheDocument();
    fireEvent.keyDown(window, { key: "ArrowDown", shiftKey: true }); // demo
    fireEvent.keyDown(window, { key: "ArrowDown", shiftKey: true }); // 父塊（展開後進入可視列）
    expect(tree.getByRole("button", { name: "父塊" })).toHaveAttribute("aria-pressed", "true");
    expect(router.state.location.search).toContain("block=p1");

    fireEvent.keyDown(window, { key: "p", ctrlKey: true, shiftKey: true }); // 收合全部
    expect(tree.queryByRole("button", { name: "父塊" })).toBeNull();
  });

  it("ED38 🔴 群組帶 Add section：enabled_on.groups 過濾＋limit 達標灰化 (n/limit)；footer 帶按鈕在列之上；範本帶只列模板可用者", async () => {
    const boot = JSON.parse(JSON.stringify(BOOTSTRAP)) as typeof BOOTSTRAP;
    const theme = boot.data.theme as unknown as Record<string, unknown>;
    (theme.sectionGroups as unknown[]).push({
      name: "footer-group", label: "Footer group", type: "footer", position: "after",
      path: "sections/footer-group.json", json: { sections: {}, order: [] }, lockVersion: null });
    (theme.sectionCatalog as unknown[]).push({ type: "sid-probe", name: "Sid probe", preset: { settings: {}, blocks: null } });
    const schemas = theme.sectionSchemas as Record<string, unknown>;
    schemas["sid-probe"] = { name: "Sid probe", settings: [], enabled_on: { groups: [ "header" ] }, limit: 1 };
    schemas.promo = { name: "促銷條", settings: [], enabled_on: { templates: [ "index" ] } };
    stubFetch([], boot);
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    // footer 類群組：Add section 緊接標題（列之上；本尊 100 §2）
    const footer = tree.getByText("Footer group").closest("section")!;
    expect(footer.querySelector("h4 + button")?.getAttribute("aria-label")).toBe("新增區段：Footer group");

    fireEvent.click(tree.getByRole("button", { name: "新增區段：Header group" }));
    let picker = within(screen.getByRole("list", { name: "可新增的區段" }));
    expect(picker.getByRole("button", { name: "Sid probe" })).toBeInTheDocument();
    expect(picker.queryByRole("button", { name: "促銷條" })).toBeNull(); // 只限 index 模板 ⇒ 群組不列
    fireEvent.click(picker.getByRole("button", { name: "Sid probe" }));
    expect(nodeNames(tree)).toEqual([ "Hero", "Sid probe", "Hero", "Blocks demo" ]); // 進頁首帶尾端

    fireEvent.click(tree.getByRole("button", { name: "新增區段：Header group" }));
    picker = within(screen.getByRole("list", { name: "可新增的區段" }));
    expect(picker.getByRole("button", { name: "Sid probe (1/1)" })).toBeDisabled(); // limit 達標

    fireEvent.click(tree.getByRole("button", { name: "新增區段" })); // 範本帶
    picker = within(screen.getByRole("list", { name: "可新增的區段" }));
    expect(picker.getByRole("button", { name: "促銷條" })).toBeInTheDocument();
    expect(picker.queryByRole("button", { name: /Sid probe/ })).toBeNull(); // 只限群組 ⇒ 範本帶不列
  });

  it("ED39 🔴 資源模板的 Preview 列：選產品 ⇒ ?previewPath=；命中者出「編輯」連結", async () => {
    stubFetch();
    const router = renderEditorAt("/admin/themes/7/editor?template=product");
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByRole("button", { name: "預覽" }));
    fireEvent.click(await screen.findByRole("option", { name: "Acme Tee" }));
    expect(router.state.location.search).toContain("previewPath=%2Fproducts%2Facme-tee");
    expect(await tree.findByLabelText("編輯")).toHaveAttribute("href", "/admin/products/1");
    expect(screen.queryByRole("option")).toBeNull(); // 選後即關
  });

  it("ED40 🔴 URL 還原 ?section=&block= ⇒ 祖先自動展開＋block 選中；隱藏 block 灰列＋眼睛常駐", async () => {
    stubFetch();
    renderEditorAt("/admin/themes/7/editor?section=demo&block=p1");
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    // 還原走載入後的 effect（資料到了才有 section 可展開）⇒ 以 findBy 等它
    expect(await tree.findByRole("button", { name: "父塊" })).toHaveAttribute("aria-pressed", "true");
    expect(await within(screen.getByRole("complementary", { name: "設定" })).findByLabelText("標籤")).toBeInTheDocument();

    fireEvent.keyDown(window, { key: "h", ctrlKey: true, shiftKey: true });
    expect(tree.getByLabelText("顯示 p1").className).toContain("is-persistent");
    expect(tree.getByRole("button", { name: "父塊" }).closest(".cl-tree__row")?.className).toContain("is-hidden");
  });

  it("ED41 🔴 static block：不在 block_order 也列在樹上（鎖 icon、不可拖、無垃圾桶）；Shift+⌫ 不刪；可隱藏；save 保留", async () => {
    const boot = JSON.parse(JSON.stringify(BOOTSTRAP)) as typeof BOOTSTRAP;
    const demo = boot.data.theme!.templateJson!.sections!.demo as {
      block_order?: string[]; blocks?: Record<string, { type: string; static?: boolean; settings?: Record<string, unknown> }> };
    demo.block_order = [ "p1" ];
    demo.blocks = { p1: { type: "_parent" }, sb: { type: "_parent", static: true, settings: {} } }; // Ella product.json 形：static 不在 block_order
    const fetchMock = stubFetch([], boot);
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" }));
    const rows = tree.getAllByRole("button", { name: "父塊" });
    expect(rows).toHaveLength(2); // p1（可拖）＋ sb（static，附在後）
    const staticLi = rows[1].closest("li")!;
    expect(staticLi.getAttribute("draggable")).toBe("false");
    expect(within(staticLi).getByRole("img", { name: "靜態區塊（固定位置）" })).toBeInTheDocument(); // 鎖 icon
    expect(within(staticLi).queryByLabelText("移除 block sb")).toBeNull(); // 無垃圾桶
    expect(within(staticLi).getByLabelText("隱藏 sb")).toBeInTheDocument(); // 眼睛照舊

    fireEvent.click(rows[1]);
    const settings = within(screen.getByRole("complementary", { name: "設定" }));
    expect(settings.getByLabelText("標籤")).toBeInTheDocument(); // 設定可改
    expect(settings.queryByRole("button", { name: /移除 block/ })).toBeNull(); // 面板底部也無移除
    fireEvent.keyDown(window, { key: "Backspace", shiftKey: true });
    expect(tree.getAllByRole("button", { name: "父塊" })).toHaveLength(2); // Shift+⌫ 不刪 static

    fireEvent.click(tree.getByLabelText("隱藏 sb"));
    expect(tree.getByLabelText("顯示 sb")).toBeInTheDocument();

    fireEvent.keyDown(window, { key: "s", ctrlKey: true });
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { block_order: string[]; blocks: Record<string, unknown> }> } } };
    expect(sent.variables.content.sections.demo.block_order).toEqual([ "p1" ]); // static 不進 block_order
    expect(sent.variables.content.sections.demo.blocks.sb).toMatchObject({ type: "_parent", static: true, disabled: true });
  });

  it("ED42 🔴 實例 name 是 t: 鍵 ⇒ 樹列／面板標題／改名預設值顯示翻譯；無翻譯鍵 fail-open 顯示原鍵", async () => {
    const boot = JSON.parse(JSON.stringify(BOOTSTRAP)) as typeof BOOTSTRAP;
    const theme = boot.data.theme as unknown as Record<string, unknown>;
    theme.nameTranslations = { "t:names.hero": "英雄橫幅" };
    (theme.sectionGroups as { json: { sections: Record<string, { name?: string }> } }[])[0].json.sections.gh.name = "t:names.hero";
    (theme.templateJson as { sections: Record<string, { name?: string }> }).sections.hero.name = "t:names.unknown";
    stubFetch([], boot);
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));

    expect(tree.getByRole("button", { name: "英雄橫幅" })).toBeInTheDocument(); // 頁首帶 gh：翻譯
    expect(tree.getByRole("button", { name: "t:names.unknown" })).toBeInTheDocument(); // 範本帶 hero：無翻譯 ⇒ 原鍵

    fireEvent.click(tree.getByRole("button", { name: "英雄橫幅" }));
    expect(screen.getByRole("heading", { name: "英雄橫幅" })).toBeInTheDocument(); // 面板標題同源
    fireEvent.contextMenu(tree.getByRole("button", { name: "英雄橫幅" }));
    fireEvent.click(within(screen.getByRole("menu")).getByRole("menuitem", { name: "重新命名" }));
    expect((screen.getByLabelText("名稱") as HTMLInputElement).value).toBe("英雄橫幅"); // 改名預設值＝翻譯後文字
  });

  // ── E4：右欄逐控件（docs/research/100 §3）──
  const e4Boot = () => {
    const boot = JSON.parse(JSON.stringify(BOOTSTRAP)) as typeof BOOTSTRAP;
    const theme = boot.data.theme as unknown as Record<string, unknown>;
    const schemas = theme.sectionSchemas as Record<string, { settings: Record<string, unknown>[]; theme_settings?: string[] }>;
    schemas.hero.settings.push(
      { id: "toggle", type: "checkbox", label: "開關", default: false },
      { id: "dep", type: "text", label: "相依", visible_if: "{{ section.settings.toggle == true }}" },
      { id: "size", type: "select", label: "尺寸", options: [ { value: "s", label: "小", group: "基本" }, { value: "l", label: "大", group: "基本" } ], default: "s" },
      { id: "pos", type: "radio", label: "位置", options: [ { value: "top", label: "上" }, { value: "bottom", label: "下" } ], default: "top" },
      { id: "ta", type: "text_alignment", label: "文字對齊" },
      { id: "accent", type: "color", label: "強調色", alpha: true, default: "#ff0000" },
      { id: "scheme", type: "color_scheme", label: "配色", default: "scheme-1" },
      { id: "menu", type: "link_list", label: "選單", default: "main-menu" },
      { id: "link", type: "url", label: "連結" },
      { id: "video", type: "video_url", label: "影片", accept: [ "youtube" ] },
      { id: "code", type: "liquid", label: "Liquid" },
      { id: "rich", type: "richtext", label: "內文" },
    );
    schemas.hero.theme_settings = [ "brand_color" ];
    (theme.settingsSchema as { name: string; settings: Record<string, unknown>[] }[]).push({ name: "Typography", settings: [
      { id: "body_font", type: "font_picker", label: "內文字型", default: "jost_n4" } ] });
    (theme.settingsSchema as { name: string; settings: Record<string, unknown>[] }[])[0].settings.push(
      { id: "color_schemes", type: "color_scheme_group", label: "配色方案", definition: [ { id: "background", type: "color", label: "底" }, { id: "foreground", type: "color", label: "字" }, { id: "primary_button_background", type: "color", label: "鈕" } ],
        role: { background: { solid: "background" }, text: "foreground", primary_button: { solid: "primary_button_background" } } });
    (theme.themeSettingsJson as Record<string, unknown>).color_schemes = {
      "scheme-1": { settings: { background: "#ffffff", foreground: "#111111", primary_button_background: "#222222" } },
      "scheme-2": { settings: { background: "#000000", foreground: "#eeeeee", primary_button_background: "#dddddd" } },
    };
    theme.fontLibrary = [
      { key: "system_ui", name: "system-ui", system: true, handles: [ "n4" ] },
      { key: "jost", name: "Jost", system: false, handles: [ "n4", "n7" ] },
    ];
    (theme.templateJson as { sections: Record<string, { settings: Record<string, unknown> }> }).sections.hero.settings.dep = "保留值";
    (boot.data as unknown as Record<string, unknown>).menus = [ { handle: "main-menu", title: "Main menu" }, { handle: "footer", title: "Footer" } ];
    return boot;
  };
  const openHero = async () => {
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]);
    return { tree, settings: within(screen.getByRole("complementary", { name: "設定" })) };
  };
  const savedTemplate = async (fetchMock: ReturnType<typeof vi.fn>) => {
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    return (JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { settings: Record<string, unknown> }> } } }).variables.content.sections;
  };

  it("ED43 🔴 visible_if：條件不成立的列不渲染、值仍保留；toggle（switch）開啟後出現並帶保留值", async () => {
    const fetchMock = stubFetch([], e4Boot());
    renderEditor();
    const { settings } = await openHero();
    expect(settings.queryByLabelText("相依")).toBeNull(); // toggle=false ⇒ 隱藏
    fireEvent.click(settings.getByRole("switch", { name: "開關" }));
    expect(settings.getByLabelText("相依")).toHaveValue("保留值"); // 出現且值未被清
    fireEvent.click(settings.getByRole("switch", { name: "開關" }));
    expect(settings.queryByLabelText("相依")).toBeNull();
    const sections = await savedTemplate(fetchMock);
    expect(sections.hero.settings.dep).toBe("保留值"); // 隱藏不清值（官方未說明 ⇒ 我方保留）
    expect(sections.hero.settings.toggle).toBe(false);
  });

  it("ED44 🔴 基本控件形態：select optgroup／radio 分段／range 數字框＋滑桿／text_alignment icon 分段／video_url accept 驗證", async () => {
    const fetchMock = stubFetch([], e4Boot());
    renderEditor();
    const { settings } = await openHero();
    expect(settings.getByRole("group", { name: "基本" })).toBeInTheDocument(); // optgroup
    fireEvent.change(settings.getByLabelText("尺寸"), { target: { value: "l" } });
    fireEvent.click(settings.getByRole("radio", { name: "下" }));
    expect(settings.getByRole("radio", { name: "下" })).toHaveAttribute("aria-checked", "true");
    fireEvent.change(settings.getByLabelText("間距"), { target: { value: "48" } }); // 數字框
    expect(settings.getByLabelText("間距 slider")).toHaveValue("48"); // 滑桿同步
    fireEvent.click(settings.getByRole("radio", { name: "置中" }));
    fireEvent.change(settings.getByLabelText("影片"), { target: { value: "https://vimeo.com/1" } });
    expect(settings.getByText(/youtube/)).toBeInTheDocument(); // accept 只收 youtube ⇒ 錯誤句
    fireEvent.change(settings.getByLabelText("影片"), { target: { value: "https://youtu.be/abc" } });
    expect(settings.queryByText(/youtube.*網址|有效的/)).toBeNull();
    expect(settings.getByPlaceholderText("貼上連結或搜尋")).toBeInTheDocument(); // url
    expect(settings.getByRole("toolbar")).toBeInTheDocument(); // richtext 工具列
    const sections = await savedTemplate(fetchMock);
    expect(sections.hero.settings).toMatchObject({ size: "l", pos: "bottom", spacing: 48, ta: "center", video: "https://youtu.be/abc" });
  });

  it("ED44b 🔴 E10：range／radio／checkbox 為「標籤｜控件」單列（.cl-panel__row--inline）；video_url／text 仍上下排；短選項 select＝分段", async () => {
    stubFetch([], e4Boot());
    renderEditor();
    const { settings } = await openHero();
    const rowOf = (label: string) => settings.getByText(label, { selector: "label" }).closest(".cl-panel__row") as HTMLElement;
    expect(rowOf("間距").className).toContain("cl-panel__row--inline");
    expect(rowOf("位置").className).toContain("cl-panel__row--inline");
    expect(rowOf("影片").className).not.toContain("cl-panel__row--inline");
    // 單列：滑桿與數字框同在 .cl-panel__inline 內（本尊：標籤｜滑桿｜數字＋單位）
    expect(rowOf("間距").querySelector(".cl-panel__inline .cl-ctl-range__slider")).not.toBeNull();
    expect(rowOf("間距").querySelector(".cl-panel__inline .cl-ctl-range__number")).not.toBeNull();
  });

  it("ED45 🔴 color：色票鈕顯示 HEX；popover 內 HEX／色相／透明度（alpha:true 才有）；alpha 改 ⇒ rgba 寫回", async () => {
    const fetchMock = stubFetch([], e4Boot());
    renderEditor();
    const { settings } = await openHero();
    const swatch = settings.getByLabelText("強調色");
    expect(swatch).toHaveTextContent("#FF0000");
    fireEvent.click(swatch);
    expect(screen.getByLabelText("色相")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("不透明度"), { target: { value: "50" } });
    const sections = await savedTemplate(fetchMock);
    expect(sections.hero.settings.accent).toBe("rgba(255, 0, 0, 0.5)");
  });

  it("ED46 🔴 color_scheme：Aa 預覽＋配色名；popover 列全部 scheme（選中打勾）；Edit ⇒ 佈景設定 Colors 分類＋URL colorScheme", async () => {
    const fetchMock = stubFetch([], e4Boot());
    const router = renderEditor();
    const { settings } = await openHero();
    const picker = settings.getByLabelText("配色");
    expect(picker).toHaveTextContent("配色 1");
    fireEvent.click(picker);
    fireEvent.click(screen.getByRole("option", { name: /配色 2/ }));
    expect(settings.getByLabelText("配色")).toHaveTextContent("配色 2");
    fireEvent.click(settings.getByLabelText("配色"));
    fireEvent.click(screen.getByRole("button", { name: "編輯" }));
    expect(screen.getByRole("complementary", { name: "佈景主題設定" })).toBeInTheDocument();
    expect(router.state.location.search).toContain("colorScheme=scheme-2");
    expect(router.state.location.search).toContain("category=Colors");
    fireEvent.click(screen.getByRole("button", { name: "區段" })); // 回 sections 面板再存
    fireEvent.click(screen.getAllByRole("button", { name: "Hero" })[1]);
    const sections = await savedTemplate(fetchMock);
    expect(sections.hero.settings.scheme).toBe("scheme-2");
  });

  it("ED47 🔴 font_picker：字型名鈕 ⇒ 右欄整面選字型（系統／其他兩組＋字重＋完成）⇒ 寫回 handle", async () => {
    const fetchMock = stubFetch([], e4Boot());
    renderEditor();
    await screen.findByRole("complementary", { name: "區段" });
    fireEvent.click(screen.getByRole("button", { name: "佈景主題設定" }));
    const panel = within(screen.getByRole("complementary", { name: "佈景主題設定" }));
    fireEvent.click(panel.getByText("Typography"));
    const btn = panel.getByLabelText("內文字型");
    expect(btn).toHaveTextContent("Jost");
    fireEvent.click(btn);
    // 佈景設定面板內沒有右欄殼；font_picker 由頁面接到右欄 ⇒ 標題「選取內文字型」
    expect(await screen.findByRole("heading", { name: "選取內文字型" })).toBeInTheDocument();
    expect(screen.getByText("系統字型")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("option", { name: "system-ui" }));
    fireEvent.click(screen.getByRole("button", { name: "完成" }));
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeSettingsUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeSettingsUpsert")[0].body)) as { variables: { settings: Record<string, unknown> } };
    expect(sent.variables.settings.body_font).toBe("system_ui_n4");
  });

  it("ED48 🔴 link_list：選單名鈕 ⇒ 取代／編輯／移除選單；取代 ⇒ 清單選另一個 ⇒ 寫回 handle；移除 ⇒ 空", async () => {
    const fetchMock = stubFetch([], e4Boot());
    renderEditor();
    const { settings } = await openHero();
    const btn = settings.getByLabelText("選單");
    expect(btn).toHaveTextContent("Main menu");
    fireEvent.click(btn);
    fireEvent.click(screen.getByRole("menuitem", { name: "取代" }));
    fireEvent.click(screen.getByRole("option", { name: "Footer" }));
    expect(settings.getByLabelText("選單")).toHaveTextContent("Footer");
    const sections = await savedTemplate(fetchMock);
    expect(sections.hero.settings.menu).toBe("footer");
  });

  it("ED49 🔴 右欄「…」：建立副本（section 與 block）、複製 ⇒ 左樹右鍵貼上、隱藏、移除；static block 無副本／移除", async () => {
    const boot = e4Boot();
    const demo = (boot.data.theme!.templateJson!.sections! as Record<string, { blocks?: Record<string, unknown>; block_order?: string[] }>).demo;
    demo.block_order = [ "p1" ];
    demo.blocks = { p1: { type: "_parent" }, sb: { type: "_parent", static: true, settings: {} } };
    stubFetch([], boot);
    renderEditor();
    const { tree } = await openHero();
    const more = () => within(screen.getByRole("complementary", { name: "設定" })).getByRole("button", { name: "更多動作" });
    fireEvent.click(more());
    fireEvent.click(screen.getByRole("menuitem", { name: "建立副本" }));
    expect(tree.getAllByRole("button", { name: "Hero" })).toHaveLength(3); // 範本帶 hero 複本（選取移到複本）
    fireEvent.click(more());
    fireEvent.click(screen.getByRole("menuitem", { name: "複製" }));
    fireEvent.contextMenu(tree.getByRole("button", { name: "Blocks demo" }));
    const paste = within(screen.getByRole("menu")).getByRole("menuitem", { name: "貼上" });
    expect(paste).not.toBeDisabled();
    fireEvent.click(paste);
    expect(tree.getAllByRole("button", { name: "Hero" })).toHaveLength(4); // 貼在 demo 之後
    fireEvent.click(more());
    fireEvent.click(screen.getByRole("menuitem", { name: /隱藏/ }));
    expect(tree.getAllByLabelText(/^顯示 /).length).toBeGreaterThanOrEqual(1);
    // block：建立副本
    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" }));
    fireEvent.click(tree.getAllByRole("button", { name: "父塊" })[0]);
    fireEvent.click(more());
    fireEvent.click(screen.getByRole("menuitem", { name: "建立副本" }));
    expect(tree.getAllByRole("button", { name: "父塊" })).toHaveLength(3); // p1＋副本＋static
    // static block：無副本／無移除
    fireEvent.click(tree.getAllByRole("button", { name: "父塊" })[2]);
    fireEvent.click(more());
    expect(screen.queryByRole("menuitem", { name: "建立副本" })).toBeNull();
    expect(screen.queryByRole("menuitem", { name: "移除" })).toBeNull();
    expect(screen.getByRole("menuitem", { name: /編輯代碼/ })).toBeInTheDocument();
  });

  it("ED50 🔴 section 尾部「佈景主題設定」收合區列出該 section 引用的全域設定並可改；Custom CSS 展開寫 URL customCss=true", async () => {
    const fetchMock = stubFetch([], e4Boot());
    const router = renderEditor();
    const { settings } = await openHero();
    fireEvent.click(settings.getByRole("button", { name: "佈景主題設定" }));
    const brand = settings.getByLabelText("品牌色");
    expect(brand).toHaveTextContent("#A9502C");
    fireEvent.click(brand);
    const hex = screen.getByLabelText("Hex");
    fireEvent.change(hex, { target: { value: "123456" } });
    fireEvent.blur(hex);
    fireEvent.click(settings.getByRole("button", { name: "自訂 CSS" }));
    expect(router.state.location.search).toContain("customCss=true");
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeSettingsUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeSettingsUpsert")[0].body)) as { variables: { settings: Record<string, unknown> } };
    expect(sent.variables.settings.brand_color).toBe("#123456");
  });

  it("ED51 🔴 image_picker：選取 ⇒ 檔案庫 modal（搜尋＋格狀）⇒ 完成 ⇒ 寫 shopify://shopify/files/{filename}；已設值 ⇒ 變更／移除", async () => {
    const fetchMock = stubFetch([], e4Boot());
    renderEditor();
    const { settings } = await openHero();
    fireEvent.click(settings.getByRole("button", { name: "圖片" }));
    const dialog = within(await screen.findByRole("dialog", { name: "圖片" }));
    fireEvent.click(await dialog.findByRole("option", { name: /hero\.png/ }));
    fireEvent.click(dialog.getByRole("button", { name: "完成" }));
    expect(settings.getByText("hero.png")).toBeInTheDocument();
    const sections = await savedTemplate(fetchMock);
    expect(sections.hero.settings.image).toBe("shopify://shopify/files/hero.png");
    fireEvent.click(settings.getByRole("button", { name: "移除" }));
    expect(settings.getByRole("button", { name: "圖片" })).toHaveTextContent("選取");
  });

  // ── E5：兩欄 picker（docs/research/100 §4＋§8.1）──
  const e5Boot = () => {
    const boot = JSON.parse(JSON.stringify(BOOTSTRAP)) as typeof BOOTSTRAP;
    const theme = boot.data.theme as unknown as Record<string, unknown>;
    (theme.sectionCatalog as unknown[]).push(
      { type: "promo", presetIndex: 1, name: "促銷條（橫幅）", category: "橫幅", preset: { settings: { text: "橫幅文案" }, blocks: null } },
      { type: "gallery", presetIndex: 0, name: "圖庫", category: "橫幅", preset: { settings: {},
        blocks: [ { type: "_parent", settings: { label: "A" }, blocks: [ { type: "_leaf", settings: { txt: "子" } } ] }, { type: "_parent", static: true, settings: {} } ] } },
      { type: "hero", presetIndex: 0, name: "英雄（preset）", category: null, preset: { settings: { heading: "H" }, blocks: { intro: { type: "_parent", settings: {} } }, block_order: [ "intro" ] } },
    );
    (theme.sectionSchemas as Record<string, unknown>).gallery = { name: "Gallery", settings: [], blocks: [ { type: "_parent", name: "父塊", settings: [] } ] };
    theme.themeBlocks = {
      _parent: { type: "_parent", name: "父塊", category: "基本", settings: [ { id: "label", type: "text", label: "標籤" } ], blocks: [ "_leaf" ] },
      _leaf: { type: "_leaf", name: "葉塊", category: "版面", settings: [ { id: "txt", type: "text", label: "文字" } ], blocks: [] },
    };
    return boot;
  };

  it("ED52 🔴 section picker 兩欄形態：搜尋框／Sections|Apps 分段／Generate／扁平清單＋分類收合區／Apps 空態；同型多 preset 各列一項", async () => {
    stubFetch([], e5Boot());
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByRole("button", { name: "新增區段" }));
    expect(screen.getByLabelText("搜尋區段")).toHaveFocus();
    expect(screen.getByRole("tab", { name: "區段" })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("button", { name: "生成" })).toHaveAttribute("aria-disabled", "true");
    const flat = within(screen.getByRole("list", { name: "可新增的區段" }));
    expect(flat.getByRole("button", { name: "促銷條" })).toBeInTheDocument(); // 無分類 ⇒ 扁平區
    expect(flat.getByRole("button", { name: "英雄（preset）" })).toBeInTheDocument();
    const group = screen.getByRole("button", { name: "橫幅" });
    expect(group).toHaveAttribute("aria-expanded", "true");
    const banner = within(screen.getByRole("list", { name: "橫幅" }));
    expect(banner.getByRole("button", { name: "促銷條（橫幅）" })).toBeInTheDocument(); // 同型第二個 preset 各列一項
    expect(banner.getByRole("button", { name: "圖庫" })).toBeInTheDocument();
    fireEvent.click(group);
    expect(screen.queryByRole("list", { name: "橫幅" })).toBeNull(); // 收合
    expect(screen.getByText("沒有可用的預覽")).toBeInTheDocument(); // 右欄預覽
    fireEvent.click(screen.getByRole("tab", { name: "應用程式" }));
    expect(screen.getByText("沒有可用的應用程式區段")).toBeInTheDocument();
  });

  it("ED53 🔴 選第二個 preset ⇒ 用它的 settings；preset blocks 陣列形實例化（生 id、巢狀、static 不進 block_order）；hash 形照 block_order", async () => {
    const fetchMock = stubFetch([], e5Boot());
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByRole("button", { name: "新增區段" }));
    fireEvent.click(within(screen.getByRole("list", { name: "橫幅" })).getByRole("button", { name: "促銷條（橫幅）" }));
    expect(within(screen.getByRole("complementary", { name: "設定" })).getByDisplayValue("橫幅文案")).toBeInTheDocument();
    fireEvent.click(tree.getByRole("button", { name: "新增區段" }));
    fireEvent.click(within(screen.getByRole("list", { name: "橫幅" })).getByRole("button", { name: "圖庫" }));
    fireEvent.click(tree.getByRole("button", { name: "新增區段" }));
    fireEvent.click(within(screen.getByRole("list", { name: "可新增的區段" })).getByRole("button", { name: "英雄（preset）" }));
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sections = (JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as {
      variables: { content: { sections: Record<string, { settings: Record<string, unknown>; blocks?: Record<string, { type: string; static?: boolean; blocks?: Record<string, { type: string }>; block_order?: string[] }>; block_order?: string[] }> } } }).variables.content.sections;
    expect(sections.promo.settings.text).toBe("橫幅文案");
    const gallery = sections.gallery;
    expect(gallery.block_order).toHaveLength(1); // static 不進 block_order
    const [ dynamicId ] = gallery.block_order!;
    expect(dynamicId).toMatch(/^_parent_[0-9A-Za-z]{6}$/); // 生成 id 形
    expect(Object.keys(gallery.blocks ?? {})).toHaveLength(2);
    expect(gallery.blocks?.[dynamicId].block_order).toHaveLength(1); // 巢狀
    expect(Object.values(gallery.blocks ?? {}).some((b) => b.static)).toBe(true);
    expect(sections.hero_1 ?? sections["hero-1"]).toBeDefined(); // 同 type 已存在 ⇒ 尾碼
    const hero2 = sections.hero_1 ?? sections["hero-1"];
    expect(hero2.block_order).toEqual([ "intro" ]); // hash 形照 block_order
  });

  it("ED54 🔴 block picker：分類收合區（theme block category）＋搜尋；選取 ⇒ 進容器；插入線在目標列", async () => {
    stubFetch([], e5Boot());
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" }));
    fireEvent.click(tree.getByRole("button", { name: "新增區塊" }));
    expect(screen.getByLabelText("搜尋區塊")).toHaveFocus();
    expect(screen.getByRole("tab", { name: "區塊" })).toHaveAttribute("aria-selected", "true");
    const basic = within(screen.getByRole("list", { name: "基本" }));
    fireEvent.click(basic.getByRole("button", { name: "父塊" }));
    expect(tree.getAllByRole("button", { name: /^父塊/ })).toHaveLength(2); // 新 block 帶 default 摘要「父塊 – P」
    // 右鍵 Add section after ⇒ 插入線在 hero 之後（data-insert=after 於 hero 列；index=1 ⇒ demo 列 before）
    fireEvent.contextMenu(tree.getAllByRole("button", { name: "Hero" })[1]);
    fireEvent.click(within(screen.getByRole("menu")).getByRole("menuitem", { name: "在後面新增區段" }));
    expect(tree.getByRole("button", { name: "Blocks demo" }).closest("li")).toHaveAttribute("data-insert", "before");
    fireEvent.keyDown(document.body, { key: "Escape" }); // Escape 關 picker（Popover capture 監聽）
    expect(screen.queryByRole("list", { name: "可新增的區段" })).toBeNull();
  });

  // ── E6：預覽互動（docs/research/100 §5／§9.5）──
  const fromPreview = (data: Record<string, unknown>) => fireEvent(window, new MessageEvent("message", { data, origin: window.location.origin }));

  it("ED55 🔴 預覽 section 邊界「+」（cl:insert after）⇒ 區段 picker 開在該位置：插入線在下一列、選取後插到該 index", async () => {
    const fetchMock = stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fromPreview({ type: "cl:insert", id: "hero", position: "after" });
    expect(tree.getByRole("button", { name: "Blocks demo" }).closest("li")).toHaveAttribute("data-insert", "before"); // hero 之後＝demo 之前
    fireEvent.click(within(screen.getByRole("list", { name: "可新增的區段" })).getByRole("button", { name: "促銷條" }));
    fireEvent.click(screen.getByRole("button", { name: /儲存/ }));
    await vi.waitFor(() => expect(callsTo(fetchMock, "themeTemplateUpsert")).toHaveLength(1));
    const sent = JSON.parse(String(callsTo(fetchMock, "themeTemplateUpsert")[0].body)) as { variables: { content: { order: string[] } } };
    expect(sent.variables.content.order).toEqual([ "hero", "promo", "demo" ]);
  });

  it("ED56 🔴 預覽右鍵（cl:contextmenu 帶 blockId）⇒ 左樹同款選單開在 iframe 座標；項目含 Rename／隱藏／編輯代碼", async () => {
    stubFetch();
    renderEditor();
    await screen.findByRole("complementary", { name: "區段" });
    fromPreview({ type: "cl:contextmenu", id: "demo", blockId: "p1", x: 120, y: 80 });
    const menu = screen.getByRole("menu");
    expect(within(menu).getByRole("menuitem", { name: "重新命名" })).toBeInTheDocument();
    expect(within(menu).getByRole("menuitem", { name: /隱藏/ })).toBeInTheDocument();
    expect(within(menu).getByRole("menuitem", { name: /編輯代碼/ })).toBeInTheDocument();
    expect(within(menu).queryByRole("menuitem", { name: "在後面新增區段" })).toBeNull(); // block 列無 section 專屬項
    fireEvent.click(within(menu).getByRole("menuitem", { name: /隱藏/ }));
    const tree = within(screen.getByRole("complementary", { name: "區段" }));
    fireEvent.click(tree.getByRole("button", { name: "展開 Blocks demo" }));
    expect(tree.getByLabelText("顯示 p1")).toBeInTheDocument(); // block 已隱藏
  });

  it("ED57 🔴 預覽浮動工具列 cl:op：hide／duplicate／remove 對 block（blockId）與 section 都走同一 op；異 origin 忽略", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    fromPreview({ type: "cl:op", op: "duplicate", id: "demo", blockId: "p1" });
    // duplicateNode 選中副本 ⇒ demo 已自動展開；保險：若仍收合則展開
    const expand = tree.queryByRole("button", { name: "展開 Blocks demo" });
    if (expand) fireEvent.click(expand);
    expect(tree.getAllByRole("button", { name: "父塊" })).toHaveLength(2); // block 副本
    fromPreview({ type: "cl:op", op: "hide", id: "hero" });
    expect(tree.getByLabelText("顯示 hero")).toBeInTheDocument();
    fromPreview({ type: "cl:op", op: "remove", id: "demo", blockId: "p1" });
    expect(tree.getAllByRole("button", { name: "父塊" })).toHaveLength(1);
    fireEvent(window, new MessageEvent("message", { data: { type: "cl:op", op: "remove", id: "hero" }, origin: "https://evil.example" }));
    expect(tree.getAllByRole("button", { name: "Hero" })).toHaveLength(2); // 異 origin 不動
  });

  it("ED58 🔴 iframe 載入 ⇒ 推 cl:names（顯示名同左樹、含工具列文字）與 cl:inspector；bands 變動再推", async () => {
    stubFetch();
    renderEditor();
    const tree = within(await screen.findByRole("complementary", { name: "區段" }));
    const iframe = screen.getByTitle("主題預覽") as HTMLIFrameElement;
    const spy = vi.spyOn(iframe.contentWindow!, "postMessage");
    fireEvent.load(iframe);
    const names = spy.mock.calls.map((c) => c[0] as { type: string }).filter((m) => m.type === "cl:names").at(-1) as unknown as
      { sections: Record<string, string>; blocks: Record<string, Record<string, string>>; labels: Record<string, string> };
    expect(names.sections).toEqual({ gh: "Hero", hero: "Hero", demo: "Blocks demo" });
    expect(names.blocks.demo).toEqual({ p1: "父塊" });
    expect(names.labels).toEqual({ addSection: "新增區段", duplicate: "建立副本", hide: "隱藏", remove: "移除" });
    expect(spy.mock.calls.some((c) => (c[0] as { type: string }).type === "cl:inspector")).toBe(true);
    spy.mockClear();
    fireEvent.click(tree.getAllByRole("button", { name: "Hero" })[1]);
    fireEvent.contextMenu(tree.getAllByRole("button", { name: "Hero" })[1]);
    fireEvent.click(within(screen.getByRole("menu")).getByRole("menuitem", { name: "重新命名" }));
    const input = screen.getByLabelText("名稱") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "主視覺" } });
    fireEvent.keyDown(input, { key: "Enter" });
    const again = spy.mock.calls.map((c) => c[0] as { type: string; sections?: Record<string, string> }).filter((m) => m.type === "cl:names").at(-1);
    expect(again?.sections?.hero).toBe("主視覺"); // 改名 ⇒ 重推
  });

});
