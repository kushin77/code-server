import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    setupFiles: ["./src/test-setup.ts"],
    exclude: [
      "**/node_modules/**",
      "**/dist/**",
      "src/lib/__tests__/tracer.test.ts",
      "src/services/ai/__tests__/router.test.ts",
    ],
  },
});
