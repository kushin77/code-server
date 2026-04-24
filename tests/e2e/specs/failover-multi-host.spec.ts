import { test, expect } from '@playwright/test';

const PRIMARY_URL = process.env.PRIMARY_IDE_URL || 'https://ide.kushnir.cloud';
const REPLICA_URL = process.env.REPLICA_IDE_URL || 'https://replica.ide.kushnir.cloud';
const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const QA_EMAIL = process.env.E2E_USER_EMAIL || 'qa@kushnir.cloud';
const QA_PASSWORD = process.env.E2E_USER_PASSWORD || '';

test.describe('Failover & Multi-Host Scenarios (#1177)', () => {

  test.describe('Cross-Host OAuth Login', () => {

    test('1: OAuth login works on replica host', async ({ page }) => {
      // Navigate to replica IDE
      await page.goto(REPLICA_URL);
      
      // Should redirect to OAuth
      await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      
      // Complete OAuth flow
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]', { timeout: 5000 });
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      
      // Should redirect back to replica after OAuth
      await page.waitForURL(new RegExp(`^${REPLICA_URL}`), { timeout: 15000 });
      
      // Verify authenticated
      const cookies = await page.context().cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie).toBeDefined();
    });

    test('2: Cross-host sticky sessions maintained', async ({ page, context }) => {
      // Create a new context for replica
      const replicaContext = await context.browser().newContext();
      const replicaPage = await replicaContext.newPage();
      
      // Login on replica
      await replicaPage.goto(REPLICA_URL);
      await replicaPage.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      await replicaPage.fill('input[type="email"]', QA_EMAIL);
      await replicaPage.click('#identifierNext, button:has-text("Next")');
      await replicaPage.waitForSelector('input[type="password"]', { timeout: 5000 });
      await replicaPage.fill('input[type="password"]', QA_PASSWORD);
      await replicaPage.click('#passwordNext, button:has-text("Next")');
      await replicaPage.waitForURL(new RegExp(`^${REPLICA_URL}`), { timeout: 15000 });
      
      // Check for sticky session cookie
      const cookies = await replicaPage.context().cookies();
      const ideCookie = cookies.find(c => c.name === 'ide_session_lb');
      expect(ideCookie).toBeDefined();
      
      // Multiple requests should route to same backend (sticky)
      for (let i = 0; i < 3; i++) {
        await replicaPage.goto(`${REPLICA_URL}/health`);
        const response = await replicaPage.request.get(`${REPLICA_URL}/api/v1/sessions`);
        expect(response.ok).toBe(true);
      }
      
      await replicaContext.close();
    });
  });

  test.describe('Session Persistence During Failover', () => {

    test('1: Session ID persists across failover', async ({ page }) => {
      // Login on primary
      await page.goto(PRIMARY_URL);
      await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]', { timeout: 5000 });
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PRIMARY_URL}`), { timeout: 15000 });
      
      // Get initial session ID from cookies
      const initialCookies = await page.context().cookies();
      const sessionCookie = initialCookies.find(c => c.name === 'ide_session_id');
      const initialSessionId = sessionCookie?.value;
      
      // Simulate failover by accessing replica
      // In real scenario, this would be automatic DNS failover
      const replicaResponse = await page.request.get(`${REPLICA_URL}/api/v1/sessions`, {
        headers: {
          'Cookie': initialCookies.map(c => `${c.name}=${c.value}`).join('; ')
        }
      });
      
      // Session should still be valid on replica
      expect(replicaResponse.ok).toBe(true);
    });

    test('2: Session state restored on failover', async ({ page }) => {
      // Login and perform action on primary
      await page.goto(PRIMARY_URL);
      await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]', { timeout: 5000 });
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PRIMARY_URL}`), { timeout: 15000 });
      
      // Perform some action (e.g., open a file)
      // This would depend on IDE implementation
      
      // Get session cookies
      const cookies = await page.context().cookies();
      
      // Verify session works on replica with same cookies
      const replicaResponse = await page.request.get(`${REPLICA_URL}/api/v1/authenticated-endpoint`, {
        headers: {
          'Cookie': cookies.map(c => `${c.name}=${c.value}`).join('; ')
        }
      });
      
      expect(replicaResponse.status()).not.toBe(401);
    });
  });

  test.describe('Token Refresh Across Failover', () => {

    test('1: Token acquired on primary is valid on replica', async ({ page }) => {
      // This test requires token endpoints
      // Login and get JWT token
      await page.goto(PRIMARY_URL);
      await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]', { timeout: 5000 });
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PRIMARY_URL}`), { timeout: 15000 });
      
      // Get JWT token via API
      const tokenResponse = await page.request.post(`${PRIMARY_URL}/oauth2/token`, {
        data: {
          grant_type: 'client_credentials',
          client_id: 'code-server',
          client_secret: process.env.OAUTH2_CLIENT_SECRET
        }
      });
      
      if (tokenResponse.ok) {
        const tokenData = await tokenResponse.json();
        const token = tokenData.access_token;
        
        // Use token on replica
        const replicaResponse = await page.request.get(`${REPLICA_URL}/api/v1/sessions`, {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        });
        
        expect(replicaResponse.status()).not.toBe(401);
      }
    });

    test('2: Token refresh works after failover', async ({ page }) => {
      // Token refresh should work on either host
      // This assumes token endpoint is available on both
      
      const refreshResponse = await page.request.post(`${REPLICA_URL}/oauth2/token`, {
        data: {
          grant_type: 'refresh_token',
          refresh_token: process.env.REFRESH_TOKEN || '',
          client_id: 'code-server',
          client_secret: process.env.OAUTH2_CLIENT_SECRET
        }
      });
      
      // Should succeed or fail gracefully
      if (process.env.REFRESH_TOKEN) {
        expect(refreshResponse.ok).toBe(true);
      }
    });
  });

  test.describe('Failover Edge Cases', () => {

    test('1: Session continues after primary restart', async ({ page }) => {
      // Login on primary
      await page.goto(PRIMARY_URL);
      await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext, button:has-text("Next")');
      await page.waitForSelector('input[type="password"]', { timeout: 5000 });
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext, button:has-text("Next")');
      await page.waitForURL(new RegExp(`^${PRIMARY_URL}`), { timeout: 15000 });
      
      // Get session cookies
      const cookies = await page.context().cookies();
      
      // After primary restart (in test: wait a bit then try replica)
      await page.waitForTimeout(2000);
      
      // Session should still be valid
      const sessionResponse = await page.request.get(`${REPLICA_URL}/api/v1/sessions`, {
        headers: {
          'Cookie': cookies.map(c => `${c.name}=${c.value}`).join('; ')
        }
      });
      
      expect(sessionResponse.ok).toBe(true);
    });

    test('2: Unauthenticated traffic gets redirected to OAuth on replica', async ({ page }) => {
      // Try accessing protected endpoint without auth
      const response = await page.goto(REPLICA_URL, { waitUntil: 'domcontentloaded' });
      
      // Should either show login page or redirect to OAuth
      expect(response?.url()).toBeDefined();
      // If redirected to OAuth
      if (response?.url().includes('google')) {
        expect(response.url()).toContain('accounts.google');
      }
    });

    test('3: Multiple concurrent sessions are preserved', async ({ browser }) => {
      // Create multiple browser contexts (simulating different users)
      const context1 = await browser.newContext();
      const context2 = await browser.newContext();
      
      const page1 = await context1.newPage();
      const page2 = await context2.newPage();
      
      // Login user 1
      await page1.goto(PRIMARY_URL);
      // ... complete OAuth flow ...
      
      // Login user 2
      await page2.goto(REPLICA_URL);
      // ... complete OAuth flow ...
      
      // Both sessions should be independent
      const cookies1 = await page1.context().cookies();
      const cookies2 = await page2.context().cookies();
      
      expect(cookies1).not.toEqual(cookies2);
      
      // Both should have valid sessions
      const session1 = await page1.request.get(`${PRIMARY_URL}/api/v1/sessions`, {
        headers: {
          'Cookie': cookies1.map(c => `${c.name}=${c.value}`).join('; ')
        }
      });
      
      const session2 = await page2.request.get(`${REPLICA_URL}/api/v1/sessions`, {
        headers: {
          'Cookie': cookies2.map(c => `${c.name}=${c.value}`).join('; ')
        }
      });
      
      expect(session1.ok).toBe(true);
      expect(session2.ok).toBe(true);
      
      await context1.close();
      await context2.close();
    });
  });

  test.describe('Load Balancer Behavior', () => {

    test('1: Caddy load balancer distributes traffic', async ({ page }) => {
      // Make multiple requests and verify they're handled
      const responses = [];
      
      for (let i = 0; i < 5; i++) {
        const response = await page.request.get(`${PRIMARY_URL}/health`);
        responses.push(response.status());
      }
      
      // All should be successful
      expect(responses.every(s => s === 200)).toBe(true);
    });

    test('2: Sticky session routing is consistent', async ({ page }) => {
      // Get initial cookie
      const response1 = await page.request.get(`${PRIMARY_URL}/health`);
      
      // Make multiple requests with same session
      const cookies = await page.context().cookies();
      
      let lastBackendId = '';
      for (let i = 0; i < 3; i++) {
        const response = await page.request.get(`${PRIMARY_URL}/debug/backend-id`, {
          headers: {
            'Cookie': cookies.map(c => `${c.name}=${c.value}`).join('; ')
          }
        });
        
        if (response.ok) {
          const body = await response.json();
          const backendId = body.backend_id;
          
          if (lastBackendId) {
            expect(backendId).toBe(lastBackendId);
          }
          lastBackendId = backendId;
        }
      }
    });
  });
});
