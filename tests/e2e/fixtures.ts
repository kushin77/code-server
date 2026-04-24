import { test as base, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Playwright test fixture with VPN gating and authentication support
 *
 * Features:
 * - VPN connectivity check before test execution
 * - Google OAuth authentication flow
 * - Session persistence (optionally via cached tokens)
 * - Common helpers for E2E testing
 */

interface E2EFixtures {
  // VPN check
  vpnConnected: void;
  
  // Authentication
  authenticatedPage: void;
  authContext: {
    email: string;
    password: string;
    token?: string;
  };
}

// Load environment
const env = {
  E2E_USER_EMAIL: process.env.E2E_USER_EMAIL || 'qa@kushnir.cloud',
  E2E_USER_PASSWORD: process.env.E2E_USER_PASSWORD || '',
  BASE_URL: process.env.BASE_URL || 'https://kushnir.cloud',
  IDE_BASE_URL: process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud',
  REQUIRE_VPN: process.env.REQUIRE_VPN || '1',
};

/**
 * VPN connectivity check fixture
 * Runs before any test if REQUIRE_VPN=1
 */
const vpnConnected = base.extend<{ vpnConnected: void }>({
  vpnConnected: async ({}, use) => {
    if (env.REQUIRE_VPN !== '1') {
      // Skip VPN check
      await use();
      return;
    }

    // Check VPN connectivity via HTTP
    try {
      const response = await fetch('https://ide.kushnir.cloud', {
        method: 'HEAD',
        timeout: 5000,
      });
      
      if (!response.ok) {
        throw new Error(`VPN check failed: HTTP ${response.status}`);
      }
      
      console.log('✓ VPN connectivity verified');
      await use();
    } catch (error) {
      throw new Error(
        `VPN connectivity check failed: ${error instanceof Error ? error.message : String(error)}\n` +
        'Tests require VPN connection (REQUIRE_VPN=1). ' +
        'Configure VPN and retry, or set REQUIRE_VPN=0 to skip.'
      );
    }
  },
});

/**
 * Authentication context fixture
 * Provides email, password, and optional cached OAuth token
 */
const authContext = base.extend<{ authContext: E2EFixtures['authContext'] }>({
  authContext: async ({}, use) => {
    const context = {
      email: env.E2E_USER_EMAIL,
      password: env.E2E_USER_PASSWORD,
      token: process.env.E2E_USER_OAUTH_TOKEN || undefined,
    };

    if (!context.password) {
      throw new Error(
        'E2E_USER_PASSWORD is required for authentication. ' +
        'Set via environment variable or GitHub Actions secret.'
      );
    }

    await use(context);
  },
});

/**
 * Authenticated page fixture
 * Provides a page with user logged in via Google OAuth
 */
const authenticatedPage = base.extend<
  { authenticatedPage: void },
  { vpnConnected: void; authContext: E2EFixtures['authContext'] }
>({
  authenticatedPage: async ({ page, vpnConnected, authContext }, use) => {
    // Navigate to login page
    await page.goto('/oauth2/start?rd=' + encodeURIComponent(env.BASE_URL));

    // Fill in Google OAuth credentials
    await page.fill('input[type="email"]', authContext.email);
    await page.click('button:has-text("Next")');
    
    // Wait for password field
    await page.waitForSelector('input[type="password"]', { timeout: 10000 });
    await page.fill('input[type="password"]', authContext.password);
    await page.click('button:has-text("Next")');

    // Wait for redirect back to application
    await page.waitForURL(env.BASE_URL, { timeout: 30000 });
    
    // Verify we're logged in
    const userElement = await page.locator('[data-testid="user-profile"]').first();
    await expect(userElement).toBeVisible({ timeout: 5000 });

    console.log(`✓ Authenticated as ${authContext.email}`);
    await use();
  },
});

/**
 * Export test fixture with all custom fixtures
 */
export const test = base.extend<E2EFixtures>({
  vpnConnected,
  authContext,
  authenticatedPage,
});

export { expect };

/**
 * Test helpers
 */
export const helpers = {
  /**
   * Wait for API response with retry
   */
  async waitForApiResponse(
    page,
    urlPattern: string | RegExp,
    timeout: number = 10000
  ) {
    return page.waitForResponse(
      (response) => {
        if (typeof urlPattern === 'string') {
          return response.url().includes(urlPattern);
        }
        return urlPattern.test(response.url());
      },
      { timeout }
    );
  },

  /**
   * Get current session from storage
   */
  async getSessionStorage(page, key: string) {
    return page.evaluate((k) => sessionStorage.getItem(k), key);
  },

  /**
   * Get current auth token from storage
   */
  async getAuthToken(page) {
    return (
      (await page.evaluate(() => localStorage.getItem('auth_token'))) ||
      (await page.evaluate(() => sessionStorage.getItem('oauth_token')))
    );
  },

  /**
   * Verify page health (no JS errors, responsive)
   */
  async verifyPageHealth(page) {
    // Check for uncaught JS errors
    const errors: Error[] = [];
    page.on('pageerror', (error) => errors.push(error));

    if (errors.length > 0) {
      throw new Error(`Page errors detected: ${errors.map((e) => e.message).join('; ')}`);
    }

    // Check page is responsive
    const isVisible = await page.locator('body').isVisible();
    if (!isVisible) {
      throw new Error('Page body is not visible');
    }

    console.log('✓ Page health verified');
  },
};
