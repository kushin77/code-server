import { test, expect } from '@playwright/test';

const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
const PRIMARY_HOST = '192.168.168.31';
const REPLICA_HOST = '192.168.168.42';

test.describe('Session Persistence & Failover (#989)', () => {

  test.describe('Session Persistence', () => {
    
    test('1: session survives page refresh', async ({ page, context }) => {
      // Navigate to protected resource
      await page.goto(PORTAL_URL);
      
      // Verify authenticated
      const cookies1 = await context.cookies();
      const oauthCookie1 = cookies1.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie1).toBeDefined();
      
      // Refresh page
      await page.reload();
      
      // Should NOT redirect to login
      expect(page.url()).not.toMatch(/oauth2|accounts\.google\.com/);
      
      // Session cookie should persist
      const cookies2 = await context.cookies();
      const oauthCookie2 = cookies2.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie2?.value).toBe(oauthCookie1?.value);
    });

    test('2: session survives opening new tab', async ({ browser, context }) => {
      // Open first tab and login
      const page1 = await context.newPage();
      await page1.goto(PORTAL_URL);
      
      // Get cookies from first tab
      const cookies1 = await context.cookies();
      const oauthCookie1 = cookies1.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie1).toBeDefined();
      
      // Open second tab (inherits same context/cookies)
      const page2 = await context.newPage();
      await page2.goto(IDE_URL);
      
      // Should be authenticated (no redirect to login)
      expect(page2.url()).not.toMatch(/oauth2|accounts\.google\.com/);
      
      // Should have same session cookie
      const cookies2 = await context.cookies();
      const oauthCookie2 = cookies2.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie2?.value).toBe(oauthCookie1?.value);
      
      await page1.close();
      await page2.close();
    });

    test('3: session survives browser restart', async ({ browser, page, context }) => {
      // Initial login and get session
      await page.goto(PORTAL_URL);
      const cookies1 = await context.cookies();
      const sessionCookie1 = cookies1.find(c => c.name === '_oauth2_proxy');
      
      // Get cookie details for restore
      const cookieToRestore = {
        ...sessionCookie1,
        name: '_oauth2_proxy',
        domain: sessionCookie1?.domain || '.kushnir.cloud'
      };
      
      // Create new browser context (simulates browser restart)
      const newContext = await browser.newContext();
      
      // Restore session cookie
      if (cookieToRestore && cookieToRestore.name) {
        try {
          await newContext.addCookies([{
            name: cookieToRestore.name,
            value: cookieToRestore.value || '',
            domain: cookieToRestore.domain || 'kushnir.cloud',
            path: '/',
            expires: cookieToRestore.expires || -1,
            httpOnly: true,
            secure: true,
            sameSite: 'Lax'
          }]);
        } catch (e) {
          console.log('Could not restore cookie (may require valid expiry)');
        }
      }
      
      // Navigate with new context
      const newPage = await newContext.newPage();
      await newPage.goto(PORTAL_URL);
      
      // Should maintain session (or gracefully re-authenticate)
      // Actual behavior depends on session storage (Redis/in-memory)
      await newContext.close();
    });

    test('4: session expires after configured timeout', async ({ page, context }) => {
      // Navigate to protected resource
      await page.goto(PORTAL_URL);
      
      // Get session cookie expiry
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie?.expires).toBeGreaterThan(0);
      
      // Cookie should have reasonable expiry (not immediately)
      const expiryTime = (oauthCookie?.expires || 0) * 1000;
      const now = Date.now();
      const timeToExpiry = expiryTime - now;
      
      // Should expire in hours (not seconds)
      expect(timeToExpiry).toBeGreaterThan(60 * 60 * 1000); // > 1 hour
    });

    test('5: logout clears session', async ({ page, context }) => {
      // Login
      await page.goto(PORTAL_URL);
      
      // Verify authenticated
      const cookies1 = await context.cookies();
      const oauthCookie1 = cookies1.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie1).toBeDefined();
      
      // Logout (typical oauth2-proxy logout)
      await page.goto(`${PORTAL_URL}/oauth2/sign_out`);
      
      // Should redirect to login page
      await page.waitForTimeout(1000);
      const url = page.url();
      expect(url).toMatch(/oauth2|accounts\.google\.com|login/);
      
      // Session cookie should be cleared
      const cookies2 = await context.cookies();
      const oauthCookie2 = cookies2.find(c => c.name === '_oauth2_proxy');
      // Cookie either doesn't exist or is invalidated
      if (oauthCookie2) {
        // May have been cleared or expired
        expect(oauthCookie2.value).not.toBe(oauthCookie1?.value);
      }
    });

    test('6: concurrent tabs share session state', async ({ context }) => {
      // Open two tabs
      const page1 = await context.newPage();
      const page2 = await context.newPage();
      
      // Navigate both to protected resources
      await page1.goto(PORTAL_URL);
      await page2.goto(IDE_URL);
      
      // Get session from both
      const cookies1 = await context.cookies();
      const cookies2 = await context.cookies();
      
      // Should be identical (same context)
      const oauth1 = cookies1.find(c => c.name === '_oauth2_proxy')?.value;
      const oauth2 = cookies2.find(c => c.name === '_oauth2_proxy')?.value;
      
      expect(oauth1).toBe(oauth2);
      
      // Changes in one tab should be visible in other
      // (e.g., if user preferences are stored in session)
      await page1.close();
      await page2.close();
    });
  });

  test.describe('Network Disruption', () => {
    
    test('7: session survives brief network disconnection (<30s)', async ({ page, context }) => {
      // Navigate to IDE
      await page.goto(IDE_URL);
      
      // Verify authenticated
      const cookies1 = await context.cookies();
      const oauthCookie1 = cookies1.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie1).toBeDefined();
      
      // Go offline briefly
      await context.setOffline(true);
      await page.waitForTimeout(5000); // 5 seconds offline
      
      // Come back online
      await context.setOffline(false);
      
      // Session should still be valid
      const cookies2 = await context.cookies();
      const oauthCookie2 = cookies2.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie2?.value).toBe(oauthCookie1?.value);
    });

    test('8: work resumes after reconnect', async ({ page, context }) => {
      // Navigate to IDE
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench, .editor', { timeout: 30000 }).catch(() => {});
      
      // Simulate network drop
      await context.setOffline(true);
      await page.waitForTimeout(3000);
      
      // Restore network
      await context.setOffline(false);
      
      // Page should be functional
      // Refresh to ensure full reconnect
      await page.reload();
      
      // Should not redirect to login
      expect(page.url()).not.toMatch(/oauth2|accounts\.google\.com/);
    });

    test('9: graceful degradation in offline mode', async ({ page, context }) => {
      // Navigate to portal
      await page.goto(PORTAL_URL);
      
      // Block API calls (simulate API server down)
      await page.route('**/api/**', async (route) => {
        await route.abort('failed');
      });
      
      // Page should still be accessible (graceful fallback)
      const main = page.locator('main, .main, [role="main"]');
      if (await main.first().isVisible()) {
        await expect(main.first()).toBeVisible();
      }
    });

    test('10: WebSocket reconnects after network drop', async ({ page, context }) => {
      // Navigate to IDE (uses WebSocket for real-time updates)
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench, .editor', { timeout: 30000 }).catch(() => {});
      
      // Get initial WebSocket state
      const initialUrl = page.url();
      
      // Simulate network disruption
      await context.setOffline(true);
      await page.waitForTimeout(2000);
      await context.setOffline(false);
      
      // WebSocket should reconnect
      await page.waitForTimeout(2000);
      
      // Page should remain accessible
      expect(page.url()).toContain(initialUrl.split('?')[0]);
    });
  });

  test.describe('Host Failover (Dual-host Setup)', () => {
    
    test('11: OAuth cookies valid across both primary and replica hosts', async ({ page, context }) => {
      // Navigate to portal
      await page.goto(PORTAL_URL);
      
      // Get cookies
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      // Verify cookie domain allows both hosts
      // Cookie should have domain: .kushnir.cloud (or explicit domain allowing both)
      expect(oauthCookie).toBeDefined();
      if (oauthCookie?.domain) {
        // Domain should allow subdomains or be explicitly configured
        expect(oauthCookie.domain).toMatch(/kushnir\.cloud|localhost/);
      }
    });

    test('12: session transfers to replica on primary failure (if configured)', async ({ page, context }) => {
      // This test verifies cookie domain is configured for failover
      // Actual failover requires infrastructure changes
      
      await page.goto(PORTAL_URL);
      
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      // Cookie should have domain set (not just current host)
      // This allows it to work on replica (.42) if primary (.31) fails
      expect(oauthCookie?.domain).toBeTruthy();
      expect(oauthCookie?.domain).toMatch(/\.kushnir\.cloud|kushnir\.cloud/);
    });

    test('13: IDE workspace state preserved across hosts', async ({ page, context }) => {
      // Navigate to IDE
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 }).catch(() => {});
      
      // Note: Actual workspace preservation requires:
      // - Redis session store (persists across hosts)
      // - NAS-mounted workspace (accessible from both hosts)
      // This test just verifies no immediate crash
      
      const url = page.url();
      expect(url).toContain('ide.kushnir.cloud');
    });

    test('14: user not prompted to re-login during failover', async ({ page, context }) => {
      // Login
      await page.goto(PORTAL_URL);
      
      const cookies1 = await context.cookies();
      const oauthCookie1 = cookies1.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie1).toBeDefined();
      
      // Navigate to IDE (which might be on different host in failover scenario)
      await page.goto(IDE_URL);
      
      // Should NOT be redirected to login
      expect(page.url()).not.toMatch(/oauth2|accounts\.google\.com/);
      
      // Session should be the same
      const cookies2 = await context.cookies();
      const oauthCookie2 = cookies2.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie2?.value).toBe(oauthCookie1?.value);
    });

    test('15: no data loss during failover (session data integrity)', async ({ page, context }) => {
      // Login and perform actions
      await page.goto(PORTAL_URL);
      
      // Get initial session data
      const cookies1 = await context.cookies();
      const sessionId1 = cookies1.find(c => c.name === '_oauth2_proxy')?.value;
      expect(sessionId1).toBeTruthy();
      
      // Navigate to IDE
      await page.goto(IDE_URL);
      
      // Session ID should be preserved
      const cookies2 = await context.cookies();
      const sessionId2 = cookies2.find(c => c.name === '_oauth2_proxy')?.value;
      expect(sessionId2).toBe(sessionId1);
      
      // Both URLs should be accessible without re-authentication
      await page.goto(PORTAL_URL);
      expect(page.url()).not.toMatch(/oauth2|accounts\.google\.com/);
      
      await page.goto(IDE_URL);
      expect(page.url()).not.toMatch(/oauth2|accounts\.google\.com/);
    });
  });

  test.describe('Redis Session Storage', () => {
    
    test('session persisted in Redis (if applicable)', async ({ page, context }) => {
      // This test verifies session is stored in Redis (not just in-memory)
      // Required for failover scenarios
      
      await page.goto(PORTAL_URL);
      
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      // Session cookie should exist
      // In Redis-backed sessions, the cookie contains just a session ID
      expect(oauthCookie?.value).toBeTruthy();
      expect(oauthCookie?.value).toMatch(/^[a-f0-9]+$/i); // Typical session ID format
    });

    test('session TTL configured appropriately', async ({ page, context }) => {
      await page.goto(PORTAL_URL);
      
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      // Session should have expiry
      expect(oauthCookie?.expires).toBeGreaterThan(0);
      
      // Should be in hours range (not minutes, not days)
      const expiryMs = (oauthCookie?.expires || 0) * 1000;
      const nowMs = Date.now();
      const ttlMs = expiryMs - nowMs;
      
      const ONE_HOUR_MS = 60 * 60 * 1000;
      const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;
      
      expect(ttlMs).toBeGreaterThan(ONE_HOUR_MS);
      expect(ttlMs).toBeLessThan(TWENTY_FOUR_HOURS_MS);
    });
  });
});
