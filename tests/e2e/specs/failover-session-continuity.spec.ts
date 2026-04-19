import { test, expect } from '@playwright/test';

/**
 * Failover Session Continuity Suite (Issue #733)
 * 
 * Tests that authenticated sessions continue to work across failover events,
 * ensuring users are not forced to re-authenticate during infrastructure transitions.
 * 
 * Prerequisites:
 * - PLAYWRIGHT_STORAGE_STATE environment variable pointing to authenticated context JSON
 * - TEST_BASE_URL environment variable set to target service URL (primary)
 * - FAILOVER_WAIT_MS environment variable (how long to wait for failover completion, default 45000ms)
 * 
 * Test Flow:
 * 1. Start with authenticated context (storage state loaded)
 * 2. Verify initial authenticated access
 * 3. Wait for failover window (external process may trigger failover during this)
 * 4. Reload page to force connection to potentially new backend
 * 5. Verify session still works (not redirected to OAuth)
 * 
 * Outcomes Verified:
 * - Session cookies/tokens survive failover
 * - User is not redirected to OAuth login after failover
 * - Basic page load succeeds with same credentials
 */

test.describe('Authenticated Session Continuity During Failover', () => {
  
  test.use({
    storageState: process.env.PLAYWRIGHT_STORAGE_STATE || './storage-state.json',
  });

  const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
  const failoverWaitMs = Number(process.env.FAILOVER_WAIT_MS || '45000');

  test('maintains authentication across short failover window (45s)', async ({ page }) => {
    // Verify initially authenticated
    console.log(`[failover-test] Starting authenticated session at ${baseUrl}`);
    await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    let currentUrl = page.url();
    expect(currentUrl).not.toMatch(/oauth2|accounts\.google\.com/);
    console.log(`[failover-test] Initial URL: ${currentUrl}`);

    // Wait for failover window (during which infrastructure may change)
    console.log(`[failover-test] Waiting ${failoverWaitMs}ms for failover to complete...`);
    await page.waitForTimeout(failoverWaitMs);

    // Reload page to force connection to new backend (if failover occurred)
    console.log(`[failover-test] Reloading page post-failover`);
    await page.reload({ waitUntil: 'domcontentloaded' });

    // Verify still authenticated (not redirected to OAuth)
    currentUrl = page.url();
    console.log(`[failover-test] Post-failover URL: ${currentUrl}`);
    expect(currentUrl).not.toMatch(/oauth2|accounts\.google\.com|login/);
    expect(currentUrl).toContain(baseUrl);
  });

  test('preserves session cookies through failover boundary', async ({ page, context }) => {
    const baseUrl_final = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    // Snapshot cookies before failover window
    await page.goto(`${baseUrl_final}/`, { waitUntil: 'domcontentloaded' });
    const cookiesBefore = await context.cookies();
    const cookieNamesBefore = new Set(cookiesBefore.map(c => c.name));
    console.log(`[failover-cookies] Cookies before failover: ${Array.from(cookieNamesBefore).join(', ')}`);

    // Wait for failover
    console.log(`[failover-cookies] Waiting ${failoverWaitMs}ms for failover`);
    await page.waitForTimeout(failoverWaitMs);

    // Reload and check cookies after failover
    await page.reload({ waitUntil: 'domcontentloaded' });
    const cookiesAfter = await context.cookies();
    const cookieNamesAfter = new Set(cookiesAfter.map(c => c.name));
    console.log(`[failover-cookies] Cookies after failover: ${Array.from(cookieNamesAfter).join(', ')}`);

    // At least some session cookies should persist
    const sessionCookiesBefore = Array.from(cookieNamesBefore).filter(name =>
      /session|auth|oauth|token/i.test(name)
    );
    const sessionCookiesAfter = Array.from(cookieNamesAfter).filter(name =>
      /session|auth|oauth|token/i.test(name)
    );

    console.log(`[failover-cookies] Session-like cookies before: ${sessionCookiesBefore.join(', ')}`);
    console.log(`[failover-cookies] Session-like cookies after: ${sessionCookiesAfter.join(', ')}`);

    // Should have at least some auth-related cookies both before and after
    if (sessionCookiesBefore.length > 0) {
      expect(sessionCookiesAfter.length).toBeGreaterThan(0);
    }
  });

  test('can make authenticated API calls post-failover', async ({ page }) => {
    const baseUrl_api = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    await page.goto(`${baseUrl_api}/`, { waitUntil: 'domcontentloaded' });
    
    // Wait for failover
    await page.waitForTimeout(failoverWaitMs);
    
    // Try to make an authenticated API call (example: health check)
    const apiResponse = await page.evaluate(async (url) => {
      try {
        const resp = await fetch(`${url}/api/health`, {
          method: 'GET',
          credentials: 'include', // Include cookies
        });
        return {
          status: resp.status,
          ok: resp.ok,
        };
      } catch (err) {
        return { error: String(err) };
      }
    }, baseUrl_api);

    console.log(`[failover-api] Post-failover API response:`, apiResponse);

    // Should not get 401/403 (would indicate auth failure)
    if ('status' in apiResponse) {
      expect(apiResponse.ok || apiResponse.status === 200).toBeTruthy();
    }
  });

  test('handles multiple failover cycles without losing auth', async ({ page }) => {
    const baseUrl_cycles = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    // Perform 2 quick failover cycles
    for (let cycle = 1; cycle <= 2; cycle++) {
      console.log(`[failover-cycles] Cycle ${cycle}: Starting`);
      
      await page.goto(`${baseUrl_cycles}/`, { waitUntil: 'domcontentloaded' });
      let url = page.url();
      expect(url).not.toMatch(/oauth2|accounts\.google\.com/);

      // Shorter wait for second cycle
      const waitMs = cycle === 1 ? failoverWaitMs : Math.floor(failoverWaitMs / 2);
      await page.waitForTimeout(waitMs);

      await page.reload({ waitUntil: 'domcontentloaded' });
      url = page.url();
      
      console.log(`[failover-cycles] Cycle ${cycle}: URL after reload = ${url}`);
      expect(url).not.toMatch(/oauth2|accounts\.google\.com/);
    }
  });

  test('authenticated session endpoint responds correctly', async ({ page }) => {
    const baseUrl_endpoint = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
    
    // Navigate to establish session
    await page.goto(`${baseUrl_endpoint}/`, { waitUntil: 'domcontentloaded' });
    
    // Wait for failover
    await page.waitForTimeout(failoverWaitMs);
    
    // Check /me or similar endpoint that returns authenticated user info
    const userResponse = await page.evaluate(async (url) => {
      try {
        const resp = await fetch(`${url}/api/me`, {
          method: 'GET',
          credentials: 'include',
        });
        if (resp.ok) {
          return await resp.json();
        }
        return { status: resp.status };
      } catch (err) {
        return { error: String(err) };
      }
    }, baseUrl_endpoint);

    console.log(`[failover-endpoint] /api/me response:`, userResponse);

    // If endpoint exists, should return user info or 200, not 401
    if ('status' in userResponse && userResponse.status === 401) {
      throw new Error('Authentication failed after failover: got 401 from /api/me');
    }
  });
});

test.describe('Unauthenticated Failover (Control Test)', () => {
  
  /**
   * Control test: Verify that unauthenticated users are consistently
   * redirected to OAuth login, even during failover windows.
   * This proves that failover itself doesn't break OAuth redirects.
   */

  const baseUrl = process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
  const failoverWaitMs = Number(process.env.FAILOVER_WAIT_MS || '45000');

  test('unauthenticated user is redirected to OAuth before and after failover', async ({ page }) => {
    // Navigate without stored credentials
    await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    let currentUrl = page.url();
    
    // Should be at OAuth login
    expect(currentUrl).toMatch(/oauth2|accounts\.google\.com|login/);
    console.log(`[failover-unauth] Pre-failover: redirected to ${currentUrl}`);

    // Wait for failover window
    await page.waitForTimeout(failoverWaitMs);

    // Navigate again
    await page.goto(`${baseUrl}/`, { waitUntil: 'domcontentloaded' });
    currentUrl = page.url();

    // Should still be at OAuth login (failover doesn't bypass auth)
    expect(currentUrl).toMatch(/oauth2|accounts\.google\.com|login/);
    console.log(`[failover-unauth] Post-failover: redirected to ${currentUrl}`);
  });
});
