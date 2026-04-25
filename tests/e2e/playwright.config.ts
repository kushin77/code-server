// @file        tests/e2e/playwright.config.ts
// @module      testing/e2e
// @description Playwright E2E test configuration for code-server-enterprise
// @governance  GOV-002: IaC, idempotent test infrastructure
// Issue #1537: Testing & QA 100x — E2E Playwright

import { existsSync } from "fs";
import path from "path";
import { defineConfig, devices } from "@playwright/test";

const BASE_URL = process.env.BASE_URL || "https://ide.kushnir.cloud";
const REQUIRE_VPN = process.env.REQUIRE_VPN === "1";
const QA_SESSION_PATH = path.resolve(process.cwd(), "auth", "qa-session.json");
const QA_SESSION_STATE = existsSync(QA_SESSION_PATH) ? QA_SESSION_PATH : undefined;

export default defineConfig({
  testDir: "./",
  testMatch: "**/*.spec.ts",

  // Fail fast on CI, retry once in headful mode
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : 2,

  // Global timeout per test
  timeout: 60_000,
  expect: { timeout: 15_000 },

  // Reporter
  reporter: [
    ["list"],
    ["html", { outputFolder: "../../artifacts/reports/playwright-html", open: "never" }],
    ["json", { outputFile: "../../artifacts/reports/playwright-results.json" }],
  ],

  // Artifacts
  outputDir: "../../artifacts/reports/playwright-traces",
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "on-first-retry",
    // Ignore SSL errors for self-signed cert scenarios
    ignoreHTTPSErrors: process.env.IGNORE_SSL === "1",
    extraHTTPHeaders: {
      "X-Test-Source": "playwright-e2e",
    },
  },

  projects: [
    // ── Portal flows (authenticated landing page) ─────────────────────────
    {
      name: "portal-chrome",
      testMatch: "**/portal/**/*.spec.ts",
      use: {
        ...devices["Desktop Chrome"],
        ...(QA_SESSION_STATE ? { storageState: QA_SESSION_STATE } : {}),
      },
    },

    // ── Authenticated flows (requires QA session) ──────────────────────────
    {
      name: "ide-chrome",
      testMatch: "**/ide/**/*.spec.ts",
      use: {
        ...devices["Desktop Chrome"],
        ...(QA_SESSION_STATE ? { storageState: QA_SESSION_STATE } : {}),
      },
    },

    // ── Unauthenticated / login flows ──────────────────────────────────────
    {
      name: "auth-chrome",
      testMatch: "**/auth/**/*.spec.ts",
      use: { ...devices["Desktop Chrome"] },
    },

    // ── API tests (non-browser) ────────────────────────────────────────────
    {
      name: "api",
      testMatch: "**/api/**/*.spec.ts",
      use: { ...devices["Desktop Chrome"] },
    },
  ],

  // Global setup: check VPN connectivity if REQUIRE_VPN=1
  globalSetup: "./global-setup.ts",
});
