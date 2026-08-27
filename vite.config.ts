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
  },
});
