import { useCallback, useId, useMemo, useState } from "react";
import type { KeyboardEvent as ReactKeyboardEvent, RefObject } from "react";
import { Button } from "./Button";
import { Calendar } from "./Calendar";
import { Popover } from "./Popover";
import { TextField } from "./TextField";
import { useT, useUiLocale } from "../i18n/I18nContext";
import type { WallClock } from "../lib/timezone";
import {
  formatWallDate,
  formatWallTime12h,
  instantToWallClock,
  parseTimeInput,
  wallClockToInstant,
  zoneOffsetLabel,
} from "../lib/timezone";

/**
 * 排程發布彈層（S6b-2；本尊 `Schedule publishing`，`docs/research/82` §15）。
 *
 * ①這是什麼：發布 modal 內某個管道列的日曆圖示開出的浮層——日期欄／時間欄
 *   （右側內嵌時區徽章）／月曆／頁尾三顆鈕。**只掛在 `supportsFuturePublishing`
 *   的管道上**（§15.10：icon 的顯示條件是能力旗標，不是「目前已發布」）。
 *
 * ②值域與交互全部照 §15.3／§15.4 實測：
 *   - 日期欄**可打字但只吃 ISO `YYYY-MM-DD`**，顯示成長格式；**錯誤靜默回退**到上一個
 *     有效值（本尊沒有錯誤訊息、沒有紅框）。
 *   - 時間欄 12 小時制顯示，**24 小時制輸入也吃**；下拉是 30 分鐘刻度**但打字不吸附**。
 *   - 🔴 **選「今天」時的過去時間會被靜默吸附到 now**——本尊的決定性實測是：
 *     先設 `11:00 PM` 再打 `1:00 PM`，blur 後值變成**當下時刻**而不是回退到 `11:00 PM`
 *     ⇒ 那不是「回退上一個有效值」，是**夾到 now**。
 *
 * ③🔴 **`Remove schedule` 的終態是「立即發布」不是「清空」**（§15.7 抓包）：
 *   本尊送的是 `publishDate: <當下時刻>`，不是 null ⇒ 該管道變成已發布。
 *   本元件因此把它做成 `onApply(now)` 而不是 `onApply(null)`。
 *
 * ④跨功能影響：`values.publicationDelta` 的排程欄、送出時的 `publishDate`
 *   （UTC 帶毫秒 `Z`，§15.8）、發布卡的排程 badge。
 *
 * 🔴 **所有「今天／現在」一律走店鋪時區**（`shopTimezone`），不是瀏覽器時區——
 * 本尊的徽章證實時區是後端下發的（§15.6：React fiber prop `timeZone: "Asia/Hong_Kong"`
 * 而瀏覽器是 `Asia/Taipei`）。
 *
 * @see docs/dev/m2-schedule-popover.md
 */
export interface SchedulePopoverProps {
  /**
   * 🔴 **本元件沒有 `open` prop——呼叫端必須條件渲染** `{open && <SchedulePopover …/>}`。
   *
   * 本尊實測（`82` §15.10）：每次重開彈層**完全重置**（月曆回當月、未按 Done 的編輯全丟）。
   * 初版把 `open` 當 prop、state 宣告在本元件上 ⇒ 關閉時只有內層 `Popover` 下線、
   * 本元件仍掛載、`useState` 的初值不會重取 ⇒ 商家把日期打成 12/25、月曆翻到 12 月、
   * 按 Cancel 再重開，看到的還是 12/25 和 12 月。條件渲染讓 unmount 自然清空，
   * 與 `PublishingModal`（S6b）同一個慣例。
   */
  anchorRef: RefObject<HTMLElement | null>;
  /** 店鋪的 IANA 時區（`Query.shop.ianaTimezone`）。 */
  shopTimezone: string;
  /** 現在（毫秒 epoch）。**由呼叫端注入**，元件本身不碰 `Date.now()`（可測）。 */
  now: number;
  /** 已存的排程時刻；null＝尚未排程。 */
  scheduledAt: number | null;
  /** 是否已有**已儲存**的排程（決定 `Remove schedule` 能不能按，§15.7）。 */
  hasSavedSchedule: boolean;
  /**
   * 套用一個排程時刻。
   *
   * 🔴 **本元件在呼叫它之後會自己 `onClose()`**——本尊實測 `Remove schedule`
   * 與 `Done` 都是**按下即關**（`82` §15.7）。把關閉交給呼叫端的話，每個消費端
   * 都要記得做一次，漏掉的那個症狀是「按了完成但彈層還在」。
   */
  onApply: (instant: number) => void;
  onClose: () => void;
}

/** 30 分鐘刻度的時間選項（`HH:mm`）。 */
function halfHourSlots(): string[] {
  return Array.from({ length: 48 }, (_, i) =>
    `${String(Math.floor(i / 2)).padStart(2, "0")}:${i % 2 === 0 ? "00" : "30"}`);
}

export function SchedulePopover({
  anchorRef,
  shopTimezone,
  now,
  scheduledAt,
  hasSavedSchedule,
  onApply,
  onClose,
}: SchedulePopoverProps) {
  const t = useT();
  const uiLocale = useUiLocale();
  const dateId = useId();
  const timeId = useId();

  // 店鋪時區下的「現在」與「今天」——所有下限判斷的基準
  const nowWall = useMemo(() => instantToWallClock(now, shopTimezone), [now, shopTimezone]);
  const initial = useMemo(
    () => instantToWallClock(scheduledAt ?? now, shopTimezone),
    [scheduledAt, now, shopTimezone],
  );

  const [ date, setDate ] = useState(initial.date);
  const [ time, setTime ] = useState(initial.time);
  // 🔴 月份游標**獨立於選中值**（§15.3：打字選了非當月日期時月曆不跳頁）
  const [ cursor, setCursor ] = useState(initial.date);
  const [ dateDraft, setDateDraft ] = useState(() => formatWallDate(initial.date, uiLocale));
  const [ timeDraft, setTimeDraft ] = useState(formatWallTime12h(initial.time));
  const [ slotsOpen, setSlotsOpen ] = useState(false);

  // 🔴 APG combobox：DOM 焦點**留在 input**，用 `aria-activedescendant` 標示 popup 內的
  //   active option ⇒ 需要一個 index。-1＝尚未用鍵盤移動過。
  const [ activeSlot, setActiveSlot ] = useState(-1);
  const listboxId = useId();

  /**
   * 把 (date, time) 夾到不早於「現在」，並**正規化成實際會發布的當地時間**。
   *
   * 🔴 **比較必須在 instant 域做，不能比牆鐘字串**——牆鐘→instant 的映射在 DST 日
   * **不是單調的**，字串上「不早於 now」的值仍可能落在 now 之前。審查實跑三例：
   * ①前跳日 now＝當地 01:45 EST，選 `2:00 AM` ⇒ instant 比 now **早 45 分鐘**
   *   （字串上 `02:00 >= 01:45` 通過檢查，但 02:00 不存在、解到 01:00 EST）；
   * ②回撥日第二輪什麼都沒改按 Done ⇒ **早整整 60 分鐘**（解到重複小時的第一輪）；
   * ③**所有時區都會發生（含香港）**：`nowWall` 的秒被截掉 ⇒ 早 40.5 秒。
   *
   * 🔴 **回傳正規化後的牆鐘**（不是原輸入）：選到 gap 時間時，欄位顯示的必須是
   * **實際會發布的那個當地時間**。不回寫的話商家在欄位看到 `2:00 AM`、
   * 實際在 `1:00 AM` 發布，而中間沒有任何一步告訴他。
   */
  const normalize = useCallback((day: string, wallTime: string): WallClock => {
    const raw = wallClockToInstant({ date: day, time: wallTime }, shopTimezone);
    if (raw === null) return { date: day, time: wallTime };
    return instantToWallClock(Math.max(raw, now), shopTimezone);
  }, [shopTimezone, now]);

  /** 日期欄 blur：只吃 ISO；不合法**靜默回退**（本尊無錯誤訊息）。 */
  const commitDate = useCallback(() => {
    const raw = dateDraft.trim();
    const valid = /^\d{4}-\d{2}-\d{2}$/.test(raw) && wallClockToInstant({ date: raw, time: "00:00" }, shopTimezone) !== null;
    if (!valid || raw < nowWall.date) {
      setDateDraft(formatWallDate(date, uiLocale));   // 回退到上一個有效值（同樣長格式）
      return;
    }
    const next = normalize(raw, time);
    setDate(next.date);
    setDateDraft(formatWallDate(next.date, uiLocale));
    setTime(next.time);
    setTimeDraft(formatWallTime12h(next.time));
  }, [dateDraft, date, time, shopTimezone, nowWall.date, normalize, uiLocale]);

  /** 時間欄 blur：12／24 小時制都吃；今天的過去時間**夾到 now**（不是回退）。 */
  const commitTime = useCallback(() => {
    const parsed = parseTimeInput(timeDraft);
    if (parsed === null) {
      setTimeDraft(formatWallTime12h(time));    // 不合法才回退
      return;
    }
    const next = normalize(date, parsed);
    setDate(next.date);
    setDateDraft(formatWallDate(next.date, uiLocale));
    setTime(next.time);
    setTimeDraft(formatWallTime12h(next.time));
  }, [timeDraft, time, date, normalize]);

  const pickSlot = useCallback((slot: string) => {
    const next = normalize(date, slot);
    setDate(next.date);
    setDateDraft(formatWallDate(next.date, uiLocale));
    setTime(next.time);
    setTimeDraft(formatWallTime12h(next.time));
    setSlotsOpen(false);
    setActiveSlot(-1);
  }, [date, normalize]);

  const pickDay = useCallback((day: string) => {
    const next = normalize(day, time);
    setDate(next.date);
    setDateDraft(formatWallDate(next.date, uiLocale));
    setTime(next.time);
    setTimeDraft(formatWallTime12h(next.time));
  }, [time, normalize]);

  const instant = useMemo(() => wallClockToInstant({ date, time }, shopTimezone), [date, time, shopTimezone]);

  // 🔴 今天只給**剩餘**的刻度（§15.4：當下 21:17 時 listbox 只剩 5 個選項）。
  //   比較同樣在 **instant 域**（理由見 `normalize`）；另濾掉當日**不存在**的牆鐘
  //   （DST 前跳的那一小時）——留著會讓使用者選了之後被靜默改成別的時間。
  const slots = useMemo(
    () => halfHourSlots().filter((slot) => {
      const at = wallClockToInstant({ date, time: slot }, shopTimezone);
      if (at === null || at < now) return false;
      return instantToWallClock(at, shopTimezone).time === slot;   // gap 的 slot 回讀不相等
    }),
    [date, shopTimezone, now],
  );

  /**
   * 時間欄的鍵盤（APG Combobox）。
   *
   * 🔴 **Escape 在 popup 開著時只關 popup**，不關整個排程彈層——否則本包宣稱要避免的
   * 「一個 Escape 丟掉一整層編輯」在下拉這一層原樣重演。做法是 `stopPropagation()`
   * 擋住 `Popover` 掛在 document capture 階段的那個 listener。
   */
  const handleTimeKeyDown = useCallback((event: ReactKeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Escape" && slotsOpen) {
      event.preventDefault();
      event.stopPropagation();
      setSlotsOpen(false);
      setActiveSlot(-1);
      return;
    }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!slotsOpen) { setSlotsOpen(true); return; }
      const delta = event.key === "ArrowDown" ? 1 : -1;
      setActiveSlot((current) => {
        const next = current + delta;
        if (next < 0) return slots.length - 1;
        if (next >= slots.length) return 0;
        return next;
      });
      return;
    }
    if (event.key === "Enter" && slotsOpen && activeSlot >= 0) {
      event.preventDefault();
      pickSlot(slots[activeSlot]);
    }
  }, [slotsOpen, activeSlot, slots, pickSlot]);

  // 🔴 dirty 判準＝牆鐘值與開場值不同（理由見下方 Done 鈕的註釋）
  const changed = date !== initial.date || time !== initial.time;

  // 徽章以**目標時刻**為基準算偏移，不是「現在」（跨 DST 會差一小時）
  const offsetLabel = zoneOffsetLabel(instant ?? now, shopTimezone);

  // 🔴 popup 開著時，Escape／點外先關 popup 而不是整個彈層——`Popover` 的 Escape 是
  //   document capture 階段的 listener，比 React 的 onKeyDown 更早，所以「哪一層先關」
  //   必須在這裡用 `onClose` 分流，不能靠內層 handler 攔截。
  return (
    <Popover
      anchorRef={anchorRef}
      label={t("schedule.title")}
      onClose={slotsOpen ? () => { setSlotsOpen(false); setActiveSlot(-1); } : onClose}
      open
    >
      <div className="cl-sched">
        <h3 className="cl-sched__title">{t("schedule.title")}</h3>

        {/* 🔴 blur 後顯示**長格式**（本尊 §15.3 逐字「`2026-09-15` → blur 後
            `September 15, 2026`」）；**聚焦時切回 ISO** 供編輯。
            ⚠️ 後半是**刻意偏離**：本尊的日期欄「不能回打自己的顯示格式」
            （打 `October 5, 2026` 會被吃成 `52026`，§15.3）——那是可用性缺陷，
            我方讓聚焦時就是可編輯的 ISO，避開它。 */}
        <TextField
          id={dateId}
          label={t("schedule.date")}
          onBlur={commitDate}
          onChange={(event) => setDateDraft(event.target.value)}
          onFocus={() => setDateDraft(date)}
          placeholder="YYYY-MM-DD"
          value={dateDraft}
        />

        <div className="cl-sched__time">
          {/* 🔴 APG Combobox Pattern（取證 2026-08-27）：
              - popup 及其後代**排除在 Tab 序列外**，逐字 `The popup indicator icon or button
                (if present), the popup, and the popup descendants are excluded from the page
                Tab sequence.` ⇒ option 用 `<li role="option">` 不用 `<button>`。
              - DOM 焦點留在 input，用 `aria-activedescendant` 指向 active option。
              - `aria-controls` 建立 input 與 popup 的關聯。
              初版把 48 個 option 做成原生 `<button>` 且只綁 `onMouseDown` ⇒ 鍵盤使用者
              要按 51 次 Tab 才走得到月曆，而且 Enter／方向鍵**一律無效**（審查實跑）。 */}
          <TextField
            aria-activedescendant={slotsOpen && activeSlot >= 0 ? `${listboxId}-${activeSlot}` : undefined}
            aria-autocomplete="list"
            aria-controls={slotsOpen ? listboxId : undefined}
            aria-expanded={slotsOpen}
            id={timeId}
            label={t("schedule.time")}
            onBlur={() => { commitTime(); setSlotsOpen(false); setActiveSlot(-1); }}
            onChange={(event) => setTimeDraft(event.target.value)}
            onFocus={() => setSlotsOpen(true)}
            onKeyDown={handleTimeKeyDown}
            role="combobox"
            value={timeDraft}
          />
          {/* 時區徽章內嵌在時間欄右側（本尊形態，§15.6：逐字 `GMT+8`、無 tooltip） */}
          <span className="cl-sched__tz">{offsetLabel}</span>
          {slotsOpen ? (
            /* 🔴 `<li>` 直接就是 option——初版是 `<ul role="listbox"><li><button role="option">`，
               中間那層 `<li>` 夾在 listbox 與 option 之間，違反 listbox 的 required owned
               elements 與 option 的 required context role。 */
            <ul className="cl-sched__slots" id={listboxId} role="listbox">
              {slots.map((slot, index) => (
                <li
                  aria-selected={slot === time}
                  className={`cl-sched__slot ${index === activeSlot ? "cl-sched__slot--active" : ""}`.trim()}
                  id={`${listboxId}-${index}`}
                  key={slot}
                  onMouseDown={(event) => { event.preventDefault(); pickSlot(slot); }}
                  role="option"
                >
                  {formatWallTime12h(slot)}
                </li>
              ))}
            </ul>
          ) : null}
        </div>

        <Calendar
          cursor={cursor}
          min={nowWall.date}
          onCursorChange={setCursor}
          onDismiss={onClose}
          onSelect={pickDay}
          today={nowWall.date}
          value={date}
        />

        <div className="cl-sched__foot">
          {/* 🔴 `Remove schedule` 送的是**現在**不是 null（§15.7）⇒ 終態是「立即發布」。
              啟用條件是「已**儲存**的排程存在」，不是「本次編輯有值」。 */}
          <Button
            disabled={!hasSavedSchedule}
            onClick={() => { onApply(now); onClose(); }}
            variant="critical"
          >
            {t("schedule.remove")}
          </Button>
          <Button onClick={onClose}>{t("common.cancel")}</Button>
          {/* 🔴 **未改動時 disabled**（本尊 §12.3 頁尾逐字「`Done`（未改動時 disabled）」）。
              判準是**牆鐘值**與開場值比對，不是「碰過沒」也不是 instant 比對：
              instant 比對在重複小時會把「改了又改回」誤判成已改動，於是按下 Done 會送出
              一個平移了 60 分鐘的值（審查實跑 NY／London／Sydney 各一例）。 */}
          <Button
            disabled={instant === null || !changed}
            onClick={() => { if (instant !== null) { onApply(instant); onClose(); } }}
            variant="primary"
          >
            {t("common.done")}
          </Button>
        </div>
      </div>
    </Popover>
  );
}
