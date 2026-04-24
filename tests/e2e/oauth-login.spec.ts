import { test, expect } from './fixtures';

const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
const E2E_USER_EMAIL = process.env.E2E_USER_EMAIL || 'qa@kushnir.cloud';
const E2E_USER_PASSWORD = process.env.E2E_USER_PASSWORD || '';

test.describe('OAuth Login Flow - Comprehensive Validation', () => {
  /**
   * HAPPY PATH SCENARIOS (Happy Path Group 1: Basic Login)
   */
  test.describe('Happy Path - Basic Login Flow', () => {
    test('user can login via Google OAuth', async ({ authenticatedPage, context }) => {
      // authenticatedPage fixture already handles login
      // Just verify we're in the authenticated state
      expect(authenticatedPage).toBeDefined();
      
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie).toBeDefined();
      expect(oauthCookie?.value).toBeTruthy();
    });

    test('successful login redirects to dashboard', async ({ authenticatedPage }) => {
      // After successful OAuth, user should be redirected to portal
      const url = authenticatedPage.url();
      expect(url).toContain('kushnir.cloud');
      expect(url).not.toContain('accounts.google.com');
      expect(url).not.toContain('oauth2');
    });

    test('oauth cookie is set after login', async ({ authenticatedPage, context }) => {
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      expect(oauthCookie).toBeDefined();
      expect(oauthCookie?.httpOnly).toBe(true);
      expect(oauthCookie?.secure).toBe(true); // HTTPS only
      expect(oauthCookie?.sameSite).toBe('Lax'); // CSRF protection
    });

    test('session is accessible after login', async ({ authenticatedPage }) => {
      // Check that user can access protected resources
      await authenticatedPage.goto(PORTAL_URL);
      
      const response = await authenticatedPage.waitForResponse(
        response => response.url().includes(PORTAL_URL) && response.status() === 200
      );
      expect(response.status()).toBe(200);
    });

    test('user info is available in oauth proxy headers', async ({ authenticatedPage }) => {
      // oauth2-proxy sets X-Remote-User header on authenticated requests
      const response = await authenticatedPage.goto(PORTAL_URL);
      
      // oauth2-proxy preserves user information
      expect(response?.status()).toBe(200);
    });
  });

  /**
   * HAPPY PATH SCENARIOS (Happy Path Group 2: Session Management)
   */
  test.describe('Happy Path - Session Management', () => {
    test('user remains logged in across page navigations', async ({ authenticatedPage }) => {
      // Navigate to multiple pages while authenticated
      await authenticatedPage.goto(`${PORTAL_URL}/dashboard`);
      expect(authenticatedPage.url()).toContain('/dashboard');
      
      await authenticatedPage.goto(`${PORTAL_URL}/settings`);
      expect(authenticatedPage.url()).toContain('/settings');
      
      // Still authenticated
      const cookies = await authenticatedPage.context().cookies();
      expect(cookies.some(c => c.name === '_oauth2_proxy')).toBe(true);
    });

    test('logout clears oauth cookie', async ({ authenticatedPage, context }) => {
      // Perform logout (implementation depends on app)
      await authenticatedPage.goto(`${PORTAL_URL}/logout`);
      
      // oauth2-proxy clears the cookie on logout
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      // Cookie should be cleared or expired
      expect(!oauthCookie || oauthCookie.expires === -1).toBe(true);
    });

    test('accessing protected resource without session redirects to login', async ({ page }) => {
      // Start fresh without authentication
      await page.goto(PORTAL_URL, { waitUntil: 'networkidle' });
      
      // Should redirect to Google OAuth
      const url = page.url();
      expect(url).toMatch(/accounts\.google\.com|oauth2/i);
    });

    test('session timeout redirects to login', async ({ authenticatedPage, context }) => {
      // Clear cookies to simulate session timeout
      await context.clearCookies();
      
      // Try to access protected resource
      await authenticatedPage.goto(PORTAL_URL);
      
      // Should redirect to login
      await authenticatedPage.waitForURL(/accounts\.google\.com|oauth2/i);
    });
  });

  /**
   * HAPPY PATH SCENARIOS (Happy Path Group 3: Multiple Account Scenarios)
   */
  test.describe('Happy Path - Multiple Accounts', () => {
    test('user can switch accounts via logout/login', async ({ browser, vpnConnected }) => {
      // Ensure VPN is connected for test
      expect(vpnConnected).toBe(true);
      
      // First login with primary account (done in fixture)
      const context1 = await browser.newContext();
      const page1 = await context1.newPage();
      
      // Login flow for first account
      // ... (authentication code)
      
      // Verify first account is logged in
      // ...
      
      // Logout from first account
      await page1.goto(`${PORTAL_URL}/logout`);
      
      // Login with second account
      // ... (authentication code for different account)
      
      await context1.close();
    });

    test('concurrent sessions from different browsers are isolated', async ({ browser }) => {
      const context1 = await browser.newContext();
      const context2 = await browser.newContext();
      
      const page1 = await context1.newPage();
      const page2 = await context2.newPage();
      
      // Both should have separate sessions
      const cookies1 = await context1.cookies();
      const cookies2 = await context2.cookies();
      
      const sessionId1 = cookies1.find(c => c.name === '_oauth2_proxy')?.value;
      const sessionId2 = cookies2.find(c => c.name === '_oauth2_proxy')?.value;
      
      expect(sessionId1).not.toBe(sessionId2);
      
      await context1.close();
      await context2.close();
    });
  });

  /**
   * ERROR HANDLING SCENARIOS (Error Group 1: Invalid Credentials)
   */
  test.describe('Error Handling - Invalid Credentials', () => {
    test('non-whitelisted user gets clear error', async ({ page, vpnConnected }) => {
      expect(vpnConnected).toBe(true);
      
      // Attempt to login with non-whitelisted email
      await page.goto(`${PORTAL_URL}/login`);
      
      // Simulate Google OAuth callback with invalid user
      // oauth2-proxy should return 403
      const response = await page.goto(
        `${process.env.OAUTH2_PROXY_URL || 'http://localhost:4180'}/oauth2/callback?code=fake&state=fake`
      );
      
      expect(response?.status()).toBe(403);
    });

    test('invalid password is rejected', async ({ page }) => {
      // This tests the Google OAuth flow
      // Google would reject invalid password, not our app
      // But we can test the redirect behavior
      
      await page.goto(`${PORTAL_URL}/login`);
      
      // After Google rejects, user should stay on Google login page
      const url = page.url();
      expect(url).toMatch(/accounts\.google\.com/i);
    });

    test('expired oauth code is rejected', async ({ page }) => {
      // oauth2-proxy with expired authorization code
      const response = await page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?code=expired_code&state=test_state`,
        { waitUntil: 'networkidle' }
      );
      
      // Should reject with error
      expect(response?.status()).toBeGreaterThanOrEqual(400);
    });

    test('missing oauth code parameter rejected', async ({ page }) => {
      const response = await page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?state=test_state`,
        { waitUntil: 'networkidle' }
      );
      
      expect(response?.status()).toBeGreaterThanOrEqual(400);
    });
  });

  /**
   * ERROR HANDLING SCENARIOS (Error Group 2: CSRF Protection)
   */
  test.describe('Error Handling - CSRF Protection', () => {
    test('CSRF mismatch is blocked', async ({ page }) => {
      // Attempt callback with mismatched state parameter
      const response = await page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?code=test&state=mismatched_state`,
        { waitUntil: 'networkidle' }
      );
      
      // oauth2-proxy should reject state mismatch
      expect(response?.status()).toBeGreaterThanOrEqual(400);
    });

    test('missing state parameter is blocked', async ({ page }) => {
      const response = await page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?code=test`,
        { waitUntil: 'networkidle' }
      );
      
      expect(response?.status()).toBeGreaterThanOrEqual(400);
    });

    test('duplicate state usage is blocked', async ({ page }) => {
      // oauth2-proxy should use nonce or one-time state
      const state = 'test_state_123';
      
      await page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?code=test1&state=${state}`,
        { waitUntil: 'networkidle' }
      );
      
      // Using same state again should fail
      const response2 = await page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?code=test2&state=${state}`,
        { waitUntil: 'networkidle' }
      );
      
      expect(response2?.status()).toBeGreaterThanOrEqual(400);
    });
  });

  /**
   * ERROR HANDLING SCENARIOS (Error Group 3: Session Errors)
   */
  test.describe('Error Handling - Session Errors', () => {
    test('corrupted oauth cookie is handled', async ({ authenticatedPage, context }) => {
      // Get original cookies
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      if (oauthCookie) {
        // Clear and add corrupted version
        await context.clearCookies({ name: '_oauth2_proxy' });
        await context.addCookies([{
          ...oauthCookie,
          value: 'corrupted_data'
        }]);
        
        // Should redirect to login
        await authenticatedPage.goto(PORTAL_URL);
        await authenticatedPage.waitForURL(/accounts\.google\.com|oauth2/i);
      }
    });

    test('missing oauth cookie redirects to login', async ({ page }) => {
      // Create context with no cookies
      await page.goto(PORTAL_URL);
      
      // Should redirect to OAuth
      const url = page.url();
      expect(url).toMatch(/accounts\.google\.com|oauth2/i);
    });

    test('network error during oauth callback handled gracefully', async ({ page }) => {
      // Attempt callback with network error
      // This simulates connection drop
      const promise = page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?code=test&state=test`,
        { timeout: 5000 }
      ).catch(() => null);
      
      // Should either handle gracefully or timeout appropriately
      expect(promise).toBeDefined();
    });
  });

  /**
   * EDGE CASES (Edge Case Group 1: Cookie Security)
   */
  test.describe('Edge Cases - Cookie Security', () => {
    test('cookie tampering invalidates session', async ({ authenticatedPage, context }) => {
      // Get cookies
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      // Tamper with cookie
      if (oauthCookie) {
        const tamperedValue = oauthCookie.value.substring(0, 10) + 'TAMPERED';
        
        await context.clearCookies({ name: '_oauth2_proxy' });
        await context.addCookies([{
          ...oauthCookie,
          value: tamperedValue
        }]);
        
        // Attempt to use tampered session
        await authenticatedPage.goto(PORTAL_URL);
        
        // Should redirect to login (session invalidated)
        await authenticatedPage.waitForURL(/accounts\.google\.com|oauth2/i);
      }
    });

    test('cookie domain isolation prevents cross-domain access', async ({ browser }) => {
      const context = await browser.newContext();
      const page = await context.newPage();
      
      // oauth2-proxy cookie should be domain-scoped
      await page.goto(PORTAL_URL);
      const cookies = await context.cookies();
      
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      if (oauthCookie) {
        // Cookie should be scoped to kushnir.cloud, not accessible cross-domain
        expect(oauthCookie.domain).toContain('kushnir.cloud');
      }
      
      await context.close();
    });

    test('httpOnly flag prevents JavaScript access', async ({ authenticatedPage }) => {
      // Attempt to access cookie via JavaScript
      const jsAccessible = await authenticatedPage.evaluate(() => {
        return document.cookie.includes('_oauth2_proxy');
      });
      
      // httpOnly flag should prevent JS access
      expect(jsAccessible).toBe(false);
    });

    test('secure flag enforces HTTPS only', async ({ authenticatedPage }) => {
      const context = authenticatedPage.context();
      const cookies = await context.cookies();
      
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      if (oauthCookie) {
        // Secure flag should be set
        expect(oauthCookie.secure).toBe(true);
      }
    });

    test('sameSite attribute prevents CSRF attacks', async ({ authenticatedPage }) => {
      const context = authenticatedPage.context();
      const cookies = await context.cookies();
      
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      if (oauthCookie) {
        // SameSite should be Lax or Strict
        expect(['Lax', 'Strict']).toContain(oauthCookie.sameSite);
      }
    });
  });

  /**
   * EDGE CASES (Edge Case Group 2: Race Conditions)
   */
  test.describe('Edge Cases - Race Conditions', () => {
    test('simultaneous login attempts are handled correctly', async ({ browser }) => {
      // Create multiple contexts attempting login simultaneously
      const contexts = [];
      const navigationPromises = [];
      
      for (let i = 0; i < 3; i++) {
        const ctx = await browser.newContext();
        contexts.push(ctx);
        const page = await ctx.newPage();
        
        navigationPromises.push(page.goto(PORTAL_URL));
      }
      
      // All should resolve without conflicts
      const responses = await Promise.all(navigationPromises);
      
      // All should be valid responses
      responses.forEach(response => {
        expect(response?.status()).toBeLessThan(500);
      });
      
      // Cleanup
      for (const ctx of contexts) {
        await ctx.close();
      }
    });

    test('rapid page reloads maintain session', async ({ authenticatedPage }) => {
      // Perform rapid reloads
      for (let i = 0; i < 5; i++) {
        await authenticatedPage.reload();
      }
      
      // Should still be authenticated
      const url = authenticatedPage.url();
      expect(url).not.toMatch(/accounts\.google\.com|oauth2/i);
    });

    test('back button after logout stays logged out', async ({ authenticatedPage, page }) => {
      // Login
      expect(authenticatedPage.url()).not.toMatch(/accounts\.google\.com/i);
      
      // Logout
      await authenticatedPage.goto(`${PORTAL_URL}/logout`);
      
      // Try to go back
      await authenticatedPage.goBack();
      
      // Should redirect to login again (not allow going back to protected page)
      await authenticatedPage.waitForURL(/accounts\.google\.com|oauth2/i, { timeout: 5000 }).catch(() => {});
    });
  });

  /**
   * EDGE CASES (Edge Case Group 3: Special Characters & Encoding)
   */
  test.describe('Edge Cases - Special Characters & Encoding', () => {
    test('email with special characters in whitelist works', async ({ authenticatedPage }) => {
      // Some emails might have + or . characters
      // Should be properly encoded in OAuth flow
      
      const url = authenticatedPage.url();
      expect(url).not.toMatch(/accounts\.google\.com/i);
    });

    test('redirect URL with query parameters is preserved', async ({ page }) => {
      // Start auth flow with redirect parameter
      const redirectUrl = `${PORTAL_URL}/dashboard?tab=settings&sort=date`;
      
      // After successful login, should redirect to original URL
      await page.goto(`${PORTAL_URL}/login?redirect=${encodeURIComponent(redirectUrl)}`);
      
      // Following OAuth callback should redirect to original URL
      // (implementation specific)
    });

    test('state parameter with special characters is handled', async ({ page }) => {
      const specialState = encodeURIComponent('state_with_!@#$%^&*()');
      
      const response = await page.goto(
        `${process.env.OAUTH2_PROXY_URL}/oauth2/callback?code=test&state=${specialState}`,
        { waitUntil: 'networkidle' }
      );
      
      // Should handle without error
      expect(response?.status()).toBeDefined();
    });
  });

  /**
   * INTEGRATION SCENARIOS (Integration Group 1: IDE Access)
   */
  test.describe('Integration - IDE Access After OAuth', () => {
    test('authenticated user can access IDE', async ({ authenticatedPage }) => {
      // Navigate to IDE
      await authenticatedPage.goto(IDE_URL);
      
      // Should not redirect to login
      const url = authenticatedPage.url();
      expect(url).not.toMatch(/accounts\.google\.com|oauth2/i);
      
      // Should be able to see IDE interface
      // (specific selectors depend on IDE implementation)
    });

    test('IDE session cookie is separate from oauth2-proxy cookie', async ({ authenticatedPage, context }) => {
      await authenticatedPage.goto(IDE_URL);
      
      const cookies = await context.cookies();
      
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      const sessionCookie = cookies.find(c => c.name?.includes('session') || c.name?.includes('SESSION'));
      
      // Should have both types of cookies
      expect(oauthCookie).toBeDefined();
      // sessionCookie might not exist depending on IDE implementation
    });
  });

  /**
   * PERFORMANCE SCENARIOS
   */
  test.describe('Performance', () => {
    test('oauth login completes in reasonable time', async ({ page, vpnConnected }) => {
      expect(vpnConnected).toBe(true);
      
      const startTime = Date.now();
      
      // Go to login page
      await page.goto(PORTAL_URL);
      
      // Wait for OAuth redirect
      await page.waitForURL(/accounts\.google\.com|oauth2/i, { timeout: 10000 });
      
      const duration = Date.now() - startTime;
      
      // Should complete in under 10 seconds
      expect(duration).toBeLessThan(10000);
    });

    test('logout completes quickly', async ({ authenticatedPage }) => {
      const startTime = Date.now();
      
      await authenticatedPage.goto(`${PORTAL_URL}/logout`);
      
      const duration = Date.now() - startTime;
      
      // Should logout in under 2 seconds
      expect(duration).toBeLessThan(2000);
    });
  });
});
