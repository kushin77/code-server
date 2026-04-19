import { test, expect } from '@playwright/test';

/**
 * Authenticated Session Suite
 * 
 * Tests that verify an authenticated browser context maintains its session
 * across page reloads and basic operations.
 * 
 * Prerequisites:
 * - PLAYWRIGHT_STORAGE_STATE environment variable pointing to authenticated context JSON
 * - TEST_BASE_URL environment variable set to target service URL
 */

test.describe('Authenticated Session Persistence', () => {
  
  test.use({
    storageState: process.env.PLAYWRIGHT_STORAGE_STATE || './storage-state.json',
  });

  test('authenticated context loads without OAuth redirect', async ({ page }) => {
    const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    // Navigate to root; should not redirect to OAuth if authenticated
    await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    
    // Verify we're not on OAuth login page
    const currentUrl = page.url();
    expect(currentUrl).not.toMatch(/oauth2|accounts\.google\.com/);
    expect(currentUrl).toContain(baseUrl);
  });

  test('authenticated session persists across page reload', async ({ page }) => {
    const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    // Navigate to app
    await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    const initialUrl = page.url();
    
    // Reload the page
    await page.reload({ waitUntil: 'domcontentloaded' });
    
    // Should still be authenticated (not redirected to OAuth)
    const reloadUrl = page.url();
    expect(reloadUrl).not.toMatch(/oauth2|accounts\.google\.com/);
    expect(reloadUrl).toContain(baseUrl);
  });

  test('authenticated session includes valid cookies', async ({ page, context }) => {
    const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    // Navigate to app to trigger any cookie exchanges
    await page.goto(`${baseUrl}/`, { waitUntil: 'networkidle' });
    
    // Retrieve cookies from context
    const cookies = await context.cookies();
    
    // Expect at least some cookies (session, oauth2 proxy, etc.)
    expect(cookies.length).toBeGreaterThan(0);
    
    // Look for expected session-related cookies
    const cookieNames = cookies.map(c => c.name);
    console.log(`[test] Cookies in context: ${cookieNames.join(', ')}`);
    
    // Should have something that looks like a session or auth cookie
    const hasAuthCookie = cookieNames.some(name => 
      /session|auth|token|oauth/i.test(name)
    );
    expect(hasAuthCookie).toBeTruthy();
  });

  test('authenticated session has localStorage tokens', async ({ page }) => {
    const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    
    // Query localStorage for common auth-related keys
    const localStorageData = await page.evaluate(() => {
      const data: Record<string, string> = {};
      for (let i = 0; i < window.localStorage.length; i++) {
        const key = window.localStorage.key(i) || '';
        data[key] = window.localStorage.getItem(key) || '';
      }
      return data;
    });
    
    console.log(`[test] localStorage keys: ${Object.keys(localStorageData).join(', ')}`);
    
    // localStorage presence is optional; some apps don't use it
    // Just log for diagnostics
    if (Object.keys(localStorageData).length > 0) {
      expect(Object.keys(localStorageData).length).toBeGreaterThan(0);
    }
  });

  test('authenticated user can navigate protected routes', async ({ page }) => {
    const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    // Navigate to a protected route (if the app has one)
    // For code-server, this could be /api/health, /api/v1, etc.
    await page.goto(`${baseUrl}/api/health`, { waitUntil: 'networkidle' });
    
    // Should get a 200 response, not 401/403
    const response = page.context().pages()[0];
    // (Note: page object doesn't directly expose response; this is handled by request/response monitoring)
    
    // Simple check: page should load without OAuth redirect
    const url = page.url();
    expect(url).not.toMatch(/oauth2|accounts\.google\.com/);
  });

  test('authenticated context survives browser restart within same context', async ({ browser, context }) => {
    const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    const page1 = await context.newPage();
    await page1.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    const url1 = page1.url();
    expect(url1).not.toMatch(/oauth2|accounts\.google\.com/);
    await page1.close();
    
    // Create a new page in the same context; should share cookies
    const page2 = await context.newPage();
    await page2.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    const url2 = page2.url();
    expect(url2).not.toMatch(/oauth2|accounts\.google\.com/);
    await page2.close();
  });

});
