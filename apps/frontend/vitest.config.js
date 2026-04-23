import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";
export default defineConfig({
    plugins: [react()],
    resolve: {
        alias: {
            '@': path.resolve(__dirname, './src'),
        },
    },
    test: {
        globals: true,
        environment: "jsdom",
        setupFiles: ["./src/test-setup.ts"],
        exclude: [
            "**/node_modules/**",
            "**/dist/**",
        ],
        coverage: {
            provider: "v8",
            reporter: ["text", "json-summary"],
            thresholds: {
                lines: 40,
                functions: 40,
                branches: 35,
                statements: 40,
            },
        },
    },
});
//# sourceMappingURL=vitest.config.js.map