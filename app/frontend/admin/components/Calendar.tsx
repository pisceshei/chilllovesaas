import { ChevronLeft, ChevronRight } from "lucide-react";
import { useCallback, useId, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { KeyboardEvent } from "react";
import { useT, useUiLocale } from "../i18n/I18nContext";

/**
 * 月曆網格（S6b-2 排程發布的日期選擇面）。
 *
 * ①這是什麼：一個月的日期網格 ＋ 上下月切換。本尊形態＝`‹ August 2026 ›` ＋ **Sun–Sat**
 *   表頭、**當日之前的日期全部灰掉不可選**（`docs/research/82` §12.3／§15.5）。
 *
 * ②🔴 **ARIA 形態照 W3C ARIA APG 的 Date Picker Dialog Example**
 *   （<https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/examples/datepicker-dialog/>，
 *   取證 2026-08-27）：
 *   - `<table role="grid">`，日期格用 `<td>`（**隱含 gridcell，不用 `<button>`**）
 *     ——APG 逐字 `Identifies the table element as a grid widget.`，並註明
 *     `the row, columnheader, and gridcell roles ... are implied`。
 *   - **roving tabindex**：APG 逐字 `only one gridcell within the grid is in the dialog
 *     Tab sequence`，其餘 `tabindex="-1"`。
 *   - 選中的那格 `aria-selected="true"`，APG 逐字 `no other cells have aria-selected specified`
 *     ⇒ **全網格恰一格**。
 *   - 不可選的日期用 `aria-disabled` **保留可聚焦**（APG Developing a Keyboard Interface
 *     逐字 `Screen reader users are far less likely to discover disabled elements that are
 *     not focusable`）。⚠️ APG 的 date picker 範例本身**沒有** disabled 日期，
 *     這條是從通則推到本情境，登記於 `docs/dev/m2-schedule-popover.md`。
 *
 * ③🔴 **月份游標是獨立 state，不跟隨 `value`**——本尊實測逐字「打字選了非當前月份的日期時，
 *   月曆不跳頁（打 `2026-10-05` 後表頭仍停在 `August 2026`）」（`82` §15.3）。
 *   直覺實作會讓月曆跟著選中值跳，那與本尊相反。
 *
 * ④🔴 **`today` 必須由呼叫端用店鋪時區算好傳進來**，本元件不碰 `Date.now()`。
 *   用瀏覽器的今天會在跨日的時區差上錯一天——例如店鋪在香港、商家人在紐約，
 *   紐約的 2026-09-01 晚上是香港的 09-02，「今天之前灰掉」會灰錯一天。
 *
 * @see docs/dev/m2-schedule-popover.md
 */

/** `YYYY-MM-DD` → UTC 毫秒（純日曆日期，不含時刻）。 */
function dayToUtc(day: string): number {
  const [ y, m, d ] = day.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

/** UTC 毫秒 → `YYYY-MM-DD`。 */
function utcToDay(ms: number): string {
  const at = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${at.getUTCFullYear()}-${pad(at.getUTCMonth() + 1)}-${pad(at.getUTCDate())}`;
}

/** 位移天數。 */
function addDays(day: string, delta: number): string {
  return utcToDay(dayToUtc(day) + delta * 86_400_000);
}

/**
 * 位移月份，落在同號日；該日不存在則落到當月最後一天。
 *
 * APG 對四個 Page 鍵的落點逐字：`the day of the month that has the same number.
 * If that day does not exist, moves focus to the last day of the month.`
 */
function addMonths(day: string, delta: number): string {
  const [ y, m, d ] = day.split("-").map(Number);
  const target = new Date(Date.UTC(y, m - 1 + delta, 1));
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  return utcToDay(Date.UTC(target.getUTCFullYear(), target.getUTCMonth(), Math.min(d, lastDay)));
}

/** 該月的日期格（前後補空白對齊週日起始）。 */
function monthGrid(cursor: string): (string | null)[][] {
  const [ y, m ] = cursor.split("-").map(Number);
  const firstWeekday = new Date(Date.UTC(y, m - 1, 1)).getUTCDay();          // 0＝週日
  const dayCount = new Date(Date.UTC(y, m, 0)).getUTCDate();

  const cells: (string | null)[] = Array.from({ length: firstWeekday }, () => null);
  for (let d = 1; d <= dayCount; d += 1) cells.push(utcToDay(Date.UTC(y, m - 1, d)));
  while (cells.length % 7 !== 0) cells.push(null);

  return Array.from({ length: cells.length / 7 }, (_, row) => cells.slice(row * 7, row * 7 + 7));
}

export interface CalendarProps {
  /** 選中的日期 `YYYY-MM-DD`；null＝未選。 */
  value: string | null;
  /** 目前顯示的月份 `YYYY-MM-DD`（只看年月）。**獨立於 `value`**，見檔頭 ③。 */
  cursor: string;
  onCursorChange: (cursor: string) => void;
  /** 可選的最早日期（含）；本尊是「今天」。 */
  min: string;
  /** 店鋪時區的今天 `YYYY-MM-DD`（本元件不碰 `Date.now()`，見檔頭 ④）。 */
  today: string;
  onSelect: (day: string) => void;
  /** Escape：由呼叫端決定關掉哪一層。 */
  onDismiss: () => void;
}

export function Calendar({ value, cursor, onCursorChange, min, today, onSelect, onDismiss }: CalendarProps) {
  const t = useT();
  const uiLocale = useUiLocale();
  const gridId = useId();
  const rows = useMemo(() => monthGrid(cursor), [cursor]);

  const inMonth = (day: string) => day.slice(0, 7) === cursor.slice(0, 7);

  /**
   * roving tabindex 的落點。
   *
   * 初始值＝已選日期 → 今天 → 該月一號（APG 逐字 `Move focus to selected date...
   * If no date has been selected, places focus on the current date.`）。
   *
   * 🔴 **它必須是 state 而不是導出值**——用方向鍵／PageUp／PageDown 移動焦點之後，
   * `tabindex="0"` 要**跟著移到新的那一格**，否則使用者 Tab 出去再 Tab 回來會落回舊位置
   * （roving tabindex 的整個用途就是記住位置）。初版把它由 `value`／`today` 導出
   * ⇒ 焦點移動時它紋風不動，而「只驗初始態」的測試分辨不出來（審查點名）。
   */
  const [ roving, setRoving ] = useState<string | null>(null);
  const focusDay =
    roving && inMonth(roving) ? roving
      : value && inMonth(value) ? value
        : inMonth(today) ? today
          : `${cursor.slice(0, 7)}-01`;

  const cellRefs = useRef(new Map<string, HTMLTableCellElement>());

  /**
   * 把焦點移到某一天；跨月時同時翻頁。
   *
   * 🔴 **這裡只更新 state，聚焦一律交給下面的 `useLayoutEffect`**——
   * 兩條路徑（同月／跨月）不再分岔。理由見該 effect 的註釋。
   */
  const moveFocus = useCallback((day: string) => {
    setRoving(day);
    if (!inMonth(day)) onCursorChange(day);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cursor, onCursorChange]);

  /**
   * 把焦點放到 `roving` 那一格。
   *
   * 🔴 **必須是 `useLayoutEffect`，不得用 `requestAnimationFrame`。**
   *
   * `handleKeyDown` 是**逐格掛在 `<td>` 上**的，只有 `document.activeElement` 落在某一格時
   * 才會觸發。跨月時 `<td key={day}>` 全部換 key ⇒ 原本被聚焦的那格被卸載
   * ⇒ activeElement 掉回 `document.body`。若補聚焦排到 rAF，在它執行前的窗口內按下的鍵
   * **不經過任何 `<td>`、被整個吞掉**——使用者連按（含鍵盤 auto-repeat）兩次 PageDown
   * 只會生效一次，月曆等於失去鍵盤焦點（WCAG 2.1.1）。
   *
   * 🔴 **這個窗口是量出來的，不是理論值**：jsdom 的 rAF 是 `setInterval(…, 1000/60)`，
   * 且只在 outstanding 數 0→1 時才建 interval ⇒ 每次跨月都要從零等一個新的 ≈16.7ms 週期。
   * 同一台機器把兩次按鍵的間隔縮到 22.2／22.8ms 就必敗（activeElement＝BODY），
   * 26.7／33.4ms 就會過——臨界值正好落在那個幀週期上（2026-08-28 實測）。
   * 舊寫法在本機恆勝只是因為 Windows 的 `setTimeout(0)` 粒度約 15.5ms，
   * 把 userEvent 的按鍵間隔撐到 54–97ms；Linux CI 上該粒度約 1ms ⇒ 偶發紅。
   *
   * `setRoving` 與 `onCursorChange` 在同一個事件裡被 React 批次成一次 render，
   * 而 layout effect 在 DOM 變更後、繪製前**同步**執行，此時新月份的格子與 ref 都已就位
   * ⇒ 窗口歸零。
   *
   * ⚠️ `roving === null`（初次掛載）時**不搶焦點**——彈層的焦點進場由 `Popover` 負責。
   *   這一條**是承重的**：拿掉它，掛載與點換月鈕都會把焦點拉進網格（突變實測殺掉 2 格）。
   *
   * ⚠️ `inMonth(roving)` 守衛擋的是「只換 cursor 沒換 roving」（點上／下月鈕後 roving
   *   還停在舊月份）。🔴 **它是純防禦、不可觀測**——下面的 `ref` 回呼在卸載時
   *   `cellRefs.current.delete(day)`，所以舊月份的 key 早已不在 map 裡，`get()` 回
   *   `undefined`；就算保留失效節點，對**已卸載元素**呼叫 `focus()` 依規範也是 no-op。
   *   2026-08-28 實測兩個突變（只拿掉本守衛／再加上不刪 ref）**都殺不掉任何測試**。
   *   保留它是因為它把前提寫成了程式碼，代價為零；但**不得**把它當成有測試覆蓋的防線。
   */
  useLayoutEffect(() => {
    if (roving === null || !inMonth(roving)) return;
    cellRefs.current.get(roving)?.focus();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roving, cursor]);

  const handleKeyDown = useCallback((event: KeyboardEvent<HTMLTableCellElement>, day: string) => {
    // 🔴 十三條照 APG（Tab／Shift+Tab 除外——本尊的排程面是 popover 不是 dialog，
    //   沒有 focus trap，Tab 照瀏覽器預設走出去，`82` §15.1）。
    const moves: Record<string, () => string> = {
      ArrowUp: () => addDays(day, -7),
      ArrowDown: () => addDays(day, 7),
      ArrowLeft: () => addDays(day, -1),
      ArrowRight: () => addDays(day, 1),
      // Home／End＝**本週**的週日／週六（不是月初／月末）
      Home: () => addDays(day, -new Date(dayToUtc(day)).getUTCDay()),
      End: () => addDays(day, 6 - new Date(dayToUtc(day)).getUTCDay()),
    };

    if (event.key === "PageUp") {
      event.preventDefault();
      moveFocus(addMonths(day, event.shiftKey ? -12 : -1));
      return;
    }
    if (event.key === "PageDown") {
      event.preventDefault();
      moveFocus(addMonths(day, event.shiftKey ? 12 : 1));
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      onDismiss();
      return;
    }
    if (event.key === " " || event.key === "Enter") {
      event.preventDefault();
      if (day >= min) onSelect(day);
      return;
    }
    const next = moves[event.key];
    if (!next) return;
    event.preventDefault();
    moveFocus(next());
  }, [min, moveFocus, onDismiss, onSelect]);

  const monthLabel = new Intl.DateTimeFormat(uiLocale, { year: "numeric", month: "long", timeZone: "UTC" })
    .format(new Date(dayToUtc(`${cursor.slice(0, 7)}-01`)));

  // 🔴 週幾名稱由 `Intl` 依 **UI 語言**產生，不進 i18n 檔——那會是 14 個純機械的 key
  //   （7 個縮寫 ＋ 7 個全名）× 5 個語言包，翻譯者能改壞、`Intl` 不會。
  //   ⚠️ 順序固定 **Sun–Sat**（本尊表頭，82 §12.3），**不跟隨 locale 的週起始**——
  //   `Intl` 沒有「該地區週從哪天開始」的穩定 API，而我們也不需要它。
  const weekdays = useMemo(() => {
    const short = new Intl.DateTimeFormat(uiLocale, { weekday: "short", timeZone: "UTC" });
    const long = new Intl.DateTimeFormat(uiLocale, { weekday: "long", timeZone: "UTC" });
    // 1970-01-04 是星期日
    return Array.from({ length: 7 }, (_, i) => {
      const at = new Date(Date.UTC(1970, 0, 4 + i));
      return { short: short.format(at), long: long.format(at) };
    });
  }, [uiLocale]);

  return (
    <div className="cl-cal">
      <div className="cl-cal__head">
        <button
          aria-label={t("calendar.previousMonth")}
          className="cl-icon-button"
          onClick={() => onCursorChange(addMonths(cursor, -1))}
          type="button"
        >
          <ChevronLeft aria-hidden="true" size={14} />
        </button>
        <span aria-live="polite" className="cl-cal__month" id={`${gridId}-label`}>{monthLabel}</span>
        <button
          aria-label={t("calendar.nextMonth")}
          className="cl-icon-button"
          onClick={() => onCursorChange(addMonths(cursor, 1))}
          type="button"
        >
          <ChevronRight aria-hidden="true" size={14} />
        </button>
      </div>

      <table aria-labelledby={`${gridId}-label`} className="cl-cal__grid" role="grid">
        <thead>
          <tr>
            {weekdays.map((weekday) => (
              <th abbr={weekday.long} key={weekday.long} scope="col">{weekday.short}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, rowIndex) => (
            <tr key={rowIndex}>
              {row.map((day, colIndex) => {
                if (!day) return <td className="cl-cal__pad" key={colIndex} role="gridcell" />;
                const disabled = day < min;
                const selected = day === value;
                return (
                  <td
                    // 🔴 `aria-current="date"` 標今天、`aria-selected` 標選中——**兩者並存是 ours**。
                    //   APG 的 date picker 範例**完全不含** `aria-current`（全文查證 2026-08-27），
                    //   而 MDN 只警告「不要拿 aria-current **取代** aria-selected」，沒有正面授權
                    //   兩者並存 ⇒ 無第一方背書，登記於 `docs/dev/m2-schedule-popover.md`。
                    aria-current={day === today ? "date" : undefined}
                    aria-disabled={disabled ? true : undefined}
                    aria-selected={selected ? true : undefined}
                    className={[
                      "cl-cal__day",
                      disabled ? "cl-cal__day--off" : "",
                      selected ? "cl-cal__day--on" : "",
                      day === today ? "cl-cal__day--today" : "",
                    ].filter(Boolean).join(" ")}
                    key={day}
                    onClick={() => { if (!disabled) onSelect(day); }}
                    onKeyDown={(event) => handleKeyDown(event, day)}
                    ref={(node) => { if (node) cellRefs.current.set(day, node); else cellRefs.current.delete(day); }}
                    // ⚠️ **顯式寫 `gridcell` 雖然冗餘，但刻意保留**：ARIA in HTML 規定
                    //   `<td>` 在 `role=grid` 的表格下隱含 `gridcell`（APG 也說 implied），
                    //   但那條**上下文推導**依賴實作——`dom-accessibility-api`（testing-library
                    //   的 role 計算）就沒做，會把它算成 `cell`。顯式寫讓 AX 語義不依賴推導完整度。
                    role="gridcell"
                    tabIndex={day === focusDay ? 0 : -1}
                  >
                    {Number(day.slice(8))}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
