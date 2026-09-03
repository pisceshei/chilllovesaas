/**
 * `visible_if` 條件顯示求值器（E4；純函式，跑在前端——設定一改就重算可見性）。
 *
 * ①這是什麼：schema setting 的 `visible_if` 是 Liquid 布林表達式字串（官方語法句逐字：
 *   `"visible_if": "{{ block.settings.layout_style == 'flex' }}"`，shopify.dev settings 頁，取證 2026-09-03）。
 *   Ella 6,735 個 setting 有 2,999 個帶它（`docs/research/66` §A.4）——不做等於面板攤開兩倍欄位。
 * ②值域（66 §A.4 fixture 實測＋官方 operators 頁）：運算子 `== != > < >= <= contains`、邏輯 `and`／`or`、
 *   引用 `block.settings.*`／`section.settings.*`／`settings.*`（全域）、字面量字串／數字／`true`／`false`／
 *   `nil`／`blank`／`empty`；無括號（官方："Parentheses `()` aren't valid characters within Liquid tags."）。
 * ③🔴 求值順序照 Liquid：官方逐字 "When using more than one operator in a tag, the operators are evaluated from
 *   right to left, and you can't change this order."（<https://shopify.dev/docs/api/liquid/basics/operators>，
 *   取證 2026-09-03）⇒ `a or b and c` ＝ `a or (b and c)`，不是 JS 的優先序。
 *   真假值照 Liquid：只有 `false` 與 `nil` 為假（官方：empty strings 為真，要用 `blank` 判空）。
 * ④fail-open：無 `visible_if`／空字串／解析失敗 ⇒ 顯示（本尊對不合法表達式的行為未取得；隱藏一個欄位
 *   比多顯示一個更糟）。隱藏的欄位**值仍保留**（官方未說明；我方不清值）。
 * ⑤跨功能影響：`ThemeEditorPage` 的 section／block／theme settings 三處面板；E5 picker 不用。
 */
export interface VisibleIfScope {
  /** 當前 block 的 settings（block 面板時） */
  block?: Record<string, unknown>;
  /** 當前 section 的 settings */
  section?: Record<string, unknown>;
  /** 全域 theme settings（14 條 Ella 條件引用它——漏了的症狀是「少數欄位永遠不顯示」） */
  settings?: Record<string, unknown>;
}

type Token =
  | { kind: "ref"; path: string[] }
  | { kind: "str"; value: string }
  | { kind: "num"; value: number }
  | { kind: "lit"; value: unknown }
  | { kind: "op"; value: string }
  | { kind: "logic"; value: "and" | "or" };

const COMPARISON = new Set([ "==", "!=", ">=", "<=", ">", "<", "contains" ]);
const LITERALS: Record<string, unknown> = { true: true, false: false, nil: null, null: null, blank: "", empty: "" };

/** 官方真假值：只有 false 與 nil 為假。 */
export function liquidTruthy(value: unknown): boolean {
  return value !== false && value !== null && value !== undefined;
}

function tokenize(source: string): Token[] | null {
  const tokens: Token[] = [];
  let i = 0;
  while (i < source.length) {
    const ch = source[i];
    if (/\s/.test(ch)) { i += 1; continue; }
    if (ch === "'" || ch === "\"") {
      const end = source.indexOf(ch, i + 1);
      if (end < 0) return null;
      tokens.push({ kind: "str", value: source.slice(i + 1, end) });
      i = end + 1;
      continue;
    }
    const two = source.slice(i, i + 2);
    if (two === "==" || two === "!=" || two === ">=" || two === "<=") { tokens.push({ kind: "op", value: two }); i += 2; continue; }
    if (ch === ">" || ch === "<") { tokens.push({ kind: "op", value: ch }); i += 1; continue; }
    const word = /^[A-Za-z_][\w.\-]*/.exec(source.slice(i));
    if (word) {
      const text = word[0];
      i += text.length;
      if (text === "and" || text === "or") tokens.push({ kind: "logic", value: text });
      else if (text === "contains") tokens.push({ kind: "op", value: text });
      else if (text in LITERALS) tokens.push({ kind: "lit", value: LITERALS[text] });
      else tokens.push({ kind: "ref", path: text.split(".") });
      continue;
    }
    const num = /^-?\d+(?:\.\d+)?/.exec(source.slice(i));
    if (num) { tokens.push({ kind: "num", value: Number(num[0]) }); i += num[0].length; continue; }
    return null; // 括號或其他字元 ⇒ 不合法（官方：括號不是合法字元）
  }
  return tokens;
}

function resolve(path: string[], scope: VisibleIfScope): unknown {
  // `block.settings.x`／`section.settings.x`／`settings.x`；其他前綴（如 `product.*`）＝runtime 資料，官方明說
  // 條件不能存取 ⇒ 視為 nil。
  if (path[0] === "settings") return scope.settings?.[path.slice(1).join(".")];
  if ((path[0] === "block" || path[0] === "section") && path[1] === "settings") {
    return scope[path[0]]?.[path.slice(2).join(".")];
  }
  return undefined;
}

function compare(op: string, left: unknown, right: unknown): boolean {
  switch (op) {
    case "==": return looseEqual(left, right);
    case "!=": return !looseEqual(left, right);
    case ">": return Number(left) > Number(right);
    case "<": return Number(left) < Number(right);
    case ">=": return Number(left) >= Number(right);
    case "<=": return Number(left) <= Number(right);
    case "contains":
      if (Array.isArray(left)) return left.some((item) => String(item) === String(right));
      return typeof left === "string" && left.includes(String(right));
    default: return false;
  }
}

/** Liquid 的 `==`：nil 與 blank 互不相等以外，數字／字串以值比（`"3" == 3` 在 Liquid 為 false，但 schema 裡不會出現）。 */
function looseEqual(left: unknown, right: unknown): boolean {
  if ((left === null || left === undefined) && (right === null || right === undefined)) return true;
  if (left === null || left === undefined || right === null || right === undefined) return false;
  return left === right;
}

function operand(token: Token | undefined, scope: VisibleIfScope): unknown {
  if (!token) return undefined;
  switch (token.kind) {
    case "ref": return resolve(token.path, scope);
    case "str": return token.value;
    case "num": return token.value;
    case "lit": return token.value;
    default: return undefined;
  }
}

/**
 * 求值；回 `true`＝顯示。無表達式／解析失敗 ⇒ true（fail-open）。
 * 結構：`clause (logic clause)*`，clause＝`operand (op operand)?`；邏輯由右往左結合（官方）。
 */
export function evaluateVisibleIf(expression: string | undefined | null, scope: VisibleIfScope): boolean {
  if (!expression) return true;
  const inner = expression.trim().replace(/^\{\{-?/, "").replace(/-?\}\}$/, "").trim();
  if (!inner) return true;
  const tokens = tokenize(inner);
  if (!tokens) return true;

  // 切成 clause 序列與邏輯運算子序列
  const clauses: Token[][] = [ [] ];
  const logics: ("and" | "or")[] = [];
  for (const token of tokens) {
    if (token.kind === "logic") { logics.push(token.value); clauses.push([]); } else clauses[clauses.length - 1].push(token);
  }
  const values: boolean[] = [];
  for (const clause of clauses) {
    if (clause.length === 1) values.push(liquidTruthy(operand(clause[0], scope)));
    else if (clause.length === 3 && clause[1].kind === "op" && COMPARISON.has(clause[1].value)) {
      values.push(compare(clause[1].value, operand(clause[0], scope), operand(clause[2], scope)));
    } else return true; // 形狀不合法 ⇒ fail-open
  }
  // 由右往左：result = v[n-1]；往左逐個套 logic[i]
  let result = values[values.length - 1];
  for (let index = values.length - 2; index >= 0; index -= 1) {
    result = logics[index] === "and" ? (values[index] && result) : (values[index] || result);
  }
  return result;
}
