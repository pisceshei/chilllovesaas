import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { Calendar } from "./Calendar";
import { I18nProvider } from "../i18n/I18nContext";

/**
 * 月曆網格（S6b-2）。ARIA 契約照 W3C ARIA APG 的 Date Picker Dialog Example。
 *
 * 🔴 本組刻意用 **2026-08**（31 天、1 號是星期六）與 **2026-01/02**（跨年、月底不同）
 * 當測資——2026-08-01 是週六 ⇒ 第一列有 6 個空白格，能同時驗到補白對齊；
 * 1/31 → PageDown 落到 2/28 能驗到 APG 的「同號日不存在則落月底」。
 */
function Harness({
  value = null,
  min = "2026-08-27",
  today = "2026-08-27",
  onSelect = vi.fn(),
  onDismiss = vi.fn(),
  initialCursor = "2026-08-01",
}: {
  value?: string | null;
  min?: string;
  today?: string;
  onSelect?: (day: string) => void;
  onDismiss?: () => void;
  initialCursor?: string;
}) {
  const [ cursor, setCursor ] = useState(initialCursor);
  return (
    <I18nProvider initialLocale="zh-Hant">
      <Calendar
        cursor={cursor}
        min={min}
        onCursorChange={setCursor}
        onDismiss={onDismiss}
        onSelect={onSelect}
        today={today}
        value={value}
      />
    </I18nProvider>
  );
}

const cell = (day: number) => screen.getByRole("gridcell", { name: String(day) });

describe("Calendar 結構", () => {
  it("表頭七欄、Sun–Sat 固定順序（本尊 82 §12.3，不跟隨 locale 的週起始）", () => {
    render(<Harness />);
    const headers = screen.getAllByRole("columnheader");
    expect(headers).toHaveLength(7);
    // zh-Hant 的 Intl short weekday 是「週日」…「週六」；只驗首尾與順序不驗逐字
    expect(headers[0].getAttribute("abbr")).toMatch(/日|Sun/);
    expect(headers[6].getAttribute("abbr")).toMatch(/六|Sat/);
  });

  it("2026 年 8 月：31 格日期，1 號落在最後一欄（該日是星期六）", () => {
    render(<Harness />);
    // 🔴 補白格也是 gridcell（grid 的每列格數必須一致）⇒ 數「有日期文字的」那些
    const dayCells = screen.getAllByRole("gridcell").filter((c) => c.textContent?.trim());
    expect(dayCells).toHaveLength(31);

    const firstRow = screen.getAllByRole("row")[1];        // [0] 是表頭列
    const firstRowCells = within(firstRow).getAllByRole("gridcell");
    expect(firstRowCells).toHaveLength(7);                 // 每列恆七格
    expect(firstRowCells.filter((c) => c.textContent?.trim())).toHaveLength(1);
    expect(firstRowCells[6]).toHaveTextContent("1");       // 1 號是星期六 ⇒ 落最後一欄
  });

  it("🔴 min 之前的日期 aria-disabled（本尊：當日之前全部灰掉）", () => {
    render(<Harness />);
    expect(cell(26)).toHaveAttribute("aria-disabled", "true");
    expect(cell(27)).not.toHaveAttribute("aria-disabled");
  });

  it("🔴 aria-selected 全網格恰一格（APG 逐字 no other cells have aria-selected specified）", () => {
    render(<Harness value="2026-08-28" />);
    const selected = screen.getAllByRole("gridcell").filter((c) => c.getAttribute("aria-selected") === "true");
    expect(selected).toHaveLength(1);
    expect(selected[0]).toHaveTextContent("28");
  });

  it("🔴 roving tabindex：全網格恰一格 tabIndex=0（APG 逐字 only one gridcell ... in the Tab sequence）", () => {
    render(<Harness value="2026-08-28" />);
    const focusable = screen.getAllByRole("gridcell").filter((c) => c.getAttribute("tabindex") === "0");
    expect(focusable).toHaveLength(1);
    expect(focusable[0]).toHaveTextContent("28");
  });

  it("未選日期時 roving 落點是「今天」（APG：places focus on the current date）", () => {
    render(<Harness />);
    const focusable = screen.getAllByRole("gridcell").filter((c) => c.getAttribute("tabindex") === "0");
    expect(focusable[0]).toHaveTextContent("27");
  });

  /**
   * 🔴 `today` 由呼叫端用**店鋪時區**算好傳入，本元件不碰 `Date.now()`。
   * 用瀏覽器的今天會在跨日的時區差上錯一天。
   */
  it("🔴 今天標 aria-current=date，且用的是傳入的 today 不是系統時間", () => {
    render(<Harness today="2026-08-15" min="2026-08-15" />);
    expect(cell(15)).toHaveAttribute("aria-current", "date");
    expect(cell(27)).not.toHaveAttribute("aria-current");
  });
});

describe("Calendar 鍵盤（APG Date Picker Dialog）", () => {
  it("方向鍵：左右一天、上下一週（同月內）", async () => {
    render(<Harness min="2026-08-01" today="2026-08-13" />);
    cell(13).focus();

    await userEvent.keyboard("{ArrowRight}");
    await waitFor(() => expect(cell(14)).toHaveFocus());
    await userEvent.keyboard("{ArrowLeft}");
    await waitFor(() => expect(cell(13)).toHaveFocus());
    await userEvent.keyboard("{ArrowDown}");
    await waitFor(() => expect(cell(20)).toHaveFocus());   // +7
    await userEvent.keyboard("{ArrowUp}");
    await waitFor(() => expect(cell(13)).toHaveFocus());
  });

  it("🔴 方向鍵跨出當月時自動翻頁（8/27 往下一週＝9/3，8 月只有 31 天）", async () => {
    render(<Harness />);
    cell(27).focus();

    await userEvent.keyboard("{ArrowDown}");
    await waitFor(() => expect(screen.getByText("2026年9月")).toBeVisible());
    await waitFor(() => expect(cell(3)).toHaveFocus());
  });

  it("🔴 Home／End 是**本週**的週日與週六（不是月初月末）", async () => {
    render(<Harness />);
    cell(27).focus();                                       // 2026-08-27 是星期四

    await userEvent.keyboard("{Home}");
    await waitFor(() => expect(cell(23)).toHaveFocus());    // 該週週日
    await userEvent.keyboard("{End}");
    await waitFor(() => expect(cell(29)).toHaveFocus());    // 該週週六
  });

  it("PageUp／PageDown 換月，焦點落在同號日", async () => {
    render(<Harness />);
    cell(27).focus();

    await userEvent.keyboard("{PageDown}");
    await waitFor(() => expect(screen.getByText("2026年9月")).toBeVisible());
    await waitFor(() => expect(cell(27)).toHaveFocus());

    await userEvent.keyboard("{PageUp}");
    await waitFor(() => expect(screen.getByText("2026年8月")).toBeVisible());
  });

  it("Shift+PageUp／PageDown 換年", async () => {
    render(<Harness />);
    cell(27).focus();

    await userEvent.keyboard("{Shift>}{PageDown}{/Shift}");
    await waitFor(() => expect(screen.getByText("2027年8月")).toBeVisible());
    await userEvent.keyboard("{Shift>}{PageUp}{/Shift}");
    await waitFor(() => expect(screen.getByText("2026年8月")).toBeVisible());
  });

  /**
   * 🔴 APG 逐字：`the day of the month that has the same number. If that day does not
   * exist, moves focus to the last day of the month.`
   * 1/31 往後一個月 ⇒ 2 月沒有 31 號 ⇒ 落到 2/28（2026 非閏年）。
   */
  it("🔴 換月時同號日不存在 ⇒ 落到當月最後一天（1/31 → 2/28）", async () => {
    render(<Harness initialCursor="2026-01-01" min="2026-01-01" today="2026-01-01" />);
    cell(31).focus();

    await userEvent.keyboard("{PageDown}");
    await waitFor(() => expect(screen.getByText("2026年2月")).toBeVisible());
    await waitFor(() => expect(cell(28)).toHaveFocus());
  });

  it("Enter／Space 選取；aria-disabled 的日子不選", async () => {
    const onSelect = vi.fn();
    render(<Harness onSelect={onSelect} />);

    cell(28).focus();
    await userEvent.keyboard("{Enter}");
    expect(onSelect).toHaveBeenCalledWith("2026-08-28");

    onSelect.mockClear();
    cell(26).focus();                                        // min 之前
    await userEvent.keyboard("{Enter}");
    expect(onSelect).not.toHaveBeenCalled();
  });

  it("Escape 交給呼叫端決定關哪一層", async () => {
    const onDismiss = vi.fn();
    render(<Harness onDismiss={onDismiss} />);
    cell(27).focus();
    await userEvent.keyboard("{Escape}");
    expect(onDismiss).toHaveBeenCalledTimes(1);
  });

  /**
   * 🔴 由審查開出：原本的 roving tabindex 測試**只驗初始態**，
   * 而初版把 `focusDay` 由 `value`／`today` 導出 ⇒ 焦點移動後 `tabindex="0"` 紋風不動，
   * 「只驗初始態」的斷言分辨不出這兩種實作。roving tabindex 的整個用途就是記住位置：
   * 使用者 Tab 出去再 Tab 回來，應該落在他最後停的那一格。
   */
  it("🔴 tabindex=0 跟著焦點移動（roving 要真的 roving）", async () => {
    render(<Harness min="2026-08-01" today="2026-08-13" />);
    const focusable = () => screen.getAllByRole("gridcell")
      .filter((c) => c.getAttribute("tabindex") === "0");

    expect(focusable()[0]).toHaveTextContent("13");

    cell(13).focus();
    await userEvent.keyboard("{ArrowRight}{ArrowRight}");
    await waitFor(() => expect(cell(15)).toHaveFocus());

    // 🔴 初版在這裡仍是 13
    expect(focusable()).toHaveLength(1);
    expect(focusable()[0]).toHaveTextContent("15");
  });

  it("🔴 換月鈕真的換對方向（‹ 上個月、› 下個月）", async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "下個月" }));
    expect(screen.getByText("2026年9月")).toBeVisible();

    await userEvent.click(screen.getByRole("button", { name: "上個月" }));
    expect(screen.getByText("2026年8月")).toBeVisible();

    await userEvent.click(screen.getByRole("button", { name: "上個月" }));
    expect(screen.getByText("2026年7月")).toBeVisible();
    // 本尊可以往回翻到過去月份，該月全部 disabled（§15.5）
    expect(screen.getByRole("gridcell", { name: "15" })).toHaveAttribute("aria-disabled", "true");
  });

  it("點擊：可選的日子觸發 onSelect，灰掉的不觸發", async () => {
    const onSelect = vi.fn();
    render(<Harness onSelect={onSelect} />);

    await userEvent.click(cell(29));
    expect(onSelect).toHaveBeenCalledWith("2026-08-29");

    onSelect.mockClear();
    await userEvent.click(cell(3));
    expect(onSelect).not.toHaveBeenCalled();
  });
});
