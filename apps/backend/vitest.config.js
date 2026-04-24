import { defineConfig } from "vitest/config";
export default defineConfig({
    resolve: {
        // Prefer TypeScript sources in tests to avoid stale/generated JS artifacts.
        extensions: [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".json"],
    },
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
        coverage: {
            provider: "v8",
            reporter: ["text", "json-summary"],
            thresholds: {
                lines: 35,
                functions: 35,
                branches: 30,
                statements: 35,
            },
            exclude: [
                "src/lib/tracer.ts",
                "src/lib/tracing.ts",
                "src/middleware/tracing.ts",
                "src/services/ai/index.ts",
                "src/services/ai/router.ts",
                "src/services/replication/**",
                "src/services/session/index.ts",
            ],
        },
    },
});
//# sourceMappingURL=vitest.config.js.map