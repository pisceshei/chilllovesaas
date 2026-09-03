import { describe, expect, it } from "vitest";
import { effectiveValue, formatColor, parseColor } from "./SettingControls";

// E4：官方 default 規則（input-settings 逐字，external-facts §F7）與色彩值形
describe("effectiveValue", () => {
  it("S1 checkbox 未給 default ⇒ false（官方：If `default` is unspecified, then the value is `false` by default）", () => {
    expect(effectiveValue({ id: "a", type: "checkbox" }, undefined)).toBe(false);
    expect(effectiveValue({ id: "a", type: "checkbox", default: true }, undefined)).toBe(true);
    expect(effectiveValue({ id: "a", type: "checkbox", default: true }, false)).toBe(false); // 實例值優先
  });

  it("S2 radio／select 未給 default ⇒ 第一個選項；text_alignment ⇒ left；range 保留 undefined（default 必填，由 schema 給）", () => {
    const options = [ { value: "x", label: "X" }, { value: "y", label: "Y" } ];
    expect(effectiveValue({ id: "a", type: "select", options }, undefined)).toBe("x");
    expect(effectiveValue({ id: "a", type: "radio", options }, undefined)).toBe("x");
    expect(effectiveValue({ id: "a", type: "text_alignment" }, undefined)).toBe("left");
    expect(effectiveValue({ id: "a", type: "range", min: 0, max: 10 }, undefined)).toBeUndefined();
    expect(effectiveValue({ id: "a", type: "text" }, null)).toBeUndefined(); // null 視同未設
  });
});

describe("parseColor / formatColor", () => {
  it("S3 hex／短 hex／hex8／rgba 皆可解析；輸出 alpha=1 ⇒ #rrggbb、alpha<1 ⇒ rgba()", () => {
    expect(parseColor("#ff0000")).toEqual({ r: 255, g: 0, b: 0, a: 1 });
    expect(parseColor("#F00")).toEqual({ r: 255, g: 0, b: 0, a: 1 });
    expect(parseColor("#ff000080")?.a).toBeCloseTo(0.5, 1);
    expect(parseColor("rgba(1, 2, 3, 0.25)")).toEqual({ r: 1, g: 2, b: 3, a: 0.25 });
    expect(parseColor("nonsense")).toBeNull();
    expect(formatColor({ r: 255, g: 0, b: 0, a: 1 })).toBe("#ff0000");
    expect(formatColor({ r: 255, g: 0, b: 0, a: 0.5 })).toBe("rgba(255, 0, 0, 0.5)");
  });
});
