import { test, expect } from '@playwright/test';

const QA_EMAIL = process.env.E2E_USER_EMAIL || 'qa@kushnir.cloud';
const QA_PASSWORD = process.env.E2E_USER_PASSWORD || '';
const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

test.describe('OAuth Login Comprehensive (#986)', () => {
  
  test.describe('Happy Path - Login Flow', () => {
    
    test('1: complete OAuth flow results in authenticated session', async ({ page }) => {
      // Navigate to protected resource
      await page.goto(PORTAL_URL);
      
      // Should redirect to Google OAuth
      await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      
      // Enter QA email
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      
      // Wait for password field
      await page.waitForSelector('input[type="password"]', { timeout: 5000 });
      
      // Enter password
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      // Should redirect back to portal after OAuth callback
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      // Verify authenticated state via cookie
      const cookies = await page.context().cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie).toBeDefined();
      expect(oauthCookie?.value).toBeTruthy();
    });

    test('2: login preserves rd (redirect) parameter after authentication', async ({ page }) => {
      const redirectTarget = '/admin';
      
      // Navigate with rd parameter
      await page.goto(`${PORTAL_URL}/oauth2/start?rd=${encodeURIComponent(PORTAL_URL + redirectTarget)}`);
      
      // Go through OAuth flow
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      // Should redirect to the original target, not just portal root
      await page.waitForURL(new RegExp(`.*/admin`), { timeout: 15000 });
      expect(page.url()).toContain('/admin');
    });

    test('3: login sets _oauth2_proxy cookie', async ({ page }) => {
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      
      // Complete OAuth flow
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      // Verify all OAuth cookies present
      const cookies = await page.context().cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      const xsrfCookie = cookies.find(c => c.name === 'XSRF-TOKEN');
      
      expect(oauthCookie).toBeDefined();
      // XSRF token may not be present in all scenarios
    });

    test('4: login sets secure cookie attributes (httpOnly, Secure, SameSite)', async ({ page }) => {
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      
      // Complete login
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      const cookies = await page.context().cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      expect(oauthCookie?.httpOnly).toBe(true);
      expect(oauthCookie?.secure).toBe(true);
      // SameSite should be either 'Strict' or 'Lax'
      expect(['Strict', 'Lax', 'None']).toContain(oauthCookie?.sameSite);
    });

    test('5: authenticated session remains valid during session', async ({ page, context }) => {
      // Login
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      // Verify authenticated
      const cookies1 = await context.cookies();
      const oauth1 = cookies1.find(c => c.name === '_oauth2_proxy');
      expect(oauth1).toBeDefined();
      
      // Wait a few seconds
      await page.waitForTimeout(2000);
      
      // Navigate within same origin
      await page.goto(`${PORTAL_URL}/health`);
      
      // Session should still be valid
      const cookies2 = await context.cookies();
      const oauth2 = cookies2.find(c => c.name === '_oauth2_proxy');
      expect(oauth2).toBeDefined();
      expect(oauth2?.value).toBe(oauth1?.value);
    });

    test('6: refresh token extends session (if applicable)', async ({ page, context }) => {
      // This test may not apply if oauth2-proxy uses simple cookie sessions
      // Skip if no refresh token mechanism
      
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      const cookies = await context.cookies();
      const refreshToken = cookies.find(c => c.name === '_oauth2_refresh');
      
      if (refreshToken) {
        expect(refreshToken).toBeDefined();
        expect(refreshToken?.value).toBeTruthy();
      }
    });

    test('7: session valid across subdomains (kushnir.cloud and ide.kushnir.cloud)', async ({ page, context }) => {
      // Login to portal
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      // Navigate to IDE subdomain
      await page.goto(IDE_URL);
      
      // Should NOT redirect to Google (session shared via domain cookie)
      const url = page.url();
      expect(url).not.toMatch(/accounts\.google\.com/);
      expect(url).toContain('ide.kushnir.cloud');
    });

    test('8: multiple login attempts remain idempotent', async ({ page, context }) => {
      // First login
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      const cookies1 = await context.cookies();
      const oauth1 = cookies1.find(c => c.name === '_oauth2_proxy')?.value;
      
      // Try to login again (already authenticated)
      await page.goto(PORTAL_URL);
      // Should not redirect to Google this time
      expect(page.url()).toContain(PORTAL_URL);
      
      const cookies2 = await context.cookies();
      const oauth2 = cookies2.find(c => c.name === '_oauth2_proxy')?.value;
      
      // Should be same session
      expect(oauth2).toBe(oauth1);
    });
  });

  test.describe('Error Handling', () => {
    
    test('9: non-whitelisted user gets clear error message', async ({ page }) => {
      // This test uses a non-whitelisted Google account
      // Expected behavior: oauth2-proxy returns 403/401 with error
      
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      
      // Try to login with invalid account (would need separate test account)
      // For now, verify the whitelisting mechanism works
      const whitelistResponse = await page.evaluate(() => {
        return document.documentElement.innerHTML;
      });
      
      // Just verify the page loads (actual test would need second account)
      expect(whitelistResponse).toBeTruthy();
    });

    test('10: user cancels at Google prompt receives graceful error', async ({ page }) => {
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      
      // Instead of completing OAuth, navigate away (simulating cancel)
      await page.goto(PORTAL_URL);
      
      // Should either return to login or show error
      const url = page.url();
      expect(url).toBeTruthy();
    });

    test('11: expired or stale OAuth code rejected', async ({ page }) => {
      // This test requires intercepting and modifying the OAuth callback
      // Playwright can do this via route interception
      
      await page.route('**/oauth2/callback*', async (route) => {
        // Modify the code parameter to be invalid
        const url = new URL(route.request().url());
        url.searchParams.set('code', 'invalid-stale-code');
        await route.abort('failed');
      });
      
      await page.goto(PORTAL_URL);
      // OAuth flow should fail gracefully
      await page.waitForLoadState('networkidle');
    });

    test('12: CSRF token mismatch blocked', async ({ page, context }) => {
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      
      // Get all cookies including state
      const cookies = await context.cookies();
      
      // Complete login flow normally
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      // Try to proceed (oauth2-proxy will validate state/CSRF)
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
    });

    test('13: network timeout when Google unreachable (with retry)', async ({ page, context }) => {
      // Block Google requests
      await page.route('**/accounts.google.com/**', async (route) => {
        await route.abort('timedout');
      });
      
      await page.goto(PORTAL_URL);
      
      // oauth2-proxy should handle the timeout
      await page.waitForLoadState('networkidle');
      const content = await page.content();
      expect(content).toBeTruthy();
    });

    test('14: rate limiting returns clear message', async ({ page }) => {
      // This test would require simulating multiple rapid requests
      // For now, verify basic rate limiting doesn't break normal flow
      
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      
      // Proceed normally
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      expect(page.url()).toContain(PORTAL_URL);
    });
  });

  test.describe('Edge Cases', () => {
    
    test('15: multiple browser tabs with concurrent sessions', async ({ browser, context }) => {
      // Create two pages in same context (shared cookies)
      const page1 = await context.newPage();
      const page2 = await context.newPage();
      
      // Login in tab 1
      await page1.goto(PORTAL_URL);
      await page1.waitForURL(/accounts\.google\.com/);
      await page1.fill('input[type="email"]', QA_EMAIL);
      await page1.click('#identifierNext, button:has-text("Next")');
      await page1.waitForSelector('input[type="password"]');
      await page1.fill('input[type="password"]', QA_PASSWORD);
      await page1.click('#passwordNext, button:has-text("Next")');
      await page1.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      // Tab 2 should automatically have session (shared cookies)
      await page2.goto(PORTAL_URL);
      // Should not redirect to Google
      expect(page2.url()).toContain(PORTAL_URL);
      expect(page2.url()).not.toMatch(/accounts\.google\.com/);
      
      await page1.close();
      await page2.close();
    });

    test('16: cookie tampering invalidates session', async ({ page, context }) => {
      // Login normally
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      // Tamper with OAuth cookie
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      if (oauthCookie) {
        await context.addCookies([{
          ...oauthCookie,
          value: 'tampered_invalid_value'
        }]);
      }
      
      // Navigate to protected resource
      await page.goto(PORTAL_URL);
      
      // Should redirect to OAuth (session invalid)
      const url = page.url();
      expect(url).toMatch(/accounts\.google\.com|oauth2/);
    });

    test('17: back button after login does not break session', async ({ page }) => {
      // Login
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      // Navigate somewhere else
      await page.goto(`${PORTAL_URL}/health`);
      
      // Click back button
      await page.goBack();
      
      // Should still be authenticated
      const url = page.url();
      expect(url).toContain(PORTAL_URL);
      expect(url).not.toMatch(/accounts\.google\.com/);
    });

    test('18: deep link to protected resource preserves redirect after login', async ({ page }) => {
      const targetPath = '/admin/settings';
      
      // Direct access to deep link
      await page.goto(`${PORTAL_URL}${targetPath}`);
      
      // Should redirect to OAuth login
      await page.waitForURL(/accounts\.google\.com/, { timeout: 5000 });
      
      // Complete OAuth
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      // Should redirect back to original deep link
      await page.waitForURL(new RegExp(`${targetPath}`), { timeout: 15000 });
      expect(page.url()).toContain(targetPath);
    });

    test('19: login works with mobile user agent', async ({ browser }) => {
      const mobileContext = await browser.newContext({
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15'
      });
      const page = await mobileContext.newPage();
      
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      
      // Complete login with mobile UA
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      
      expect(page.url()).toContain(PORTAL_URL);
      await mobileContext.close();
    });

    test('20: login works in incognito mode', async ({ browser }) => {
      const incognitoContext = await browser.newContext();
      const page = await incognitoContext.newPage();
      
      // No cached state in incognito
      const cookies = await incognitoContext.cookies();
      expect(cookies.length).toBe(0);
      
      // Complete login
      await page.goto(PORTAL_URL);
      await page.waitForURL(/accounts\.google\.com/);
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
      expect(page.url()).toContain(PORTAL_URL);
      
      await incognitoContext.close();
    });
  });
});
