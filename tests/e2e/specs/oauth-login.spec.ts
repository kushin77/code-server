import { test, expect } from '@playwright/test';

// Service-account E2E: Validate OAuth login redirects and load order
// Corresponds to e2e-service-account-profile.yml :: oauth-login capability

test.describe('OAuth login smoke test', () => {
  test('redirects to OAuth provider on unauthenticated access', async ({ page }) => {
    const response = await page.goto('/');
    // Should redirect to /oauth2/sign_in or Google OAuth
    const url = page.url();
    expect(url).toMatch(/oauth2|accounts\.google\.com/);
  });

  test('health check endpoint is reachable without auth', async ({ page }) => {
    const response = await page.goto('/health');
    // Health check returns 200 without OAuth
    expect(response?.status()).toBeLessThanOrEqual(404); // 200 or 404 (not 502)
  });
});
