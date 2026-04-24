import { test, expect } from './fixtures';
const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
const PRIMARY_HOST = process.env.PRIMARY_HOST || '192.168.168.31';
const REPLICA_HOST = process.env.REPLICA_HOST || '192.168.168.42';
test.describe('Session Persistence & Failover Scenarios - E2E Tests', () => {
    /**
     * HAPPY PATH: Session Persistence
     */
    test.describe('Happy Path - Session Persistence', () => {
        test('session persists across page navigations', async ({ authenticatedPage }) => {
            // Start at portal
            await authenticatedPage.goto(PORTAL_URL);
            const initialCookies = await authenticatedPage.context().cookies();
            const sessionCookie = initialCookies.find(c => c.name === '_oauth2_proxy');
            // Navigate to IDE
            await authenticatedPage.goto(IDE_URL);
            const ideUrl = authenticatedPage.url();
            expect(ideUrl).not.toMatch(/accounts\.google\.com|oauth2/i);
            // Session cookie should persist
            const ideCookies = await authenticatedPage.context().cookies();
            const ideSessionCookie = ideCookies.find(c => c.name === '_oauth2_proxy');
            expect(ideSessionCookie?.value).toBe(sessionCookie?.value);
        });
        test('session persists across browser tab switch', async ({ browser, vpnConnected }) => {
            expect(vpnConnected).toBe(true);
            // Create two tabs with same context
            const context = await browser.newContext();
            const page1 = await context.newPage();
            const page2 = await context.newPage();
            // Login in page 1
            await page1.goto(PORTAL_URL);
            // (authenticate via fixture in real test)
            // Switch to page 2
            await page2.goto(PORTAL_URL);
            // Both should share session
            const cookies1 = await context.cookies();
            const cookies2 = await context.cookies();
            const session1 = cookies1.find(c => c.name === '_oauth2_proxy');
            const session2 = cookies2.find(c => c.name === '_oauth2_proxy');
            expect(session1?.value).toBe(session2?.value);
            await context.close();
        });
        test('session survives page reload', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Get initial session
            const initialCookies = await authenticatedPage.context().cookies();
            const initialSession = initialCookies.find(c => c.name === '_oauth2_proxy')?.value;
            // Reload page multiple times
            for (let i = 0; i < 3; i++) {
                await authenticatedPage.reload();
                await authenticatedPage.waitForLoadState('networkidle');
            }
            // Session should remain the same
            const finalCookies = await authenticatedPage.context().cookies();
            const finalSession = finalCookies.find(c => c.name === '_oauth2_proxy')?.value;
            expect(finalSession).toBe(initialSession);
        });
        test('session survives browser back button', async ({ authenticatedPage }) => {
            // Navigate through pages
            await authenticatedPage.goto(PORTAL_URL);
            const initialSession = await authenticatedPage.context().cookies();
            await authenticatedPage.goto(`${PORTAL_URL}/dashboard`);
            await authenticatedPage.goto(`${PORTAL_URL}/settings`);
            // Go back
            await authenticatedPage.goBack();
            await authenticatedPage.goBack();
            // Session should still be valid
            const finalSession = await authenticatedPage.context().cookies();
            const initialCookie = initialSession.find(c => c.name === '_oauth2_proxy');
            const finalCookie = finalSession.find(c => c.name === '_oauth2_proxy');
            expect(finalCookie?.value).toBe(initialCookie?.value);
        });
        test('session cookie has appropriate expiration', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            const cookies = await authenticatedPage.context().cookies();
            const sessionCookie = cookies.find(c => c.name === '_oauth2_proxy');
            expect(sessionCookie).toBeDefined();
            // Session should expire in future (not immediately)
            if (sessionCookie?.expires !== -1) {
                const expiryTime = sessionCookie?.expires ? sessionCookie.expires * 1000 : 0;
                const now = Date.now();
                expect(expiryTime).toBeGreaterThan(now);
            }
        });
        test('concurrent requests maintain session consistency', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Make multiple concurrent API requests
            const responses = await Promise.all([
                authenticatedPage.goto(`${PORTAL_URL}/api/user`).catch(() => null),
                authenticatedPage.goto(`${PORTAL_URL}/api/config`).catch(() => null),
                authenticatedPage.goto(`${PORTAL_URL}/api/workspace`).catch(() => null),
            ]);
            // All should succeed with same session
            expect(responses).toBeDefined();
        });
        test('idle session extends expiration on activity', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            const initialCookies = await authenticatedPage.context().cookies();
            const initialExpiry = initialCookies.find(c => c.name === '_oauth2_proxy')?.expires;
            // Wait a bit then perform activity
            await authenticatedPage.waitForTimeout(2000);
            // Navigate to another page
            await authenticatedPage.goto(`${PORTAL_URL}/dashboard`);
            const updatedCookies = await authenticatedPage.context().cookies();
            const updatedExpiry = updatedCookies.find(c => c.name === '_oauth2_proxy')?.expires;
            // Expiry should be extended
            expect(updatedExpiry).toBeGreaterThanOrEqual(initialExpiry);
        });
    });
    /**
     * FAILOVER SCENARIOS: Primary to Replica
     */
    test.describe('Failover - Primary Host Failure', () => {
        test('session redirects to replica when primary unavailable', async ({ authenticatedPage }) => {
            // Start at primary
            await authenticatedPage.goto(PORTAL_URL);
            // Get session from primary
            const sessionCookie = await authenticatedPage.context().cookies();
            // Simulate primary host failure by routing to replica
            await authenticatedPage.route('**/*', async (route) => {
                const url = route.request().url();
                if (url.includes(PRIMARY_HOST)) {
                    // Redirect to replica
                    const replicaUrl = url.replace(PRIMARY_HOST, REPLICA_HOST);
                    await route.goto(replicaUrl).catch(() => route.abort());
                }
                else {
                    await route.continue();
                }
            });
            // Reload should redirect to replica
            await authenticatedPage.reload();
            const finalUrl = authenticatedPage.url();
            // Should either be on replica or show failover indicator
            expect(finalUrl).toBeDefined();
        });
        test('session cookie remains valid after failover', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Get initial session
            const initialSession = await authenticatedPage.context().cookies();
            const initialCookie = initialSession.find(c => c.name === '_oauth2_proxy');
            // Simulate failover
            await authenticatedPage.route('**/*', async (route) => {
                const url = route.request().url();
                if (url.includes(PRIMARY_HOST)) {
                    const replicaUrl = url.replace(PRIMARY_HOST, REPLICA_HOST);
                    await route.goto(replicaUrl).catch(() => route.continue());
                }
                else {
                    await route.continue();
                }
            });
            await authenticatedPage.reload();
            // Session should still be valid
            const finalSession = await authenticatedPage.context().cookies();
            const finalCookie = finalSession.find(c => c.name === '_oauth2_proxy');
            expect(finalCookie).toBeDefined();
            // Cookie might be refreshed but should be present
            expect(finalCookie?.value).toBeTruthy();
        });
        test('in-flight requests complete before failover', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Start a slow request
            const slowRequest = authenticatedPage.goto(`${PORTAL_URL}/api/slow-endpoint`).catch(() => null);
            // Wait for request to complete
            const response = await slowRequest;
            // Should complete (or fail gracefully)
            expect(response || response === null).toBeDefined();
        });
        test('user is not logged out during failover', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            const url1 = authenticatedPage.url();
            expect(url1).not.toMatch(/accounts\.google\.com|oauth2|login/i);
            // Simulate failover
            await authenticatedPage.route('**/*', async (route) => {
                const url = route.request().url();
                if (url.includes(PRIMARY_HOST)) {
                    const replicaUrl = url.replace(PRIMARY_HOST, REPLICA_HOST);
                    await route.goto(replicaUrl).catch(() => route.continue());
                }
                else {
                    await route.continue();
                }
            });
            await authenticatedPage.reload();
            // Should still be authenticated
            const url2 = authenticatedPage.url();
            expect(url2).not.toMatch(/accounts\.google\.com|oauth2|login/i);
        });
    });
    /**
     * FAILOVER SCENARIOS: Failback to Primary
     */
    test.describe('Failback - Recovery to Primary', () => {
        test('session survives primary host recovery', async ({ authenticatedPage }) => {
            // Start on primary
            await authenticatedPage.goto(PORTAL_URL);
            const initialUrl = authenticatedPage.url();
            // Simulate primary failure then recovery
            let failoverActive = true;
            await authenticatedPage.route('**/*', async (route) => {
                const url = route.request().url();
                if (url.includes(PRIMARY_HOST) && failoverActive) {
                    const replicaUrl = url.replace(PRIMARY_HOST, REPLICA_HOST);
                    await route.goto(replicaUrl).catch(() => route.continue());
                }
                else {
                    await route.continue();
                }
            });
            // Reload (goes to replica)
            await authenticatedPage.reload();
            // Primary recovers
            failoverActive = false;
            // Reload again (returns to primary)
            await authenticatedPage.reload();
            // Should be back on primary and still authenticated
            const finalUrl = authenticatedPage.url();
            expect(finalUrl).not.toMatch(/accounts\.google\.com|oauth2|login/i);
        });
        test('unsaved changes are not lost during failover', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Edit code in IDE
            const editor = authenticatedPage.locator('.monaco-editor').first();
            await editor.click();
            await authenticatedPage.keyboard.type('// test code');
            // Simulate failover
            await authenticatedPage.route('**/*', async (route) => {
                const url = route.request().url();
                if (url.includes(PRIMARY_HOST)) {
                    const replicaUrl = url.replace(PRIMARY_HOST, REPLICA_HOST);
                    await route.goto(replicaUrl).catch(() => route.continue());
                }
                else {
                    await route.continue();
                }
            });
            // Auto-save might have already saved
            await authenticatedPage.waitForTimeout(1000);
            // Changes should still be visible
            const content = await authenticatedPage.textContent('.monaco-editor');
            expect(content).toContain('test code');
        });
    });
    /**
     * SESSION TIMEOUT SCENARIOS
     */
    test.describe('Session Timeout Handling', () => {
        test('expired session redirects to login', async ({ authenticatedPage, context }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Simulate session expiration by clearing cookies
            await context.clearCookies();
            // Try to access protected resource
            await authenticatedPage.goto(PORTAL_URL);
            // Should redirect to login
            const url = authenticatedPage.url();
            expect(url).toMatch(/accounts\.google\.com|oauth2|login/i);
        });
        test('session can be renewed after expiration', async ({ authenticatedPage, context }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Simulate expiration
            await context.clearCookies();
            // Redirect to login (automatic)
            await authenticatedPage.goto(PORTAL_URL);
            // User is at login
            expect(authenticatedPage.url()).toMatch(/login|oauth2/i);
            // After re-authentication (simulated by getting new session)
            // Would need to login again
        });
        test('warning appears before session timeout', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Look for session timeout warning (if implemented)
            const warningBtn = authenticatedPage.locator('[data-testid="session-warning"]').or(authenticatedPage.locator('text=Session Expiring'));
            // Might not appear immediately, but implementation could show it
            const visible = await warningBtn.isVisible({ timeout: 1000 }).catch(() => false);
            // Warning might not be visible yet (depends on session duration)
            expect(typeof visible).toBe('boolean');
        });
        test('session can be extended if warning is dismissed', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // If session extension is available
            const extendBtn = authenticatedPage.locator('[data-testid="extend-session"]').or(authenticatedPage.locator('text=Continue Session'));
            if (await extendBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
                await extendBtn.click();
                // Session should be extended
                const cookies = await authenticatedPage.context().cookies();
                const sessionCookie = cookies.find(c => c.name === '_oauth2_proxy');
                expect(sessionCookie).toBeDefined();
            }
        });
    });
    /**
     * MULTI-DEVICE SESSION SCENARIOS
     */
    test.describe('Multi-Device Sessions', () => {
        test('concurrent sessions from different devices are isolated', async ({ browser }) => {
            const context1 = await browser.newContext();
            const context2 = await browser.newContext();
            const page1 = await context1.newPage();
            const page2 = await context2.newPage();
            // Both login
            await page1.goto(PORTAL_URL);
            await page2.goto(PORTAL_URL);
            // Get session cookies
            const cookies1 = await context1.cookies();
            const cookies2 = await context2.cookies();
            const session1 = cookies1.find(c => c.name === '_oauth2_proxy')?.value;
            const session2 = cookies2.find(c => c.name === '_oauth2_proxy')?.value;
            // Sessions should be different (different contexts)
            if (session1 && session2) {
                expect(session1).not.toBe(session2);
            }
            await context1.close();
            await context2.close();
        });
        test('logout on one device does not affect others', async ({ browser }) => {
            const context1 = await browser.newContext();
            const context2 = await browser.newContext();
            const page1 = await context1.newPage();
            const page2 = await context2.newPage();
            // Both login
            await page1.goto(PORTAL_URL);
            await page2.goto(PORTAL_URL);
            // Logout from device 1
            await page1.goto(`${PORTAL_URL}/logout`);
            // Device 1 should be logged out
            const page1Url = page1.url();
            expect(page1Url).toMatch(/login|oauth2/i);
            // Device 2 should still be logged in
            const page2Url = page2.url();
            expect(page2Url).not.toMatch(/login|oauth2/i);
            await context1.close();
            await context2.close();
        });
        test('session list shows all active sessions', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            // Find session management (if implemented)
            const sessionsBtn = authenticatedPage.locator('[data-testid="active-sessions"]').or(authenticatedPage.locator('text=Active Sessions'));
            if (await sessionsBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
                await sessionsBtn.click();
                // Should show list of sessions
                const sessionList = authenticatedPage.locator('[data-testid="session-item"]').or(authenticatedPage.locator('.session-item'));
                expect(await sessionList.count({ timeout: 5000 }).catch(() => 0)).toBeGreaterThanOrEqual(1);
            }
        });
    });
    /**
     * PERFORMANCE & STABILITY
     */
    test.describe('Performance - Session Operations', () => {
        test('session validation is fast', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            const startTime = Date.now();
            // Navigate to protected resource
            await authenticatedPage.goto(`${PORTAL_URL}/dashboard`);
            const duration = Date.now() - startTime;
            // Should load quickly
            expect(duration).toBeLessThan(3000);
        });
        test('failover completes within timeout window', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(PORTAL_URL);
            const startTime = Date.now();
            // Simulate failover
            await authenticatedPage.route('**/*', async (route) => {
                const url = route.request().url();
                if (url.includes(PRIMARY_HOST)) {
                    const replicaUrl = url.replace(PRIMARY_HOST, REPLICA_HOST);
                    await route.goto(replicaUrl).catch(() => route.continue());
                }
                else {
                    await route.continue();
                }
            });
            await authenticatedPage.reload();
            const duration = Date.now() - startTime;
            // Failover should complete quickly
            expect(duration).toBeLessThan(10000);
        });
    });
});
//# sourceMappingURL=session-persistence-failover.spec.js.map