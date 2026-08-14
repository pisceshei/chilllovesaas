import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";
import RubyPlugin from "vite-plugin-ruby";

export default defineConfig({
  plugins: [RubyPlugin(), react()],
  test: {
    environment: "jsdom",
    setupFiles: ["test/setup.ts"],
  },
});
