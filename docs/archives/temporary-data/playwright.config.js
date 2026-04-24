import { defineConfig, devices } from '@playwright/test';
/**
 * Read environment from .env files in order of precedence
 */
function loadEnv() {
    const env = {
        E2E_USER_EMAIL: process.env.E2E_USER_EMAIL || 'qa@kushnir.cloud',
        E2E_USER_PASSWORD: process.env.E2E_USER_PASSWORD || '',
        BASE_URL: process.env.BASE_URL || 'https://kushnir.cloud',
        IDE_BASE_URL: process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud',
        REQUIRE_VPN: process.env.REQUIRE_VPN || '1',
    };
    // Check VPN requirement
    if (env.REQUIRE_VPN === '1') {
        if (!process.env.E2E_USER_PASSWORD) {
            console.error('ERROR: E2E_USER_PASSWORD is required for VPN-gated tests (REQUIRE_VPN=1)');
            process.exit(1);
        }
    }
    return env;
}
const env = loadEnv();
/**
 * Playwright configuration for E2E testing
 *
 * Features:
 * - VPN gating: Tests require VPN connectivity (configurable via REQUIRE_VPN)
 * - Multi-browser testing: Chrome, Firefox, WebKit
 * - Sharding: Split tests across workers for parallel execution
 * - Screenshot & video on failure: For debugging
 * - Retries: Transient failure recovery
 *
 * Usage:
 *   # Run all tests
 *   pnpm exec playwright test
 *
 *   # Run with debug mode
 *   pnpm exec playwright test --debug
 *
 *   # Run specific suite
 *   pnpm exec playwright test oauth-login.spec.ts
 *
 *   # Run with specific shard (CI)
 *   pnpm exec playwright test --shard=1/2
 */
export default defineConfig({
    testDir: './tests/e2e/specs',
    testMatch: '*.spec.ts',
    // Timeout and retry configuration
    timeout: 60 * 1000, // 60s per test
    expect: { timeout: 10 * 1000 }, // 10s per assertion
    globalTimeout: 60 * 60 * 1000, // 1h total
    fullyParallel: true,
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 2 : 0, // Retry 2x in CI, 0x locally
    // Reporting
    reporter: [
        ['html'],
        ['json', { outputFile: 'test-results/results.json' }],
        ['junit', { outputFile: 'test-results/results.xml' }],
        ['github'],
    ],
    // Shared settings for all browsers
    use: {
        baseURL: env.BASE_URL,
        trace: 'on-first-retry', // Trace on first retry
        screenshot: 'only-on-failure', // Screenshot on failure
        video: 'retain-on-failure', // Video on failure
        // Navigation and performance
        navigationTimeout: 30 * 1000, // 30s page loads
        actionTimeout: 10 * 1000, // 10s actions (click, fill, etc)
        // Context and auth
        locale: 'en-US',
        timezone: 'UTC',
    },
    // Browser configurations
    projects: [
        {
            name: 'chromium',
            use: {
                ...devices['Desktop Chrome'],
                // Chrome-specific settings
                launchArgs: [
                    '--disable-blink-features=AutomationControlled',
                    '--disable-features=IsolateOrigins,site-per-process',
                ],
            },
        },
        {
            name: 'firefox',
            use: {
                ...devices['Desktop Firefox'],
            },
        },
        {
            name: 'webkit',
            use: {
                ...devices['Desktop Safari'],
            },
        },
        // Mobile testing
        {
            name: 'mobile-chrome',
            use: {
                ...devices['Pixel 5'],
            },
        },
    ],
    // Web server configuration (disabled - tests use remote servers)
    // Uncomment below if you need to start a local web server for tests
    /*
    webServer: {
      command: 'npm run dev',  // Start your local dev server
      url: 'http://localhost:3000',
      timeout: 120 * 1000,
      reuseExistingServer: true,
    },
    */
    // Output configuration
    outputDir: 'test-results',
    snapshotDir: 'tests/e2e/snapshots',
});
//# sourceMappingURL=playwright.config.js.map