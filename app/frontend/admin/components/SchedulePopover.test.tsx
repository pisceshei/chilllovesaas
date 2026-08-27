import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useRef } from "react";
import { describe, expect, it, vi } from "vitest";
import { SchedulePopover } from "./SchedulePopover";
import { I18nProvider } from "../i18n/I18nContext";

/**
 * 排程彈層（S6b-2）。值域與交互全部對位 `docs/research/82` §15.3／§15.4／§15.7。
 *
 * 🔴 測資刻意讓**店鋪時區與 UTC 差 8 小時**（`Asia/Hong_Kong`），且注入的 `now`
 * 選在「UTC 與香港不同日」的時刻——`2026-08-27T16:30:00Z` 在香港已是 **08-28 00:30**。
 * 用瀏覽器時區或 UTC 判斷「今天」的實作會在這裡露餡（會把 8/27 當今天）。
 */
function Harness({
  now = Date.parse("2026-08-27T16:30:00Z"),   // 香港 08-28 00:30
  scheduledAt = null as number | null,
  hasSavedSchedule = false,
  onApply = vi.fn(),
  onClose = vi.fn(),
  shopTimezone = "Asia/Hong_Kong",
}) {
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  return (
    <I18nProvider initialLocale="zh-Hant">
      <button ref={anchorRef} type="button">錨</button>
      <SchedulePopover
        anchorRef={anchorRef}
        hasSavedSchedule={hasSavedSchedule}
        now={now}
        onApply={onApply}
        onClose={onClose}
        scheduledAt={scheduledAt}
        shopTimezone={shopTimezone}
      />
    </I18nProvider>
  );
}

const dateBox = () => screen.getByLabelText("日期");
const timeBox = () => screen.getByLabelText("時間");

describe("SchedulePopover 預設值與時區", () => {
  it("🔴 **預設值**用店鋪時區換算（now 在 UTC 是 8/27、香港已是 8/28）", () => {
    render(<Harness />);
    expect(dateBox()).toHaveValue("2026年8月28日");   // 🔴 blur 後是長格式（§15.3）
    // 香港 00:30
    expect(timeBox()).toHaveValue("12:30 AM");
  });

  /**
   * 🔴 上一格驗的是**預設值**（`initial`），本格驗的是**下限基準**（`nowWall`）——
   * 兩條是不同的程式碼路徑。把 `nowWall` 改成 UTC 的突變殺不掉上一格，只殺得掉本格
   * 與「夾到 now」「slots 過濾」那兩格。
   * ⚠️ 這與 S6b 的 M11 同型：**測試的描述必須對得上它真正走到的那條路**。
   */
  it("🔴 月曆的「今天」與下限也用店鋪時區（UTC 的 8/27 在香港已是 8/28）", () => {
    render(<Harness />);
    const today = screen.getByRole("gridcell", { name: "28" });
    expect(today).toHaveAttribute("aria-current", "date");
    // 香港的 8/27 已經過去 ⇒ 灰掉
    expect(screen.getByRole("gridcell", { name: "27" })).toHaveAttribute("aria-disabled", "true");
  });

  it("已有排程時帶入該時刻（同樣換到店鋪時區）", () => {
    render(<Harness scheduledAt={Date.parse("2026-09-01T02:35:00Z")} />);
    expect(dateBox()).toHaveValue("2026年9月1日");
    expect(timeBox()).toHaveValue("10:35 AM");
  });

  it("時區徽章＝本尊逐字形態 GMT+8（82 §15.6）", () => {
    render(<Harness />);
    expect(screen.getByText("GMT+8")).toBeVisible();
  });
});

describe("SchedulePopover 日期欄（82 §15.3）", () => {
  it("🔴 只吃 ISO YYYY-MM-DD；其他格式**靜默回退**到上一個有效值（本尊無錯誤訊息）", async () => {
    render(<Harness />);

    await userEvent.clear(dateBox());
    await userEvent.type(dateBox(), "2026-09-15");
    await userEvent.tab();
    expect(dateBox()).toHaveValue("2026年9月15日");          // blur 後正規化成長格式

    // 🔴 聚焦時切回 ISO 供編輯（刻意偏離：本尊的顯示格式回打不進去）
    await userEvent.click(dateBox());
    expect(dateBox()).toHaveValue("2026-09-15");

    await userEvent.clear(dateBox());
    await userEvent.type(dateBox(), "09/15/2026");
    await userEvent.tab();
    expect(dateBox()).toHaveValue("2026年9月15日");          // 回退，不是清空、不是報錯
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("過去的日期也回退（本尊月曆把今天之前灰掉）", async () => {
    render(<Harness />);
    await userEvent.clear(dateBox());
    await userEvent.type(dateBox(), "2026-08-01");
    await userEvent.tab();
    expect(dateBox()).toHaveValue("2026年8月28日");
  });
});

describe("SchedulePopover 時間欄（82 §15.3／§15.4）", () => {
  it("12 小時制與 24 小時制都吃，且**不吸附**到半點", async () => {
    render(<Harness scheduledAt={Date.parse("2026-09-01T02:00:00Z")} />);

    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "22:45");
    await userEvent.tab();
    expect(timeBox()).toHaveValue("10:45 PM");             // 24 → 12 小時制

    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "10:37 PM");
    await userEvent.tab();
    expect(timeBox()).toHaveValue("10:37 PM");             // 🔴 分鐘級保留，不吸附到 10:30
  });

  /**
   * 🔴 本尊的決定性實測（§15.4）：日期是今天時，先設一個合法的未來時間再打一個過去時間，
   * blur 後值變成**當下時刻**——**不是**回退到剛才那個合法值。
   * ⇒ 證明它是「夾到 now」而不是「回退上一個有效值」，兩者只有這個順序分得出來。
   */
  it("🔴 今天的過去時間被**夾到 now**，不是回退到上一個有效值", async () => {
    render(<Harness />);                                    // 香港今天 00:30

    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "11:00 PM");
    await userEvent.tab();
    expect(timeBox()).toHaveValue("11:00 PM");

    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "12:10 AM");            // 早於 00:30
    await userEvent.tab();
    expect(timeBox()).toHaveValue("12:30 AM");              // ＝now，不是回退的 11:00 PM
  });

  it("未來日期不夾（任何時間都合法）", async () => {
    render(<Harness />);
    await userEvent.clear(dateBox());
    await userEvent.type(dateBox(), "2026-09-15");
    await userEvent.tab();

    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "12:10 AM");
    await userEvent.tab();
    expect(timeBox()).toHaveValue("12:10 AM");
  });

  it("🔴 下拉是 30 分鐘刻度；今天只給**剩餘**的（§15.4：當下 00:30 ⇒ 少於 48 個）", async () => {
    render(<Harness />);
    await userEvent.click(timeBox());

    const options = within(screen.getByRole("listbox")).getAllByRole("option");
    expect(options.length).toBeLessThan(48);
    expect(options[0]).toHaveTextContent("12:30 AM");       // 第一個＝now 之後的第一個刻度
    expect(options.at(-1)).toHaveTextContent("11:30 PM");
  });
});

describe("SchedulePopover 頁尾（82 §15.7／§15.8）", () => {
  it("🔴 Remove schedule 只在**已儲存**的排程存在時可按", () => {
    const { unmount } = render(<Harness hasSavedSchedule={false} />);
    expect(screen.getByRole("button", { name: "移除排程" })).toBeDisabled();
    unmount();

    render(<Harness hasSavedSchedule scheduledAt={Date.parse("2026-09-01T02:35:00Z")} />);
    expect(screen.getByRole("button", { name: "移除排程" })).toBeEnabled();
  });

  /**
   * 🔴 本尊抓包（§15.7）：`Remove schedule` 存檔後送的是
   * `publishDate: <當下時刻>`，**不是 null** ⇒ 該管道變成**已發布**。
   * 做成 `onApply(null)`／`onRemove()` 就與本尊的終態不同。
   */
  it("🔴 Remove schedule 送出的是「現在」不是 null（終態＝立即發布）", async () => {
    const onApply = vi.fn();
    const now = Date.parse("2026-08-27T16:30:00Z");
    render(<Harness hasSavedSchedule now={now} onApply={onApply} scheduledAt={Date.parse("2026-09-01T02:35:00Z")} />);

    await userEvent.click(screen.getByRole("button", { name: "移除排程" }));
    expect(onApply).toHaveBeenCalledWith(now);
  });

  it("Done 送出的是店鋪時區牆鐘時間換算的 UTC instant", async () => {
    const onApply = vi.fn();
    render(<Harness onApply={onApply} />);

    await userEvent.clear(dateBox());
    await userEvent.type(dateBox(), "2026-09-01");
    await userEvent.tab();
    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "10:35 AM");
    await userEvent.tab();
    await userEvent.click(screen.getByRole("button", { name: "完成" }));

    // 香港 10:35 → 02:35Z
    expect(onApply).toHaveBeenCalledWith(Date.parse("2026-09-01T02:35:00Z"));
  });

  it("Cancel 呼叫 onClose，不送任何值", async () => {
    const onApply = vi.fn();
    const onClose = vi.fn();
    render(<Harness onApply={onApply} onClose={onClose} />);

    await userEvent.click(screen.getByRole("button", { name: "取消" }));
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onApply).not.toHaveBeenCalled();
  });

  /**
   * 🔴 本尊按 Escape 會把 popover **與 modal 一起關掉、丟失 modal 內未存的改動**
   * （§15.2，重現 2 次）。我方**刻意不照抄**：Escape 只關 popover，
   * 靠 `event.preventDefault()` 讓外層 `Modal` 看到 `defaultPrevented` 而不關自己。
   */
  it("🔴 Escape 只關 popover，且 preventDefault 讓外層 modal 不跟著關", async () => {
    const onClose = vi.fn();
    render(<Harness onClose={onClose} />);

    const outer = vi.fn();
    document.addEventListener("keydown", (event) => { if (!event.defaultPrevented) outer(); });

    await userEvent.click(dateBox());
    await userEvent.keyboard("{Escape}");

    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(outer).not.toHaveBeenCalled();
  });
});

/**
 * 🔴 本組由 2026-08-27 對抗性審查開出來：原本 15 格**全部**用 `Asia/Hong_Kong`
 * ——正是本包自己在 dev doc 點名的那個陷阱（香港全年 +08:00 無 DST）。
 * 下面三格全部用 `America/New_York` 的 DST 轉換日，且每一格都對應一個實跑證實的缺陷。
 */
describe("SchedulePopover 的 DST 日（審查開出的缺口）", () => {
  const NY = "America/New_York";

  /**
   * 🔴 前跳日：now＝當地 01:45 EST。牆鐘字串上 `02:00 >= 01:45` 會通過檢查，
   * 但 02:00 那一小時**不存在**——舊實作（比牆鐘字串）解出來的 instant
   * 比 now **早 45 分鐘**，等於把排程靜默改成立即發布。
   */
  it("🔴 前跳日打入不存在的時間：送出的 instant 不得早於 now，且欄位正規化成實際發布時間", async () => {
    const onApply = vi.fn();
    const now = Date.parse("2026-03-08T06:45:00Z");        // 當地 01:45 EST
    render(<Harness now={now} onApply={onApply} shopTimezone={NY} />);

    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "2:00 AM");
    await userEvent.tab();

    // 02:00 不存在 ⇒ 正規化到跳躍後的 03:00 EDT，欄位顯示的就是實際會發布的時間
    expect(timeBox()).toHaveValue("3:00 AM");

    await userEvent.click(screen.getByRole("button", { name: "完成" }));
    const sent = onApply.mock.calls[0][0] as number;
    expect(sent).toBeGreaterThanOrEqual(now);
    expect(sent).toBe(Date.parse("2026-03-08T07:00:00Z"));
  });

  /**
   * 🔴 回撥日的重複小時：`instantToWallClock` 丟失「哪一輪」的資訊，
   * 重新解析會平移一個 DST delta。使用者**什麼都沒改**按 Done，排程被提早 60 分鐘。
   */
  /**
   * 🔴 回撥日的重複小時：`instantToWallClock` 丟失「哪一輪」的資訊，重新解析會平移
   * 一個 DST delta（審查實跑：NY 提早 60 分、London 與 Sydney 各延後 60 分）。
   * 防線是「未改動時 `Done` disabled」——本尊同形態（§12.3 頁尾逐字）。
   * 🔴 判準是**牆鐘值比對**：改了又改回時 instant 可能已平移，用 instant 比會誤判成已改動。
   */
  it("🔴 回撥日第二輪：未改動時完成鍵 disabled；改了又改回也 disabled（不得送出平移值）", async () => {
    const scheduledAt = Date.parse("2026-11-01T06:30:00Z");  // 當地 01:30 EST（第二輪）
    render(<Harness now={Date.parse("2026-10-01T00:00:00Z")}
                    scheduledAt={scheduledAt} shopTimezone={NY} />);

    const done = screen.getByRole("button", { name: "完成" });
    expect(done).toBeDisabled();

    // 改成別的時間 ⇒ 可按
    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "5:00 AM");
    await userEvent.tab();
    expect(done).toBeEnabled();

    // 再改回原本的牆鐘 ⇒ 回到 disabled（instant 比對在這裡會誤判成已改動）
    await userEvent.clear(timeBox());
    await userEvent.type(timeBox(), "1:30 AM");
    await userEvent.tab();
    expect(done).toBeDisabled();
  });

  it("🔴 下拉不得列出當日**不存在**的牆鐘（選了會被靜默改成別的時間）", async () => {
    render(<Harness now={Date.parse("2026-03-08T05:00:00Z")} shopTimezone={NY} />);
    await userEvent.click(timeBox());

    const labels = within(screen.getByRole("listbox")).getAllByRole("option")
      .map((option) => option.textContent);
    // 2026-03-08 的 02:00／02:30 EST 不存在（前跳到 03:00 EDT）
    expect(labels).not.toContain("2:00 AM");
    expect(labels).not.toContain("2:30 AM");
    expect(labels).toContain("3:00 AM");
  });
});

/**
 * 🔴 本組全部由 2026-08-27 對抗性審查點名的**測試覆蓋缺口**開出來——
 * 每一格底下都有一個「拿掉某段實作，18 格照樣全綠」的突變。
 */
describe("SchedulePopover 審查點名的覆蓋缺口", () => {
  it("🔴 兩顆送出鈕都**按下即關**（本尊 §15.7；交給呼叫端做的話每個消費端都要記得）", async () => {
    const onClose = vi.fn();
    render(<Harness hasSavedSchedule onClose={onClose} scheduledAt={Date.parse("2026-09-01T02:35:00Z")} />);

    await userEvent.click(screen.getByRole("button", { name: "移除排程" }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  /**
   * 🔴 `hasSavedSchedule` 與 `scheduledAt` 在原本的測資中**共變**（要嘛都有、要嘛都沒有）
   * ⇒ 「`Remove` 的啟用條件是已**儲存**的排程」這個宣稱沒被釘住：
   * 拿 `scheduledAt !== null` 當條件也會全綠。本格把兩者拆開。
   */
  it("🔴 Remove 只看 hasSavedSchedule，不看 scheduledAt（兩者必須拆得開）", () => {
    // 有 scheduledAt 但尚未儲存（本次編輯剛設的）⇒ 仍 disabled
    const { unmount } = render(
      <Harness hasSavedSchedule={false} scheduledAt={Date.parse("2026-09-01T02:35:00Z")} />,
    );
    expect(screen.getByRole("button", { name: "移除排程" })).toBeDisabled();
    unmount();

    // 已儲存但沒帶 scheduledAt ⇒ 仍可按
    render(<Harness hasSavedSchedule scheduledAt={null} />);
    expect(screen.getByRole("button", { name: "移除排程" })).toBeEnabled();
  });

  /**
   * 🔴 徽章必須以**目標時刻**為基準算偏移。`lib/timezone.test.ts` 已釘住函式本身，
   * 但**元件有沒有把目標時刻餵給它**是另一回事——改成用 `now` 算，在無 DST 的時區
   * （含 TZ=UTC 的 runner）完全看不出來。本格用 NY 的冬夏兩側分辨。
   */
  it("🔴 徽章的接線：偏移以選定的目標時刻算，不是以 now 算", async () => {
    // now 在夏令（GMT-4），把排程設到冬令（GMT-5）
    render(<Harness now={Date.parse("2026-07-15T14:00:00Z")} shopTimezone="America/New_York" />);
    expect(screen.getByText("GMT-4")).toBeVisible();

    await userEvent.clear(dateBox());
    await userEvent.type(dateBox(), "2026-12-15");
    await userEvent.tab();

    // 用 now 算的實作會一直顯示 GMT-4
    expect(screen.getByText("GMT-5")).toBeVisible();
  });

  it("🔴 未來日期的下拉給滿 48 格（「只有今天才裁切」的守衛）", async () => {
    render(<Harness />);
    await userEvent.clear(dateBox());
    await userEvent.type(dateBox(), "2026-09-15");
    await userEvent.tab();
    await userEvent.click(timeBox());

    expect(within(screen.getByRole("listbox")).getAllByRole("option")).toHaveLength(48);
  });

  it("🔴 月曆點選日期會回寫日期欄（pickDay 的接線）", async () => {
    render(<Harness />);
    // 香港今天 8/28 ⇒ 點 30 號
    await userEvent.click(screen.getByRole("gridcell", { name: "30" }));
    expect(dateBox()).toHaveValue("2026年8月30日");
  });

  it("🔴 下拉選項可以用鍵盤選取（ArrowDown → Enter），且選完關閉", async () => {
    render(<Harness />);
    await userEvent.click(timeBox());
    expect(screen.getByRole("listbox")).toBeVisible();

    await userEvent.keyboard("{ArrowDown}{Enter}");
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(timeBox()).toHaveValue("12:30 AM");           // 今天剩餘的第一個刻度
  });

  it("🔴 popup 開著時 Escape 只關 popup，不關整個彈層", async () => {
    const onClose = vi.fn();
    render(<Harness onClose={onClose} />);
    await userEvent.click(timeBox());
    expect(screen.getByRole("listbox")).toBeVisible();

    await userEvent.keyboard("{Escape}");
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(onClose).not.toHaveBeenCalled();              // 彈層本身還在
  });
});
