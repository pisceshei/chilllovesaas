/**
 * 店鋪時區的牆鐘時間 ⇄ UTC 換算（S6b-2 排程發布）。
 *
 * ## 為什麼不能用 `new Date(...)` 直接做
 *
 * JS 的 `Date` 只認**執行環境的時區**與 UTC 兩種。排程發布要的是第三種：
 * **店鋪設定的 IANA 時區**——而它與瀏覽器時區經常不同（本尊實測環境即為
 * 瀏覽器 `Asia/Taipei`、店鋪 `Asia/Hong_Kong`，`docs/research/82` §15.6）。
 *
 * 🔴 **偏移不是常數**：同一個 IANA 時區的 UTC 偏移隨日期變（DST 與政治性變更）。
 * MDN 逐字 `To know the offset, we need two pieces of information, the time zone,
 * and the instant.`（<https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Temporal/ZonedDateTime>，
 * 取證 2026-08-27）⇒ **任何「用現在的偏移去換算一個未來時刻」的寫法都是錯的**，
 * 而它在不跨 DST 的時區（例如香港，全年 +08:00）上**100% 測綠**。
 *
 * ## 演算法：候選集合 ＋ 自洽性檢驗
 *
 * `Intl.DateTimeFormat` 只能「把一個 instant 格式化到某時區」，沒有反向 API。
 * 反推偏移的做法是把牆鐘欄位先**當成 UTC** 造一個 instant、格式化回該時區、取差值。
 * 但偏移依賴 instant，而我們手上只有牆鐘。
 *
 * ⇒ 做法是**列出候選再驗證**：用「前一天／當刻／後一天」三個偏移各解一次得到候選 `t`，
 * 再對每個候選檢驗**自洽性**——`asIfUtc - zoneOffsetMs(t) === t`（用 `t` 當地的實際偏移
 * 回頭解，得到的還是 `t`）。自洽的候選就是真的對應到那個牆鐘時間的 instant。
 *
 * 🔴 **DST 的兩種病態情形＝ours 顯式裁定**（MDN 逐字 `one local time can correspond to
 * zero, one, or many UTC times`；官方對本尊行為沉默，且 `82` §15 的量測環境是
 * 全年 +08:00 的香港 ⇒ **本尊在 DST 下的行為未取得**）：
 * - **零個自洽候選＝不存在的牆鐘時間**（春季前跳）⇒ 取 `Math.max(candidates)`，
 *   語義是**跳躍後的時刻**（往後推）。
 * - **多個自洽候選＝重複的牆鐘時間**（秋季回撥）⇒ 取 `Math.min`，語義是**較早**那一個。
 *
 * ⚠️ **2026-08-27 更正**：初版寫的是「兩次迭代」，並宣稱上面兩條是它的自然結果。
 * **那是錯的，而且錯在兩層**：①程式碼**根本沒有實作任何裁定**，落點只是偏移正負號的
 * 副產物；②那兩條敘述**只在 UTC 以西成立**——對抗性審查掃了全部 418 個 IANA 時區
 * ×2025–2031 的 DST 轉換點，實跑證實「往後推」在 **57 個時區是往回推**、
 * 「取較早」在 **73 個時區取的是較晚**。唯一同時符合兩條敘述的是 UTC 以西，
 * 也就是當時測試唯一覆蓋的 `America/New_York`。⇒ 改成上面的顯式裁定，
 * 行為在所有時區一致，並補 UTC 以東的正反格。
 *
 * @see docs/research/82-admin-channels.md §15.6／§15.8
 */

/**
 * 某個 instant 在某 IANA 時區的 UTC 偏移（毫秒；正數＝該時區在 UTC 之東）。
 *
 * 用 `hourCycle: "h23"` 明確要求 0–23（`hour12: false` 的午夜輸出在各實作間有已知差異）。
 *
 * ⚠️ **誠實登記：`% 24` 是防禦性的，現有測試證明不了它必要**。`hourCycle: "h23"` 規範上
 * 就回 0–23 ⇒ 拿掉那個取模，13 格全綠（MT5 突變實跑）。保留它是為了跨引擎的意外，
 * 不是為了通過任何一格測試。同型處置見 `channelSwitchId` 的 GID 轉義。
 */
function zoneOffsetMs(instant: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(new Date(instant));

  const pick = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? "0");
  const hour = pick("hour") % 24;
  const asIfUtc = Date.UTC(pick("year"), pick("month") - 1, pick("day"), hour, pick("minute"), pick("second"));
  return asIfUtc - instant;
}

/** 牆鐘欄位（店鋪時區下的年月日時分）。 */
export interface WallClock {
  /** `YYYY-MM-DD` */
  date: string;
  /** `HH:mm`（24 小時制） */
  time: string;
}

/** `YYYY-MM-DD` ＋ `HH:mm` 拆成數字；任一格式不合回 null。 */
function parseWallClock(wall: WallClock): [number, number, number, number, number] | null {
  const date = /^(\d{4})-(\d{2})-(\d{2})$/.exec(wall.date);
  const time = /^(\d{1,2}):(\d{2})$/.exec(wall.time);
  if (!date || !time) return null;

  const [ y, mo, d ] = [ Number(date[1]), Number(date[2]), Number(date[3]) ];
  const [ h, mi ] = [ Number(time[1]), Number(time[2]) ];
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null;
  // 🔴 逐欄範圍檢查擋不掉 2 月 30 日——`Date.UTC` 會把它捲到 3 月 2 日而不報錯。
  //   造出來之後比對回讀值，捲過的就是非法日期。
  const probe = new Date(Date.UTC(y, mo - 1, d));
  if (probe.getUTCFullYear() !== y || probe.getUTCMonth() !== mo - 1 || probe.getUTCDate() !== d) return null;

  return [ y, mo, d, h, mi ];
}

/**
 * 店鋪時區的牆鐘時間 → UTC instant。
 *
 * @returns 毫秒 epoch；輸入格式不合回 `null`
 */
export function wallClockToInstant(wall: WallClock, timeZone: string): number | null {
  const fields = parseWallClock(wall);
  if (!fields) return null;

  const [ y, mo, d, h, mi ] = fields;
  const asIfUtc = Date.UTC(y, mo - 1, d, h, mi);

  // 候選：用「前一天／當刻／後一天」的偏移各解一次。DST 轉換在一天內完成 ⇒ ±24h 涵蓋。
  const DAY = 86_400_000;
  const candidates = [ ...new Set(
    [ asIfUtc - DAY, asIfUtc, asIfUtc + DAY ].map((probe) => asIfUtc - zoneOffsetMs(probe, timeZone)),
  ) ];

  // 🔴 自洽性檢驗：用候選 `t` 當地的**實際**偏移回頭解，得到的還是 `t` 才算數。
  //   不自洽的候選對應的是「別的牆鐘時間」，不是使用者輸入的那一個。
  const consistent = candidates.filter((t) => asIfUtc - zoneOffsetMs(t, timeZone) === t);

  // 零個＝gap（不存在的牆鐘時間）⇒ 跳躍後的時刻；多個＝重複 ⇒ 較早那一個。
  return consistent.length === 0 ? Math.max(...candidates) : Math.min(...consistent);
}

/** UTC instant → 店鋪時區的牆鐘欄位。 */
export function instantToWallClock(instant: number, timeZone: string): WallClock {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).formatToParts(new Date(instant));

  const pick = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  const hour = String(Number(pick("hour")) % 24).padStart(2, "0");
  return { date: `${pick("year")}-${pick("month")}-${pick("day")}`, time: `${hour}:${pick("minute")}` };
}

/**
 * 時區徽章文字（本尊逐字形態＝`GMT+8`，`82` §15.6）。
 *
 * 🔴 **必須以「使用者選的那個目標時刻」為基準**，不得用 `Date.now()`——
 * 跨 DST 的時區在夏令與冬令的偏移不同，用當下算會標錯一個小時。
 *
 * @param at 目標 instant（毫秒 epoch）
 */
export function zoneOffsetLabel(at: number, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, timeZoneName: "shortOffset" })
    .formatToParts(new Date(at));
  return parts.find((part) => part.type === "timeZoneName")?.value ?? timeZone;
}

/**
 * 牆鐘日期顯示成長格式（本尊的日期欄顯示格式，`82` §15.3／§12.3）。
 *
 * `2026-09-15` → `September 15, 2026`（en）／`2026年9月15日`（zh-Hant）。
 * 🔴 用 `timeZone: "UTC"` 是刻意的——輸入已經是「某時區下的日曆日期」這個純字串，
 * 再套一次時區換算會讓它在跨日的偏移下位移一天。
 *
 * ⚠️ 本尊的 admin 顯示英文長格式；我方跟隨 **UI 語言**（與月曆的月份標籤同一個來源）。
 */
export function formatWallDate(day: string, locale: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
  if (!match) return day;
  return new Intl.DateTimeFormat(locale, {
    year: "numeric", month: "long", day: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))));
}

/**
 * 牆鐘時間顯示成 12 小時制（本尊的時間欄顯示格式，`82` §15.3）。
 *
 * `13:05` → `1:05 PM`；`00:30` → `12:30 AM`。
 */
export function formatWallTime12h(time: string): string {
  const match = /^(\d{1,2}):(\d{2})$/.exec(time);
  if (!match) return time;

  const hour24 = Number(match[1]);
  const suffix = hour24 < 12 ? "AM" : "PM";
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  return `${hour12}:${match[2]} ${suffix}`;
}

/**
 * 解析使用者輸入的時間，回 `HH:mm`（24 小時制）；不合法回 `null`。
 *
 * 本尊實測（`82` §15.3）兩種都吃：`11:00 PM` 與 `22:45`（後者自動轉成 `10:45 PM` 顯示）。
 * 🔴 **不吸附到半點**——下拉建議是 30 分鐘刻度，但打字保留分鐘級（`10:37 PM` 原樣留著）。
 */
export function parseTimeInput(raw: string): string | null {
  const text = raw.trim().toUpperCase();
  const match = /^(\d{1,2}):(\d{2})\s*(AM|PM)?$/.exec(text);
  if (!match) return null;

  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const meridiem = match[3];
  if (minute > 59) return null;

  if (meridiem) {
    if (hour < 1 || hour > 12) return null;
    if (meridiem === "AM") hour = hour === 12 ? 0 : hour;
    else hour = hour === 12 ? 12 : hour + 12;
  } else if (hour > 23) {
    return null;
  }
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}
