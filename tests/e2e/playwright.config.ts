import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.TEST_BASE_URL || 'https://kushnir.cloud';
const parsedWorkers = Number.parseInt(process.env.PLAYWRIGHT_WORKERS || (process.env.SCALE_PROFILE === '100x' ? '4' : '1'), 10);

export default defineConfig({
  testDir: './specs',
  timeout: 60000,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: Number.isFinite(parsedWorkers) && parsedWorkers > 0 ? parsedWorkers : 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: '../artifacts/playwright-report', open: 'never' }],
    ['json', { outputFile: '../artifacts/playwright-results.json' }],
    ['junit', { outputFile: '../artifacts/playwright-junit.xml' }],
    ['github'],
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
