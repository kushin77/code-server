import { defineConfig, devices } from '@playwright/test';

/**
 * @file        playwright.config.ts
 * @module      testing/config
 * @description Playwright test configuration for P3-1676 SSO validation
 * 
 * Features:
 * - Automatic retry on flaky failures (3 retries)
 * - Timeout configuration (30s per test, 60s per flow)
 * - Parallel test execution
 * - HTML + JSON + JUnit reporting
 * - Screenshot/trace capture on failures
 * - Environment variable configuration
 */

const retryCount = process.env.PLAYWRIGHT_RETRIES ? parseInt(process.env.PLAYWRIGHT_RETRIES) : 3;
const timeout = process.env.PLAYWRIGHT_TIMEOUT ? parseInt(process.env.PLAYWRIGHT_TIMEOUT) : 30000;

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: retryCount,
  workers: process.env.CI ? 1 : undefined,
  timeout: timeout,
  expect: {
    timeout: 5000,
  },
  fullyParallelRespectProcessEnvTrue: true,

  // Reporter configuration
  reporter: [
    ['html'],
    ['json', { outputFile: 'test-results/results.json' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
    ['list'],
  ],

  // Shared settings for all test projects
  use: {
    baseURL: process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 10000,
  },

  // Browser configurations
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  // Global test timeout
  globalTimeout: 600000, // 10 minutes

  // Webserver (optional - for local testing)
  webServer: undefined,
});
