/**
 * ICU MessageFormat **子集**（docs/plans/2026-08-23-多語言方案.md §5.1）：
 *   - 插值：`{name}`
 *   - 複數：`{count, plural, =0 {無} one {# 件} other {# 件}}`（`#` 代入數字；類別由 Intl.PluralRules 決定）
 *   - 選擇：`{kind, select, a {…} b {…} other {…}}`
 * 刻意不引入 i18n 框架（鐵律 1：未討論的重型依賴）；需要完整 ICU（日期/序數/巢狀）時再議。
 * 🔴 金額不走這裡（鐵律 3/10：幣別符號與位數由市場決定，見 lib/money.ts）。
 */
export type MessageValues = Record<string, string | number>;

/** 找到與 `{` 配對的 `}`（支援巢狀大括號）。 */
function matchingBrace(source: string, openIndex: number): number {
  let depth = 0;
  for (let index = openIndex; index < source.length; index += 1) {
    const char = source[index];
    if (char === "{") depth += 1;
    else if (char === "}") {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}

/** 解析 `=0 {…} one {…} other {…}` 形態的分支表。 */
function parseBranches(body: string): Record<string, string> {
  const branches: Record<string, string> = {};
  let cursor = 0;
  while (cursor < body.length) {
    const open = body.indexOf("{", cursor);
    if (open === -1) break;
    const key = body.slice(cursor, open).trim();
    const close = matchingBrace(body, open);
    if (close === -1) break;
    branches[key] = body.slice(open + 1, close);
    cursor = close + 1;
  }
  return branches;
}

/**
 * 渲染一則訊息。缺少的變數原樣保留 `{name}`（開發期可見，不靜默成空白——原則 2）。
 *
 * @param message - 訊息範本
 * @param values - 插值
 * @param locale - 複數規則用的 BCP-47 標籤
 */
export function formatMessage(message: string, values: MessageValues = {}, locale = "en"): string {
  let output = "";
  let cursor = 0;
  while (cursor < message.length) {
    const open = message.indexOf("{", cursor);
    if (open === -1) {
      output += message.slice(cursor);
      break;
    }
    output += message.slice(cursor, open);
    const close = matchingBrace(message, open);
    if (close === -1) {
      output += message.slice(open);
      break;
    }
    const inner = message.slice(open + 1, close);
    const firstComma = inner.indexOf(",");
    if (firstComma === -1) {
      const name = inner.trim();
      output += name in values ? String(values[name]) : `{${name}}`;
    } else {
      const name = inner.slice(0, firstComma).trim();
      const rest = inner.slice(firstComma + 1);
      const secondComma = rest.indexOf(",");
      const kind = (secondComma === -1 ? rest : rest.slice(0, secondComma)).trim();
      const body = secondComma === -1 ? "" : rest.slice(secondComma + 1);
      const branches = parseBranches(body);
      const raw = values[name];
      let chosen: string | undefined;
      if (kind === "plural") {
        const count = typeof raw === "number" ? raw : Number(raw ?? 0);
        chosen = branches[`=${count}`] ?? branches[new Intl.PluralRules(locale).select(count)] ?? branches.other;
        chosen = (chosen ?? "").replaceAll("#", new Intl.NumberFormat(locale).format(count));
      } else if (kind === "select") {
        chosen = branches[String(raw)] ?? branches.other ?? "";
      } else {
        chosen = name in values ? String(raw) : `{${name}}`;
      }
      output += formatMessage(chosen, values, locale);
    }
    cursor = close + 1;
  }
  return output;
}
