/**
 * 前端金額工具——鐵律 3 在 SPA 端的落實形（對照原型 MONEYIN/pdCents/fmtMoney）。
 *
 * 規則：
 * - 內部一律 **integer cents**；`null` ＝「未填」，與 0（真的零元）是兩件事
 *   （53 號 P0-17：`+el.value||0` 會把兩者壓成同一件事，禁止）。
 * - 輸入框收主單位、最多兩位小數、不含符號與千分位；送 API 前轉**恆兩位小數
 *   字串**（65 §B X12 的 R4 形；`Money::Decimal` 的 regex 是嚴格兩位）。
 * - float 不進金額本身：字串解析走「整數部分 ×100 ＋ 小數部分補位」的字串運算。
 */

/** 原型 `money` 驗證規則（`/^\d+(\.\d{1,2})?$/`）＋空值：合法回 true。 */
export function isValidMoneyInput(raw: string): boolean {
  const trimmed = raw.trim();
  if (trimmed === "") return true;
  return /^\d+(\.\d{1,2})?$/.test(trimmed);
}

/**
 * 輸入框字串 → integer cents；空字串回 null（未填），不合法回 undefined。
 *
 * 不經 float：`"128.5"` → 128×100 ＋ 50 ＝ 12850。
 */
export function parseMoneyToCents(raw: string): number | null | undefined {
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(trimmed);
  if (!match) return undefined;
  const whole = Number.parseInt(match[1], 10);
  const fraction = Number.parseInt((match[2] ?? "").padEnd(2, "0") || "0", 10);
  return whole * 100 + fraction;
}

/** integer cents → 送 API 的 R4 字串（恆兩位小數）；null 回 null。 */
export function centsToApiString(cents: number | null): string | null {
  if (cents === null) return null;
  if (!Number.isInteger(cents)) throw new TypeError(`金額必須是 integer cents，收到 ${cents}`);
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, "0")}`;
}

/** integer cents → 輸入框顯示值（兩位小數，無符號前綴）；null 回空字串。 */
export function centsToInputValue(cents: number | null): string {
  return cents === null ? "" : centsToApiString(cents)!;
}

/**
 * 利潤／利潤率衍生值（原型 pdProfitState 同構）。
 *
 * 算不出來一律回 null 標示 unknown、顯示 `--` 不是 0——「未填成本」的利潤不是 0
 * 而是不知道。利潤率由兩個整數相除後才進浮點，只取一位小數。
 */
export function profitState(priceCents: number | null, costCents: number | null): {
  profit: number | null;
  margin: number | null;
} {
  if (priceCents === null || costCents === null) return { profit: null, margin: null };
  const profit = priceCents - costCents;
  if (priceCents === 0) return { profit, margin: null };
  return { profit, margin: Math.round((profit * 1000) / priceCents) / 10 };
}
