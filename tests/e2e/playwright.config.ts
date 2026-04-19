import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.TEST_BASE_URL || 'https://kushnir.cloud';

export default defineConfig({
  testDir: './specs',
  timeout: 60000,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: '../artifacts/playwright-report', open: 'never' }],
    ['json', { outputFile: '../artifacts/playwright-results.json' }],
  ],
  use: {
    baseURL,
    ignoreHTTPSErrors: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
