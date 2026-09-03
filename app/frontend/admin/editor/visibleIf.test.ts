import { describe, expect, it } from "vitest";
import { evaluateVisibleIf, liquidTruthy } from "./visibleIf";

// E4：visible_if 求值器（Ella 實測值域＝66 §A.4；官方 operators 頁：由右往左、無括號、只有 false/nil 為假）
describe("evaluateVisibleIf", () => {
  const scope = {
    block: { inherit_color_scheme: false, type_preset: "custom", border: "none", width: "custom", toggle_overlay: true,
             background_media: "image", content_overlay: false, empty_text: "", count: 3, tags: [ "a", "b" ] },
    section: { background_media: "video" },
    settings: { show_countdown: true, countdown_type: "different_product" },
  };

  it("V1 Ella 最常見形：== / != / 裸布林（只有 false 與 nil 為假，空字串為真）", () => {
    expect(evaluateVisibleIf("{{ block.settings.inherit_color_scheme == false }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ block.settings.type_preset == 'custom' }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ block.settings.border != 'none' }}", scope)).toBe(false);
    expect(evaluateVisibleIf("{{ block.settings.toggle_overlay }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ block.settings.content_overlay }}", scope)).toBe(false);
    expect(evaluateVisibleIf("{{ block.settings.empty_text }}", scope)).toBe(true); // 官方：empty strings are truthy
    expect(evaluateVisibleIf("{{ block.settings.empty_text == blank }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ block.settings.missing }}", scope)).toBe(false); // nil 為假
  });

  it("V2 三個作用域：block／section／全域 settings（漏全域的症狀＝少數欄位永遠不顯示）", () => {
    expect(evaluateVisibleIf("{{ section.settings.background_media == 'image' }}", scope)).toBe(false);
    expect(evaluateVisibleIf("{{ section.settings.background_media == 'video' }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ settings.show_countdown == true and settings.countdown_type == 'different_product' }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ settings.show_countdown == true and settings.countdown_type != 'different_product' }}", scope)).toBe(false);
  });

  it("V3 🔴 and／or 由右往左（官方：evaluated from right to left, and you can't change this order）", () => {
    // a or b and c ＝ a or (b and c)：a=false, b=true, c=false ⇒ false（JS 優先序也是 false）；
    // 判準格：a=true, b=false, c=false ⇒ 右往左 true or (false and false)=true；
    // 反向格 `a and b or c`：a=false, b=true, c=true ⇒ 右往左 false and (true or true)=false，JS 優先序會是 true
    const s = { block: { a: false, b: true, c: true } };
    expect(evaluateVisibleIf("{{ block.settings.a and block.settings.b or block.settings.c }}", s)).toBe(false);
    expect(evaluateVisibleIf("{{ block.settings.c or block.settings.a and block.settings.b }}", s)).toBe(true);
    // Ella 實例："background_media == 'image' or background_media == 'video' and content_overlay"
    expect(evaluateVisibleIf("{{ block.settings.background_media == 'image' or block.settings.background_media == 'video' and block.settings.content_overlay }}", scope)).toBe(true);
  });

  it("V4 數值比較與 contains", () => {
    expect(evaluateVisibleIf("{{ block.settings.count > 2 }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ block.settings.count <= 2 }}", scope)).toBe(false);
    expect(evaluateVisibleIf("{{ block.settings.tags contains 'b' }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ block.settings.type_preset contains 'cus' }}", scope)).toBe(true);
  });

  it("V5 fail-open：無表達式／空／括號／不合法形狀 ⇒ 顯示；runtime 資料前綴視為 nil", () => {
    expect(evaluateVisibleIf(undefined, scope)).toBe(true);
    expect(evaluateVisibleIf("", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ (block.settings.a) }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ block.settings.a == }}", scope)).toBe(true);
    expect(evaluateVisibleIf("{{ product.available }}", scope)).toBe(false); // 官方：條件不能存取 runtime 資料 ⇒ nil ⇒ 假
  });

  it("V6 liquidTruthy", () => {
    expect([ false, null, undefined ].map(liquidTruthy)).toEqual([ false, false, false ]);
    expect([ 0, "", [], "x" ].map(liquidTruthy)).toEqual([ true, true, true, true ]);
  });
});
