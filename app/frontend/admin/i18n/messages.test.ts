import { describe, expect, it } from "vitest";
import { formatMessage } from "./format";
import { ALL_MESSAGES, translateWith } from "./I18nContext";
import { UI_LOCALES } from "./locales";

// 🔴 en 是 key 正典；其餘語言包 key 集合必須逐字相同（缺鍵＝畫面出現 key 本身；多鍵＝死字串）。
describe("i18n bundles", () => {
  const enKeys = Object.keys(ALL_MESSAGES.en).sort();

  it("五語包 key 集合與 en 完全一致", () => {
    for (const { tag } of UI_LOCALES) {
      const keys = Object.keys(ALL_MESSAGES[tag]).sort();
      expect(keys, `${tag} 的 key 集合與 en 不同`).toEqual(enKeys);
    }
  });

  it("每個值都是非空字串，且插值占位符與 en 同集合（漏掉 {name} 會顯示錯字）", () => {
    const placeholders = (message: string) =>
      [ ...message.matchAll(/\{(\w+)(?:,|\})/g) ].map((match) => match[1]).sort();
    for (const { tag } of UI_LOCALES) {
      for (const key of enKeys) {
        const value = ALL_MESSAGES[tag][key];
        expect(typeof value === "string" && value.trim().length > 0, `${tag}.${key} 為空`).toBe(true);
        expect(placeholders(value), `${tag}.${key} 的占位符與 en 不同`).toEqual(placeholders(ALL_MESSAGES.en[key]));
      }
    }
  });

  it("translateWith：缺鍵回 key 本身（不靜默空白）", () => {
    expect(translateWith("ja")("nav.products")).toBe("商品");
    expect(translateWith("fr")("does.not.exist")).toBe("does.not.exist");
  });
});

describe("formatMessage（ICU 子集）", () => {
  it("插值與缺變數保留", () => {
    expect(formatMessage("Hi {name}", { name: "Ken" })).toBe("Hi Ken");
    expect(formatMessage("Hi {name}", {})).toBe("Hi {name}");
  });

  it("plural 依 Intl.PluralRules；# 代入格式化數字；=N 精確分支優先", () => {
    const message = "{count, plural, =0 {none} one {# unit} other {# units}}";
    expect(formatMessage(message, { count: 0 }, "en")).toBe("none");
    expect(formatMessage(message, { count: 1 }, "en")).toBe("1 unit");
    expect(formatMessage(message, { count: 1234 }, "en")).toBe("1,234 units");
    // 中文無 one/other 之分：只給 other 也能命中
    expect(formatMessage("{count, plural, other {# 件}}", { count: 3 }, "zh-Hant")).toBe("3 件");
  });

  it("select 分支與 other fallback", () => {
    const message = "{kind, select, a {Alpha} other {Else}}";
    expect(formatMessage(message, { kind: "a" })).toBe("Alpha");
    expect(formatMessage(message, { kind: "zzz" })).toBe("Else");
  });
});
