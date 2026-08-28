import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";
import RubyPlugin from "vite-plugin-ruby";

export default defineConfig({
  plugins: [RubyPlugin(), react()],
  test: {
    environment: "jsdom",
    setupFiles: ["test/setup.ts"],
    // 🔴 **測試一律在固定時區跑**（2026-08-27 S6b-2a 審查開出）。
    //   排程發布的整套時區測試建立在「瀏覽器時區 ≠ 店鋪時區」上，而開發機的
    //   `Asia/Taipei` 與測試用的店鋪時區 `Asia/Hong_Kong` **偏移相同**
    //   （都 +08:00、都無 DST）⇒ 那個前提在該機器上是空的，
    //   「誤用瀏覽器時區」的實作照樣全綠。
    //   釘成 UTC：與所有測試用到的店鋪時區都不同，且沒有 DST、輸出可預測。
    env: { TZ: "UTC" },

    // 🔴 **逐格逾時上限 5000 → 16000**（D65，2026-08-28 使用者裁定）。
    //   **這不是「測試寫得慢」，是負載下的整套放大。** 實測（同一台機、同一 session）：
    //     安靜時 `ProductDetailPage` 那批格子 1009–1257ms；
    //     機器被壓住時同一批 5038–5297ms ⇒ **4–5× 放大**，
    //     一次實測到 **10 格紅、其中 8 格是 `Test timed out in 5000ms`**。
    //   ——因為它不是單一一格的問題，D62 把最肥的那格拆成兩格（最壞單格 2239→958ms）
    //   只救了那一格，其餘 8 格照紅。
    //
    //   **16000 的來源：全套最慢一格安靜值 1602ms 的 10 倍。**
    //   （導出指令：`pnpm vitest run --reporter=verbose`，取最大的毫秒數）
    //   推算最壞負載值 1602 × 5 = 8010ms，16000 還留一倍餘裕。
    //   ⚠️ 代價誠實登記：**真的卡死的測試會慢 16 秒才失敗**（每格一次）。
    //
    // 🔴 **不得改成 `retry`。** 它跟拉高逾時**不是同一類措施**：
    //   拉高逾時只改變「等多久才判失敗」，**失敗還是失敗**；
    //   `retry` 會讓**永久性回歸**（每次都錯、只是偶爾偵測得到）在重試後變綠。
    //   本尊在單元測試裡 **0 次**使用 retry（已以四種查法全組織確認）。
    //
    // 🔴 本檔是**機械閘門判準面**（它定義「`pnpm test` 綠」是什麼意思）
    //   ⇒ 改它命中鐵律 18.3，**一律人工審閱與人工合併**，不走 D40 自合。
    testTimeout: 16_000,
  },
});
