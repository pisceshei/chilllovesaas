import { describe, expect, it } from "vitest";
import {
  formatWallTime12h,
  instantToWallClock,
  parseTimeInput,
  wallClockToInstant,
  zoneOffsetLabel,
} from "./timezone";

const HK = "Asia/Hong_Kong";
const NY = "America/New_York";

/**
 * 🔴 本檔的每一格都選在「香港測不出來」的地方。
 *
 * 香港全年 `+08:00`、沒有 DST ⇒ 只用香港測的話，下列全部錯誤實作都會 100% 測綠：
 * ①用瀏覽器時區代替店鋪時區 ②用「現在的偏移」換算未來時刻 ③把牆鐘當 UTC 只解一次。
 * 所以主力測資是 **America/New_York**（2026 年 DST：3/8 起、11/1 止——
 * 以執行環境的 `Intl` 實測確認，非查表）。
 */
describe("wallClockToInstant", () => {
  it("無 DST 的時區：牆鐘直接減去固定偏移", () => {
    // 2026-09-01 10:35 @ GMT+8 → 02:35Z
    expect(wallClockToInstant({ date: "2026-09-01", time: "10:35" }, HK))
      .toBe(Date.parse("2026-09-01T02:35:00Z"));
  });

  it("🔴 同一個時區、同一個牆鐘時間，冬夏換算出不同的 UTC（偏移不是常數）", () => {
    const winter = wallClockToInstant({ date: "2026-01-15", time: "10:00" }, NY);
    const summer = wallClockToInstant({ date: "2026-07-15", time: "10:00" }, NY);

    expect(winter).toBe(Date.parse("2026-01-15T15:00:00Z"));  // EST = -5
    expect(summer).toBe(Date.parse("2026-07-15T14:00:00Z"));  // EDT = -4
  });

  /**
   * 🔴 DST 切換日附近，「把牆鐘當 UTC 解一次」會差一小時。
   *
   * 春季前跳日（2026-03-08）的牆鐘 03:00 EDT：把 `03:00` 當 UTC 得到的 instant
   * 在紐約還是 3/7 22:00 **EST（-5）** ⇒ 用那個偏移修正會得 `08:00Z`（錯一小時），
   * 正確答案是 `07:00Z`（EDT，-4）。
   *
   * ⚠️ **2026-08-27 更正**：本格原本的描述是「需要第二次迭代」——實作當時確實是
   * 兩次迭代，但那個做法對 DST 的病態情形沒有定義明確的語義（見下方那組的說明）。
   * 實作已改成候選集合＋自洽性檢驗，本格驗的判準不變：切換日附近不得差一小時。
   */
  it("🔴 DST 前跳日：解一次會差一小時（正確是 07:00Z 不是 08:00Z）", () => {
    expect(wallClockToInstant({ date: "2026-03-08", time: "03:00" }, NY))
      .toBe(Date.parse("2026-03-08T07:00:00Z"));
  });

  it("🔴 DST 回撥日的重複牆鐘時間：取**較早**的那一個（ours 裁定）", () => {
    // 2026-11-01 01:30 在紐約出現兩次：EDT(-4) 的 05:30Z 與 EST(-5) 的 06:30Z
    expect(wallClockToInstant({ date: "2026-11-01", time: "01:30" }, NY))
      .toBe(Date.parse("2026-11-01T05:30:00Z"));
  });

  /**
   * 🔴 **本組是 2026-08-27 對抗性審查逼出來的**。初版的兩條「ours 裁定」
   * （不存在的往後推／重複的取較早）**只在 UTC 以西成立**——審查掃了全部 418 個
   * IANA 時區 ×2025–2031 的 DST 轉換點，實跑證實「往後推」在 57 個時區是往回推、
   * 「取較早」在 73 個時區取的是較晚。而當時測試唯一覆蓋的 `America/New_York`
   * 正好是兩條敘述唯一同時成立的那一側。
   *
   * ⇒ 實作改成**顯式**裁定（候選集合＋自洽性檢驗），本組釘住它在 UTC **以東**也成立。
   */
  describe("🔴 DST 病態情形的顯式裁定（UTC 以東與以西都要成立）", () => {
    const gapCases: [string, string, string, string][] = [
      [ NY, "2026-03-08", "02:30", "03:30" ],                  // UTC 以西
      [ "Europe/London", "2026-03-29", "01:30", "02:30" ],      // UTC 以東（+0/+1）
      [ "Australia/Sydney", "2026-10-04", "02:30", "03:30" ],   // UTC 以東（+10/+11）
    ];

    it.each(gapCases)("不存在的牆鐘時間 → 跳躍**後**的時刻（%s）", (tz, date, time, expected) => {
      const instant = wallClockToInstant({ date, time }, tz);
      expect(instant).not.toBeNull();
      expect(instantToWallClock(instant as number, tz).time).toBe(expected);
    });

    const foldCases: [string, string, string, string][] = [
      [ NY, "2026-11-01", "01:30", "2026-11-01T05:30:00Z" ],           // EDT，較早
      [ "Europe/London", "2026-10-25", "01:30", "2026-10-25T00:30:00Z" ], // BST，較早
      [ "Australia/Sydney", "2026-04-05", "02:30", "2026-04-04T15:30:00Z" ], // AEDT，較早
    ];

    it.each(foldCases)("重複的牆鐘時間 → **較早**那一個（%s）", (tz, date, time, expected) => {
      expect(wallClockToInstant({ date, time }, tz)).toBe(Date.parse(expected));
    });
  });

  it("往返一致：instant → 牆鐘 → instant（跨 DST 兩側各一）", () => {
    for (const iso of [ "2026-01-15T15:00:00Z", "2026-07-15T14:00:00Z", "2026-09-01T02:35:00Z" ]) {
      const instant = Date.parse(iso);
      for (const tz of [ HK, NY ]) {
        expect(wallClockToInstant(instantToWallClock(instant, tz), tz)).toBe(instant);
      }
    }
  });

  it("格式不合回 null（含逐欄範圍通過但日期不存在的 2 月 30 日）", () => {
    expect(wallClockToInstant({ date: "2026/09/01", time: "10:35" }, HK)).toBeNull();
    expect(wallClockToInstant({ date: "2026-09-01", time: "25:00" }, HK)).toBeNull();
    expect(wallClockToInstant({ date: "2026-13-01", time: "10:00" }, HK)).toBeNull();
    // 🔴 逐欄檢查會放行（月 2 合法、日 30 ≤ 31），但 Date.UTC 會把它捲成 3 月 2 日
    expect(wallClockToInstant({ date: "2026-02-30", time: "10:00" }, HK)).toBeNull();
  });
});

describe("instantToWallClock", () => {
  it("換到店鋪時區而不是執行環境時區", () => {
    const instant = Date.parse("2026-09-01T02:35:00Z");
    expect(instantToWallClock(instant, HK)).toEqual({ date: "2026-09-01", time: "10:35" });
    expect(instantToWallClock(instant, NY)).toEqual({ date: "2026-08-31", time: "22:35" });
  });

  it("午夜輸出 00:xx 不是 24:xx（hourCycle 的已知差異）", () => {
    expect(instantToWallClock(Date.parse("2026-09-01T16:00:00Z"), HK))
      .toEqual({ date: "2026-09-02", time: "00:00" });
  });
});

describe("zoneOffsetLabel", () => {
  it("本尊逐字形態 GMT+8（82 §15.6）", () => {
    expect(zoneOffsetLabel(Date.parse("2026-09-01T02:35:00Z"), HK)).toBe("GMT+8");
  });

  /**
   * 🔴 標籤必須以**目標時刻**為基準，不是「現在」。同一個時區在冬夏標不同的字，
   * 用 `Date.now()` 算的話，夏天設一個冬天的排程會標成 `GMT-4`（實際到點時是 `GMT-5`）。
   */
  it("🔴 同一時區、不同目標時刻 ⇒ 不同標籤", () => {
    expect(zoneOffsetLabel(Date.parse("2026-01-15T15:00:00Z"), NY)).toBe("GMT-5");
    expect(zoneOffsetLabel(Date.parse("2026-07-15T14:00:00Z"), NY)).toBe("GMT-4");
  });
});

describe("parseTimeInput", () => {
  it("12 小時制與 24 小時制都吃（本尊 §15.3 實測兩種都接受）", () => {
    expect(parseTimeInput("11:00 PM")).toBe("23:00");
    expect(parseTimeInput("22:45")).toBe("22:45");
    expect(parseTimeInput("10:37 PM")).toBe("22:37");   // 🔴 不吸附到半點
    expect(parseTimeInput("12:00 AM")).toBe("00:00");
    expect(parseTimeInput("12:30 PM")).toBe("12:30");
  });

  it("不合法回 null", () => {
    expect(parseTimeInput("banana")).toBeNull();
    expect(parseTimeInput("25:00")).toBeNull();
    expect(parseTimeInput("10:75")).toBeNull();
    expect(parseTimeInput("13:00 PM")).toBeNull();      // 12 小時制不能有 13
    expect(parseTimeInput("")).toBeNull();
  });
});

describe("formatWallTime12h", () => {
  it("本尊顯示格式 h:mm AM/PM（§15.3）", () => {
    expect(formatWallTime12h("22:37")).toBe("10:37 PM");
    expect(formatWallTime12h("00:30")).toBe("12:30 AM");
    expect(formatWallTime12h("12:00")).toBe("12:00 PM");
    expect(formatWallTime12h("09:05")).toBe("9:05 AM");
  });
});
