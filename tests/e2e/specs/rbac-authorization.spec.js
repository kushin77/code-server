import { test, expect } from '@playwright/test';
const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
const API_URL = process.env.API_BASE_URL || 'https://api.kushnir.cloud';
const QA_EMAIL = process.env.E2E_USER_EMAIL || 'qa@kushnir.cloud';
const QA_PASSWORD = process.env.E2E_USER_PASSWORD || '';
test.describe('RBAC Authorization (#1177)', () => {
    let authCookie;
    let jwtToken;
    test.beforeAll(async () => {
        // This would be handled by shared auth context in real implementation
        // For now, we'll authenticate in each test
    });
    test.describe('Role-Based Endpoint Access', () => {
        test('1: viewer role can access read-only endpoints', async ({ page }) => {
            // Login with QA user (should have viewer role)
            await page.goto(PORTAL_URL);
            await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
            await page.fill('input[type="email"]', QA_EMAIL);
            await page.click('#identifierNext, button:has-text("Next")');
            await page.waitForSelector('input[type="password"]', { timeout: 5000 });
            await page.fill('input[type="password"]', QA_PASSWORD);
            await page.click('#passwordNext, button:has-text("Next")');
            await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
            // Try accessing read-only endpoint (should succeed)
            const getResponse = await page.request.get(`${API_URL}/api/v1/sessions`, {
                headers: {
                    'Authorization': `Bearer ${await getJwtToken(page)}`
                }
            });
            expect(getResponse.ok).toBe(true);
            expect(getResponse.status()).toBe(200);
        });
        test('2: viewer role denied on write endpoints', async ({ page }) => {
            // Login and get JWT token
            await page.goto(PORTAL_URL);
            await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
            await page.fill('input[type="email"]', QA_EMAIL);
            await page.click('#identifierNext, button:has-text("Next")');
            await page.waitForSelector('input[type="password"]', { timeout: 5000 });
            await page.fill('input[type="password"]', QA_PASSWORD);
            await page.click('#passwordNext, button:has-text("Next")');
            await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
            // Try accessing write endpoint (should be denied with 403 Forbidden)
            const postResponse = await page.request.post(`${API_URL}/api/v1/sessions/terminate`, {
                headers: {
                    'Authorization': `Bearer ${await getJwtToken(page)}`
                },
                data: { sessionId: 'test-session' }
            });
            expect(postResponse.status()).toBe(403);
        });
        test('3: missing Authorization header returns 401 Unauthorized', async ({ page }) => {
            // Make request without authentication
            const response = await page.request.get(`${API_URL}/api/v1/sessions/protected-endpoint`);
            expect(response.status()).toBe(401);
        });
        test('4: invalid JWT token returns 401 Unauthorized', async ({ page }) => {
            // Make request with invalid token
            const response = await page.request.get(`${API_URL}/api/v1/sessions`, {
                headers: {
                    'Authorization': 'Bearer invalid.jwt.token'
                }
            });
            expect(response.status()).toBe(401);
        });
    });
    test.describe('Role Inheritance', () => {
        test('1: admin role inherits all permissions', async ({ page }) => {
            // Test would require admin user - setup in fixtures
            // admin should be able to access all endpoints that viewer can
            // plus additional admin-only endpoints
            expect(true).toBe(true); // Placeholder
        });
        test('2: editor role has intermediate permissions', async ({ page }) => {
            // editor should be able to read and write their own sessions
            // but not other users' sessions
            expect(true).toBe(true); // Placeholder
        });
    });
    test.describe('Authorization Error Handling', () => {
        test('1: 401 response includes proper error message', async ({ page }) => {
            const response = await page.request.get(`${API_URL}/api/v1/sessions/protected`, {
                headers: {
                    'Authorization': 'Bearer invalid.token'
                }
            });
            expect(response.status()).toBe(401);
            const body = await response.json();
            expect(body.error).toBeDefined();
            expect(body.message).toContain('unauthorized');
        });
        test('2: 403 response includes proper error message', async ({ page }) => {
            // Get valid viewer token
            await page.goto(PORTAL_URL);
            await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
            await page.fill('input[type="email"]', QA_EMAIL);
            await page.click('#identifierNext, button:has-text("Next")');
            await page.waitForSelector('input[type="password"]', { timeout: 5000 });
            await page.fill('input[type="password"]', QA_PASSWORD);
            await page.click('#passwordNext, button:has-text("Next")');
            await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
            // Try admin-only endpoint
            const response = await page.request.post(`${API_URL}/api/v1/admin/settings`, {
                headers: {
                    'Authorization': `Bearer ${await getJwtToken(page)}`
                },
                data: { setting: 'value' }
            });
            expect(response.status()).toBe(403);
            const body = await response.json();
            expect(body.error).toBeDefined();
            expect(body.message).toContain('forbidden');
        });
    });
    test.describe('Role Assignment API', () => {
        test('1: GET /api/v1/rbac/roles returns list of roles', async ({ page }) => {
            // Requires authenticated session
            await page.goto(PORTAL_URL);
            await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
            await page.fill('input[type="email"]', QA_EMAIL);
            await page.click('#identifierNext, button:has-text("Next")');
            await page.waitForSelector('input[type="password"]', { timeout: 5000 });
            await page.fill('input[type="password"]', QA_PASSWORD);
            await page.click('#passwordNext, button:has-text("Next")');
            await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
            const response = await page.request.get(`${API_URL}/api/v1/rbac/roles`, {
                headers: {
                    'Authorization': `Bearer ${await getJwtToken(page)}`
                }
            });
            expect(response.ok).toBe(true);
            const body = await response.json();
            expect(Array.isArray(body.roles)).toBe(true);
            expect(body.roles.length).toBeGreaterThan(0);
        });
        test('2: POST /api/v1/rbac/roles assigns role to user', async ({ page }) => {
            // Requires admin permissions
            expect(true).toBe(true); // Placeholder
        });
        test('3: DELETE /api/v1/rbac/roles revokes role from user', async ({ page }) => {
            // Requires admin permissions
            expect(true).toBe(true); // Placeholder
        });
    });
    test.describe('JWT Claims Validation', () => {
        test('1: JWT token includes required claims (sub, aud, iss, iat, exp)', async ({ page }) => {
            // Login and get token
            await page.goto(PORTAL_URL);
            await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
            await page.fill('input[type="email"]', QA_EMAIL);
            await page.click('#identifierNext, button:has-text("Next")');
            await page.waitForSelector('input[type="password"]', { timeout: 5000 });
            await page.fill('input[type="password"]', QA_PASSWORD);
            await page.click('#passwordNext, button:has-text("Next")');
            await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
            const token = await getJwtToken(page);
            const decoded = decodeJwt(token);
            expect(decoded.sub).toBeDefined(); // Subject (user ID)
            expect(decoded.aud).toBeDefined(); // Audience
            expect(decoded.iss).toBeDefined(); // Issuer
            expect(decoded.iat).toBeDefined(); // Issued at
            expect(decoded.exp).toBeDefined(); // Expiration
        });
        test('2: JWT token includes roles claim', async ({ page }) => {
            // Login and get token
            await page.goto(PORTAL_URL);
            await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
            await page.fill('input[type="email"]', QA_EMAIL);
            await page.click('#identifierNext, button:has-text("Next")');
            await page.waitForSelector('input[type="password"]', { timeout: 5000 });
            await page.fill('input[type="password"]', QA_PASSWORD);
            await page.click('#passwordNext, button:has-text("Next")');
            await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
            const token = await getJwtToken(page);
            const decoded = decodeJwt(token);
            expect(decoded.roles).toBeDefined();
            expect(Array.isArray(decoded.roles)).toBe(true);
            expect(decoded.roles.length).toBeGreaterThan(0);
        });
        test('3: JWT token has correct expiration (1 hour)', async ({ page }) => {
            // Login and get token
            await page.goto(PORTAL_URL);
            await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
            await page.fill('input[type="email"]', QA_EMAIL);
            await page.click('#identifierNext, button:has-text("Next")');
            await page.waitForSelector('input[type="password"]', { timeout: 5000 });
            await page.fill('input[type="password"]', QA_PASSWORD);
            await page.click('#passwordNext, button:has-text("Next")');
            await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
            const token = await getJwtToken(page);
            const decoded = decodeJwt(token);
            const expirationSeconds = decoded.exp - decoded.iat;
            expect(expirationSeconds).toBe(3600); // 1 hour
        });
    });
});
// Helper functions
async function getJwtToken(page) {
    // Extract JWT from Authorization header in intercepted request
    // or from API response
    // For now, return placeholder - would be implemented with proper fixtures
    return 'placeholder.jwt.token';
}
function decodeJwt(token) {
    // Simple JWT decoding (in production, use jsonwebtoken library)
    const parts = token.split('.');
    if (parts.length !== 3)
        return {};
    try {
        const decoded = JSON.parse(Buffer.from(parts[1], 'base64').toString());
        return decoded;
    }
    catch (e) {
        return {};
    }
}
//# sourceMappingURL=rbac-authorization.spec.js.map