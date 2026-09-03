import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
// Vite `?raw`：把橋腳本原文當字串載入（vite/client 型別已在 tsconfig types）
import SCRIPT from "../../../assets/javascripts/editor-bridge.js?raw";

/**
 * E6：預覽橋（app/assets/javascripts/editor-bridge.js）在 jsdom 內執行——同一份腳本給引擎注入。
 * 契約（100 §5／§9.5）：hover 藍框＋chip、section 邊界「+」⇒ cl:insert、點選 ⇒ cl:select、右鍵 ⇒ cl:contextmenu、
 * cl:highlight ⇒ 選中框＋浮動工具列＋shopify:section/block:select、工具列 ⇒ cl:op、cl:inspector 關 ⇒ 無覆疊、
 * cl:replace ⇒ shopify:section:load。
 * 橋只掛一次（document 級監聽會累積）；每例重設頁面內容與選取狀態。
 */
const PAGE = `
    <div id="shopify-section-template--index__hero" class="shopify-section" data-shopify-editor-section='{"id":"hero","type":"hero"}'>
      <h1>Hero</h1>
      <div data-shopify-editor-block='{"id":"b1","type":"text"}'><p>Block</p></div>
      <a href="/collections/all">Catalog</a>
    </div>
    <div id="shopify-section-template--index__demo" class="shopify-section" data-shopify-editor-section='{"id":"demo","type":"demo"}'><p>Demo</p></div>`;
const posted: unknown[] = [];
const listeners: [ string, EventListener ][] = [];

function fromParent(data: unknown) {
  window.dispatchEvent(new MessageEvent("message", { data, origin: window.location.origin }));
}
function listen(name: string, handler: EventListener) {
  document.addEventListener(name, handler);
  listeners.push([ name, handler ]);
}
const hero = () => document.getElementById("shopify-section-template--index__hero")!;
const overlay = (selector: string) => document.querySelector(selector) as HTMLElement;

beforeAll(() => {
  document.body.innerHTML = `<main id="page">${PAGE}</main>`;
  new Function(SCRIPT)(); // jsdom：window.parent === window ⇒ 監看 window.postMessage
});
beforeEach(() => {
  // vitest 每例後還原 mock ⇒ 每例重新監看（第一版只在 beforeAll 監看，B2 起全部收不到）
  vi.spyOn(window, "postMessage").mockImplementation((message: unknown) => { posted.push(message); });
  document.getElementById("page")!.innerHTML = PAGE;
  posted.length = 0;
  fromParent({ type: "cl:inspector", active: true });
  fromParent({ type: "cl:highlight", id: null, blockId: null }); // 清選取
  fromParent({ type: "cl:names", sections: {}, blocks: {} });
});
afterEach(() => {
  for (const [ name, handler ] of listeners) document.removeEventListener(name, handler);
  listeners.length = 0;
});

describe("editor-bridge", () => {
  it("B1 🔴 hover：藍框＋chip（名稱來自 cl:names）；section 上下邊界「+」點擊 ⇒ cl:insert；block 上 hover 用 block 名", () => {
    fromParent({ type: "cl:names", sections: { hero: "英雄橫幅" }, blocks: { hero: { b1: "文字塊" } }, labels: { addSection: "新增區段", duplicate: "建立副本", hide: "隱藏", remove: "移除" } });
    hero().querySelector("h1")!.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
    expect((document.querySelector(".cl-ov-insert") as HTMLElement).title).toBe("新增區段"); // 文字跟 admin 語系
    expect([ ...document.querySelectorAll(".cl-ov-bar button") ].map((x) => x.textContent)).toEqual([ "建立副本", "隱藏", "移除" ]);
    const chip = overlay(".cl-ov-chip");
    expect(chip.style.display).toBe("flex");
    expect(chip.textContent).toBe("英雄橫幅");
    expect(overlay(".cl-ov-box").style.display).toBe("block");
    const plus = document.querySelectorAll(".cl-ov-insert");
    expect(plus).toHaveLength(2);
    (plus[1] as HTMLElement).click();
    expect(posted.at(-1)).toEqual({ type: "cl:insert", id: "hero", position: "after" });
    hero().querySelector("[data-shopify-editor-block] p")!.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
    expect(chip.textContent).toBe("文字塊");
  });

  it("B2 🔴 點選 ⇒ cl:select（帶 blockId）；站內連結攔截 ⇒ cl:navigate；右鍵 ⇒ cl:contextmenu 帶座標", () => {
    hero().querySelector("[data-shopify-editor-block] p")!.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(posted.at(-1)).toEqual({ type: "cl:select", id: "hero", blockId: "b1" });
    hero().querySelector("a")!.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(posted.some((m) => (m as { type: string }).type === "cl:navigate" && (m as { path: string }).path === "/collections/all")).toBe(true);
    hero().querySelector("h1")!.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 40, clientY: 50 }));
    expect(posted.at(-1)).toEqual({ type: "cl:contextmenu", id: "hero", blockId: null, x: 40, y: 50 });
  });

  it("B3 🔴 cl:highlight ⇒ 選中框＋工具列＋shopify:section:select；換選 ⇒ 前者 deselect；block ⇒ shopify:block:select；工具列 ⇒ cl:op", () => {
    const events: string[] = [];
    for (const name of [ "shopify:section:select", "shopify:section:deselect", "shopify:block:select", "shopify:block:deselect" ]) {
      listen(name, (event) => events.push(`${name}:${JSON.stringify((event as CustomEvent).detail)}`));
    }
    fromParent({ type: "cl:highlight", id: "hero", blockId: null });
    expect(events.at(-1)).toBe('shopify:section:select:{"sectionId":"hero","load":false}');
    const bar = overlay(".cl-ov-bar");
    expect(bar.style.display).toBe("flex");
    expect([ ...bar.querySelectorAll("button") ].map((b) => b.getAttribute("data-cl-op"))).toEqual([ "duplicate", "hide", "remove" ]);
    (bar.querySelector('[data-cl-op="hide"]') as HTMLElement).click();
    expect(posted.at(-1)).toEqual({ type: "cl:op", op: "hide", id: "hero", blockId: null });
    fromParent({ type: "cl:highlight", id: "hero", blockId: "b1" });
    expect(events.slice(-2)).toEqual([ 'shopify:section:deselect:{"sectionId":"hero"}', 'shopify:block:select:{"blockId":"b1","sectionId":"hero","load":false}' ]);
  });

  it("B4 🔴 cl:inspector 關 ⇒ 覆疊全隱藏、hover／右鍵不作用、派 shopify:inspector:deactivate；開 ⇒ activate", () => {
    const events: string[] = [];
    for (const name of [ "shopify:inspector:activate", "shopify:inspector:deactivate" ]) listen(name, () => events.push(name));
    fromParent({ type: "cl:highlight", id: "hero", blockId: null });
    fromParent({ type: "cl:inspector", active: false });
    expect(events).toEqual([ "shopify:inspector:deactivate" ]);
    expect(overlay(".cl-ov-bar").style.display).toBe("none");
    hero().querySelector("h1")!.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
    expect(overlay(".cl-ov-chip").style.display).toBe("none");
    const before = posted.length;
    hero().querySelector("h1")!.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true }));
    expect(posted.length).toBe(before); // 右鍵不送
    fromParent({ type: "cl:inspector", active: true });
    expect(events.at(-1)).toBe("shopify:inspector:activate");
  });

  it("B5 🔴 cl:replace ⇒ 舊段 unload、新段 load；選中段被換時選中框跟到新元素", () => {
    const events: string[] = [];
    for (const name of [ "shopify:section:load", "shopify:section:unload" ]) {
      listen(name, (event) => events.push(`${name}:${(event as CustomEvent).detail.sectionId}`));
    }
    fromParent({ type: "cl:highlight", id: "demo", blockId: null });
    fromParent({ type: "cl:replace", id: "demo", html: '<div id="shopify-section-template--index__demo" class="shopify-section"><p>Demo v2</p></div>' });
    expect(events).toEqual([ "shopify:section:unload:demo", "shopify:section:load:demo" ]);
    expect(document.getElementById("shopify-section-template--index__demo")!.textContent).toBe("Demo v2");
    expect(overlay(".cl-ov-box.is-selected").style.display).toBe("block");
  });

  it("B6 異 origin 訊息忽略", () => {
    window.dispatchEvent(new MessageEvent("message", { data: { type: "cl:highlight", id: "hero" }, origin: "https://evil.example" }));
    expect(overlay(".cl-ov-box.is-selected").style.display).toBe("none");
  });
});
